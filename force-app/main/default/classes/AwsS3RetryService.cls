/**
 * Service for handling retry logic for S3 uploads
 */
public class AwsS3RetryService {
    private UploadConfiguration config;
    private Integer maxRetries;
    private Integer retryDelayMs;
    
    /**
     * Constructor
     * @param config - Upload configuration with retry settings
     */
    public AwsS3RetryService(UploadConfiguration config) {
        this.config = config;
        this.maxRetries = config.maxRetries != null ? config.maxRetries : 3;
        this.retryDelayMs = config.retryDelayMs != null ? config.retryDelayMs : 1000;
    }
    
    /**
     * Uploads with retry logic
     * @param contentVersion - The ContentVersion to upload
     * @param folderPath - The S3 folder path
     * @return UploadResult with status and details
     */
    public UploadResult uploadWithRetry(ContentVersion contentVersion, String folderPath) {
        UploadResult result = new UploadResult();
        result.attempts = 0;
        
        String fileName = buildFileName(contentVersion);
        String s3Key = buildS3Key(folderPath, fileName);
        
        while (result.attempts < maxRetries) {
            result.attempts++;
            
            try {
                AwsS3Logger.debug('Upload attempt ' + result.attempts + ' for: ' + fileName);
                
                // Perform the actual upload
                Boolean uploadSuccess = performUpload(contentVersion, s3Key);
                
                if (uploadSuccess) {
                    result.success = true;
                    result.s3VersionId = s3Key; // Store the S3 key as version ID
                    result.statusCode = 200;
                    
                    AwsS3Logger.debug('Upload successful on attempt ' + result.attempts);
                    break;
                }
                
                // If upload failed and we have retries left, wait and retry
                if (result.attempts < maxRetries) {
                    AwsS3Logger.debug('Upload failed, retrying in ' + retryDelayMs + 'ms...');
                    sleep(retryDelayMs);
                }
                
            } catch (Exception e) {
                result.error = e.getMessage();
                AwsS3Logger.error('Upload attempt ' + result.attempts + ' failed: ' + e.getMessage());
                
                if (result.attempts < maxRetries) {
                    sleep(retryDelayMs);
                }
            }
        }
        
        if (!result.success && result.error == null) {
            result.error = 'Failed after ' + maxRetries + ' attempts';
        }
        
        return result;
    }
    
    /**
     * Performs the actual S3 upload
     * @param contentVersion - The ContentVersion to upload
     * @param s3Key - The S3 key to upload to
     * @return Boolean indicating success
     */
    private Boolean performUpload(ContentVersion contentVersion, String s3Key) {
        try {
            // Get the blob data from ContentVersion
            Blob fileData = contentVersion.VersionData;
            
            if (fileData == null || fileData.size() == 0) {
                throw new AwsS3Exception('No data available for upload');
            }
            
            // Build the S3 upload endpoint using Named Credential
            String endpoint = 'callout:AWS_S3/' + getBucketName() + '/' + EncodingUtil.urlEncode(s3Key, 'UTF-8');
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('PUT');
            request.setHeader('Content-Type', getContentType(contentVersion.FileExtension));
            request.setHeader('Content-Length', String.valueOf(fileData.size()));
            
            // Set the body as the blob data
            request.setBodyAsBlob(fileData);
            
            // Send the request
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            Integer statusCode = response.getStatusCode();
            
            // S3 successful upload returns 200 OK
            if (statusCode == 200) {
                AwsS3Logger.debug('S3 upload successful: ' + s3Key);
                return true;
            } else {
                String errorMsg = 'S3 upload failed with status: ' + statusCode + ' - ' + response.getBody();
                AwsS3Logger.error(errorMsg);
                throw new AwsS3Exception(errorMsg);
            }
            
        } catch (Exception e) {
            AwsS3Logger.error('Perform upload error: ' + e.getMessage());
            throw new AwsS3Exception('Upload failed: ' + e.getMessage());
        }
    }
    
    /**
     * Builds the file name for S3
     */
    private String buildFileName(ContentVersion contentVersion) {
        String docId = contentVersion.ContentDocumentId;
        String versionNumber = String.valueOf(contentVersion.VersionNumber);
        String extension = contentVersion.FileExtension != null ? contentVersion.FileExtension : '';
        
        // Format: documentId_vN.ext
        String fileName = docId + '_v' + versionNumber;
        
        if (!String.isBlank(extension)) {
            fileName += '.' + extension;
        }
        
        return fileName;
    }
    
    /**
     * Builds the S3 key (path + filename)
     */
    private String buildS3Key(String folderPath, String fileName) {
        // Ensure folder path ends with /
        if (!folderPath.endsWith('/')) {
            folderPath += '/';
        }
        
        // Remove leading slash if present
        if (folderPath.startsWith('/')) {
            folderPath = folderPath.substring(1);
        }
        
        return folderPath + fileName;
    }
    
    /**
     * Gets the content type based on file extension
     */
    private String getContentType(String fileExtension) {
        if (String.isBlank(fileExtension)) {
            return 'application/octet-stream';
        }
        
        String ext = fileExtension.toLowerCase();
        
        Map<String, String> mimeTypes = new Map<String, String>{
            'pdf' => 'application/pdf',
            'doc' => 'application/msword',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls' => 'application/vnd.ms-excel',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'ppt' => 'application/vnd.ms-powerpoint',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'txt' => 'text/plain',
            'csv' => 'text/csv',
            'xml' => 'application/xml',
            'json' => 'application/json',
            'zip' => 'application/zip',
            'jpg' => 'image/jpeg',
            'jpeg' => 'image/jpeg',
            'png' => 'image/png',
            'gif' => 'image/gif',
            'bmp' => 'image/bmp',
            'svg' => 'image/svg+xml',
            'mp4' => 'video/mp4',
            'mp3' => 'audio/mpeg',
            'wav' => 'audio/wav'
        };
        
        return mimeTypes.containsKey(ext) ? mimeTypes.get(ext) : 'application/octet-stream';
    }
    
    /**
     * Gets the S3 bucket name from Custom Label
     */
    private String getBucketName() {
        return System.Label.AWS_S3_Bucket;
    }
    
    /**
     * Simple sleep method for retry delay
     */
    private void sleep(Integer milliseconds) {
        if (milliseconds <= 0) return;
        
        try {
            Long startTime = DateTime.now().getTime();
            Long endTime = startTime + milliseconds;
            
            while (DateTime.now().getTime() < endTime) {
                // Busy wait
            }
        } catch (Exception e) {
            // Ignore
        }
    }
    
    /**
     * Custom exception class
     */
    public class AwsS3Exception extends Exception {
    }
}