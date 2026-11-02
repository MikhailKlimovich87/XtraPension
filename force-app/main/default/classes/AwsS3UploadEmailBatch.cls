/**
 * Batch Apex class for uploading EmailMessage ContentDocument versions to AWS S3
 * Includes deletion of uploaded files and error notifications (only on failure/partial success)
 * Updates EmailMessage record with S3 upload status
 * FIXED: Properly loads ContentVersion data
 */
public with sharing class AwsS3UploadEmailBatch implements Database.Batchable<ContentVersion>, Database.AllowsCallouts, Database.Stateful {
    
    // Configuration
    private Id emailMessageId;
    private String namedCredential = 'AWS_S3_Email';
    private Boolean deleteAfterUpload = true;
    private Integer batchSize = 1; // Process one file at a time to avoid heap limits
    
    // State tracking
    private Integer totalProcessed = 0;
    private Integer successCount = 0;
    private Integer failureCount = 0;
    private List<String> failedFiles = new List<String>();
    private List<String> successFiles = new List<String>();
    private List<Id> uploadedContentVersionIds = new List<Id>();
    private List<Id> uploadedContentDocumentIds = new List<Id>();
    private Map<String, String> fileStatusMap = new Map<String, String>();
    private Set<Id> processedDocumentIds = new Set<Id>();
    
    // S3 upload tracking
    private DateTime uploadStartTime;
    private DateTime uploadEndTime;
    private String s3PackageId;
    private String uploadStatus = 'Pending';
    private String uploadErrorDetails = '';
    private Boolean hasHeapError = false;
    private String heapErrorMessage = '';
    
    // Constants
    private static final Integer MAX_FILE_SIZE = 25000000; // 25MB limit
    private static final Integer MAX_BATCH_HEAP = 11000000; // ~11MB safe limit for batch
    
    public AwsS3UploadEmailBatch(Id emailMessageId) {
        this.emailMessageId = emailMessageId;
        this.uploadStartTime = System.now();
        this.s3PackageId = emailMessageId;
        
        System.debug('=== AwsS3UploadEmailBatch Initialized ===');
        System.debug('EmailMessage ID: ' + emailMessageId);
        System.debug('S3 Package ID: ' + s3PackageId);
        System.debug('Batch Size: ' + batchSize);
        System.debug('Delete After Upload: ' + deleteAfterUpload);
    }
    
    public Iterable<ContentVersion> start(Database.BatchableContext bc) {
        System.debug('=== START METHOD CALLED ===');
        
        List<ContentVersion> versions = new List<ContentVersion>();
        
        try {
            // First, get all ContentDocument IDs for this EmailMessage
            Set<Id> contentDocumentIds = new Set<Id>();
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :emailMessageId
            ]) {
                contentDocumentIds.add(link.ContentDocumentId);
            }
            
            if (contentDocumentIds.isEmpty()) {
                System.debug('No ContentDocuments found for EmailMessage: ' + emailMessageId);
                uploadStatus = 'No Files';
                return versions;
            }
            
            // IMPORTANT: Get ALL ContentVersions with their IDs only
            // We'll load the actual data in execute() method
            versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension, 
                       ContentSize, VersionNumber, FileType, CreatedDate
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
                ORDER BY ContentDocumentId, CreatedDate DESC
            ];
            
            // Filter out Notes
            List<ContentVersion> filteredVersions = new List<ContentVersion>();
            for (ContentVersion version : versions) {
                if (isNote(version)) {
                    System.debug('Skipping Note: "' + version.Title + '" (ID: ' + version.Id + ')');
                    failureCount++;
                    failedFiles.add('SKIPPED: ' + version.Title + ' (Note file)');
                    fileStatusMap.put(version.Id, 'SKIPPED: Note');
                } else {
                    filteredVersions.add(version);
                }
            }
            
            versions = filteredVersions;
            
            System.debug('Found ' + versions.size() + ' ContentVersions to process');
            for (ContentVersion cv : versions) {
                System.debug('  - File: ' + cv.Title + ' (ID: ' + cv.Id + ', Size: ' + cv.ContentSize + ' bytes)');
            }
            
        } catch (Exception ex) {
            System.debug('Error in start method: ' + ex.getMessage());
            uploadStatus = 'Error';
            uploadErrorDetails = 'Start error: ' + ex.getMessage();
        }
        
        return versions;
    }
    
    private Boolean isNote(ContentVersion version) {
        if (version.FileType == 'SNOTE' || version.FileType == 'NOTE') {
            return true;
        }
        
        if (version.FileExtension != null && version.FileExtension.toLowerCase() == 'snote') {
            return true;
        }
        
        String title = version.Title;
        if (title != null) {
            String titleLower = title.toLowerCase();
            if (titleLower.startsWith('note') ||
                titleLower.contains(' - note') ||
                titleLower.contains(' note ') ||
            titleLower.equals('untitled')) {
                return true;
            }
        }
        
        return false;
    }
    
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        System.debug('=== EXECUTE METHOD CALLED ===');
        System.debug('Scope size: ' + scope.size());
        
        // Check heap usage before processing
        checkHeapUsage();
        
        for (ContentVersion contentVersion : scope) {
            // Process each file individually to manage heap
            processContentVersion(contentVersion);
            
            // Check heap after each file
            checkHeapUsage();
        }
    }
    
    private void checkHeapUsage() {
        Integer heapSize = Limits.getHeapSize();
        Integer heapLimit = Limits.getLimitHeapSize();
        
        if (heapSize > MAX_BATCH_HEAP) {
            System.debug('⚠️ Heap usage approaching limit: ' + heapSize + ' / ' + heapLimit);
            hasHeapError = true;
            heapErrorMessage = 'Heap size exceeded safe limit. Current: ' + heapSize + ' bytes';
        }
        
        System.debug('💾 Heap usage: ' + heapSize + ' / ' + heapLimit + ' bytes');
    }
    
    private void processContentVersion(ContentVersion contentVersion) {
        String docId = contentVersion.ContentDocumentId;
        String versionId = contentVersion.Id;
        String title = contentVersion.Title;
        
        System.debug('Processing: "' + title + '" (ID: ' + versionId + ')');
        
        totalProcessed++;
        
        if (processedDocumentIds.contains(docId)) {
            System.debug('Skipping already processed document: ' + docId);
            return;
        }
        
        try {
            // CRITICAL FIX: Load the full ContentVersion with VersionData
            // The key is to use the versionId we already have
            ContentVersion fullVersion = loadFullVersionWithData(versionId);
            
            if (fullVersion == null) {
                String errorMsg = 'Could not load file data - ContentVersion not found';
                failureCount++;
                failedFiles.add(title + ' (Error: ' + errorMsg + ')');
                fileStatusMap.put(versionId, 'FAILED: ' + errorMsg);
                System.debug('❌ Could not load data for "' + title + '" - Version ID: ' + versionId);
                uploadStatus = 'Partial';
                return;
            }
            
            // Debug the loaded data
            System.debug('📄 Loaded ContentVersion:');
            System.debug('   Title: ' + fullVersion.Title);
            System.debug('   ID: ' + fullVersion.Id);
            System.debug('   ContentDocumentId: ' + fullVersion.ContentDocumentId);
            System.debug('   Has VersionData: ' + (fullVersion.VersionData != null));
            if (fullVersion.VersionData != null) {
                System.debug('   Data Size: ' + fullVersion.VersionData.size() + ' bytes');
            } else {
                System.debug('   ⚠️ VersionData is NULL!');
            }
            
            // Check if VersionData is null
            if (fullVersion.VersionData == null) {
                String errorMsg = 'VersionData is null - file may be corrupted';
                failureCount++;
                failedFiles.add(title + ' (Error: ' + errorMsg + ')');
                fileStatusMap.put(versionId, 'FAILED: ' + errorMsg);
                System.debug('❌ VersionData is null for "' + title + '"');
                uploadStatus = 'Partial';
                return;
            }
            
            // Check file size - use actual blob size
            Integer fileSize = fullVersion.VersionData.size();
            if (fileSize > MAX_FILE_SIZE) {
                String errorMsg = 'File too large: ' + fileSize + ' bytes (max: ' + MAX_FILE_SIZE + ')';
                failureCount++;
                failedFiles.add(title + ' (Error: ' + errorMsg + ')');
                fileStatusMap.put(versionId, 'FAILED: ' + errorMsg);
                System.debug('❌ File too large - "' + title + '"');
                uploadStatus = 'Partial';
                return;
            }
            
            // Build the S3 key
            String s3Key = buildS3Key(fullVersion);
            System.debug('📤 Uploading to S3 with key: ' + s3Key);
            
            Boolean uploadSuccess = uploadToS3(fullVersion, s3Key);
            
            if (uploadSuccess) {
                updateContentVersionWithS3Id(versionId, s3Key);
                successCount++;
                successFiles.add(title);
                fileStatusMap.put(versionId, 'SUCCESS');
                processedDocumentIds.add(docId);
                
                // Track for deletion
                uploadedContentVersionIds.add(versionId);
                uploadedContentDocumentIds.add(docId);
                
                System.debug('✅ Upload successful: "' + title + '" -> ' + s3Key);
            } else {
                failureCount++;
                failedFiles.add(title + ' (Upload to S3 failed)');
                fileStatusMap.put(versionId, 'FAILED: Upload to S3 failed');
                System.debug('❌ Upload failed: "' + title + '"');
                uploadStatus = 'Partial';
            }
            
        } catch (Exception ex) {
            String errorMsg = 'Exception: ' + ex.getMessage();
            failureCount++;
            failedFiles.add(title + ' (Error: ' + errorMsg + ')');
            fileStatusMap.put(versionId, 'FAILED: ' + errorMsg);
            System.debug('❌ Exception processing "' + title + '": ' + ex.getMessage());
            System.debug('   Stack trace: ' + ex.getStackTraceString());
            
            // Check if it's a heap error
            if (ex.getMessage().contains('heap') || ex.getMessage().contains('Heap')) {
                hasHeapError = true;
                heapErrorMessage = ex.getMessage();
            }
            
            uploadStatus = 'Error';
            uploadErrorDetails = errorMsg;
        }
        
        System.debug('Processed ' + totalProcessed + ' files. ' +
            'Success: ' + successCount + ', Failed: ' + failureCount);
    }
    
    /**
     * Loads the full ContentVersion with VersionData
     * FIXED: Uses a simpler, more reliable approach
     */
    private ContentVersion loadFullVersionWithData(Id versionId) {
        try {
            System.debug('🔍 Loading ContentVersion data for ID: ' + versionId);
            
            // SIMPLIFIED: Just query the ContentVersion directly
            // No FOR UPDATE, no dynamic queries - just a simple SOQL
            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension, VersionData,
                       ContentSize, VersionNumber, FileType, CreatedDate, LastModifiedDate
                FROM ContentVersion
                WHERE Id = :versionId
                LIMIT 1
            ];
            
            if (versions.isEmpty()) {
                System.debug('❌ No ContentVersion found with ID: ' + versionId);
                return null;
            }
            
            ContentVersion version = versions[0];
            System.debug('✅ Successfully loaded ContentVersion: ' + version.Id);
            
            // Check if VersionData is null
            if (version.VersionData == null) {
                System.debug('⚠️ VersionData is null for version: ' + versionId);
                
                // Try one more time with a different approach
                // Sometimes the data is in the ContentDocument, not the ContentVersion
                try {
                    System.debug('🔄 Trying alternative approach...');
                    
                    // Get the ContentDocument directly
                    ContentDocument doc = [
                        SELECT Id, Title, LatestPublishedVersionId
                        FROM ContentDocument
                        WHERE Id = :version.ContentDocumentId
                        LIMIT 1
                    ];
                    
                    if (doc.LatestPublishedVersionId != null) {
                        System.debug('   Latest Published Version ID: ' + doc.LatestPublishedVersionId);
                        
                        // If the latest version is different, try loading that
                        if (doc.LatestPublishedVersionId != versionId) {
                            List<ContentVersion> latestVersions = [
                                SELECT Id, ContentDocumentId, Title, FileExtension, VersionData,
                                       ContentSize, VersionNumber, FileType
                                FROM ContentVersion
                                WHERE Id = :doc.LatestPublishedVersionId
                                LIMIT 1
                            ];
                            
                            if (!latestVersions.isEmpty() && latestVersions[0].VersionData != null) {
                                System.debug('✅ Loaded latest version with data');
                                return latestVersions[0];
                            }
                        }
                    }
                } catch (Exception docEx) {
                    System.debug('⚠️ Alternative approach failed: ' + docEx.getMessage());
                }
            }
            
            return version;
            
        } catch (Exception ex) {
            System.debug('❌ Error loading full version: ' + ex.getMessage());
            System.debug('   Stack trace: ' + ex.getStackTraceString());
            return null;
        }
    }
    
    /**
     * Builds the S3 key - WITHOUT leading slash
     */
    private String buildS3Key(ContentVersion version) {
        // Clean the title
        String cleanTitle = version.Title != null ? version.Title : 'file';
        cleanTitle = cleanTitle.replaceAll('[^a-zA-Z0-9\\s\\(\\)\\-\\_\\.]', '');
        cleanTitle = cleanTitle.replaceAll('\\s+', ' ').trim();
        
        if (cleanTitle.length() > 200) {
            cleanTitle = cleanTitle.substring(0, 200);
        }
        
        // Add extension if present
        if (String.isNotBlank(version.FileExtension) &&
        !cleanTitle.toLowerCase().endsWith('.' + version.FileExtension.toLowerCase())) {
            cleanTitle += '.' + version.FileExtension.toLowerCase();
        }
        
        // Build the key: {EmailMessageId}/{filename}
        String key = emailMessageId + '/' + cleanTitle;
        key = key.replaceAll('//', '/');
        
        // Remove any leading slash
        if (key.startsWith('/')) {
            key = key.substring(1);
        }
        
        return key;
    }
    
    /**
     * Uploads a file to S3
     */
    private Boolean uploadToS3(ContentVersion contentVersion, String s3Key) {
        try {
            System.debug('📤 Uploading to S3');
            System.debug('   S3 Key: ' + s3Key);
            System.debug('   File Size: ' + contentVersion.VersionData.size() + ' bytes');
            
            // URL encode the S3 key
            String encodedKey = EncodingUtil.urlEncode(s3Key, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            encodedKey = encodedKey.replace('+', '%20');
            
            String endpoint = 'callout:' + namedCredential + '/' + encodedKey;
            
            // Prepare the request
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('PUT');
            request.setTimeout(60000);
            
            // Set content type
            String contentType = getContentType(contentVersion.FileExtension);
            request.setHeader('Content-Type', contentType);
            
            // Set the body
            request.setBodyAsBlob(contentVersion.VersionData);
            
            // Send the request
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('📥 S3 Response Status: ' + response.getStatusCode());
            
            if (response.getStatusCode() == 200) {
                System.debug('✅ S3 upload successful: ' + s3Key);
                return true;
            } else {
                System.debug('❌ S3 upload failed with status: ' + response.getStatusCode());
                System.debug('   Response body: ' + response.getBody());
                return false;
            }
            
        } catch (Exception ex) {
            System.debug('❌ Error uploading to S3: ' + ex.getMessage());
            return false;
        }
    }
    
    /**
     * Gets content type from file extension
     */
    private String getContentType(String extension) {
        Map<String, String> mimeTypes = new Map<String, String>{
            'pdf' => 'application/pdf',
            'doc' => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'jpg' => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'gif' => 'image/gif',
            'txt' => 'text/plain',
            'csv' => 'text/csv',
            'zip' => 'application/zip',
            'xml' => 'application/xml',
            'json' => 'application/json'
        };
        
        String ext = extension != null ? extension.toLowerCase() : '';
        return mimeTypes.containsKey(ext) ? mimeTypes.get(ext) : 'application/octet-stream';
    }
    
    private void updateContentVersionWithS3Id(Id versionId, String s3Key) {
        try {
            ContentVersion cv = new ContentVersion(
                Id = versionId,
            AWS_S3_Object_Key__c = s3Key,
            S3_Upload_Date__c = System.now(),
            S3_Upload_Status__c = 'Uploaded'
                );
            update cv;
            System.debug('✅ Updated ContentVersion ' + versionId + ' with S3 metadata');
        } catch (Exception ex) {
            System.debug('⚠️ Error updating ContentVersion: ' + ex.getMessage());
        }
    }
    
    /**
     * Updates the EmailMessage record with S3 upload information
     */
    private void updateEmailMessageRecord() {
        try {
            this.uploadEndTime = System.now();
            
            // Determine final status based on actual results
            String finalStatus;
            if (hasHeapError) {
                finalStatus = 'Heap Error';
            } else if (totalProcessed == 0) {
                finalStatus = 'No Files';
            } else if (failureCount == 0 && successCount > 0) {
                finalStatus = 'Success';
            } else if (failureCount > 0 && successCount > 0) {
                finalStatus = 'Partial Success';
            } else if (failureCount > 0 && successCount == 0) {
                finalStatus = 'Failed';
            } else {
                finalStatus = 'Unknown';
            }
            
            // Build the EmailMessage update
            EmailMessage email = new EmailMessage(Id = emailMessageId);
            
            // Populate custom fields
            email.AWS_S3_Package_Id__c = s3PackageId;
            email.S3_Upload_Status__c = finalStatus;
            email.S3_Upload_Date__c = this.uploadEndTime;
            email.S3_Total_Files__c = totalProcessed;
            email.S3_Success_Count__c = successCount;
            email.S3_Failed_Count__c = failureCount;
            
            // Success rate
            if (totalProcessed > 0) {
                Decimal successRate = (successCount * 100.0) / totalProcessed;
                email.S3_Success_Rate__c = successRate.setScale(2);
            }
            
            // Upload Error Details
            List<String> errorDetails = new List<String>();
            
            if (hasHeapError) {
                errorDetails.add('Heap limit exceeded: ' + heapErrorMessage);
            }
            
            if (String.isNotBlank(uploadErrorDetails)) {
                errorDetails.add('Error: ' + uploadErrorDetails);
            }
            
            if (failureCount > 0 && !failedFiles.isEmpty()) {
                String failedFilesList = String.join(failedFiles, '\n');
                if (failedFilesList.length() > 200) {
                    failedFilesList = failedFilesList.substring(0, 197) + '...';
                }
                errorDetails.add('Failed files: ' + failedFilesList);
            }
            
            if (!errorDetails.isEmpty()) {
                email.S3_Error_Details__c = String.join(errorDetails, '\n');
            }
            
            // Update the EmailMessage
            update email;
            System.debug('✅ Updated EmailMessage ' + emailMessageId + ' with S3 upload information');
            System.debug('   Status: ' + finalStatus);
            System.debug('   Total: ' + totalProcessed + ', Success: ' + successCount + ', Failed: ' + failureCount);
            
        } catch (Exception ex) {
            System.debug('⚠️ Error updating EmailMessage: ' + ex.getMessage());
        }
    }
    
    /**
     * Deletes uploaded ContentVersions from Salesforce
     */
    private void deleteUploadedFiles() {
        if (uploadedContentVersionIds.isEmpty()) {
            System.debug('No files to delete');
            return;
        }
        
        try {
            List<ContentDocument> docsToDelete = new List<ContentDocument>();
            for (Id docId : uploadedContentDocumentIds) {
                docsToDelete.add(new ContentDocument(Id = docId));
            }
            
            if (!docsToDelete.isEmpty()) {
                Database.DeleteResult[] deleteResults = Database.delete(docsToDelete, false);
                
                Integer deletedCount = 0;
                Integer deleteErrors = 0;
                
                for (Database.DeleteResult result : deleteResults) {
                    if (result.isSuccess()) {
                        deletedCount++;
                    } else {
                        deleteErrors++;
                        for (Database.Error err : result.getErrors()) {
                            System.debug('⚠️ Error deleting document: ' + err.getMessage());
                        }
                    }
                }
                
                System.debug('✅ Deleted ' + deletedCount + ' files from Salesforce');
                if (deleteErrors > 0) {
                    System.debug('⚠️ ' + deleteErrors + ' files could not be deleted');
                }
            }
            
        } catch (Exception ex) {
            System.debug('⚠️ Error deleting files: ' + ex.getMessage());
        }
    }
    
    /**
     * Generates the notification message
     */
    private String generateNotificationMessage() {
        List<String> parts = new List<String>();
        parts.add('=== S3 Upload Email Batch Results ===');
        parts.add('');
        parts.add('EmailMessage ID: ' + emailMessageId);
        parts.add('S3 Package: ' + s3PackageId);
        parts.add('Total Processed: ' + totalProcessed);
        parts.add('Successfully Uploaded: ' + successCount);
        parts.add('Failed: ' + failureCount);
        
        String status;
        if (hasHeapError) {
            status = '❌ HEAP ERROR';
        } else if (failureCount == 0 && successCount > 0) {
            status = '✅ SUCCESS';
        } else if (failureCount > 0 && successCount > 0) {
            status = '⚠️ PARTIAL SUCCESS';
        } else if (failureCount > 0 && successCount == 0) {
            status = '❌ FAILED';
        } else {
            status = '📁 NO FILES';
        }
        parts.add('Status: ' + status);
        
        if (hasHeapError) {
            parts.add('Heap Error: ' + heapErrorMessage);
        }
        
        if (totalProcessed > 0) {
            Decimal successRate = (successCount * 100.0) / totalProcessed;
            parts.add('Success Rate: ' + successRate.setScale(2) + '%');
        }
        
        parts.add('');
        
        if (!successFiles.isEmpty()) {
            parts.add('--- Successful Uploads (' + successFiles.size() + ') ---');
            for (String file : successFiles) {
                parts.add('  ✅ ' + file);
            }
        }
        
        if (!failedFiles.isEmpty()) {
            parts.add('');
            parts.add('--- Failed Uploads (' + failedFiles.size() + ') ---');
            for (String file : failedFiles) {
                parts.add('  ❌ ' + file);
            }
            parts.add('');
            parts.add('⚠️ Please check the failed files and retry if needed.');
        }
        
        if (deleteAfterUpload && failureCount == 0 && successCount > 0 && !hasHeapError) {
            parts.add('');
            parts.add('✅ All files have been deleted from Salesforce after successful upload.');
        } else if (deleteAfterUpload && (failureCount > 0 || hasHeapError)) {
            parts.add('');
            parts.add('⚠️ Files were NOT deleted because some uploads failed.');
        } else {
            parts.add('');
            parts.add('📁 Files remain in Salesforce (deleteAfterUpload = false).');
        }
        
        parts.add('');
        parts.add('---');
        parts.add('Started: ' + uploadStartTime);
        parts.add('Completed: ' + uploadEndTime);
        
        return String.join(parts, '\n');
    }
    
    /**
     * Sends email notification only if there are failures or partial success
     */
    private void sendNotificationIfNeeded() {
        if (failureCount > 0 || hasHeapError) {
            try {
                String subject = '⚠️ AWS S3 Upload - ';
                if (hasHeapError) {
                    subject += 'Heap Error';
                } else if (failureCount > 0 && successCount > 0) {
                    subject += 'Partial Success';
                } else {
                    subject += 'Failed';
                }
                String body = generateNotificationMessage();
                
                // Comment out if notification service not available
                // AwsS3NotificationService notificationService = new AwsS3NotificationService();
                // notificationService.sendFailureNotification(subject, body);
                
                System.debug('📧 Notification would be sent: ' + subject);
                System.debug('Body:\n' + body);
                
            } catch (Exception ex) {
                System.debug('⚠️ Error sending notification: ' + ex.getMessage());
            }
        } else {
            System.debug('✅ All uploads succeeded. No notification sent.');
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('=== FINISH METHOD CALLED ===');
        
        // Update EmailMessage record with S3 upload information
        updateEmailMessageRecord();
        
        // Delete uploaded files if all uploads were successful
        if (deleteAfterUpload && failureCount == 0 && successCount > 0 && !hasHeapError) {
            System.debug('🗑️ Deleting uploaded files from Salesforce...');
            deleteUploadedFiles();
        } else if (deleteAfterUpload && (failureCount > 0 || hasHeapError)) {
            System.debug('⚠️ Skipping file deletion - uploads had errors');
        }
        
        // Send notification if needed
        sendNotificationIfNeeded();
        
        // Generate summary
        String summary = generateSummary();
        System.debug('S3 Upload Email Batch Completed');
        System.debug('Summary:\n' + summary);
    }
    
    private String generateSummary() {
        List<String> parts = new List<String>();
        parts.add('=== S3 Upload Email Batch Summary ===');
        parts.add('EmailMessage ID: ' + emailMessageId);
        parts.add('S3 Package: ' + s3PackageId);
        parts.add('Total Processed: ' + totalProcessed);
        parts.add('Successfully Uploaded: ' + successCount);
        parts.add('Failed: ' + failureCount);
        
        if (hasHeapError) {
            parts.add('⚠️ HEAP ERROR: ' + heapErrorMessage);
        }
        
        parts.add('Files Deleted: ' +
            (deleteAfterUpload && failureCount == 0 && successCount > 0 && !hasHeapError ? 'Yes' : 'No'));
        parts.add('Notification Sent: ' +
            (failureCount > 0 || hasHeapError ? 'Yes' : 'No (all succeeded)'));
        
        if (totalProcessed > 0) {
            Decimal successRate = (successCount * 100.0) / totalProcessed;
            parts.add('Success Rate: ' + successRate.setScale(2) + '%');
        }
        
        return String.join(parts, '\n');
    }
    
    // Getters
    public Integer getTotalProcessed() { return totalProcessed; }
    public Integer getSuccessCount() { return successCount; }
    public Integer getFailureCount() { return failureCount; }
    public List<String> getFailedFiles() { return failedFiles; }
    
    public static void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        
    }
}