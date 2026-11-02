public class AwsS3BatchState {
    // Existing fields
    public Integer uploadedCount { get; set; }
    public Integer totalProcessed { get; set; }
    public List<String> failedUploads { get; set; }
    public Map<String, String> uploadStatusMap { get; set; }
    public Map<String, Integer> versionStats { get; set; }
    public Map<Id, ContentDocument> documentsToUpdate { get; set; }
    public Set<Id> contentDocumentIdsToDelete { get; set; }
    public Boolean allUploadsSuccessful { get; set; }
    public Boolean totalSet { get; set; }
    
    public Id uploadResultId;
    public String uploadResultStatus = 'Pending';
    public String uploadResultErrorMessage = '';
    
    // ===== NEW FIELDS FOR S3 PACKAGE EXISTENCE CHECK =====
    
    // Track if the package exists in S3
    public Boolean packageExistsInS3 { get; set; }
    
    // Track action performed: 'CREATE_NEW' or 'UPDATE_EXISTING'
    public String packageAction { get; set; }
    
    // Track versions that were skipped (already exist in S3)
    public List<String> skippedVersions { get; set; }
    
    // Track version comparison results
    public Map<String, String> versionComparisonMap { get; set; }
    
    // Track which documents were updated vs newly created
    public Map<String, String> documentOperationMap { get; set; }
    
    // Track S3 object metadata for existing files
    public Map<String, Map<String, Object>> existingS3Objects { get; set; }
    
    // Store the package folder path
    public String packageFolderPath { get; set; }
    
    // Total number of versions found in S3
    public Integer totalVersionsInS3 { get; set; }
    
    // Timestamp when package check was performed
    public DateTime packageCheckTimestamp { get; set; }
    
    // ===== CONSTRUCTOR =====
    
    public AwsS3BatchState() {
        // Initialize existing fields
        this.uploadedCount = 0;
        this.totalProcessed = 0;
        this.failedUploads = new List<String>();
        this.uploadStatusMap = new Map<String, String>();
        this.versionStats = new Map<String, Integer>();
        this.documentsToUpdate = new Map<Id, ContentDocument>();
        this.contentDocumentIdsToDelete = new Set<Id>();
        this.allUploadsSuccessful = false;
        this.totalSet = false;
        
        // Initialize new fields
        this.packageExistsInS3 = false;
        this.packageAction = 'CREATE_NEW';
        this.skippedVersions = new List<String>();
        this.versionComparisonMap = new Map<String, String>();
        this.documentOperationMap = new Map<String, String>();
        this.existingS3Objects = new Map<String, Map<String, Object>>();
        this.totalVersionsInS3 = 0;
        this.packageCheckTimestamp = System.now();
    }
    
    // ===== HELPER METHODS =====
    
    /**
     * Adds a failed upload with error message
     * @param fileName - The name of the file that failed
     * @param errorMessage - The error message
     */
    public void addFailedUpload(String fileName, String errorMessage) {
        this.failedUploads.add(fileName + ' - ' + errorMessage);
        this.uploadStatusMap.put(fileName, 'FAILED: ' + errorMessage);
    }
    
    /**
     * Adds a successful upload
     * @param fileName - The name of the file uploaded
     * @param s3Key - The S3 key where the file was uploaded
     */
    public void addSuccessfulUpload(String fileName, String s3Key) {
        this.uploadedCount++;
        this.uploadStatusMap.put(fileName, 'SUCCESS: ' + s3Key);
    }
    
    /**
     * Checks if all uploads were successful
     * @return True if all uploads succeeded, false otherwise
     */
    public Boolean isAllUploadsSuccessful() {
        Integer totalAttempted = this.uploadedCount + this.failedUploads.size();
        return totalAttempted > 0 &&
            this.failedUploads.isEmpty() &&
            this.uploadedCount == totalAttempted;
    }
    
    /**
     * Gets the number of skipped versions
     * @return The count of skipped versions
     */
    public Integer getSkippedCount() {
        return this.skippedVersions != null ? this.skippedVersions.size() : 0;
    }
    
    /**
     * Resets the state for a new batch run
     */
    public void reset() {
        this.uploadedCount = 0;
        this.totalProcessed = 0;
        this.failedUploads.clear();
        this.uploadStatusMap.clear();
        this.versionStats.clear();
        this.documentsToUpdate.clear();
        this.contentDocumentIdsToDelete.clear();
        this.allUploadsSuccessful = false;
        this.totalSet = false;
        this.skippedVersions.clear();
        this.versionComparisonMap.clear();
        this.documentOperationMap.clear();
        this.existingS3Objects.clear();
        this.totalVersionsInS3 = 0;
        this.packageCheckTimestamp = System.now();
    }
}