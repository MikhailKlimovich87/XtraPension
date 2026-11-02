/**
 * Service for managing ContentDocument operations (update/delete)
 */
public class AwsS3ContentDocumentService {
    private AwsS3BatchState state;
    private UploadConfiguration config;
    
    public AwsS3ContentDocumentService(UploadConfiguration config, AwsS3BatchState state) {
        this.config = config;
        this.state = state;
    }
    
    public void updateDocuments() {
        if (state.documentsToUpdate.isEmpty()) {
            return;
        }
        
        try {
            List<ContentDocument> docsToUpdate = new List<ContentDocument>(state.documentsToUpdate.values());
            update docsToUpdate;
            AwsS3Logger.info('Updated ' + docsToUpdate.size() + ' ContentDocuments with S3 metadata');
            state.documentsToUpdate.clear();
        } catch (Exception ex) {
            AwsS3Logger.error('Error updating ContentDocuments: ' + ex.getMessage());
        }
    }
    
    /**
     * Deletes uploaded files from Salesforce (excluding Notes)
     * This is the main method called from the batch class
     */
    public void deleteFiles() {
        // Call the overloaded method with an empty set (no notes to exclude)
        deleteFiles(new Set<Id>());
    }
    
    /**
     * Deletes uploaded files from Salesforce, excluding Notes
     * @param noteDocumentIds - Set of ContentDocument IDs that are Notes (will not be deleted)
     */
    public void deleteFiles(Set<Id> noteDocumentIds) {
        if (!config.deleteAfterUpload || state.contentDocumentIdsToDelete.isEmpty()) {
            AwsS3Logger.debug('Skipping file deletion - deleteAfterUpload is false or no documents to delete');
            return;
        }
        
        if (!state.allUploadsSuccessful) {
            AwsS3Logger.debug('Skipping file deletion - not all uploads succeeded');
            return;
        }
        
        try {
            // Query ContentDocuments and exclude Notes in the SOQL
            List<ContentDocument> docsToDelete = [
                SELECT Id, Title, FileType
                FROM ContentDocument
                WHERE Id IN :state.contentDocumentIdsToDelete
                AND FileType NOT IN ('SNOTE', 'NOTE')  // Exclude Notes in the query
            ];
            
            // Also check the noteDocumentIds set as an additional safety check
            List<ContentDocument> finalDocsToDelete = new List<ContentDocument>();
            Integer noteCount = 0;
            
            for (ContentDocument doc : docsToDelete) {
                // Double-check if this document is in the noteDocumentIds set
                if (noteDocumentIds != null && noteDocumentIds.contains(doc.Id)) {
                    noteCount++;
                    AwsS3Logger.debug('Skipping deletion of Note: "' + doc.Title + '" (ID: ' + doc.Id + ')');
                } else {
                    finalDocsToDelete.add(doc);
                }
            }
            
            if (noteCount > 0) {
                AwsS3Logger.info('Excluded ' + noteCount + ' Note(s) from deletion (additional check)');
            }
            
            if (!finalDocsToDelete.isEmpty()) {
                delete finalDocsToDelete;
                AwsS3Logger.info('Deleted ' + finalDocsToDelete.size() + ' file(s) from Salesforce');
            } else {
                AwsS3Logger.info('No non-Note documents to delete');
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error deleting files: ' + ex.getMessage());
        }
    }
}