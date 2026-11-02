/**
 * Configuration class for upload operations
 * Supports both Application and Email attachment uploads
 */
public class UploadConfiguration {
    // Application context
    public Id applicationId { get; set; }
    public String applicationName { get; set; }
    
    // Email context
    public Id emailMessageId { get; set; }
    public String emailSubject { get; set; }
    
    // S3 configuration
    public String packageFolder { get; set; }
    public String s3PackageId { get; set; }
    public String s3ObjectKey { get; set; } // Individual file key
    public String namedCredential { get; set; } // Custom named credential override
    
    // Upload options
    public Boolean deleteAfterUpload { get; set; }
    public Boolean enableVersioning { get; set; }
    public String storageClass { get; set; }
    
    // Upload source tracking
    public String uploadSource { get; set; } // 'Application' or 'Email'
    
    public UploadConfiguration() {
        this.deleteAfterUpload = true;
        this.enableVersioning = true;
        this.storageClass = 'STANDARD';
        this.uploadSource = 'Application'; // Default
    }
    
   
    /**
     * Checks if this is an email upload
     */
    public Boolean isEmailUpload() {
        return emailMessageId != null;
    }
    
}