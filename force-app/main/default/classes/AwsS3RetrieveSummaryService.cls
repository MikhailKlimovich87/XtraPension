/**
 * Service class for generating S3 retrieve summaries
 */
public with sharing class AwsS3RetrieveSummaryService {
    
    private Id applicationId;
    private AwsS3RetrieveState state;
    private RetrieveConfiguration config;
    
    public AwsS3RetrieveSummaryService(Id applicationId, AwsS3RetrieveState state, RetrieveConfiguration config) {
        this.applicationId = applicationId;
        this.state = state;
        this.config = config;
    }
    
    /**
     * Generates detailed summary of retrieval results
     */
    public String generateDetailedSummary() {
        List<String> summaryParts = new List<String>();
        
        summaryParts.add('=== S3 RETRIEVE FILES BATCH SUMMARY ===');
        summaryParts.add('Application ID: ' + applicationId);
        summaryParts.add('S3 Package: ' + config.packageFolder);
        summaryParts.add('Upload Result ID: ' + (state.uploadResultId != null ? state.uploadResultId : 'N/A'));
        summaryParts.add('Total files: ' + state.totalProcessed);
        summaryParts.add('Successfully linked: ' + state.successfulRetrievals);
        summaryParts.add('Failed: ' + state.failedCount);
        
        if (state.totalProcessed > 0) {
            Decimal successRate = (state.successfulRetrievals * 100.0) / state.totalProcessed;
            summaryParts.add('Success rate: ' + successRate.setScale(2) + '%');
        }
        
        if (!state.successFiles.isEmpty()) {
            summaryParts.add('--- Successfully Linked Files ---');
            for (Integer i = 0; i < Math.min(state.successFiles.size(), 20); i++) {
                summaryParts.add((i + 1) + '. ' + state.successFiles[i]);
            }
            if (state.successFiles.size() > 20) {
                summaryParts.add('... and ' + (state.successFiles.size() - 20) + ' more files');
            }
        }
        
        if (!state.failedFiles.isEmpty()) {
            summaryParts.add('--- Failed Files ---');
            for (Integer i = 0; i < Math.min(state.failedFiles.size(), 20); i++) {
                summaryParts.add((i + 1) + '. ' + state.failedFiles[i]);
            }
            if (state.failedFiles.size() > 20) {
                summaryParts.add('... and ' + (state.failedFiles.size() - 20) + ' more failures');
            }
        }
        
        if (state.failedCount == 0 && state.successfulRetrievals > 0) {
            summaryParts.add('--- Package Deletion ---');
            summaryParts.add('✅ All files retrieved successfully. Package deleted from S3.');
        }
        
        return String.join(summaryParts, '\n');
    }
}