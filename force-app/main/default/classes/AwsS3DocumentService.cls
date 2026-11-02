/**
 * Service for querying ContentDocument and ContentVersion records
 */
public class AwsS3DocumentService {
    private Id applicationId;
    private AwsS3BatchState state;
    private Map<String, List<String>> documentVersionsMap;
    
    public AwsS3DocumentService(Id applicationId, AwsS3BatchState state) {
        this.applicationId = applicationId;
        this.state = state;
        this.documentVersionsMap = new Map<String, List<String>>();
    }
    
    public List<ContentVersion> getVersionsToProcess() {
        AwsS3Logger.debug('Getting ContentDocuments for application: ' + applicationId);
        
        List<ContentDocument> documents = getApplicationContentDocuments();
        
        if (documents.isEmpty()) {
            AwsS3Logger.warn('No ContentDocuments found for application');
            state.totalProcessed = 0;
            state.totalSet = true;
            return new List<ContentVersion>();
        }
        
        // Track documents for deletion
        for (ContentDocument doc : documents) {
            state.contentDocumentIdsToDelete.add(doc.Id);
        }
        
        Set<Id> docIds = new Set<Id>();
        for (ContentDocument doc : documents) {
            docIds.add(doc.Id);
        }
        
        // ***** CRITICAL FIX: Add S3 metadata fields to the query *****
        // Query versions with S3 metadata fields
        List<ContentVersion> versions = [
            SELECT Id, Title, FileType, ContentSize, 
                   VersionNumber, ContentDocumentId, CreatedDate,
                   IsLatest, Description, FileExtension,
                   AWS_S3_Object_Key__c, S3_Version_Id__c, 
                   S3_Upload_Status__c, S3_Upload_Date__c, S3_Upload_Error__c
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds 
            AND FileExtension != 'snote'
            ORDER BY ContentDocumentId, VersionNumber ASC
        ];
        
        // Group versions by document
        for (ContentVersion version : versions) {
            String docId = version.ContentDocumentId;
            if (!documentVersionsMap.containsKey(docId)) {
                documentVersionsMap.put(docId, new List<String>());
            }
            documentVersionsMap.get(docId).add(String.valueOf(version.VersionNumber));
        }
        
        state.totalProcessed = versions.size();
        state.totalSet = true;
        
        AwsS3Logger.debug('Found ' + versions.size() + ' versions to process');
        
        return versions;
    }
    
    public ContentVersion loadFullVersion(Id versionId) {
        // Also update this method to include S3 metadata fields
        List<ContentVersion> versions = [
            SELECT Id, Title, VersionData, FileType, ContentSize, 
                   VersionNumber, ContentDocumentId, CreatedDate,
                   IsLatest, Description, FileExtension,
                   AWS_S3_Object_Key__c, S3_Version_Id__c,
                   S3_Upload_Status__c, S3_Upload_Date__c, S3_Upload_Error__c
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0];
    }
    
    public List<ContentDocument> getApplicationContentDocuments() {
        List<ContentDocumentLink> documentLinks = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
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
        
        return [
            SELECT Id, Title, FileType, Description
            FROM ContentDocument
            WHERE Id IN :contentDocumentIds
        ];
    }
    
    public Map<String, List<String>> getDocumentVersionsMap() {
        return documentVersionsMap;
    }
}