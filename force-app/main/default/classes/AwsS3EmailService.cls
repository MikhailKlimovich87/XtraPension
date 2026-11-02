public class AwsS3EmailService {
    public Id emailMessageId;
    public EmailUploadConfiguration config;
    public AwsS3BatchState state;
    
    public AwsS3EmailService(Id emailMessageId, EmailUploadConfiguration config, AwsS3BatchState state) {
        this.emailMessageId = emailMessageId;
        this.config = config;
        this.state = state;
    }
    
    public void updateEmailMessage() {
        try {
            // Update EmailMessage with S3 package info
            // This would depend on your custom fields on EmailMessage
            // Example:
            // EmailMessage email = new EmailMessage(
            //     Id = emailMessageId,
            //     S3_Package_Folder__c = config.packageFolder,
            //     S3_Upload_Date__c = System.now(),
            //     S3_Upload_Status__c = state.allUploadsSuccessful ? 'Completed' : 'Partial'
            // );
            // update email;
            
            AwsS3Logger.debug('Updated EmailMessage ' + emailMessageId + ' with S3 package info');
        } catch (Exception ex) {
            AwsS3Logger.error('Error updating EmailMessage: ' + ex.getMessage());
        }
    }
}