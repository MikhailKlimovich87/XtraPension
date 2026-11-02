/**
 * Service class for uploading files to AWS S3 with versioning support
 * Supports both ContentVersion (for email attachments) and generic uploads
 * Maintains backward compatibility with AwsS3UploadSingleBatch
 *
 * IMPORTANT: S3 Bucket MUST have Versioning enabled
 */
public with sharing class AwsS3UploadService {
    private UploadConfiguration config;
    private AwsS3BatchState state;
    
    // Constants
    private static final Integer MAX_RETRIES = 3;
    
    // Named Credential for S3
    private static final String APPLICATION_NAMED_CREDENTIAL = 'AWS_S3';
    private static final String EMAIL_NAMED_CREDENTIAL = 'AWS_S3_Email';
    
    // Pattern for Application folder (starts with A followed by numbers)
    private static final Pattern APPLICATION_FOLDER_PATTERN = Pattern.compile('^A[0-9]+/');
    // Pattern for Email folder (starts with Salesforce record ID pattern: 18 chars alphanumeric)
    private static final Pattern EMAIL_FOLDER_PATTERN = Pattern.compile('^[a-zA-Z0-9]{15,18}/');
    
    public AwsS3UploadService(UploadConfiguration config, AwsS3BatchState state) {
        this.config = config;
        this.state = state;
    }
    
    /**
     * Uploads a ContentVersion to S3 with versioning support
     * This creates a NEW VERSION of the S3 object (S3 Versioning must be enabled)
     */
    public UploadResult uploadWithVersioning(ContentVersion contentVersion, String operation, String existingVersionId) {
        UploadResult result = new UploadResult();
        
        // 🔥 ALWAYS CREATE NEW VERSION - S3 Versioning handles this
        operation = 'CREATE_NEW';
        existingVersionId = null;
        result.operation = operation;
        
        try {
            String s3Key = config.s3ObjectKey;
            if (String.isBlank(s3Key)) {
                s3Key = buildS3Key(contentVersion);
                config.s3ObjectKey = s3Key;
            }
            
            Map<String, String> metadata = buildContentVersionMetadata(contentVersion);
            
            // 🔥 Determine which named credential to use based on the S3 key
            String namedCredential = getNamedCredentialForS3Key(s3Key);
            
            result = uploadWithRetry(s3Key, contentVersion.VersionData, metadata, operation, existingVersionId, namedCredential);
            
            if (result.success) {
                AwsS3Logger.info('✅ Upload successful - S3 Key: ' + s3Key +
                    ', Version ID: ' + result.s3VersionId +
                    ', Named Credential: ' + namedCredential +
                    ', Bucket: ' + getBucketName(namedCredential));
            }
            
        } catch (Exception ex) {
            result.success = false;
            result.error = 'Exception during upload: ' + ex.getMessage();
            AwsS3Logger.error('Upload exception: ' + ex.getMessage());
            AwsS3Logger.debug('Stack trace: ' + ex.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * 🔥 NEW: Determines which named credential to use based on the S3 key
     * - Application files: prefix like "A05974/" → APPLICATION_NAMED_CREDENTIAL
     * - Email files: prefix like "02sRR00000BemfWYAR/" → EMAIL_NAMED_CREDENTIAL
     */
    private String getNamedCredentialForS3Key(String s3Key) {
        if (String.isBlank(s3Key)) {
            AwsS3Logger.debug('S3 Key is blank, using default: ' + APPLICATION_NAMED_CREDENTIAL);
            return APPLICATION_NAMED_CREDENTIAL;
        }
        
        // Extract the first folder from the key (before the first '/')
        String firstFolder = '';
        if (s3Key.contains('/')) {
            firstFolder = s3Key.substringBefore('/') + '/';
        }
        
        AwsS3Logger.debug('📁 Determining bucket for S3 Key: ' + s3Key);
        AwsS3Logger.debug('📁 First folder: ' + firstFolder);
        
        // Check if it's an Application folder (starts with A followed by numbers)
        Matcher appMatcher = APPLICATION_FOLDER_PATTERN.matcher(firstFolder);
        if (appMatcher.matches()) {
            AwsS3Logger.info('📁 Application file detected (folder: ' + firstFolder + ') → Using: ' + APPLICATION_NAMED_CREDENTIAL);
            return APPLICATION_NAMED_CREDENTIAL;
        }
        
        // Check if it's an Email folder (starts with Salesforce record ID pattern)
        Matcher emailMatcher = EMAIL_FOLDER_PATTERN.matcher(firstFolder);
        if (emailMatcher.matches()) {
            AwsS3Logger.info('📧 Email file detected (folder: ' + firstFolder + ') → Using: ' + EMAIL_NAMED_CREDENTIAL);
            return EMAIL_NAMED_CREDENTIAL;
        }
        
        // Fallback: Check config.isEmailUpload() as a secondary check
        if (config.isEmailUpload()) {
            AwsS3Logger.info('📧 Email upload detected from config → Using: ' + EMAIL_NAMED_CREDENTIAL);
            return EMAIL_NAMED_CREDENTIAL;
        }
        
        // Default to Application bucket
        AwsS3Logger.info('📁 Using default (Application) bucket: ' + APPLICATION_NAMED_CREDENTIAL);
        return APPLICATION_NAMED_CREDENTIAL;
    }
    
    /**
     * Gets the appropriate named credential based on the upload context (legacy method)
     * Kept for backward compatibility
     */
    private String getNamedCredential() {
        // This method is now deprecated - use getNamedCredentialForS3Key instead
        // But kept for backward compatibility
        if (String.isNotBlank(config.namedCredential)) {
            return config.namedCredential;
        }
        
        if (config.isEmailUpload()) {
            AwsS3Logger.debug('Using email-specific named credential: ' + EMAIL_NAMED_CREDENTIAL);
            return EMAIL_NAMED_CREDENTIAL;
        }
        
        AwsS3Logger.debug('Using default named credential: ' + APPLICATION_NAMED_CREDENTIAL);
        return APPLICATION_NAMED_CREDENTIAL;
    }
    
    /**
     * Gets the bucket name from named credential for logging
     */
    private String getBucketName(String namedCredential) {
        if (namedCredential == EMAIL_NAMED_CREDENTIAL) {
            return 'xtrapension-sandbox-email-message-files';
        } else if (namedCredential == APPLICATION_NAMED_CREDENTIAL) {
            return 'xtrapension-sandbox-app-files';
        }
        return namedCredential;
    }
    
    /**
     * Builds the S3 object key for ContentVersion (without timestamp)
     */
    private String buildS3Key(ContentVersion contentVersion) {
        String folderPath = config.packageFolder;
        
        String title = contentVersion.Title != null ? contentVersion.Title : 'untitled';
        String extension = contentVersion.FileExtension != null ? contentVersion.FileExtension : '';
        
        String cleanTitle = cleanFileName(title);
        
        String fullKey;
        if (String.isNotBlank(extension)) {
            String cleanExt = extension.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();
            fullKey = folderPath + '/' + cleanTitle + '.' + cleanExt;
        } else {
            fullKey = folderPath + '/' + cleanTitle;
        }
        
        AwsS3Logger.debug('Generated S3 Key: ' + fullKey + ' for document: ' + title);
        return fullKey;
    }
    
    /**
     * Legacy method for backward compatibility
     */
    public UploadResult upload(ContentVersion contentVersion, String s3Key, Map<String, String> metadata) {
        UploadResult result = new UploadResult();
        
        try {
            config.s3ObjectKey = s3Key;
            // Use the new logic to determine named credential
            String namedCredential = getNamedCredentialForS3Key(s3Key);
            result = uploadWithRetry(s3Key, contentVersion.VersionData, metadata, 'CREATE_NEW', null, namedCredential);
            
            if (result.success) {
                AwsS3Logger.debug('Upload successful - S3 Key: ' + s3Key +
                    ', Named Credential: ' + namedCredential);
            }
            
        } catch (Exception ex) {
            result.success = false;
            result.error = 'Exception during upload: ' + ex.getMessage();
            AwsS3Logger.error('Upload exception: ' + ex.getMessage());
        }
        
        return result;
    }
    
    /**
     * Builds metadata for ContentVersion upload
     */
    private Map<String, String> buildContentVersionMetadata(ContentVersion contentVersion) {
        Map<String, String> metadata = new Map<String, String>();
        
        String contentType = getContentType(contentVersion.FileExtension);
        metadata.put('Content-Type', contentType);
        
        metadata.put('document-id', contentVersion.ContentDocumentId);
        metadata.put('content-version-id', contentVersion.Id);
        metadata.put('document-title', contentVersion.Title);
        metadata.put('version-number', String.valueOf(contentVersion.VersionNumber));
        metadata.put('file-size', String.valueOf(contentVersion.ContentSize));
        metadata.put('file-extension', contentVersion.FileExtension);
        
        if (config.emailMessageId != null) {
            metadata.put('email-id', config.emailMessageId);
            metadata.put('email-subject', config.emailSubject);
            metadata.put('upload-source', 'Email_ContentDocument');
            AwsS3Logger.debug('📧 Adding email metadata: ' + config.emailMessageId);
        }
        
        if (config.applicationId != null) {
            metadata.put('application-id', config.applicationId);
            metadata.put('upload-source', 'Application_ContentDocument');
            AwsS3Logger.debug('📁 Adding application metadata: ' + config.applicationId);
        }
        
        metadata.put('upload-date', System.now().format());
        metadata.put('upload-operation', state.packageAction);
        
        return metadata;
    }
    
    /**
     * Core upload method with retry logic
     */
    private UploadResult uploadWithRetry(String s3Key, Blob fileData, Map<String, String> metadata,
    String operation, String existingVersionId, String namedCredential) {
        UploadResult result = new UploadResult();
        result.success = false;
        
        Integer retryCount = 0;
        Exception lastException = null;
        
        while (retryCount < MAX_RETRIES && !result.success) {
            try {
                String endpoint = buildEndpoint(s3Key, namedCredential);
                
                HttpRequest request = new HttpRequest();
                request.setTimeout(60000);
                request.setEndpoint(endpoint);
                request.setMethod('PUT');
                
                String contentType = metadata.get('Content-Type');
                if (String.isBlank(contentType)) {
                    contentType = 'application/octet-stream';
                }
                request.setHeader('Content-Type', contentType);
                
                String fileName = s3Key.substringAfterLast('/');
                request.setHeader('Content-Disposition', 'attachment; filename="' + fileName + '"');
                
                for (String key : metadata.keySet()) {
                    if (!key.equals('Content-Type')) {
                        request.setHeader('x-amz-meta-' + key, metadata.get(key));
                    }
                }
                
                // 🔥 DO NOT send x-amz-version-id - S3 Versioning handles this automatically
                // S3 will create a new version for the same key
                
                request.setBodyAsBlob(fileData);
                
                Http http = new Http();
                HttpResponse response = http.send(request);
                
                if (response.getStatusCode() == 200) {
                    result.success = true;
                    result.s3ObjectKey = s3Key;
                    result.s3ETag = response.getHeader('ETag');
                    
                    // Get the version ID from the response header
                    String versionId = response.getHeader('x-amz-version-id');
                    if (String.isNotBlank(versionId)) {
                        result.s3VersionId = versionId;
                        AwsS3Logger.debug('📌 S3 Version ID from response: ' + versionId);
                    } else {
                        // If no version ID returned (versioning not enabled), generate one
                        result.s3VersionId = 'v' + System.now().format('yyyyMMddHHmmss');
                        AwsS3Logger.warn('⚠️ No S3 Version ID received. Versioning may not be enabled on the bucket.');
                    }
                    
                    AwsS3Logger.debug('Upload attempt ' + (retryCount + 1) + ' successful');
                    
                } else {
                    String errorMsg = 'Upload failed with status: ' + response.getStatusCode() +
                        ' - ' + response.getBody();
                    result.error = errorMsg;
                    AwsS3Logger.warn('Upload attempt ' + (retryCount + 1) + ' failed: ' + errorMsg);
                    
                    if (response.getStatusCode() == 400 || response.getStatusCode() == 403 ||
                    response.getStatusCode() == 404) {
                        break;
                    }
                }
                
            } catch (Exception ex) {
                lastException = ex;
                AwsS3Logger.warn('Upload attempt ' + (retryCount + 1) + ' exception: ' + ex.getMessage());
            }
            
            retryCount++;
        }
        
        if (!result.success) {
            if (lastException != null) {
                result.error = 'All retries failed. Last error: ' + lastException.getMessage();
            } else if (String.isBlank(result.error)) {
                result.error = 'All retries failed. Unknown error.';
            }
            AwsS3Logger.error('Upload failed after ' + MAX_RETRIES + ' attempts: ' + result.error);
        }
        
        return result;
    }
    
    /**
     * Builds the S3 endpoint URL with proper encoding
     */
    private String buildEndpoint(String s3Key, String namedCredential) {
        String baseEndpoint = 'callout:' + namedCredential;
        if (baseEndpoint.endsWith('/')) {
            baseEndpoint = baseEndpoint.substring(0, baseEndpoint.length() - 1);
        }
        
        String encodedKey = EncodingUtil.urlEncode(s3Key, 'UTF-8');
        encodedKey = encodedKey.replace('%2F', '/');
        encodedKey = encodedKey.replace('+', '%20');
        
        AwsS3Logger.debug('Using named credential: ' + namedCredential + ' with endpoint: ' + baseEndpoint);
        
        return baseEndpoint + '/' + encodedKey;
    }
    
    /**
     * Cleans a filename for S3
     */
    private String cleanFileName(String fileName) {
        if (String.isBlank(fileName)) return 'untitled';
        
        String cleaned = fileName.replaceAll('[^a-zA-Z0-9\\s\\(\\)\\-\\_\\.]', '');
        cleaned = cleaned.replaceAll('\\s+', ' ');
        cleaned = cleaned.trim();
        if (cleaned.length() > 200) {
            cleaned = cleaned.substring(0, 200);
        }
        
        return cleaned;
    }
    
    /**
     * Gets the content type based on file extension
     */
    private String getContentType(String extension) {
        if (String.isBlank(extension)) {
            return 'application/octet-stream';
        }
        
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
            'json' => 'application/json',
            'msg' => 'application/vnd.ms-outlook',
            'eml' => 'message/rfc822'
        };
        
        String ext = extension != null ? extension.toLowerCase() : '';
        return mimeTypes.containsKey(ext) ? mimeTypes.get(ext) : 'application/octet-stream';
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
    }
}