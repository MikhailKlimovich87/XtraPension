/**
 * Configuration class for Email upload
 */
public class EmailUploadConfiguration {
    public Id emailMessageId;
    public String packageFolder;
    public String s3PackageId;
    public String emailSubject;
    public String emailFromAddress;
    public Boolean deleteAfterUpload;
    public String namedCredential; // Named credential for email S3 bucket
    
    public EmailUploadConfiguration() {
        this.deleteAfterUpload = false;
        this.namedCredential = 'AWS_S3_Email'; // Default to email named credential
    }
}