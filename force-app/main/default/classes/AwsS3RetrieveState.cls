/**
 * State class for S3 retrieve batch
 */
public with sharing class AwsS3RetrieveState {
    
    public Integer totalProcessed = 0;
    public Integer successfulRetrievals = 0;
    public Integer failedCount = 0;
    public Boolean totalSet = false;
    
    public List<String> failedFiles = new List<String>();
    public List<String> successFiles = new List<String>();
    public Map<String, String> fileStatusMap = new Map<String, String>();
    
    public Id uploadResultId;
    public String uploadResultStatus = 'Pending';
    public String uploadResultErrorMessage = '';
}