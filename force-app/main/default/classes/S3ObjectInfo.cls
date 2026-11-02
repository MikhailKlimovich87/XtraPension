/**
 * Wrapper class for S3 object information
 */
public class S3ObjectInfo {
    public String key;
    public String extension;
    public Long size;
    public String eTag;
    public DateTime lastModified;
    
    // Constructor with Long for size
    public S3ObjectInfo(String key, String extension, Long size, String eTag, DateTime lastModified) {
        this.key = key;
        this.extension = extension;
        this.size = size;
        this.eTag = eTag;
        this.lastModified = lastModified;
    }
}