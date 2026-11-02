public with sharing class AwsS3ApiHandler {
    // Constants
    private static final String AWS_API_ENDPOINT = 'callout:AWS_S3';
    private static final Integer SUCCESS_STATUS_CODE_MIN = 200;
    private static final Integer SUCCESS_STATUS_CODE_MAX = 299;
    
    // Content type mappings
    private static final Map<String, String> CONTENT_TYPE_MAP = new Map<String, String>{
        'PDF' => 'application/pdf',
        'PNG' => 'image/png',
        'JPG' => 'image/jpeg',
        'JPEG' => 'image/jpeg',
        'CSV' => 'text/csv',
        'XML' => 'application/xml',
        'DOC' => 'application/msword',
        'DOCX' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'XLS' => 'application/vnd.ms-excel',
        'XLSX' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'PPT' => 'application/vnd.ms-powerpoint',
        'PPTX' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'TXT' => 'text/plain',
        'JSON' => 'application/json',
        'ZIP' => 'application/zip'
    };
    private static final String DEFAULT_CONTENT_TYPE = 'application/octet-stream';
    
    /**
     * Uploads a ContentVersion document to AWS S3
     * @param contentVersionId - Id of the ContentVersion to upload
     * @return AwsS3APIResponseWrapper containing the result of the operation
     */
    public static AwsS3APIResponseWrapper uploadToS3(Id contentVersionId) {
        // Validate input
        if (contentVersionId == null) {
            return createErrorResponse('ContentVersion ID cannot be null');
        }
        
        try {
            ContentVersion contentVersion = getContentVersion(contentVersionId);
            
            if (contentVersion == null || contentVersion.VersionData == null) {
                return createErrorResponse('ContentVersion has no body or does not exist');
            }
            
            HttpRequest request = buildHttpRequest(contentVersion);
            HttpResponse response = sendHttpRequest(request);
            
            // Process response and update ContentVersion with S3 version ID
            return processHttpResponse(response, contentVersion);
            
        } catch (Exception ex) {
            System.debug('Error in uploadToS3: ' + ex.getMessage());
            return createErrorResponse('An error occurred while processing the request: ' + ex.getMessage());
        }
    }
    
    /**
     * Uploads a ContentVersion document to AWS S3 inside a specified folder path
     * @param contentVersionId - Id of the ContentVersion to upload
     * @param folderPath - Folder path in S3 (for example: invoices/2026)
     * @return AwsS3APIResponseWrapper containing the result of the operation
     */
    public static AwsS3APIResponseWrapper uploadToS3WithFolder(Id contentVersionId, String folderPath) {
        if (contentVersionId == null) {
            return createErrorResponse('ContentVersion ID cannot be null');
        }
        
        if (String.isBlank(folderPath)) {
            return createErrorResponse('Folder path cannot be blank');
        }
        
        try {
            ContentVersion contentVersion = getContentVersion(contentVersionId);
            
            if (contentVersion == null || contentVersion.VersionData == null) {
                return createErrorResponse('ContentVersion has no body or does not exist');
            }
            
            HttpRequest request = buildHttpRequest(contentVersion, folderPath);
            HttpResponse response = sendHttpRequest(request);
            
            // Process response and update ContentVersion with S3 version ID
            return processHttpResponse(response, contentVersion);
            
        } catch (Exception ex) {
            System.debug('Error in uploadToS3WithFolder: ' + ex.getMessage());
            return createErrorResponse('An error occurred while processing the request: ' + ex.getMessage());
        }
    }
    
    /**
     * Uploads all versions of ContentDocument files linked to an Application record
     * This method now delegates to the batch class for processing
     * @param applicationId - Id of the Application record
     * @return AwsS3APIResponseWrapper containing the result of the operation
     */
    public static AwsS3APIResponseWrapper uploadApplicationFilesWithFolder(Id applicationId) {
        if (applicationId == null) {
            return createErrorResponse('Application ID cannot be null');
        }
        
        try {
            Application__c applicationRecord = getApplication(applicationId);
            if (applicationRecord == null) {
                return createErrorResponse('Application record not found');
            }
            
            // Use the batch class to process files one by one
            AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(applicationId);
            Id batchJobId = Database.executeBatch(batch, 1); // Batch size of 1
            
            return createSuccessResponse('Upload initiated in batch mode. Batch Job ID: ' + batchJobId);
            
        } catch (Exception ex) {
            System.debug('Error in uploadApplicationFilesWithFolder: ' + ex.getMessage());
            return createErrorResponse('An error occurred while processing the request: ' + ex.getMessage());
        }
    }
    
    /**
     * Synchronous version of uploadApplicationFilesWithFolder for small datasets
     * @param applicationId - Id of the Application record
     * @return AwsS3APIResponseWrapper containing the result of the operation
     */
    public static AwsS3APIResponseWrapper uploadApplicationFilesSynchronous(Id applicationId) {
        if (applicationId == null) {
            return createErrorResponse('Application ID cannot be null');
        }
        
        try {
            Application__c applicationRecord = getApplication(applicationId);
            if (applicationRecord == null) {
                return createErrorResponse('Application record not found');
            }
            
            String packageFolder = buildApplicationPackageFolder(applicationRecord, null);
            List<ContentDocument> contentDocuments = getApplicationContentDocuments(applicationId);
            
            if (contentDocuments.isEmpty()) {
                return createErrorResponse('No files found for Application record: ' + applicationRecord.Name);
            }
            
            // Prepare list of all ContentVersion records to upload (including all versions)
            List<ContentVersion> allVersions = new List<ContentVersion>();
            Map<String, List<ContentVersion>> documentVersionsMap = getContentDocumentVersions(contentDocuments);
            
            // Collect all versions for each document
            for (ContentDocument doc : contentDocuments) {
                List<ContentVersion> versions = documentVersionsMap.get(doc.Id);
                if (versions != null && !versions.isEmpty()) {
                    allVersions.addAll(versions);
                }
            }
            
            if (allVersions.isEmpty()) {
                return createErrorResponse('No content versions found for the documents');
            }
            
            // Process all versions synchronously
            Integer totalFiles = allVersions.size();
            Integer uploadedCount = 0;
            List<String> failedUploads = new List<String>();
            Map<String, Integer> versionStats = new Map<String, Integer>();
            
            // List to collect updated ContentVersions
            List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
            
            for (ContentVersion contentVersion : allVersions) {
                if (contentVersion == null || contentVersion.VersionData == null) {
                    String docId = contentVersion != null ? contentVersion.ContentDocumentId : 'Unknown';
                    failedUploads.add('Document ID: ' + docId + ' (Version ' +
                        (contentVersion != null ? String.valueOf(contentVersion.VersionNumber) : 'Unknown') + ')');
                    continue;
                }
                
                // Create folder path WITHOUT version information
                String folderPath = packageFolder;
                
                try {
                    HttpRequest request = buildHttpRequest(contentVersion, folderPath);
                    HttpResponse response = sendHttpRequest(request);
                    
                    if (isSuccessStatusCode(response.getStatusCode())) {
                        uploadedCount++;
                        // Track version upload statistics
                        String docId = contentVersion.ContentDocumentId;
                        if (versionStats.containsKey(docId)) {
                            versionStats.put(docId, versionStats.get(docId) + 1);
                        } else {
                            versionStats.put(docId, 1);
                        }
                        
                        // Extract S3 version ID (ETag or x-amz-version-id) and update ContentVersion
                        String s3VersionId = extractS3VersionId(response);
                        if (!String.isBlank(s3VersionId)) {
                            // Create a clone of the ContentVersion with the S3 version ID
                            ContentVersion updatedVersion = new ContentVersion(
                                Id = contentVersion.Id,
                            S3_Version_Id__c = s3VersionId,
                            S3_Upload_Date__c = System.now(),
                            S3_Upload_Status__c = 'Success'
                                );
                            versionsToUpdate.add(updatedVersion);
                        }
                    } else {
                        failedUploads.add(contentVersion.Title + ' (Version ' +
                            String.valueOf(contentVersion.VersionNumber) + ') - Status: ' + response.getStatusCode());
                    }
                } catch (Exception ex) {
                    failedUploads.add(contentVersion.Title + ' (Version ' +
                        String.valueOf(contentVersion.VersionNumber) + ') - Error: ' + ex.getMessage());
                }
            }
            
            // Update ContentVersion records with S3 version IDs
            if (!versionsToUpdate.isEmpty()) {
                try {
                    update versionsToUpdate;
                } catch (Exception ex) {
                    System.debug('Error updating ContentVersions with S3 version IDs: ' + ex.getMessage());
                }
            }
            
            // Generate detailed response
            String details = generateUploadSummary(uploadedCount, totalFiles, versionStats, failedUploads);
            
            if (uploadedCount == 0) {
                return createErrorResponse('No files were uploaded. ' + details);
            }
            
            if (!failedUploads.isEmpty()) {
                return createErrorResponse('Partial upload: ' + details);
            }
            
            return createSuccessResponse('Successfully uploaded all ' + uploadedCount +
                ' file versions to S3 package: ' + packageFolder + '. ' + details);
            
        } catch (Exception ex) {
            System.debug('Error in uploadApplicationFilesSynchronous: ' + ex.getMessage());
            return createErrorResponse('An error occurred while processing the request: ' + ex.getMessage());
        }
    }
    
    /**
     * Asynchronous version of uploadApplicationFilesWithFolder using @future
     * Use this for large numbers of files
     */
    @future(callout=true)
    public static void uploadApplicationFilesWithFolderAsync(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        
        try {
            // Use the batch class for asynchronous processing
            AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(applicationId);
            Id batchJobId = Database.executeBatch(batch, 1);
            
            System.debug('Async upload initiated. Batch Job ID: ' + batchJobId);
            
        } catch (Exception ex) {
            System.debug('Async upload failed with error: ' + ex.getMessage());
        }
    }
    
    /**
     * Utility method to upload a single document with all its versions
     * @param documentId - Id of the ContentDocument
     * @param folderPath - Optional folder path in S3
     * @return AwsS3APIResponseWrapper
     */
    public static AwsS3APIResponseWrapper uploadDocumentWithAllVersions(Id documentId, String folderPath) {
        if (documentId == null) {
            return createErrorResponse('ContentDocument ID cannot be null');
        }
        
        try {
            // Get all versions of this document
            List<ContentVersion> versions = [
                SELECT Id, Title, VersionData, FileType, ContentSize, 
                       VersionNumber, ContentDocumentId, CreatedDate,
                       IsLatest, Description, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId = :documentId
                ORDER BY VersionNumber ASC
            ];
            
            if (versions.isEmpty()) {
                return createErrorResponse('No versions found for document');
            }
            
            Integer uploadedCount = 0;
            List<String> failedUploads = new List<String>();
            List<ContentVersion> versionsToUpdate = new List<ContentVersion>();
            
            for (ContentVersion version : versions) {
                if (version == null || version.VersionData == null) {
                    failedUploads.add('Version ' + String.valueOf(version.VersionNumber) + ' has no data');
                    continue;
                }
                
                String versionFolder = String.isBlank(folderPath) ?
                    'document_' + documentId :
                    folderPath;
                
                try {
                    HttpRequest request = buildHttpRequest(version, versionFolder);
                    HttpResponse response = sendHttpRequest(request);
                    
                    if (isSuccessStatusCode(response.getStatusCode())) {
                        uploadedCount++;
                        
                        // Extract S3 version ID and update ContentVersion
                        String s3VersionId = extractS3VersionId(response);
                        if (!String.isBlank(s3VersionId)) {
                            ContentVersion updatedVersion = new ContentVersion(
                                Id = version.Id,
                            S3_Version_Id__c = s3VersionId,
                            S3_Upload_Date__c = System.now(),
                            S3_Upload_Status__c = 'Success'
                                );
                            versionsToUpdate.add(updatedVersion);
                        }
                    } else {
                        failedUploads.add('Version ' + String.valueOf(version.VersionNumber) +
                            ' - Status: ' + response.getStatusCode());
                    }
                } catch (Exception ex) {
                    failedUploads.add('Version ' + String.valueOf(version.VersionNumber) +
                        ' - Error: ' + ex.getMessage());
                }
            }
            
            // Update ContentVersion records with S3 version IDs
            if (!versionsToUpdate.isEmpty()) {
                try {
                    update versionsToUpdate;
                } catch (Exception ex) {
                    System.debug('Error updating ContentVersions with S3 version IDs: ' + ex.getMessage());
                }
            }
            
            if (uploadedCount == 0) {
                return createErrorResponse('No versions uploaded. Failed: ' +
                    String.join(failedUploads, ', '));
            }
            
            if (!failedUploads.isEmpty()) {
                return createErrorResponse('Partial upload: ' + uploadedCount +
                    ' of ' + versions.size() + ' versions uploaded. Failed: ' +
                    String.join(failedUploads, ', '));
            }
            
            return createSuccessResponse('All ' + uploadedCount +
                ' versions uploaded successfully (overwritten in S3)');
            
        } catch (Exception ex) {
            return createErrorResponse('Error uploading document: ' + ex.getMessage());
        }
    }
    
    // ==================== PRIVATE HELPER METHODS ====================
    
    /**
     * Extracts S3 version ID from HTTP response
     * S3 returns ETag (MD5 hash) and optionally x-amz-version-id if versioning is enabled
     */
    private static String extractS3VersionId(HttpResponse response) {
        // Check for x-amz-version-id header (S3 versioning)
        String versionId = response.getHeader('x-amz-version-id');
        if (!String.isBlank(versionId)) {
            return versionId;
        }
        
        // Fallback to ETag
        String etag = response.getHeader('ETag');
        if (!String.isBlank(etag)) {
            // Remove quotes from ETag if present
            etag = etag.replace('"', '');
            return etag;
        }
        
        // If no version ID available, generate a custom one based on timestamp
        // This ensures we can track the upload even without S3 versioning
        return 'upload_' + String.valueOf(System.now().getTime()) + '_' +
            String.valueOf(Crypto.getRandomInteger());
    }
    
    /**
     * Retrieves Application record
     */
    private static Application__c getApplication(Id applicationId) {
        List<Application__c> applications = [
            SELECT
                Id,
                Name
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }
    
    /**
     * Retrieves all ContentDocument records linked to the Application record
     */
    private static List<ContentDocument> getApplicationContentDocuments(Id applicationId) {
        List<ContentDocumentLink> documentLinks = [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
        ];
        
        if (documentLinks.isEmpty()) {
            return new List<ContentDocument>();
        }
        
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : documentLinks) {
            if (link.ContentDocumentId != null) {
                contentDocumentIds.add(link.ContentDocumentId);
            }
        }
        
        if (contentDocumentIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        
        return [
            SELECT Id, Title, FileType, Description, CreatedDate, LastModifiedDate
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ];
    }
    
    /**
     * Retrieves all versions of ContentDocuments with their data
     */
    private static Map<String, List<ContentVersion>> getContentDocumentVersions(List<ContentDocument> documents) {
        if (documents.isEmpty()) {
            return new Map<String, List<ContentVersion>>();
        }
        
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocument doc : documents) {
            contentDocumentIds.add(doc.Id);
        }
        
        List<ContentVersion> allVersions = [
            SELECT Id, Title, VersionData, FileType, ContentSize, 
                   VersionNumber, ContentDocumentId, CreatedDate,
                   IsLatest, Description, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
            ORDER BY ContentDocumentId, VersionNumber ASC
        ];
        
        // Group versions by ContentDocumentId
        Map<String, List<ContentVersion>> versionsMap = new Map<String, List<ContentVersion>>();
        for (ContentVersion version : allVersions) {
            String docId = version.ContentDocumentId;
            if (!versionsMap.containsKey(docId)) {
                versionsMap.put(docId, new List<ContentVersion>());
            }
            versionsMap.get(docId).add(version);
        }
        
        return versionsMap;
    }
    
    /**
     * Retrieves ContentVersion record
     */
    private static ContentVersion getContentVersion(Id contentVersionId) {
        List<ContentVersion> contentVersions = [
            SELECT Id, VersionData, FileType, ContentSize, Title, VersionNumber, 
                   ContentDocumentId, IsLatest, FileExtension
            FROM ContentVersion 
            WHERE Id = :contentVersionId 
            LIMIT 1
        ];
        return contentVersions.isEmpty() ? null : contentVersions[0];
    }
    
    /**
     * Builds HTTP request for S3 upload
     */
    public static HttpRequest buildHttpRequest(ContentVersion contentVersion) {
        return buildHttpRequest(contentVersion, null);
    }
    
    /**
     * Builds HTTP request for S3 upload with a folder path
     */
    public static HttpRequest buildHttpRequest(ContentVersion contentVersion, String folderPath) {
        HttpRequest request = new HttpRequest();
        
        // Build the object key
        String objectKey = buildObjectKey(contentVersion, folderPath);
        AwsS3Logger.debug('Original title: [' + contentVersion.Title + ']');
        AwsS3Logger.debug('Object key: [' + objectKey + ']');
        // URL encode the entire object key to handle spaces and special characters
        // This is required because Named Credentials don't support spaces in URLs
        String encodedObjectKey = EncodingUtil.urlEncode(objectKey, 'UTF-8');
        encodedObjectKey = encodedObjectKey.replace('%2F', '/');
        encodedObjectKey = encodedObjectKey.replace('+', '%20');
        
        // Set the endpoint with the encoded key
        request.setEndpoint(AWS_API_ENDPOINT + '/' + encodedObjectKey);
        
        // Set method and headers
        request.setMethod('PUT');
        request.setHeader('Content-Type', getContentType(contentVersion.FileType));
        request.setBodyAsBlob(contentVersion.VersionData);
        
        // Add additional headers for better tracking
        request.setHeader('x-amz-meta-version', String.valueOf(contentVersion.VersionNumber));
        request.setHeader('x-amz-meta-document-id', contentVersion.ContentDocumentId);
        request.setHeader('x-amz-meta-content-version-id', contentVersion.Id);
        if (contentVersion.IsLatest) {
            request.setHeader('x-amz-meta-is-latest', 'true');
        }
        
        // Add timestamp to track when the file was uploaded
        request.setHeader('x-amz-meta-upload-timestamp', String.valueOf(System.now().getTime()));
        
        return request;
    }
    /**
     * Builds the S3 object key including the optional folder path
     * NOTE: This creates a SINGLE file per document (no version folders)
     */
    private static String buildObjectKey(ContentVersion contentVersion, String folderPath) {
        // Use the original filename without version numbers
        String cleanFileName = contentVersion.Title;
        
        // Remove any version numbers from filename if they exist
        if (cleanFileName.contains('_v')) {
            cleanFileName = cleanFileName.substring(0, cleanFileName.indexOf('_v'));
        }
        
        if (String.isBlank(folderPath)) {
            return cleanFileName;
        }
        
        String normalizedFolderPath = folderPath.replace('\\', '/');
        List<String> segments = new List<String>();
        
        for (String segment : normalizedFolderPath.split('/')) {
            if (String.isBlank(segment)) {
                continue;
            }
            segments.add(segment.trim());
        }
        
        String folderKey = String.join(segments, '/');
        return String.isBlank(folderKey) ? cleanFileName : folderKey + '/' + cleanFileName;
    }
    /**
     * Encodes filename for URL
     */
    /*private static String encodeFileName(String fileName) {
        if (String.isBlank(fileName)) {
            return 'untitled';
        }
        return EncodingUtil.urlEncode(fileName, 'UTF-8').replace('+', '%20');
    }*/
    
    /**
     * Sends HTTP request and returns response
     */
    public static HttpResponse sendHttpRequest(HttpRequest request) {
        Http http = new Http();
        return http.send(request);
    }
    /**
     * Processes HTTP response and updates ContentVersion with S3 version ID
     */
    private static AwsS3APIResponseWrapper processHttpResponse(HttpResponse response, ContentVersion contentVersion) {
        Integer statusCode = response.getStatusCode();
        String responseBody = response.getBody();
        System.debug('Status: ' + response.getStatusCode());
        System.debug('Headers: ' + response.getHeaderKeys());
        System.debug('Body: ' + response.getBody());
        
        if (isSuccessStatusCode(statusCode)) {
            // Extract S3 version ID
            String s3VersionId = extractS3VersionId(response);
            
            // Update ContentVersion with S3 version ID
            if (contentVersion != null && !String.isBlank(s3VersionId)) {
                try {
                    ContentVersion updatedVersion = new ContentVersion(
                        Id = contentVersion.Id,
                    S3_Version_Id__c = s3VersionId,
                    S3_Upload_Date__c = System.now(),
                    S3_Upload_Status__c = 'Success'
                        );
                    update updatedVersion;
                } catch (Exception ex) {
                    System.debug('Error updating ContentVersion with S3 version ID: ' + ex.getMessage());
                }
            }
            
            String successMessage = String.isBlank(responseBody) ?
                'File uploaded successfully. S3 Version ID: ' + s3VersionId : responseBody;
            
            return createSuccessResponse(successMessage);
        } else {
            // Update ContentVersion with failure status
            if (contentVersion != null) {
                try {
                    ContentVersion updatedVersion = new ContentVersion(
                        Id = contentVersion.Id,
                    S3_Upload_Status__c = 'Failed',
                    S3_Upload_Error__c = 'Status: ' + statusCode
                        );
                    update updatedVersion;
                } catch (Exception ex) {
                    System.debug('Error updating ContentVersion with failure status: ' + ex.getMessage());
                }
            }
            
            String errorMessage = parseErrorMessage(responseBody, statusCode);
            return createErrorResponse('S3 upload failed with status ' + statusCode + ': ' + errorMessage);
        }
    }
    
    /**
     * Checks if status code indicates success
     */
    public static Boolean isSuccessStatusCode(Integer statusCode) {
        return statusCode >= SUCCESS_STATUS_CODE_MIN && statusCode <= SUCCESS_STATUS_CODE_MAX;
    }
    
    /**
     * Gets content type based on file type
     */
    private static String getContentType(String fileType) {
        if (String.isBlank(fileType)) {
            return DEFAULT_CONTENT_TYPE;
        }
        
        String contentType = CONTENT_TYPE_MAP.get(fileType.toUpperCase());
        return contentType != null ? contentType : DEFAULT_CONTENT_TYPE;
    }
    
    /**
     * Parses error message from response body
     */
    private static String parseErrorMessage(String responseBody, Integer statusCode) {
        if (String.isBlank(responseBody)) {
            return 'Unknown error occurred';
        }
        
        try {
            Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> errorMap = (Map<String, Object>) responseData.get('error');
            
            if (errorMap != null && errorMap.containsKey('message')) {
                return String.valueOf(errorMap.get('message'));
            }
            
            return 'Error response received but message not found';
            
        } catch (Exception ex) {
            System.debug('Error parsing error response: ' + ex.getMessage());
            
            if (responseBody.contains('<Error>')) {
                return extractFromXml(responseBody, 'Message');
            }
            
            return responseBody.length() > 200 ?
                responseBody.substring(0, 200) + '...' : responseBody;
        }
    }
    
    /**
     * Simple XML extraction helper (for S3 error responses)
     */
    private static String extractFromXml(String xml, String tag) {
        try {
            String startTag = '<' + tag + '>';
            String endTag = '</' + tag + '>';
            Integer startIndex = xml.indexOf(startTag);
            if (startIndex != -1) {
                Integer endIndex = xml.indexOf(endTag, startIndex);
                if (endIndex != -1) {
                    return xml.substring(startIndex + startTag.length(), endIndex);
                }
            }
        } catch (Exception ex) {
            System.debug('Error extracting from XML: ' + ex.getMessage());
        }
        return 'Error response received';
    }
    
    /**
     * Builds the S3 package folder path using the Application name
     */
    public static String buildApplicationPackageFolder(Application__c applicationRecord, String folderPath) {
        String applicationName = String.isBlank(applicationRecord.Name) ? 'application' : applicationRecord.Name;
        String sanitizedApplicationName = sanitizeFolderPathSegment(applicationName);
        
        if (String.isBlank(folderPath)) {
            return sanitizedApplicationName;
        }
        
        String normalizedFolderPath = folderPath.replace('\\', '/');
        List<String> segments = new List<String>();
        
        for (String segment : normalizedFolderPath.split('/')) {
            if (String.isBlank(segment)) {
                continue;
            }
            String sanitizedSegment = sanitizeFolderPathSegment(segment);
            if (!String.isBlank(sanitizedSegment)) {
                segments.add(sanitizedSegment);
            }
        }
        
        segments.add(sanitizedApplicationName);
        return String.join(segments, '/');
    }
    
    /**
     * Sanitizes folder path segments for S3 object keys
     */
    private static String sanitizeFolderPathSegment(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        
        return value.trim().replace('\\', '/').replace('/', '');
    }
    
    /**
     * Generates a summary of the upload results
     */
    private static String generateUploadSummary(Integer uploadedCount, Integer totalFiles,
    Map<String, Integer> versionStats, List<String> failedUploads) {
        List<String> summaryParts = new List<String>();
        
        // Overall statistics
        summaryParts.add('Uploaded ' + uploadedCount + ' of ' + totalFiles + ' file versions');
        
        // Document-level statistics
        if (versionStats != null && !versionStats.isEmpty()) {
            List<String> docStats = new List<String>();
            for (String docId : versionStats.keySet()) {
                docStats.add('Document ' + docId + ' (' + versionStats.get(docId) + ' versions)');
            }
            if (!docStats.isEmpty()) {
                summaryParts.add('Documents uploaded: ' + String.join(docStats, ', '));
            }
        }
        
        // Failed uploads
        if (!failedUploads.isEmpty()) {
            String failedSummary = String.join(failedUploads, ', ');
            if (failedSummary.length() > 200) {
                failedSummary = failedSummary.substring(0, 200) + '...';
            }
            summaryParts.add('Failed: ' + failedSummary);
        }
        
        return String.join(summaryParts, '. ');
    }
    
    /**
     * Creates success response wrapper
     */
    private static AwsS3APIResponseWrapper createSuccessResponse(String message) {
        return new AwsS3APIResponseWrapper(false, message, null);
    }
    
    /**
     * Creates error response wrapper
     */
    private static AwsS3APIResponseWrapper createErrorResponse(String errorMessage) {
        return new AwsS3APIResponseWrapper(true, null, errorMessage);
    }
    
    // ==================== RESPONSE WRAPPER CLASS ====================
    
    /**
     * Response wrapper class
     */
    public class AwsS3APIResponseWrapper {
        public Boolean isError { get; set; }
        public String responseBody { get; set; }
        public String errorMessage { get; set; }
        
        public AwsS3APIResponseWrapper(Boolean isError, String responseBody, String errorMessage) {
            this.isError = isError;
            this.responseBody = responseBody;
            this.errorMessage = errorMessage;
        }
        
        public AwsS3APIResponseWrapper() {
            this.isError = false;
        }
    }
}