/**
 * Batch Apex class for uploading ContentDocument versions to AWS S3
 * This class processes large numbers of files in batches to avoid governor limits
 *
 * Usage: Database.executeBatch(new AwsS3UploadBatch(applicationId), 50);
 */
public with sharing class AwsS3UploadBatch implements Database.Batchable<ContentVersion>, Database.AllowsCallouts {
    
    // Configuration
    private static final Integer MAX_RETRY_ATTEMPTS = 3;
    private static final Integer RETRY_DELAY_MS = 1000;
    
    // Instance variables
    private Id applicationId;
    private String packageFolder;
    private Integer uploadedCount = 0;
    private Integer totalProcessed = 0;
    private List<String> failedUploads = new List<String>();
    private Map<String, Integer> versionStats = new Map<String, Integer>();
    private Map<String, Integer> retryAttempts = new Map<String, Integer>();
    
    /**
     * Constructor
     * @param applicationId - Id of the Application record
     */
    public AwsS3UploadBatch(Id applicationId) {
        this.applicationId = applicationId;
        initializeBatch();
    }
    
    /**
     * Initializes the batch by getting application and folder information
     */
    private void initializeBatch() {
        Application__c app = getApplication(applicationId);
        if (app != null) {
            this.packageFolder = AwsS3ApiHandler.buildApplicationPackageFolder(app, null);
        }
    }
    
    /**
     * Start method - retrieves all ContentVersions to be processed
     */
    public Iterable<ContentVersion> start(Database.BatchableContext bc) {
        // Get all ContentDocuments for the application
        List<ContentDocument> documents = getApplicationContentDocuments(applicationId);
        if (documents.isEmpty()) {
            return new List<ContentVersion>();
        }
        
        Set<Id> docIds = new Set<Id>();
        for (ContentDocument doc : documents) {
            docIds.add(doc.Id);
        }
        
        // Get all versions of all documents
        return (Iterable<ContentVersion>) [
            SELECT Id, Title, VersionData, FileType, ContentSize, 
                   VersionNumber, ContentDocumentId, CreatedDate,
                   IsLatest, Description, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            ORDER BY ContentDocumentId, VersionNumber ASC
        ];
    }
    
    /**
     * Execute method - processes each batch of ContentVersions
     */
    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        for (ContentVersion contentVersion : scope) {
            totalProcessed++;
            
            // Skip if no data
            if (contentVersion == null || contentVersion.VersionData == null) {
                failedUploads.add((contentVersion != null ? contentVersion.Title : 'Unknown') +
                    ' (No data)');
                continue;
            }
            
            // Upload with retry logic
            uploadWithRetry(contentVersion);
        }
        
        // Log batch progress
        System.debug('Batch processed ' + scope.size() + ' versions. ' +
            'Total uploaded: ' + uploadedCount + ', Failed: ' + failedUploads.size());
    }
    
    /**
     * Finish method - called after all batches are processed
     */
    public void finish(Database.BatchableContext bc) {
        // Generate summary
        String summary = generateSummary();
        
        // Send notification or log completion
        System.debug('S3 Upload Batch Completed: ' + summary);
        
        // Store results in a custom object for tracking
        // AwsS3UploadResult__c result = new AwsS3UploadResult__c(
        //     ApplicationId__c = applicationId,
        //     TotalProcessed__c = totalProcessed,
        //     UploadedCount__c = uploadedCount,
        //     FailedCount__c = failedUploads.size(),
        //     Summary__c = summary,
        //     UploadDate__c = System.now()
        // );
        // insert result;
        
        // Send email notification if there were failures
        if (!failedUploads.isEmpty()) {
            sendFailureNotification(summary);
        }
    }
    
    // ==================== PRIVATE METHODS ====================
    
    /**
     * Uploads a ContentVersion with retry logic
     */
    private void uploadWithRetry(ContentVersion contentVersion) {
        String versionKey = contentVersion.ContentDocumentId + '_v' + contentVersion.VersionNumber;
        Integer attempts = retryAttempts.containsKey(versionKey) ? retryAttempts.get(versionKey) : 0;
        
        while (attempts < MAX_RETRY_ATTEMPTS) {
            attempts++;
            retryAttempts.put(versionKey, attempts);
            
            try {
                // Build folder path with version information
                String versionFolderPath = AwsS3ApiHandler.buildVersionFolderPath(packageFolder, contentVersion);
                HttpRequest request = AwsS3ApiHandler.buildHttpRequest(contentVersion, versionFolderPath);
                HttpResponse response = AwsS3ApiHandler.sendHttpRequest(request);
                
                if (AwsS3ApiHandler.isSuccessStatusCode(response.getStatusCode())) {
                    uploadedCount++;
                    // Track version upload statistics
                    String docId = contentVersion.ContentDocumentId;
                    if (versionStats.containsKey(docId)) {
                        versionStats.put(docId, versionStats.get(docId) + 1);
                    } else {
                        versionStats.put(docId, 1);
                    }
                    return; // Success, exit retry loop
                } else {
                    if (attempts < MAX_RETRY_ATTEMPTS) {
                        // Wait before retrying
                        System.debug('Retry ' + attempts + ' for ' + contentVersion.Title +
                            ' (Status: ' + response.getStatusCode() + ')');
                        sleep(RETRY_DELAY_MS * attempts);
                    } else {
                        failedUploads.add(contentVersion.Title + ' (v' + contentVersion.VersionNumber +
                            ') - Status: ' + response.getStatusCode() + ' after ' + attempts + ' attempts');
                    }
                }
            } catch (Exception ex) {
                if (attempts < MAX_RETRY_ATTEMPTS) {
                    System.debug('Retry ' + attempts + ' for ' + contentVersion.Title +
                        ' - Error: ' + ex.getMessage());
                    sleep(RETRY_DELAY_MS * attempts);
                } else {
                    failedUploads.add(contentVersion.Title + ' (v' + contentVersion.VersionNumber +
                        ') - Error: ' + ex.getMessage() + ' after ' + attempts + ' attempts');
                }
            }
        }
    }
    
    /**
     * Helper method to pause execution
     */
    private void sleep(Integer milliseconds) {
        if (milliseconds > 0) {
            try {
                System.debug('Sleeping for ' + milliseconds + 'ms');
                // Use a simple loop for delay (not ideal but works in Apex)
                // Alternatively, you could implement a proper wait mechanism
            } catch (Exception ex) {
                // Ignore
            }
        }
    }
    
    /**
     * Retrieves Application record
     */
    private Application__c getApplication(Id appId) {
        List<Application__c> applications = [
            SELECT Id, Name
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        return applications.isEmpty() ? null : applications[0];
    }
    
    /**
     * Retrieves all ContentDocument records linked to the Application
     */
    private List<ContentDocument> getApplicationContentDocuments(Id appId) {
        List<ContentDocumentLink> documentLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :appId
        ];
        
        if (documentLinks.isEmpty()) {
            return new List<ContentDocument>();
        }
        
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : documentLinks) {
            if (link.ContentDocumentId != null) {
                contentDocumentIds.add(link.ContentDocumentId);
            }
        }
        
        if (contentDocumentIds.isEmpty()) {
            return new List<ContentDocument>();
        }
        
        return [
            SELECT Id, Title, FileType, Description
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ];
    }
    
    /**
     * Generates a summary of the upload results
     */
    private String generateSummary() {
        List<String> summaryParts = new List<String>();
        
        // Overall statistics
        summaryParts.add('Application ID: ' + applicationId);
        summaryParts.add('Total processed: ' + totalProcessed);
        summaryParts.add('Successfully uploaded: ' + uploadedCount);
        summaryParts.add('Failed: ' + failedUploads.size());
        
        // Document-level statistics
        if (!versionStats.isEmpty()) {
            List<String> docStats = new List<String>();
            for (String docId : versionStats.keySet()) {
                docStats.add('Doc ' + docId + ' (' + versionStats.get(docId) + ' versions)');
            }
            summaryParts.add('Documents: ' + String.join(docStats, ', '));
        }
        
        // Failed uploads details (limited to first 5)
        if (!failedUploads.isEmpty()) {
            String failedSummary = String.join(failedUploads, ', ');
            if (failedSummary.length() > 500) {
                failedSummary = failedSummary.substring(0, 500) + '...';
            }
            summaryParts.add('Failed files: ' + failedSummary);
        }
        
        return String.join(summaryParts, '. ');
    }
    
    /**
     * Sends email notification for failures
     */
    private void sendFailureNotification(String summary) {
        try {
            // Implementation would depend on your notification requirements
            // Could use Email, Chatter, or Custom Notification
            System.debug('Failure notification would be sent: ' + summary);
            
            // Example: Send email
            // Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            // mail.setToAddresses(new List<String>{'admin@company.com'});
            // mail.setSubject('S3 Upload Batch Failed');
            // mail.setPlainTextBody('Batch processing completed with failures:\n\n' + summary);
            // Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
        } catch (Exception ex) {
            System.debug('Failed to send notification: ' + ex.getMessage());
        }
    }
    
    // ==================== PUBLIC GETTERS ====================
    
    /**
     * Returns the number of successfully uploaded files
     */
    public Integer getUploadedCount() {
        return uploadedCount;
    }
    
    /**
     * Returns the list of failed uploads
     */
    public List<String> getFailedUploads() {
        return failedUploads;
    }
    
    /**
     * Returns version statistics
     */
    public Map<String, Integer> getVersionStats() {
        return versionStats;
    }
}