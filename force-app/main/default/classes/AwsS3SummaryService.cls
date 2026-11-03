/**
 * Service for generating summary reports
 * Supports both Application and EmailMessage contexts
 */
public class AwsS3SummaryService {
    // Generic properties
    private Id recordId;
    private String recordType; // 'Application' or 'EmailMessage'
    private AwsS3BatchState state;
    private Map<String, List<String>> documentVersionsMap;
    private Object config; // Can be either UploadConfiguration or EmailUploadConfiguration
    
    // Application specific
    private String applicationName;
    
    // Email specific
    private String emailSubject;
    private String emailFromAddress;
    
    /**
     * Constructor for Application context
     */
    public AwsS3SummaryService(Id applicationId, AwsS3BatchState state,
    Map<String, List<String>> documentVersionsMap,
    UploadConfiguration config) {
        this.recordId = applicationId;
        this.recordType = 'Application';
        this.state = state;
        this.documentVersionsMap = documentVersionsMap;
        this.config = config;
        this.applicationName = getApplicationName(applicationId);
    }
    
    /**
     * Constructor for EmailMessage context
     */
    public AwsS3SummaryService(Id emailMessageId, AwsS3BatchState state,
    Map<String, List<String>> documentVersionsMap,
    EmailUploadConfiguration config) {
        this.recordId = emailMessageId;
        this.recordType = 'EmailMessage';
        this.state = state;
        this.documentVersionsMap = documentVersionsMap;
        this.config = config;
        
        // Get email details
        EmailMessage email = getEmailMessage(emailMessageId);
        if (email != null) {
            this.emailSubject = email.Subject;
            this.emailFromAddress = email.FromAddress;
        }
    }
    
