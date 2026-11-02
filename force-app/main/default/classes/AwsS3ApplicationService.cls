/**
 * Service class for managing Application records
 * Supports both Upload operations
 */
public with sharing class AwsS3ApplicationService {
    
    private Id applicationId;
    private UploadConfiguration config;
    private AwsS3BatchState state;
    
    /**
     * Constructor for Upload operations
     * @param applicationId - The Application ID
     * @param config - Upload configuration
     * @param state - Batch state for tracking progress
     */
    public AwsS3ApplicationService(Id applicationId, UploadConfiguration config, AwsS3BatchState state) {
        this.applicationId = applicationId;
        this.config = config;
        this.state = state;
    }
    
    /**
     * Updates Application record after upload
     * Sets the S3 Package ID and upload date if successful
     */
    public void updateApplication() {
        try {
            Application__c app = getApplication(applicationId);
            if (app == null) {
                AwsS3Logger.error('Application not found: ' + applicationId);
                return;
            }
            
            Application__c updateApp = new Application__c(Id = applicationId);
            Boolean needsUpdate = false;
            
            // Set S3 Package ID if not already set
            if (app.AWS_S3_Package_Id__c == null && config != null && String.isNotBlank(config.s3PackageId)) {
                updateApp.AWS_S3_Package_Id__c = config.s3PackageId;
                updateApp.Send_Files_To_AWS_S3__c = true;
                needsUpdate = true;
                AwsS3Logger.debug('Setting S3 Package ID: ' + config.s3PackageId);
            }
            
            // If all uploads succeeded, update the date
            if (state != null && state.allUploadsSuccessful) {
                updateApp.Send_To_AWS_S3_Date__c = System.today();
                updateApp.Send_Files_To_AWS_S3__c = true;
                needsUpdate = true;
                AwsS3Logger.debug('Setting upload date: ' + System.today());
            }
            
            // Update package action status
            if (state != null && String.isNotBlank(state.packageAction)) {
                // You can add a field to track the action performed
                // updateApp.AWS_S3_Action__c = state.packageAction;
                // needsUpdate = true;
            }
            
            // Perform the update if needed
            if (needsUpdate) {
                update updateApp;
                AwsS3Logger.info('Updated Application record: ' + applicationId);
                
                // Log what was updated
                if (updateApp.AWS_S3_Package_Id__c != null) {
                    AwsS3Logger.info('  - S3 Package ID: ' + updateApp.AWS_S3_Package_Id__c);
                }
                if (updateApp.Send_To_AWS_S3_Date__c != null) {
                    AwsS3Logger.info('  - Upload Date: ' + updateApp.Send_To_AWS_S3_Date__c);
                }
            } else {
                AwsS3Logger.debug('No updates needed for Application: ' + applicationId);
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error updating application: ' + ex.getMessage());
            throw new AwsS3ApplicationException('Failed to update Application: ' + ex.getMessage());
        }
    }
    
    /**
     * Gets Application record with necessary fields
     */
    private Application__c getApplication(Id appId) {
        List<Application__c> apps = [
            SELECT Id, Name, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0];
    }
    
    /**
     * Custom exception class
     */
    public class AwsS3ApplicationException extends Exception {
    }
}