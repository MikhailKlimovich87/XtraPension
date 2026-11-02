public with sharing class RE_DocumentsContentController {
    @AuraEnabled(cacheable='false')
    public static DocumentsData getContentDocuments(String recordId){
        
        List<ContentDocumentLink> forSignatureContentDocs = [
        SELECT
            ContentDocumentId,
            ContentDocument.Title,
            LinkedEntityId,
            ContentDocument.LatestPublishedVersion.CreatedDate
        FROM ContentDocumentLink
        WHERE
            LinkedEntityId = :recordId
        ];
        
        if (forSignatureContentDocs.isEmpty()) {
            return null;
        }
        DocumentsData data     = new DocumentsData();
        data.latestDocs        = new List<DocumentInfo>();
        
        for (ContentDocumentLink link : forSignatureContentDocs) {
            
            DocumentInfo latestInfo = new DocumentInfo();
            String docTitle = '';
            if(link.ContentDocument.Title.contains('CF083') && link.ContentDocument.Title.contains('completed')) {
                docTitle = 'CF083';
                latestInfo.order = 1;
                latestInfo.typeGroup = 'Completed';
                latestInfo.redoGroup = 'Completed';
            }

            if(link.ContentDocument.Title.contains('RVN') && link.ContentDocument.Title.contains('completed')) {
                docTitle = 'RVN';
                latestInfo.order = 1;
                latestInfo.typeGroup = 'Completed';
                latestInfo.redoGroup = 'Completed';
            }

            if(link.ContentDocument.Title.contains('CF083') && !link.ContentDocument.Title.contains('completed')) {
                docTitle = 'CF083';
                latestInfo.order = 1;
                latestInfo.typeGroup = 'Reapply';
                latestInfo.redoGroup = 'Reapply';
            }

            if(link.ContentDocument.Title.contains('RVN') && !link.ContentDocument.Title.contains('completed')) {
                docTitle = 'RVN';
                latestInfo.order = 1;
                latestInfo.typeGroup = 'Reapply';
                latestInfo.redoGroup = 'Reapply';
            }
            
            latestInfo.title = docTitle;
            latestInfo.documentId  = link.ContentDocumentId;
            
            Datetime docCreatedDate = link.ContentDocument.LatestPublishedVersion.CreatedDate;
            latestInfo.createdDate = docCreatedDate != null ? docCreatedDate.format('EEE dd MMM yyyy') : '';
            
            latestInfo.isCustomLetter = false;
            
            latestInfo.isApplicationForm = false;
            
            latestInfo.isAgentAuthorisation  = true;
            
            data.latestDocs.add(latestInfo);
        }
        data.latestDocs.sort();
        return data;
    }
    
    public class DocumentsData {
        @AuraEnabled
        public List<DocumentInfo> latestDocs{get; set;}
    }
    
    public class DocumentInfo  implements Comparable {
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String documentId;
        @AuraEnabled
        public String createdDate;
        @AuraEnabled
        public Boolean isCustomLetter;
        @AuraEnabled
        public Boolean isHMRCReply;
        @AuraEnabled
        public Boolean isApplicationForm = false;
        @AuraEnabled
        public Boolean isAgentAuthorisation = false;
        @AuraEnabled
        public String hmrcReplyStatus;
        @AuraEnabled
        public Boolean isCompleteDocusignStatus = false;
        @AuraEnabled
        public Integer order;
        @AuraEnabled
        public String typeGroup;
        @AuraEnabled
        public String redoGroup;
        
        public Integer compareTo(Object obj) {
            DocumentInfo other = (DocumentInfo)obj;
            if (this.order == other.order) {
                return 0;
            }
            return this.order < other.order ? -1 : 1;
        }
    }
}