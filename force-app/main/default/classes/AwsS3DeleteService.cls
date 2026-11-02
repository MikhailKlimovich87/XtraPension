/**
 * Service class for deleting files from S3
 */
public with sharing class AwsS3DeleteService {
    
    private static final String AWS_ENDPOINT = 'callout:AWS_S3';
    
    private RetrieveConfiguration config;
    private AwsS3RetrieveState state;
    
    public AwsS3DeleteService(RetrieveConfiguration config, AwsS3RetrieveState state) {
        this.config = config;
        this.state = state;
    }
    
    /**
     * Deletes the entire package folder and all files from S3
     */
    public void deletePackage() {
        try {
            AwsS3Logger.debug('=== DELETING PACKAGE FROM S3 ===');
            AwsS3Logger.debug('Package folder: ' + config.packageFolder);
            
            // Get all files in the package
            AwsS3RetrieveService retrieveService = new AwsS3RetrieveService(config, state);
            List<String> filesToDelete = retrieveService.getFileList();
            
            if (filesToDelete.isEmpty()) {
                AwsS3Logger.debug('No files to delete');
                return;
            }
            
            // Delete each file
            Integer deletedCount = 0;
            Integer failedDeleteCount = 0;
            
            for (String fileKey : filesToDelete) {
                try {
                    HttpResponse response = deleteFile(fileKey);
                    if (response != null && response.getStatusCode() == 204) {
                        deletedCount++;
                        AwsS3Logger.debug('✅ Deleted file: ' + fileKey);
                    } else {
                        failedDeleteCount++;
                        String error = response != null ? 'Status: ' + response.getStatusCode() : 'Null response';
                        AwsS3Logger.warn('❌ Failed to delete: ' + fileKey + ' - ' + error);
                    }
                } catch (Exception ex) {
                    failedDeleteCount++;
                    AwsS3Logger.error('Error deleting file: ' + fileKey + ' - ' + ex.getMessage());
                }
            }
            
            AwsS3Logger.debug('Package deletion summary: Deleted: ' + deletedCount + ', Failed: ' + failedDeleteCount);
            
            if (failedDeleteCount > 0) {
                // Log warning
                String warning = 'Warning: ' + failedDeleteCount + ' file(s) failed to delete from S3';
                AwsS3Logger.warn(warning);
                // Update result with warning (handled by caller)
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('ERROR deleting package from S3: ' + ex.getMessage());
        }
    }
    
    /**
     * Deletes a single file from S3
     */
    public HttpResponse deleteFile(String fileKey) {
        try {
            String encodedKey = EncodingUtil.urlEncode(fileKey, 'UTF-8');
            encodedKey = encodedKey.replace('%2F', '/');
            encodedKey = encodedKey.replace('+', '%20');
            
            String endpoint = AWS_ENDPOINT + '/' + encodedKey;
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('DELETE');
            
            Http http = new Http();
            return http.send(request);
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error deleting file from S3: ' + ex.getMessage());
            return null;
        }
    }
}