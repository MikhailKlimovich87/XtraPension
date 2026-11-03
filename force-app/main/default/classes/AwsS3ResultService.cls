/**
 * Service for creating AwsS3UploadResult records
 */
public class AwsS3ResultService {
    public static final String STATUS_SUCCESS = 'Success';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_PARTIAL_SUCCESS = 'Partial Success';
    public static final String STATUS_NO_FILES = 'No Files Found';
    public static final String BATCH_TYPE = 'Single File (Overwrite)';
    
    private Id applicationId;
    private AwsS3BatchState state;
    
    public AwsS3ResultService(Id applicationId, AwsS3BatchState state) {
        this.applicationId = applicationId;
        this.state = state;
    }
    
    public void createResult() {
        try {
            AwsS3UploadResult__c result = buildResultRecord();
            insert result;
            AwsS3Logger.info('Created AwsS3UploadResult record: ' + result.Id);
        } catch (Exception ex) {
            AwsS3Logger.error('Error creating AwsS3UploadResult record: ' + ex.getMessage());
        }
    }
    
    private AwsS3UploadResult__c buildResultRecord() {
        String status = determineStatus();
        Decimal successRate = calculateSuccessRate();
        String failedDetails = buildFailedDetails();
        String summary = generateConciseSummary();
        
        return new AwsS3UploadResult__c(
            Application__c = applicationId,
        Status__c = status,
        TotalProcessed__c = state.totalProcessed,
        UploadedCount__c = state.uploadedCount,
        FailedCount__c = state.failedUploads.size(),
        Success_Rate__c = successRate,
        Summary__c = summary,
        Failed_Details__c = failedDetails,
        UploadDate__c = System.now(),
        Batch_Type__c = BATCH_TYPE
            );
    }
    
    private String determineStatus() {
        if (state.totalProcessed == 0) {
            return STATUS_NO_FILES;
        }
        if (state.uploadedCount == state.totalProcessed) {
            return STATUS_SUCCESS;
        }
        if (state.uploadedCount > 0) {
            return STATUS_PARTIAL_SUCCESS;
        }
        return STATUS_FAILED;
    }
    
    private Decimal calculateSuccessRate() {
        if (state.totalProcessed == 0) {
            return 0;
        }
        Decimal rate = (state.uploadedCount * 100.0) / state.totalProcessed;
        return rate.setScale(2);
    }
    
    private String buildFailedDetails() {
        if (state.failedUploads.isEmpty()) {
            return '';
        }
        
        List<String> failedList = new List<String>();
        Integer maxDisplay = 50;
        
        for (Integer i = 0; i < state.failedUploads.size() && i < maxDisplay; i++) {
            failedList.add((i + 1) + '. ' + state.failedUploads[i]);
        }
        
        if (state.failedUploads.size() > maxDisplay) {
            failedList.add('... and ' + (state.failedUploads.size() - maxDisplay) + ' more failures');
        }
        
        String result = String.join(failedList, '\n');
        if (result.length() > 131072) {
            result = result.substring(0, 131000) + '... (truncated)';
        }
        return result;
    }
    
    private String generateConciseSummary() {
        List<String> parts = new List<String>();
        parts.add('Total: ' + state.totalProcessed);
        parts.add('Uploaded: ' + state.uploadedCount);
        parts.add('Failed: ' + state.failedUploads.size());
        
        if (state.totalProcessed > 0) {
            Decimal successRate = (state.uploadedCount * 100.0) / state.totalProcessed;
            parts.add('Rate: ' + successRate.setScale(1) + '%');
        }
        
        if (state.allUploadsSuccessful && !state.failedUploads.isEmpty()) {
            parts.add('Errors: ' + state.failedUploads.size() + ' failures');
        }
        
        String summary = String.join(parts, ' | ');
        if (summary.length() > 255) {
            summary = summary.substring(0, 252) + '...';
        }
        return summary;
    }
}