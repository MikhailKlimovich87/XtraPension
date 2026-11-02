/**
 * Service class for retrieving Email Messages and their ContentDocument attachments
 */
public with sharing class AwsS3EmailDocumentService {
    
    private Id emailMessageId;
    private AwsS3BatchState state;
    private Map<String, List<ContentVersion>> emailContentVersionMap;
    private Set<Id> contentDocumentIds;
    
    public AwsS3EmailDocumentService(Id emailMessageId, AwsS3BatchState state) {
        this.emailMessageId = emailMessageId;
        this.state = state;
        this.emailContentVersionMap = new Map<String, List<ContentVersion>>();
        this.contentDocumentIds = new Set<Id>();
    }
    
    /**
     * Retrieves Email Messages to process
     */
    public List<EmailMessage> getEmailsToProcess() {
        List<EmailMessage> emails = new List<EmailMessage>();
        
        if (emailMessageId != null) {
            // Specific email message
            List<EmailMessage> emailList = [
                SELECT Id, Subject, MessageDate, FromAddress, ToAddress, 
                       Status, HasAttachment, ParentId
                FROM EmailMessage
                WHERE Id = :emailMessageId
            ];
            
            if (!emailList.isEmpty()) {
                emails.addAll(emailList);
                // Load ContentDocument attachments for this email
                loadContentDocumentsForEmail(emailMessageId);
            }
        }
        
        return emails;
    }
    
    /**
     * Loads ContentDocument attachments for a specific email
     */
    private void loadContentDocumentsForEmail(Id emailId) {
        try {
            // Get all ContentDocumentLinks for this email
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, LinkedEntityId, ShareType, Visibility
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :emailId
            ];
            
            if (links.isEmpty()) {
                AwsS3Logger.debug('No ContentDocument links found for email: ' + emailId);
                emailContentVersionMap.put(emailId, new List<ContentVersion>());
                return;
            }
            
            // Collect all ContentDocument IDs
            Set<Id> docIds = new Set<Id>();
            for (ContentDocumentLink link : links) {
                docIds.add(link.ContentDocumentId);
            }
            this.contentDocumentIds = docIds;
            
            AwsS3Logger.debug('Found ' + docIds.size() + ' ContentDocuments linked to email: ' + emailId);
            
            // Get the latest version of each ContentDocument
            List<ContentVersion> versions = [
                SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize,
                       VersionNumber, IsLatest, VersionData, CreatedDate,
                       S3_Version_Id__c, AWS_S3_Object_Key__c, S3_Upload_Date__c,
                       S3_Upload_Status__c
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
                ORDER BY CreatedDate DESC
            ];
            
            if (!versions.isEmpty()) {
                emailContentVersionMap.put(emailId, versions);
                AwsS3Logger.debug('Loaded ' + versions.size() + ' ContentVersion(s) for email: ' + emailId);
            } else {
                emailContentVersionMap.put(emailId, new List<ContentVersion>());
                AwsS3Logger.debug('No ContentVersions found for email: ' + emailId);
            }
            
        } catch (Exception ex) {
            AwsS3Logger.error('Error loading ContentDocuments for email: ' + ex.getMessage());
            emailContentVersionMap.put(emailId, new List<ContentVersion>());
        }
    }
    
    /**
     * Gets the email content version map
     */
    public Map<String, List<ContentVersion>> getEmailContentVersionMap() {
        return emailContentVersionMap;
    }
    
    /**
     * Gets the set of ContentDocument IDs
     */
    public Set<Id> getContentDocumentIds() {
        return contentDocumentIds;
    }
    
    /**
     * Loads a full ContentVersion by ID with the VersionData
     */
    public ContentVersion loadFullVersion(Id versionId) {
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize,
                   VersionNumber, IsLatest, VersionData, CreatedDate,
                   S3_Version_Id__c, AWS_S3_Object_Key__c, S3_Upload_Date__c,
                   S3_Upload_Status__c
            FROM ContentVersion
            WHERE Id = :versionId
        ];
        return versions.isEmpty() ? null : versions[0];
    }
    
    /**
     * Deletes ContentDocument links after successful upload
     * Note: This only removes the link, not the actual ContentDocument
     */
    public void deleteContentDocumentLinks() {
        if (emailMessageId == null) return;
        
        try {
            List<ContentDocumentLink> links = [
                SELECT Id, ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :emailMessageId
            ];
            
            if (!links.isEmpty()) {
                delete links;
                AwsS3Logger.info('Deleted ' + links.size() + ' ContentDocument links from email: ' + emailMessageId);
            }
        } catch (Exception ex) {
            AwsS3Logger.error('Error deleting ContentDocument links: ' + ex.getMessage());
        }
    }
}