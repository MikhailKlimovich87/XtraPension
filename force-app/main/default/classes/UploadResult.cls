/**
 * Result class for upload operations
 */
public class UploadResult {
    public Boolean success { get; set; }
    public String error { get; set; }
    public String s3ObjectKey { get; set; }
    public String s3VersionId { get; set; }
    public String s3ETag { get; set; }
    public String operation { get; set; } // 'CREATE_NEW' or 'UPDATE_EXISTING'
    public String contentVersionId { get; set; }
    public String attachmentId { get; set; }
    
    // Additional metadata
    public DateTime uploadDateTime { get; set; }
    public String uploadSource { get; set; }
    public Id parentId { get; set; }
    
    public UploadResult() {
        this.success = false;
        this.error = '';
        this.operation = 'CREATE_NEW';
        this.uploadDateTime = System.now();
    }
}