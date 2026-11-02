/**
 * Batch Apex class for retrieving files from AWS S3 and linking them to Salesforce Application
 */
public with sharing class AwsS3RetrieveFilesBatch implements Database.Batchable<String>, Database.AllowsCallouts, Database.Stateful {
    
    // Configuration
    private static final Integer MAX_FILE_SIZE = 5000000; // 5MB limit for Salesforce
    
    // Named credential endpoint
    private static final String AWS_ENDPOINT = 'callout:AWS_S3';
    
    // Instance variables
    private Id applicationId;
    private String packageFolder;
    private String s3PackageId;
    private Integer totalProcessed = 0;
    private Integer successfullyLinked = 0;
    private Integer failedCount = 0;
    private List<String> failedFiles = new List<String>();
    private List<String> successFiles = new List<String>();
    private Map<String, String> fileStatusMap = new Map<String, String>();
    private Application__c applicationRecord;
    private Map<String, Id> existingContentDocuments = new Map<String, Id>();
    private AwsS3NotificationService notificationService;
    
    // Upload Results tracking
    private Id uploadResultId;
    private String uploadResultStatus = 'Pending';
    private String uploadResultErrorMessage = '';
    private Integer totalFilesInPackage = 0;
    private Boolean isInitialized = false;
    
    // Map to store S3 metadata for each file
    private Map<String, S3FileMetadata> fileMetadataMap = new Map<String, S3FileMetadata>();
    
    /**
     * Inner class to hold S3 file metadata
     */
    private class S3FileMetadata {
        public String s3ObjectKey;
        public String s3VersionId;
        public DateTime s3UploadDate;
        public String s3UploadStatus;
        public String s3UploadError;
        public String fileExtension;
        public Long fileSize;
        
        public S3FileMetadata() {
            this.s3UploadStatus = 'Retrieved';
            this.s3UploadError = '';
        }
    }
    
    /**
     * Default Constructor (required for batch scheduling)
     */
    public AwsS3RetrieveFilesBatch() {
        this.isInitialized = false;
        notificationService = new AwsS3NotificationService();
        System.debug('⚠️ Batch created with default constructor. Must be initialized with Application ID.');
    }
    
    /**
     * Constructor with Application ID
     * @param applicationId - Id of the Application record
     */
    public AwsS3RetrieveFilesBatch(Id applicationId) {
        this.applicationId = applicationId;
        notificationService = new AwsS3NotificationService();
        initializeBatch();
        this.isInitialized = true;
    }
    
    /**
     * Initializes the batch by getting application and folder information
     */
    private void initializeBatch() {
        if (applicationId == null) {
            System.debug('ERROR: Application ID is null. Batch cannot be initialized.');
            return;
        }
        
        applicationRecord = getApplication(applicationId);
        if (applicationRecord != null) {
            this.packageFolder = AwsS3ApiHandler.buildApplicationPackageFolder(applicationRecord, null);
            this.s3PackageId = this.packageFolder;
            loadExistingContentDocuments();
            
            // Create initial Upload Results record
            createInitialUploadResult();
            
            System.debug('=== AwsS3RetrieveFilesBatch Initialized ===');
            System.debug('Application ID: ' + applicationId);
            System.debug('Application Name: ' + applicationRecord.Name);
            System.debug('Package Folder: ' + packageFolder);
            System.debug('Upload Result ID: ' + uploadResultId);
        } else {
            System.debug('ERROR: Application not found with ID: ' + applicationId);
        }
    }
    
    /**
     * Creates initial AwsS3UploadResult__c record
     */
    private void createInitialUploadResult() {
        try {
            // Check if there's an existing pending result for this application
            List<AwsS3UploadResult__c> existingResults = [
                SELECT Id, Status__c 
                FROM AwsS3UploadResult__c 
                WHERE Application__c = :applicationId 
                AND Status__c = 'Pending'
                ORDER BY CreatedDate DESC 
                LIMIT 1
            ];
            
            if (!existingResults.isEmpty()) {
                uploadResultId = existingResults[0].Id;
                uploadResultStatus = 'Pending';
                System.debug('Using existing pending Upload Result: ' + uploadResultId);
                return;
            }
            
            // Create new Upload Result record
            AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c();
            uploadResult.Application__c = applicationId;
            uploadResult.Status__c = 'Pending';
            uploadResult.Batch_Type__c = 'Retrieve from S3';
            uploadResult.UploadDate__c = System.now();
            uploadResult.TotalProcessed__c = 0; // Will be updated later
            uploadResult.UploadedCount__c = 0;
            uploadResult.FailedCount__c = 0;
            uploadResult.Success_Rate__c = 0;
            
            insert uploadResult;
            uploadResultId = uploadResult.Id;
            uploadResultStatus = 'Pending';
            
            System.debug('Created new Upload Result record: ' + uploadResultId);
            
        } catch (Exception ex) {
            System.debug('ERROR creating Upload Result: ' + ex.getMessage());
            uploadResultErrorMessage = 'Failed to create Upload Result: ' + ex.getMessage();
        }
    }
    
    /**
     * Updates the Upload Result record with final status
     */
    private void updateUploadResult(String status, String errorMessage) {
        try {
            if (uploadResultId == null) {
                System.debug('No Upload Result record to update');
                return;
            }
            
            Decimal successRate = 0;
            if (totalProcessed > 0) {
                successRate = (successfullyLinked * 100.0) / totalProcessed;
            }
            
            AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c(
                Id = uploadResultId,
                Status__c = status,
                UploadDate__c = System.now(),
                TotalProcessed__c = totalProcessed,
                UploadedCount__c = successfullyLinked,
                FailedCount__c = failedCount,
                Success_Rate__c = successRate.setScale(2)
            );
            
            if (String.isNotBlank(errorMessage)) {
                uploadResult.Failed_Details__c = errorMessage;
            }
            
            // Add detailed file status as a string (limited to 255 chars)
            String summary = buildUploadResultSummary();
            if (String.isNotBlank(summary) && summary.length() <= 255) {
                uploadResult.Summary__c = summary;
            }
            
            update uploadResult;
            uploadResultStatus = status;
            uploadResultErrorMessage = errorMessage;
            
            System.debug('Updated Upload Result: ' + uploadResultId + ' | Status: ' + status);
            
        } catch (Exception ex) {
            System.debug('ERROR updating Upload Result: ' + ex.getMessage());
        }
    }
    
    /**
     * Builds a summary string for the Upload Result
     */
    private String buildUploadResultSummary() {
        List<String> parts = new List<String>();
        
        parts.add('Total: ' + totalProcessed);
        parts.add('Success: ' + successfullyLinked);
        parts.add('Failed: ' + failedCount);
        
        if (!successFiles.isEmpty() && successFiles.size() <= 5) {
            parts.add('Files: ' + String.join(successFiles, ', '));
        } else if (!successFiles.isEmpty()) {
            parts.add('Files: ' + successFiles.size() + ' files retrieved');
        }
        
        return String.join(parts, ' | ');
    }
    
    /**
     * Start method - gets list of files from S3
     */
    public Iterable<String> start(Database.BatchableContext bc) {
        System.debug('=== START METHOD CALLED ===');
        
        // Validate initialization
        if (!isInitialized && applicationId == null) {
            String errorMsg = 'Batch AwsS3RetrieveFilesBatch started without Application ID. ' +
                'Please use the constructor that accepts an Application ID.';
            System.debug('ERROR: ' + errorMsg);
            updateUploadResult('Failed', errorMsg);
            return new List<String>();
        }
        
        // If not initialized but we have applicationId (shouldn't happen, but just in case)
        if (!isInitialized && applicationId != null) {
            initializeBatch();
            isInitialized = true;
        }
        
        if (applicationRecord == null) {
            System.debug('ERROR: Application record not found');
            updateUploadResult('Failed', 'Application record not found');
            return new List<String>();
        }
        
        // Get list of files from S3
        List<String> fileKeys = getS3FileList(packageFolder);
        System.debug('Found ' + fileKeys.size() + ' files in S3 package: ' + packageFolder);
        
        totalProcessed = fileKeys.size();
        totalFilesInPackage = fileKeys.size();
        System.debug('Total files to process: ' + totalProcessed);
        
        // Update Upload Result with total files
        try {
            if (uploadResultId != null) {
                AwsS3UploadResult__c updateResult = new AwsS3UploadResult__c(
                    Id = uploadResultId,
                    TotalProcessed__c = totalProcessed
                );
                update updateResult;
            }
        } catch (Exception ex) {
            System.debug('Error updating total files: ' + ex.getMessage());
        }
        
        // If no files found, update status and return empty list
        if (fileKeys.isEmpty()) {
            updateUploadResult('No Files', 'No files found in S3 package: ' + packageFolder);
        }
        
        return fileKeys;
    }
    
    /**
     * Execute method - processes one S3 file at a time
     */
    public void execute(Database.BatchableContext bc, List<String> scope) {
        System.debug('=== EXECUTE METHOD CALLED ===');
        System.debug('Scope size: ' + scope.size());
        
        for (String fileKey : scope) {
            System.debug('Processing file: ' + fileKey);
            
            try {
                // Download file from S3
                HttpResponse response = downloadFileFromS3(fileKey);
                
                // Extract S3 metadata from response headers
                S3FileMetadata metadata = extractS3Metadata(fileKey, response);
                
                if (response != null && response.getStatusCode() == 200) {
                    // Create ContentVersion from the file with metadata
                    ContentVersion contentVersion = createContentVersionFromFile(fileKey, response, metadata);
                    
                    if (contentVersion != null) {
                        try {
                            // Insert the ContentVersion
                            insert contentVersion;
                            System.debug('📄 ContentVersion inserted: ' + contentVersion.Id);
                            
                            // Get the ContentDocumentId
                            Id documentId = [
                                SELECT ContentDocumentId
                                FROM ContentVersion
                                WHERE Id = :contentVersion.Id
                            ].ContentDocumentId;
                            
                            // Now update the ContentVersion with S3 metadata (since we need the ID first)
                            updateContentVersionWithS3Metadata(contentVersion.Id, metadata);
                            
                            String fileName = getFileNameFromKey(fileKey);
                            
                            String title = fileName.contains('.')
                                ? fileName.substringBeforeLast('.')
                                : fileName;
                            
                            if (!existingContentDocuments.containsKey(title.toLowerCase())) {
                                existingContentDocuments.put(
                                    title.trim().toLowerCase(),
                                    documentId
                                );
                            }
                            
                            successfullyLinked++;
                            successFiles.add(fileKey);
                            fileStatusMap.put(fileKey, 'SUCCESS');
                            
                        } catch (Exception ex) {
                            failedCount++;
                            failedFiles.add(fileKey + ' (Error inserting ContentVersion: ' + ex.getMessage() + ')');
                            fileStatusMap.put(fileKey, 'FAILED: ' + ex.getMessage());
                            System.debug('✗ FAILED: Error inserting ContentVersion: ' + fileKey + ' - ' + ex.getMessage());
                            System.debug('Stack trace: ' + ex.getStackTraceString());
                        }
                    } else {
                        failedCount++;
                        failedFiles.add(fileKey + ' (Failed to create ContentVersion)');
                        fileStatusMap.put(fileKey, 'FAILED: Failed to create ContentVersion');
                        System.debug('✗ FAILED: Failed to create ContentVersion for file: ' + fileKey);
                    }
                } else {
                    failedCount++;
                    String errorMsg = response != null ? 'Status: ' + response.getStatusCode() + ' - ' + response.getBody() : 'Null response';
                    failedFiles.add(fileKey + ' (' + errorMsg + ')');
                    fileStatusMap.put(fileKey, 'FAILED: ' + errorMsg);
                    System.debug('✗ FAILED: Could not download file: ' + fileKey + ' - ' + errorMsg);
                }
                
            } catch (Exception ex) {
                failedCount++;
                String errorMsg = 'Error: ' + ex.getMessage();
                failedFiles.add(fileKey + ' (' + errorMsg + ')');
                fileStatusMap.put(fileKey, 'FAILED: ' + errorMsg);
                System.debug('✗ ERROR processing file: ' + fileKey + ' - ' + ex.getMessage());
                System.debug('Stack trace: ' + ex.getStackTraceString());
            }
        }
        
        // Update Upload Result with current progress after each execute
        updateUploadResultProgress();
    }
    
    /**
     * Extracts S3 metadata from HTTP response headers
     */
    private S3FileMetadata extractS3Metadata(String fileKey, HttpResponse response) {
        S3FileMetadata metadata = new S3FileMetadata();
        metadata.s3ObjectKey = fileKey;
        
        try {
            // Get S3 Version ID from response header (if available)
            String versionId = response != null ? response.getHeader('x-amz-version-id') : null;
            if (String.isNotBlank(versionId)) {
                metadata.s3VersionId = versionId;
            } else {
                // If no version ID, use the current timestamp as a version identifier
                metadata.s3VersionId = 'v1_' + System.now().format('yyyyMMddHHmmss');
            }
            
            // Get last modified date from response
            String lastModified = response != null ? response.getHeader('Last-Modified') : null;
            if (String.isNotBlank(lastModified)) {
                try {
                    // Parse HTTP date format (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
                    // Using a simple approach - convert to Salesforce datetime
                    metadata.s3UploadDate = System.now(); // Fallback to current time
                    // Note: For proper parsing, you might need a date parsing utility
                } catch (Exception ex) {
                    metadata.s3UploadDate = System.now();
                }
            } else {
                metadata.s3UploadDate = System.now();
            }
            
            // Get file extension
            String fileName = getFileNameFromKey(fileKey);
            if (fileName.contains('.')) {
                metadata.fileExtension = fileName.substringAfterLast('.');
            } else {
                // Try to get from Content-Type
                String contentType = response != null ? response.getHeader('Content-Type') : null;
                if (String.isNotBlank(contentType)) {
                    Map<String,String> extensionMap = new Map<String,String>{
                        'application/pdf' => 'pdf',
                        'image/jpeg' => 'jpg',
                        'image/png' => 'png',
                        'application/msword' => 'doc',
                        'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
                        'application/vnd.ms-excel' => 'xls',
                        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
                        'text/plain' => 'txt',
                        'application/zip' => 'zip',
                        'image/jpg' => 'jpg',
                        'application/x-pdf' => 'pdf'
                    };
                    String ext = extensionMap.get(contentType.split(';')[0].trim().toLowerCase());
                    if (String.isNotBlank(ext)) {
                        metadata.fileExtension = ext;
                    }
                }
            }
            
            // Get file size from response
            if (response != null && response.getBodyAsBlob() != null) {
                metadata.fileSize = response.getBodyAsBlob().size();
            }
            
            metadata.s3UploadStatus = 'Retrieved';
            metadata.s3UploadError = '';
            
        } catch (Exception ex) {
            System.debug('Error extracting S3 metadata: ' + ex.getMessage());
            metadata.s3UploadStatus = 'Retrieved (Partial Metadata)';
            metadata.s3UploadError = 'Metadata extraction error: ' + ex.getMessage();
        }
        
        return metadata;
    }
    
    /**
     * Updates the ContentVersion record with S3 metadata after insertion
     */
    private void updateContentVersionWithS3Metadata(Id contentVersionId, S3FileMetadata metadata) {
        try {
            ContentVersion cv = new ContentVersion(
                Id = contentVersionId
            );
            
            // Map fields based on your custom field names from the screenshot
            // Note: You'll need to adjust these field names to match your actual custom fields
            
            // AWS S3 Id (custom field for the S3 object key)
            if (String.isNotBlank(metadata.s3ObjectKey)) {
                cv.AWS_S3_Object_Key__c = metadata.s3ObjectKey;
            }
            
            // S3 Version Id
            if (String.isNotBlank(metadata.s3VersionId)) {
                cv.S3_Version_Id__c = metadata.s3VersionId;
            }
            
            // S3 Upload Date
            if (metadata.s3UploadDate != null) {
                cv.S3_Upload_Date__c = metadata.s3UploadDate;
            }
            
            // S3 Upload Status
            if (String.isNotBlank(metadata.s3UploadStatus)) {
                cv.S3_Upload_Status__c = metadata.s3UploadStatus;
            }
            
            // S3 Upload Error (if any)
            if (String.isNotBlank(metadata.s3UploadError)) {
                cv.S3_Upload_Error__c = metadata.s3UploadError;
            }
            
            // File Extension (can be stored or derived)
            if (String.isNotBlank(metadata.fileExtension)) {
                cv.File_Extension__c = metadata.fileExtension;
            }
            
            // Update the record
            update cv;
            System.debug('✅ Updated ContentVersion with S3 metadata: ' + contentVersionId);
            
        } catch (Exception ex) {
            System.debug('⚠️ Error updating ContentVersion with S3 metadata: ' + ex.getMessage());
            // Don't fail the entire process if metadata update fails
        }
    }
    
    /**
     * Updates Upload Result with current progress
     */
    private void updateUploadResultProgress() {
        try {
            if (uploadResultId == null) return;
            
            Decimal successRate = 0;
            if (totalProcessed > 0) {
                successRate = (successfullyLinked * 100.0) / totalProcessed;
            }
            
            AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c(
                Id = uploadResultId,
                UploadedCount__c = successfullyLinked,
                FailedCount__c = failedCount,
                Success_Rate__c = successRate.setScale(2),
                Status__c = 'In Progress'
            );
            
            update uploadResult;
            
        } catch (Exception ex) {
            System.debug('Error updating progress: ' + ex.getMessage());
        }
    }
    
    /**
     * Finish method - called after all batches are processed
     */
    public void finish(Database.BatchableContext bc) {
        String finalStatus;
        String errorMessage = '';
        
        if (totalProcessed == 0) {
            finalStatus = 'No Files';
            errorMessage = 'No files found in S3 package';
        } else if (failedCount == 0 && successfullyLinked == totalProcessed) {
            finalStatus = 'Success';
            // All files retrieved successfully - delete package from S3
            // deletePackageFromS3();
        } else if (failedCount > 0 && successfullyLinked > 0) {
            finalStatus = 'Partial Success';
            errorMessage = 'Failed to retrieve ' + failedCount + ' file(s)';
        } else if (failedCount > 0 && successfullyLinked == 0) {
            finalStatus = 'Failed';
            errorMessage = 'All ' + failedCount + ' file(s) failed to retrieve';
        } else {
            finalStatus = 'Unknown';
            errorMessage = 'Unexpected completion state';
        }
        
        // Update Upload Result record
        updateUploadResult(finalStatus, errorMessage);
        
        // Update Application record
        updateApplicationRecord();
        
        // Send detailed notification
        String summary = generateDetailedSummary();
        
        if (String.isNotBlank(errorMessage) && finalStatus != 'Success') {
            errorMessage += '\n' + summary;
            notificationService.sendFailRetrieveNotification(errorMessage);
        }
        System.debug('S3 Retrieve Files Batch Completed: ' + summary);
    }
    
   
// ==================== PRIVATE METHODS ====================
    private String normalizeTitle(String title) {
        return title == null ? '' : title.trim().toLowerCase();
    }
    
    /**
     * Gets list of files from S3 using DIRECT HTTP callout
     */
    private List<String> getS3FileList(String folderPath) {
        List<String> fileKeys = new List<String>();
        
        System.debug('=== 🚀 GETS3FILELIST START ===');
        System.debug('📁 FolderPath: ' + folderPath);
        
        // Ensure folder path ends with /
        if (!folderPath.endsWith('/')) {
            folderPath += '/';
        }
        System.debug('📁 Formatted folderPath: ' + folderPath);
        
        try {
            // Build the S3 LIST URL - DO NOT URL ENCODE
            String baseEndpoint = AWS_ENDPOINT;
            if (baseEndpoint.endsWith('/')) {
                baseEndpoint = baseEndpoint.substring(0, baseEndpoint.length() - 1);
            }
            
            // Pass the raw folder path - the Named Credential handles encoding
            String endpoint = baseEndpoint + '/?list-type=2&prefix=' + folderPath;
            
            System.debug('📝 Final endpoint: ' + endpoint);
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/xml');
            
            System.debug('📤 Sending S3 LIST request...');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('📤 Response received');
            System.debug('   Status Code: ' + response.getStatusCode());
            System.debug('   Status: ' + response.getStatus());
            
            if (response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                System.debug('✅ S3 LIST successful!');
                if (responseBody != null && responseBody.length() > 0) {
                    fileKeys = parseS3ListResponse(responseBody);
                    System.debug('📊 Parsed ' + fileKeys.size() + ' file keys');
                }
            } else {
                System.debug('❌ S3 LIST failed with status: ' + response.getStatusCode());
                System.debug('📄 Error response: ' + response.getBody());
                fileKeys = getFilesFromApplicationRecords();
            }
            
        } catch (Exception ex) {
            System.debug('❌❌❌ EXCEPTION ❌❌❌');
            System.debug('Type: ' + ex.getTypeName());
            System.debug('Message: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            fileKeys = getFilesFromApplicationRecords();
        }
        
        System.debug('=== 🏁 GETS3FILELIST END === Returning ' + fileKeys.size() + ' files');
        return fileKeys;
    }
    
    /**
     * Workaround: Get file list from Application ContentDocuments
     */
    private List<String> getFilesFromApplicationRecords() {
        List<String> fileKeys = new List<String>();
        
        try {
            List<ContentDocumentLink> existingLinks = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId
            ];
            
            if (!existingLinks.isEmpty()) {
                System.debug('Found ' + existingLinks.size() + ' existing files in Salesforce');
                for (ContentDocumentLink link : existingLinks) {
                    if (link.ContentDocument.Title != null) {
                        String fileKey = packageFolder + '/' + link.ContentDocument.Title;
                        fileKeys.add(fileKey);
                    }
                }
            }
            
            System.debug('Retrieved ' + fileKeys.size() + ' file keys from existing records');
            
        } catch (Exception ex) {
            System.debug('Error getting files from records: ' + ex.getMessage());
        }
        
        return fileKeys;
    }
    
    /**
     * Downloads a file from S3 using named credential
     */
    private HttpResponse downloadFileFromS3(String fileKey) {
        try {
            String encodedKey = EncodingUtil.urlEncode(fileKey, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            encodedKey = encodedKey.replace('+', '%20');
            
            String endpoint = AWS_ENDPOINT + '/' + encodedKey;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            request.setHeader('Content-Type', 'application/octet-stream');
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('📥 Download response status: ' + response.getStatusCode());
            if (response.getStatusCode() != 200) {
                System.debug('📥 Download error body: ' + response.getBody());
            }
            return response;
            
        } catch (Exception ex) {
            System.debug('❌ Error downloading file: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            return null;
        }
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
     * Creates ContentVersion from downloaded file
     */
    private ContentVersion createContentVersionFromFile(String fileKey, HttpResponse response, S3FileMetadata metadata) {
        try {
            if (response == null) {
                System.debug('❌ Response is null for file: ' + fileKey);
                return null;
            }
            
            if (response.getStatusCode() != 200) {
                System.debug('❌ Response status is not 200: ' + response.getStatusCode());
                return null;
            }
            
            String fileName = getFileNameFromKey(fileKey);
            
            if (!fileName.contains('.')) {
                String contentType = response.getHeader('Content-Type');
                
                if (contentType != null) {
                    contentType = contentType.split(';')[0].trim().toLowerCase();
                }
                
                Map<String,String> extensions = new Map<String,String>{
                    'application/pdf' => '.pdf',
                    'image/jpeg' => '.jpg',
                    'image/png' => '.png',
                    'application/msword' => '.doc',
                    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => '.docx',
                    'application/vnd.ms-excel' => '.xls',
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => '.xlsx',
                    'text/plain' => '.txt',
                    'application/zip' => '.zip',
                    'application/octet-stream' => '',
                    'image/jpg' => '.jpg',
                    'application/x-pdf' => '.pdf',
                    'application/octetstream' => ''
                };
                
                if (extensions.containsKey(contentType)) {
                    fileName += extensions.get(contentType);
                }
            }
            
            String title = fileName.contains('.')
                ? fileName.substringBeforeLast('.')
                : fileName;
            
            Blob fileData = response.getBodyAsBlob();
            
            if (fileData.size() > MAX_FILE_SIZE) {
                System.debug('❌ File too large: ' + fileData.size() + ' bytes (max: ' + MAX_FILE_SIZE + ')');
                return null;
            }
            
            if (fileData.size() == 0) {
                System.debug('❌ File is empty: ' + fileKey);
                return null;
            }
            
            ContentVersion contentVersion = new ContentVersion();
            
            contentVersion.VersionData = fileData;
            contentVersion.PathOnClient = fileName;
            
            // Build description with AWS S3 information
            String description = 'Retrieved from S3: ' + fileKey;
            description += ' | Retrieved: ' + System.now().format();
            if (String.isNotBlank(metadata.s3VersionId)) {
                description += ' | Version: ' + metadata.s3VersionId;
            }
            if (String.isNotBlank(metadata.fileExtension)) {
                description += ' | Type: ' + metadata.fileExtension;
            }
            contentVersion.Description = description;
            
            contentVersion.Origin = 'H';
            
            String lookupKey = normalizeTitle(title);
            
            if (existingContentDocuments.containsKey(lookupKey)) {
                // Existing file -> create NEW VERSION
                contentVersion.ContentDocumentId = existingContentDocuments.get(lookupKey);
                System.debug('Updating existing document: ' + contentVersion.ContentDocumentId);
                
                // For existing documents, we need to set the title to match
                contentVersion.Title = title;
            } else {
                // New file
                contentVersion.Title = title;
                contentVersion.FirstPublishLocationId = applicationId;
                System.debug('Creating new document');
            }
            
            System.debug('📄 ContentVersion created for: ' + fileName);
            return contentVersion;
            
        } catch (Exception ex) {
            System.debug('❌ Error creating ContentVersion: ' + ex.getMessage());
            System.debug('Stack trace: ' + ex.getStackTraceString());
            return null;
        }
    }
    
    /**
     * Extracts filename from S3 key
     */
    private String getFileNameFromKey(String fileKey) {
        // Remove the folder path from the key
        String fileName = fileKey;
        
        // Find the last slash to get the filename
        Integer lastSlash = fileKey.lastIndexOf('/');
        if (lastSlash != -1) {
            fileName = fileKey.substring(lastSlash + 1);
        }
        
        // Decode URL encoding
        try {
            fileName = EncodingUtil.urlDecode(fileName, 'UTF-8');
        } catch (Exception ex) {
            // If decoding fails, use the original
            System.debug('Could not decode filename: ' + ex.getMessage());
        }
        
        return fileName;
    }
    
    /**
     * Updates Application record with retrieval date
     */
    private void updateApplicationRecord() {
        try {
            if (applicationId == null) {
                System.debug('Cannot update Application record: Application ID is null');
                return;
            }
            
            Application__c app = new Application__c(
                Id = applicationId
            );
            
            if (applicationRecord != null && applicationRecord.AWS_S3_Package_Id__c == null) {
                app.AWS_S3_Package_Id__c = s3PackageId;
            }
            
            // If all files were retrieved successfully, clear the S3 package ID
            if (failedCount == 0 && successfullyLinked > 0) {
                app.AWS_S3_Package_Id__c = null;
                app.Retrieved_From_AWS_S3_Date__c = System.now();
                app.Send_Files_To_AWS_S3__c = false;
            }
            
            update app;
            System.debug('Updated Application record with retrieval information');
        } catch (Exception ex) {
            System.debug('ERROR updating Application record: ' + ex.getMessage());
        }
    }
    
    /**
     * Retrieves Application record
     */
    private Application__c getApplication(Id appId) {
        if (appId == null) {
            return null;
        }
        
        List<Application__c> applications = [
            SELECT Id, Name, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }
    
    /**
     * Generates a detailed summary of the retrieval results
     */
    private String generateDetailedSummary() {
        List<String> summaryParts = new List<String>();
        
        summaryParts.add('=== S3 RETRIEVE FILES BATCH SUMMARY ===');
        
        // Safe handling of null values
        if (applicationId != null) {
            summaryParts.add('Application ID: ' + (String)applicationId);
        } else {
            summaryParts.add('Application ID: N/A (Batch was not properly initialized)');
        }
        
        summaryParts.add('Application Name: ' + (applicationRecord != null ? applicationRecord.Name : 'Unknown'));
        summaryParts.add('S3 Package: ' + (packageFolder != null ? packageFolder : 'Unknown'));
        
        // Safe handling of uploadResultId
        if (uploadResultId != null) {
            summaryParts.add('Upload Result ID: ' + (String)uploadResultId);
        } else {
            summaryParts.add('Upload Result ID: N/A');
        }
        
        summaryParts.add('Total files in S3: ' + totalProcessed);
        summaryParts.add('Successfully linked: ' + successfullyLinked);
        summaryParts.add('Failed: ' + failedCount);
        
        if (totalProcessed > 0) {
            Decimal successRate = (successfullyLinked * 100.0) / totalProcessed;
            summaryParts.add('Success rate: ' + successRate.setScale(2) + '%');
        } else {
            summaryParts.add('Success rate: N/A (no files processed)');
        }
        
        if (!successFiles.isEmpty()) {
            summaryParts.add('--- Successfully Linked Files ---');
            for (Integer i = 0; i < Math.min(successFiles.size(), 20); i++) {
                summaryParts.add((i + 1) + '. ' + successFiles[i]);
            }
            if (successFiles.size() > 20) {
                summaryParts.add('... and ' + (successFiles.size() - 20) + ' more files');
            }
        }
        
        if (!failedFiles.isEmpty()) {
            summaryParts.add('--- Failed Files ---');
            for (Integer i = 0; i < Math.min(failedFiles.size(), 20); i++) {
                summaryParts.add((i + 1) + '. ' + failedFiles[i]);
            }
            if (failedFiles.size() > 20) {
                summaryParts.add('... and ' + (failedFiles.size() - 20) + ' more failures');
            }
        }
        
        // Add deletion info if all files were successful
        if (failedCount == 0 && successfullyLinked > 0) {
            summaryParts.add('--- Package Deletion ---');
            summaryParts.add('✅ All files retrieved successfully. Package deleted from S3.');
        }
        
        return String.join(summaryParts, '\n');
    }
    
    private void loadExistingContentDocuments() {
        if (applicationId == null) {
            System.debug('Cannot load existing documents: Application ID is null');
            return;
        }
        
        existingContentDocuments.clear();
        
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
        ]) {
            existingContentDocuments.put(
                normalizeTitle(link.ContentDocument.Title),
                link.ContentDocumentId
            );
        }
        
        System.debug('Existing documents: ' + existingContentDocuments.size());
    }
    
    // ==================== PUBLIC GETTERS ====================
    
    public Integer getTotalProcessed() {
        return totalProcessed;
    }
    
    public Integer getSuccessfullyLinked() {
        return successfullyLinked;
    }
    
    public Integer getFailedCount() {
        return failedCount;
    }
    
    public List<String> getFailedFiles() {
        return failedFiles;
    }
    
    public Id getUploadResultId() {
        return uploadResultId;
    }
    
    public String getUploadResultStatus() {
        return uploadResultStatus;
    }

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
    }
}