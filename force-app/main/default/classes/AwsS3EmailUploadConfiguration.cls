public with sharing class AwsS3EmailUploadConfiguration extends UploadConfiguration {
    public Boolean includeEmailBody { get; set; }
    public Boolean includeAttachments { get; set; }
    public Boolean createPackagePerEmail { get; set; }
    
    public AwsS3EmailUploadConfiguration() {
        this.includeEmailBody = true;
        this.includeAttachments = true;
        this.createPackagePerEmail = true;
        this.deleteAfterUpload = false; // Don't delete emails by default
    }
}