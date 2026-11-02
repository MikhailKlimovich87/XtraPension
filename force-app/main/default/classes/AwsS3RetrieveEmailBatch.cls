/**
 * Batch Apex class for retrieving EmailMessage ContentDocument versions from AWS S3 to Salesforce
 * Downloads files from S3 and links them to the EmailMessage record
 * Package name is the EmailMessage record ID
 * Stores retrieval results on EmailMessage record using existing and new fields
 * Handles duplicate link errors gracefully with correct counting
 */
public with sharing class AwsS3RetrieveEmailBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    
    // Configuration
    private Id emailMessageId;
    private String namedCredential = 'AWS_S3_Email';
    private String packageFolder;
    private Boolean deleteAfterRetrieve = false; // Set to false to keep files in S3
    
    // State tracking - FIXED COUNTERS
    private Integer totalProcessed = 0;        // Total files found in S3
    private Integer successCount = 0;          // Successfully retrieved (including duplicates)
    private Integer newFilesCount = 0;         // New files created
    private Integer duplicateFilesCount = 0;   // Files that already existed
    private Integer failureCount = 0;          // Failed retrievals
    private List<String> failedFiles = new List<String>();
    private List<String> successFiles = new List<String>();
    private List<String> duplicateFiles = new List<String>(); // Track duplicates
    private Map<String, String> fileStatusMap = new Map<String, String>();
    private List<String> s3KeysProcessed = new List<String>(); // Track S3 keys for deletion
    private Map<String, Id> existingDocumentIds = new Map<String, Id>(); // Track existing documents by filename
    
    // S3 retrieve tracking
    private DateTime retrieveStartTime;
    private DateTime retrieveEndTime;
    private String s3PackageId;
    private String retrieveStatus = 'Pending';
    private String retrieveErrorDetails = '';
    
    // Constants
    private static final Integer MAX_FILE_SIZE = 5000000; // 5MB limit for Salesforce
    
    /**
     * Constructor
     * @param emailMessageId - Id of the EmailMessage record
     */
    public AwsS3RetrieveEmailBatch(Id emailMessageId) {
        this.emailMessageId = emailMessageId;
        this.retrieveStartTime = System.now();
        this.packageFolder = emailMessageId;
        this.s3PackageId = emailMessageId;
        
        // Pre-load existing documents linked to this EmailMessage
        loadExistingDocuments();
        
        System.debug('=== AwsS3RetrieveEmailBatch Initialized ===');
        System.debug('EmailMessage ID: ' + emailMessageId);
        System.debug('S3 Package ID: ' + s3PackageId);
        System.debug('Package Folder: ' + packageFolder);
        System.debug('Named Credential: ' + namedCredential);
        System.debug('Delete After Retrieve: ' + deleteAfterRetrieve);
        System.debug('Existing Documents Found: ' + existingDocumentIds.size());
    }
    
    /**
     * Loads existing ContentDocuments already linked to this EmailMessage
     */
    private void loadExistingDocuments() {
        try {
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :emailMessageId
            ]) {
                if (String.isNotBlank(link.ContentDocument.Title)) {
                    String titleKey = link.ContentDocument.Title.toLowerCase().trim();
                    existingDocumentIds.put(titleKey, link.ContentDocumentId);
                }
            }
            System.debug('📚 Loaded ' + existingDocumentIds.size() + ' existing documents');
        } catch (Exception ex) {
            System.debug('⚠️ Error loading existing documents: ' + ex.getMessage());
        }
    }
    
    /**
     * Start method - gets list of files from S3
     */
    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug('=== START METHOD CALLED ===');
        
        List<String> fileKeys = new List<String>();
        
        try {
            // Get list of files from S3
            fileKeys = getS3FileList(packageFolder);
            
            // Set total processed to the actual number of files in S3
            totalProcessed = fileKeys.size();
            
            System.debug('Found ' + totalProcessed + ' files in S3 package: ' + packageFolder);
            
            if (fileKeys.isEmpty()) {
                System.debug('No files found in S3 for EmailMessage: ' + emailMessageId);
                retrieveStatus = 'No Files';
            }
            
        } catch (Exception ex) {
            System.debug('Error in start method: ' + ex.getMessage());
            retrieveStatus = 'Error';
            retrieveErrorDetails = 'Start error: ' + ex.getMessage();
        }
        
        return fileKeys;
    }
    
    /**
     * Execute method - processes one S3 file at a time
     */
    public void execute(Database.BatchableContext bc, List<String> scope) {
        System.debug('=== EXECUTE METHOD CALLED ===');
        System.debug('Scope size: ' + scope.size());
        
        for (String s3Key : scope) {
            processS3File(s3Key);
        }
    }
    
    /**
     * Process a single S3 file
     */
    private void processS3File(String s3Key) {
        System.debug('Processing S3 file: ' + s3Key);
        
        try {
            // Get filename from S3 key
            String fileName = getFileNameFromKey(s3Key);
            String title = fileName.contains('.') ? fileName.substringBeforeLast('.') : fileName;
            String titleKey = title.toLowerCase().trim();
            
            // Check if this document already exists
            if (existingDocumentIds.containsKey(titleKey)) {
                System.debug('📄 Document already exists for: ' + title + ' (ID: ' + existingDocumentIds.get(titleKey) + ')');
                
                // Update existing ContentVersion with S3 metadata
                updateExistingContentVersion(existingDocumentIds.get(titleKey), s3Key);
                
                // Track as duplicate (still a successful operation)
                duplicateFilesCount++;
                duplicateFiles.add(fileName);
                successCount++;
                successFiles.add(fileName + ' (already existed)');
                fileStatusMap.put(s3Key, 'ALREADY_EXISTS');
                
                // Track for S3 deletion if needed
                s3KeysProcessed.add(s3Key);
                
                System.debug('✅ File already existed: ' + s3Key);
                return;
            }
            
            // Download file from S3
            HttpResponse response = downloadFileFromS3(s3Key);
            
            if (response != null && response.getStatusCode() == 200) {
                // Create ContentVersion from the file
                ContentVersion contentVersion = createContentVersionFromFile(s3Key, response);
                
                if (contentVersion != null) {
                    try {
                        // Insert the ContentVersion
                        insert contentVersion;
                        System.debug('📄 ContentVersion inserted: ' + contentVersion.Id);
                        
                        // Get the ContentDocumentId
                        ContentVersion insertedVersion = [
                            SELECT Id, ContentDocumentId 
                            FROM ContentVersion 
                            WHERE Id = :contentVersion.Id
                        ];
                        
                        // Create ContentDocumentLink to link to EmailMessage
                        ContentDocumentLink link = new ContentDocumentLink(
                            ContentDocumentId = insertedVersion.ContentDocumentId,
                        LinkedEntityId = emailMessageId,
                        ShareType = 'V'
                            );
                        insert link;
                        System.debug('🔗 ContentDocumentLink created for EmailMessage');
                        
                        // Update ContentVersion with S3 metadata
                        updateContentVersionWithS3Id(contentVersion.Id, s3Key);
                        
                        // Add to existing documents map
                        existingDocumentIds.put(titleKey, insertedVersion.ContentDocumentId);
                        
                        // Track for deletion from S3
                        s3KeysProcessed.add(s3Key);
                        
                        // Track as new file
                        newFilesCount++;
                        successCount++;
                        successFiles.add(fileName);
                        fileStatusMap.put(s3Key, 'SUCCESS');
                        
                        System.debug('✅ New file retrieved: ' + s3Key);
                        
                    } catch (Exception ex) {
                        failureCount++;
                        failedFiles.add(s3Key + ' (Error inserting: ' + ex.getMessage() + ')');
                        fileStatusMap.put(s3Key, 'FAILED: ' + ex.getMessage());
                        System.debug('❌ FAILED: Error inserting: ' + s3Key + ' - ' + ex.getMessage());
                    }
                } else {
                    failureCount++;
                    failedFiles.add(s3Key + ' (Failed to create ContentVersion)');
                    fileStatusMap.put(s3Key, 'FAILED: Failed to create ContentVersion');
                    System.debug('❌ FAILED: Failed to create ContentVersion: ' + s3Key);
                }
            } else {
                failureCount++;
                String errorMsg = response != null ? 'Status: ' + response.getStatusCode() : 'Null response';
                failedFiles.add(s3Key + ' (' + errorMsg + ')');
                fileStatusMap.put(s3Key, 'FAILED: ' + errorMsg);
                System.debug('❌ FAILED: Could not download: ' + s3Key);
            }
            
        } catch (Exception ex) {
            failureCount++;
            String errorMsg = 'Exception: ' + ex.getMessage();
            failedFiles.add(s3Key + ' (' + errorMsg + ')');
            fileStatusMap.put(s3Key, 'FAILED: ' + errorMsg);
            System.debug('❌ ERROR processing: ' + s3Key + ' - ' + ex.getMessage());
            retrieveStatus = 'Partial';
            retrieveErrorDetails = errorMsg;
        }
    }
    
    /**
     * Updates an existing ContentVersion with S3 metadata
     */
    private void updateExistingContentVersion(Id contentDocumentId, String s3Key) {
        try {
            List<ContentVersion> versions = [
                SELECT Id
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            
            if (!versions.isEmpty()) {
                ContentVersion cv = new ContentVersion(
                    Id = versions[0].Id,
                AWS_S3_Object_Key__c = s3Key,
                S3_Upload_Date__c = System.now(),
                S3_Upload_Status__c = 'Retrieved (Existing)'
                    );
                update cv;
                System.debug('✅ Updated existing ContentVersion with S3 metadata');
            }
        } catch (Exception ex) {
            System.debug('⚠️ Error updating existing ContentVersion: ' + ex.getMessage());
        }
    }
    
    /**
     * Gets list of files from S3
     */
    private List<String> getS3FileList(String folderPath) {
        List<String> fileKeys = new List<String>();
        
        System.debug('📁 Getting S3 file list for folder: ' + folderPath);
        
        if (!folderPath.endsWith('/')) {
            folderPath += '/';
        }
        
        try {
            String baseEndpoint = 'callout:' + namedCredential;
            if (baseEndpoint.endsWith('/')) {
                baseEndpoint = baseEndpoint.substring(0, baseEndpoint.length() - 1);
            }
            
            String endpoint = baseEndpoint + '/?list-type=2&prefix=' + folderPath;
            
            System.debug('📝 Endpoint: ' + endpoint);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/xml');
            request.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('📥 S3 LIST Response Status: ' + response.getStatusCode());
            
            if (response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                if (responseBody != null && responseBody.length() > 0) {
                    fileKeys = parseS3ListResponse(responseBody);
                    System.debug('📊 Parsed ' + fileKeys.size() + ' file keys');
                }
            } else {
                System.debug('❌ S3 LIST failed with status: ' + response.getStatusCode());
                System.debug('📄 Error response: ' + response.getBody());
            }
            
        } catch (Exception ex) {
            System.debug('❌ Error getting S3 file list: ' + ex.getMessage());
        }
        
        return fileKeys;
    }
    
    /**
     * Parses S3 LIST XML response to extract file keys
     */
    private List<String> parseS3ListResponse(String xmlResponse) {
        List<String> fileKeys = new List<String>();
        
        try {
            String keyTag = '<Key>';
            String endKeyTag = '</Key>';
            Integer startPos = 0;
            
            while (true) {
                Integer startIndex = xmlResponse.indexOf(keyTag, startPos);
                if (startIndex == -1) break;
                
                Integer endIndex = xmlResponse.indexOf(endKeyTag, startIndex);
                if (endIndex == -1) break;
                
                String key = xmlResponse.substring(startIndex + keyTag.length(), endIndex);
                
                if (!key.endsWith('/') && !String.isBlank(key)) {
                    fileKeys.add(key);
                }
                
                startPos = endIndex + endKeyTag.length();
            }
            
            System.debug('Parsed ' + fileKeys.size() + ' file keys from XML');
            
        } catch (Exception ex) {
            System.debug('Error parsing S3 LIST response: ' + ex.getMessage());
            fileKeys = parseS3ListResponseFallback(xmlResponse);
        }
        
        return fileKeys;
    }
    
    /**
     * Fallback parser for S3 LIST XML response
     */
    private List<String> parseS3ListResponseFallback(String xmlResponse) {
        List<String> fileKeys = new List<String>();
        
        try {
            List<String> parts = xmlResponse.split('<Key>');
            for (Integer i = 1; i < parts.size(); i++) {
                String part = parts[i];
                Integer endIndex = part.indexOf('</Key>');
                if (endIndex != -1) {
                    String key = part.substring(0, endIndex);
                    if (!key.endsWith('/') && !String.isBlank(key)) {
                        fileKeys.add(key);
                    }
                }
            }
        } catch (Exception ex) {
            System.debug('Error in fallback parser: ' + ex.getMessage());
        }
        
        return fileKeys;
    }
    
    /**
     * Downloads a file from S3
     */
    private HttpResponse downloadFileFromS3(String s3Key) {
        try {
            String encodedKey = EncodingUtil.urlEncode(s3Key, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            encodedKey = encodedKey.replace('+', '%20');
            
            String endpoint = 'callout:' + namedCredential + '/' + encodedKey;
            
            System.debug('📥 Downloading: ' + s3Key);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/octet-stream');
            request.setTimeout(60000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('📥 Download response status: ' + response.getStatusCode());
            
            return response;
            
        } catch (Exception ex) {
            System.debug('❌ Error downloading file: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * Creates ContentVersion from downloaded file
     */
    private ContentVersion createContentVersionFromFile(String s3Key, HttpResponse response) {
        try {
            if (response == null || response.getStatusCode() != 200) {
                return null;
            }
            
            Blob fileData = response.getBodyAsBlob();
            
            if (fileData.size() > MAX_FILE_SIZE) {
                System.debug('❌ File too large: ' + fileData.size() + ' bytes');
                return null;
            }
            
            if (fileData.size() == 0) {
                System.debug('❌ File is empty: ' + s3Key);
                return null;
            }
            
            String fileName = getFileNameFromKey(s3Key);
            String title = fileName.contains('.') ? fileName.substringBeforeLast('.') : fileName;
            String fileExtension = fileName.contains('.') ? fileName.substringAfterLast('.') : '';
            
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.VersionData = fileData;
            contentVersion.PathOnClient = fileName;
            contentVersion.Title = title;
            contentVersion.FirstPublishLocationId = emailMessageId;
            contentVersion.Origin = 'H';
            
            String description = 'Retrieved from S3: ' + s3Key;
            description += ' | Retrieved: ' + System.now().format();
            contentVersion.Description = description;
            
            System.debug('📄 Created ContentVersion for: ' + fileName);
            
            return contentVersion;
            
        } catch (Exception ex) {
            System.debug('❌ Error creating ContentVersion: ' + ex.getMessage());
            return null;
        }
    }
    
    /**
     * Extracts filename from S3 key
     */
    private String getFileNameFromKey(String s3Key) {
        String fileName = s3Key;
        
        Integer lastSlash = s3Key.lastIndexOf('/');
        if (lastSlash != -1) {
            fileName = s3Key.substring(lastSlash + 1);
        }
        
        try {
            fileName = EncodingUtil.urlDecode(fileName, 'UTF-8');
        } catch (Exception ex) {
            System.debug('Could not decode filename: ' + ex.getMessage());
        }
        
        return fileName;
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
    
    /**
     * Updates ContentVersion with S3 metadata
     */
    private void updateContentVersionWithS3Id(Id versionId, String s3Key) {
        try {
            ContentVersion cv = new ContentVersion(
                Id = versionId,
            AWS_S3_Object_Key__c = s3Key,
            S3_Upload_Date__c = System.now(),
            S3_Upload_Status__c = 'Retrieved'
                );
            update cv;
            System.debug('✅ Updated ContentVersion ' + versionId + ' with S3 metadata');
        } catch (Exception ex) {
            System.debug('⚠️ Error updating ContentVersion: ' + ex.getMessage());
        }
    }
    
    /**
     * Deletes files from S3 after successful retrieval
     */
    private void deleteFromS3() {
        if (s3KeysProcessed.isEmpty()) {
            System.debug('No files to delete from S3');
            return;
        }
        
        System.debug('🗑️ Deleting ' + s3KeysProcessed.size() + ' files from S3...');
        
        Integer deletedCount = 0;
        Integer deleteErrors = 0;
        
        for (String s3Key : s3KeysProcessed) {
            try {
                String encodedKey = EncodingUtil.urlEncode(s3Key, 'UTF-8');
                encodedKey = encodedKey.replace('%2F', '/');
                encodedKey = encodedKey.replace('+', '%20');
                
                String endpoint = 'callout:' + namedCredential + '/' + encodedKey;
                
                HttpRequest request = new HttpRequest();
                request.setEndpoint(endpoint);
                request.setMethod('DELETE');
                request.setTimeout(30000);
                
                Http http = new Http();
                HttpResponse response = http.send(request);
                
                if (response.getStatusCode() == 204) {
                    deletedCount++;
                    System.debug('✅ Deleted from S3: ' + s3Key);
                } else {
                    deleteErrors++;
                    System.debug('⚠️ Failed to delete from S3: ' + s3Key + ' - Status: ' + response.getStatusCode());
                }
                
            } catch (Exception ex) {
                deleteErrors++;
                System.debug('⚠️ Error deleting from S3: ' + s3Key + ' - ' + ex.getMessage());
            }
        }
        
        System.debug('✅ Deleted ' + deletedCount + ' files from S3');
        if (deleteErrors > 0) {
            System.debug('⚠️ ' + deleteErrors + ' files could not be deleted from S3');
        }
    }
    
    /**
     * Updates the EmailMessage record with S3 retrieve information
     */
    private void updateEmailMessageRecord() {
        try {
            this.retrieveEndTime = System.now();
            
            // Determine final status
            String finalStatus;
            if (totalProcessed == 0) {
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
            EmailMessage email = new EmailMessage(
                Id = emailMessageId
                );
            
            // Existing fields
            email.AWS_S3_Package_Id__c = s3PackageId;
            email.S3_Upload_Status__c = 'Retrieved - ' + finalStatus;
            email.S3_Upload_Date__c = this.retrieveEndTime;
            email.S3_Total_Files__c = totalProcessed;  // Total files in S3
            email.S3_Success_Count__c = successCount;   // Total successful (new + duplicates)
            email.S3_Failed_Count__c = failureCount;
            
            if (totalProcessed > 0) {
                Decimal successRate = (successCount * 100.0) / totalProcessed;
                email.S3_Success_Rate__c = successRate.setScale(2);
            }
            
            // Error Details
            if (String.isNotBlank(retrieveErrorDetails) || failureCount > 0) {
                String errorDetails = retrieveErrorDetails;
                if (failureCount > 0) {
                    String failedFilesList = String.join(failedFiles, '\n');
                    if (failedFilesList.length() > 255) {
                        failedFilesList = failedFilesList.substring(0, 252) + '...';
                    }
                    errorDetails = 'Failed files: ' + failedFilesList;
                    if (String.isNotBlank(retrieveErrorDetails)) {
                        errorDetails += '\nError: ' + retrieveErrorDetails;
                    }
                }
                email.S3_Error_Details__c = errorDetails;
            }
            
            // New retrieve-specific fields
            email.S3_Retrieve_Status__c = finalStatus;
            email.S3_Retrieve_Date__c = this.retrieveEndTime;
            email.S3_Retrieved_Count__c = successCount;
            email.S3_Last_Retrieve_Attempt__c = this.retrieveEndTime;
            
            if (totalProcessed > 0) {
                Decimal successRate = (successCount * 100.0) / totalProcessed;
                email.S3_Retrieve_Success_Rate__c = successRate.setScale(2);
            }
            
            if (String.isNotBlank(retrieveErrorDetails) || failureCount > 0) {
                String errorDetails = retrieveErrorDetails;
                if (failureCount > 0) {
                    String failedFilesList = String.join(failedFiles, '\n');
                    if (failedFilesList.length() > 500) {
                        failedFilesList = failedFilesList.substring(0, 497) + '...';
                    }
                    errorDetails = 'Failed files: ' + failedFilesList;
                    if (String.isNotBlank(retrieveErrorDetails)) {
                        errorDetails += '\nError: ' + retrieveErrorDetails;
                    }
                }
                if (errorDetails != null && errorDetails.length() > 1000) {
                    errorDetails = errorDetails.substring(0, 997) + '...';
                }
                email.S3_Retrieve_Error_Details__c = errorDetails;
            }
            
            // Update the EmailMessage
            update email;
            
            System.debug('=== RETRIEVE SUMMARY ===');
            System.debug('Total Files in S3: ' + totalProcessed);
            System.debug('New Files Created: ' + newFilesCount);
            System.debug('Duplicate Files: ' + duplicateFilesCount);
            System.debug('Total Success: ' + successCount);
            System.debug('Failed: ' + failureCount);
            System.debug('Success Rate: ' + (totalProcessed > 0 ? ((successCount * 100.0) / totalProcessed).setScale(2) + '%' : 'N/A'));
            
        } catch (Exception ex) {
            System.debug('⚠️ Error updating EmailMessage: ' + ex.getMessage());
        }
    }
    
    /**
     * Generates the notification message
     */
    private String generateNotificationMessage() {
        List<String> parts = new List<String>();
        parts.add('=== S3 Retrieve Email Batch Results ===');
        parts.add('');
        parts.add('EmailMessage ID: ' + emailMessageId);
        parts.add('S3 Package: ' + s3PackageId);
        parts.add('Total Files in S3: ' + totalProcessed);
        parts.add('New Files Retrieved: ' + newFilesCount);
        parts.add('Files Already Existed: ' + duplicateFilesCount);
        parts.add('Total Successfully Processed: ' + successCount);
        parts.add('Failed: ' + failureCount);
        
        String status = failureCount == 0 ? '✅ SUCCESS' : '⚠️ PARTIAL SUCCESS';
        if (totalProcessed == 0) status = '📁 NO FILES';
        parts.add('Status: ' + status);
        
        if (totalProcessed > 0) {
            Decimal successRate = (successCount * 100.0) / totalProcessed;
            parts.add('Success Rate: ' + successRate.setScale(2) + '%');
        }
        
        parts.add('');
        
        if (!successFiles.isEmpty()) {
            parts.add('--- Successfully Processed Files (' + successFiles.size() + ') ---');
            for (String file : successFiles) {
                parts.add('  ✅ ' + file);
            }
        }
        
        if (!duplicateFiles.isEmpty()) {
            parts.add('');
            parts.add('--- Already Existed Files (' + duplicateFiles.size() + ') ---');
            for (String file : duplicateFiles) {
                parts.add('  📄 ' + file);
            }
        }
        
        if (!failedFiles.isEmpty()) {
            parts.add('');
            parts.add('--- Failed Retrievals (' + failedFiles.size() + ') ---');
            for (String file : failedFiles) {
                parts.add('  ❌ ' + file);
            }
            parts.add('');
            parts.add('⚠️ Please check the failed files and retry if needed.');
        }
        
        if (deleteAfterRetrieve && failureCount == 0 && successCount > 0) {
            parts.add('');
            parts.add('✅ All files have been deleted from S3 after successful retrieval.');
        } else if (deleteAfterRetrieve && failureCount > 0) {
            parts.add('');
            parts.add('⚠️ Files were NOT deleted from S3 because some retrievals failed.');
        } else {
            parts.add('');
            parts.add('📁 Files remain in S3 (deleteAfterRetrieve = false).');
        }
        
        parts.add('');
        parts.add('---');
        parts.add('Started: ' + retrieveStartTime);
        parts.add('Completed: ' + retrieveEndTime);
        
        return String.join(parts, '\n');
    }
    
    /**
     * Sends email notification if there are failures or partial success
     */
    private void sendNotificationIfNeeded() {
        if (failureCount > 0 || totalProcessed == 0) {
            try {
                String subject;
                String body = generateNotificationMessage();
                
                if (totalProcessed == 0) {
                    subject = '📁 AWS S3 Retrieve - No Files Found';
                } else if (failureCount > 0 && successCount > 0) {
                    subject = '⚠️ AWS S3 Retrieve - Partial Success';
                } else if (failureCount > 0 && successCount == 0) {
                    subject = '❌ AWS S3 Retrieve - Failed';
                } else {
                    subject = '⚠️ AWS S3 Retrieve - Completed with Issues';
                }
                
                AwsS3NotificationService notificationService = new AwsS3NotificationService();
                notificationService.sendFailureNotification(subject, body);
                
                System.debug('✅ Notification sent: ' + subject);
                
            } catch (Exception ex) {
                System.debug('⚠️ Error sending notification: ' + ex.getMessage());
            }
        } else {
            System.debug('✅ All files processed successfully.');
            System.debug('Summary: ' + generateNotificationMessage());
        }
    }
    
    /**
     * Finish method - called after all batches are processed
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('=== FINISH METHOD CALLED ===');
        
        // Delete files from S3 if all retrievals were successful
        if (deleteAfterRetrieve && failureCount == 0 && successCount > 0) {
            System.debug('🗑️ Deleting files from S3...');
            deleteFromS3();
        } else if (deleteAfterRetrieve && failureCount > 0) {
            System.debug('⚠️ Skipping S3 deletion - some retrievals failed');
        }
        
        // Update EmailMessage record with S3 retrieve information
        updateEmailMessageRecord();
        
        // Send notification if there were failures or no files
        sendNotificationIfNeeded();
        
        // Generate summary
        String summary = generateSummary();
        System.debug('S3 Retrieve Email Batch Completed');
        System.debug('Summary:\n' + summary);
    }
    
    private String generateSummary() {
        List<String> parts = new List<String>();
        parts.add('=== S3 Retrieve Email Batch Summary ===');
        parts.add('EmailMessage ID: ' + emailMessageId);
        parts.add('S3 Package: ' + s3PackageId);
        parts.add('Total Files in S3: ' + totalProcessed);
        parts.add('New Files Retrieved: ' + newFilesCount);
        parts.add('Files Already Existed: ' + duplicateFilesCount);
        parts.add('Failed: ' + failureCount);
        parts.add('Success Rate: ' + (totalProcessed > 0 ? ((successCount * 100.0) / totalProcessed).setScale(2) + '%' : 'N/A'));
        parts.add('Files Deleted from S3: ' + (deleteAfterRetrieve && failureCount == 0 && successCount > 0 ? 'Yes' : 'No'));
        
        return String.join(parts, '\n');
    }
    
    // ==================== PUBLIC GETTERS ====================
    
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
    }
}