    public String generateDetailedSummary() {
        List<String> parts = new List<String>();
        
        parts.add('=== S3 UPLOAD BATCH SUMMARY ===');
        
        // Record-specific header
        if (recordType == 'Application') {
            parts.add('Application ID: ' + recordId);
            if (String.isNotBlank(applicationName)) {
                parts.add('Application Name: ' + applicationName);
            }
        } else if (recordType == 'EmailMessage') {
            parts.add('Email Message ID: ' + recordId);
            if (String.isNotBlank(emailSubject)) {
                parts.add('Email Subject: ' + emailSubject);
            }
            if (String.isNotBlank(emailFromAddress)) {
                parts.add('Email From: ' + emailFromAddress);
            }
        }
        
        // Common statistics
        parts.add('Package Folder: ' + getPackageFolder());
        parts.add('Package Action: ' + state.packageAction);
        parts.add('Total files processed: ' + state.totalProcessed);
        parts.add('Successfully uploaded: ' + state.uploadedCount);
        parts.add('Failed: ' + state.failedUploads.size());
        parts.add('Skipped (Notes): ' + state.getSkippedCount());
        parts.add('Note: Each document is saved as a SINGLE file in S3 (overwritten with latest version)');
        
        if (state.totalProcessed > 0) {
            Decimal successRate = (state.uploadedCount * 100.0) / state.totalProcessed;
            parts.add('Success rate: ' + successRate.setScale(2) + '%');
        } else {
            parts.add('Success rate: N/A (no files processed)');
        }
        
        if (state.allUploadsSuccessful) {
            parts.add('S3 Package ID: ' + getS3PackageId());
            parts.add('Upload Date: ' + System.now().format());
        } else {
            parts.add('⚠️ WARNING: Not all uploads were successful');
            parts.add('Failed count: ' + state.failedUploads.size());
        }
        
        // Document statistics
        if (!state.versionStats.isEmpty()) {
            parts.add('--- Document Statistics ---');
            for (String docId : state.versionStats.keySet()) {
                parts.add('Document ' + docId + ': ' +
                    state.versionStats.get(docId) + ' version(s) uploaded to S3 (overwritten)');
            }
        }
        
        // Version tracking
        if (documentVersionsMap != null && !documentVersionsMap.isEmpty()) {
            parts.add('--- Versions per Document ---');
            for (String docId : documentVersionsMap.keySet()) {
                List<String> versions = documentVersionsMap.get(docId);
                if (versions != null && !versions.isEmpty()) {
                    parts.add('Document ' + docId + ': Versions ' + String.join(versions, ', '));
                }
            }
        }
        
        // Operation details
        if (!state.documentOperationMap.isEmpty()) {
            parts.add('--- Document Operations ---');
            Integer newCount = 0;
            Integer updateCount = 0;
            for (String operation : state.documentOperationMap.values()) {
                if (operation == 'CREATE_NEW') {
                    newCount++;
                } else if (operation == 'UPDATE_EXISTING') {
                    updateCount++;
                }
            }
            parts.add('New files created: ' + newCount);
            parts.add('Existing files updated: ' + updateCount);
        }
        
        // Successful uploads (limit to first 10)
        if (!state.uploadStatusMap.isEmpty()) {
            parts.add('--- Successful Uploads (first 10) ---');
            Integer count = 0;
            for (String docId : state.uploadStatusMap.keySet()) {
                String status = state.uploadStatusMap.get(docId);
                if (status.contains('SUCCESS') && count < 10) {
                    parts.add('✅ ' + docId + ': ' + status);
                    count++;
                }
            }
            if (state.uploadStatusMap.size() > 10) {
                parts.add('... and ' + (state.uploadStatusMap.size() - 10) + ' more successful uploads');
            }
        }
        
        // Failed uploads
        if (!state.failedUploads.isEmpty()) {
            parts.add('--- Failed Uploads ---');
            for (Integer i = 0; i < state.failedUploads.size() && i < 20; i++) {
                parts.add('❌ ' + (i + 1) + '. ' + state.failedUploads[i]);
            }
            if (state.failedUploads.size() > 20) {
                parts.add('... and ' + (state.failedUploads.size() - 20) + ' more failures');
            }
        }
        
        // Skipped uploads (Notes)
        if (state.getSkippedCount() > 0) {
            parts.add('--- Skipped Uploads (Notes) ---');
            parts.add(state.getSkippedCount() + ' Note(s) were skipped (not uploaded to S3)');
            // Note: We don't list individual notes to keep the summary clean
        }
        
        // Add footer
        parts.add('========================================');
        parts.add('Batch Status: ' + (state.allUploadsSuccessful ? 'COMPLETED SUCCESSFULLY' : 'COMPLETED WITH ERRORS'));
        parts.add('Timestamp: ' + System.now().format());
        
        return String.join(parts, '\n');
    }
    
    /**
     * Gets the package folder path from the appropriate config
     */
    private String getPackageFolder() {
        if (config instanceof UploadConfiguration) {
            return ((UploadConfiguration) config).packageFolder;
        } else if (config instanceof EmailUploadConfiguration) {
            return ((EmailUploadConfiguration) config).packageFolder;
        }
        return 'Unknown';
    }
    
    /**
     * Gets the S3 package ID from the appropriate config
     */
    private String getS3PackageId() {
        if (config instanceof UploadConfiguration) {
            return ((UploadConfiguration) config).s3PackageId;
        } else if (config instanceof EmailUploadConfiguration) {
            return ((EmailUploadConfiguration) config).s3PackageId;
        }
        return 'Unknown';
    }
    
    /**
     * Gets Application name
     */
    private String getApplicationName(Id appId) {
        try {
            List<Application__c> apps = [
                SELECT Name
                FROM Application__c
                WHERE Id = :appId
                LIMIT 1
            ];
            return apps.isEmpty() ? null : apps[0].Name;
        } catch (Exception ex) {
            return null;
        }
    }
    
    /**
     * Gets EmailMessage details
     */
    private EmailMessage getEmailMessage(Id emailId) {
        try {
            List<EmailMessage> emails = [
                SELECT Id, Subject, FromAddress, ToAddress, MessageDate
                FROM EmailMessage
                WHERE Id = :emailId
                LIMIT 1
            ];
            return emails.isEmpty() ? null : emails[0];
        } catch (Exception ex) {
            return null;
        }
    }
}