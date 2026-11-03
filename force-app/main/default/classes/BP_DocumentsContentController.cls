public with sharing class BP_DocumentsContentController {
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
        System.debug('forSignatureContentDocs');
        System.debug(forSignatureContentDocs);
        if (forSignatureContentDocs.isEmpty()) {
            return null;
        }
        DocumentsData data     = new DocumentsData();
        data.latestDocs        = new List<DocumentInfo>();

        for (ContentDocumentLink link : forSignatureContentDocs) {

            DocumentInfo latestInfo = new DocumentInfo();
            String docTitle = '';
            if(link.ContentDocument.Title.contains('IPCBR1') && !link.ContentDocument.Title.contains('Wet_Signature')) {
                docTitle = 'IPCBR1 Full Form';
                latestInfo.order = 3;
                latestInfo.typeGroup = 'FullForms';
                latestInfo.redoGroup = 'FullForm';
            } else if(link.ContentDocument.Title.contains('IPC1394') && !link.ContentDocument.Title.contains('Wet_Signature')&&!link.ContentDocument.Title.contains('Payment_Notes')) {
                docTitle = 'IPC1394 Full Form';
                latestInfo.order = 4;
                latestInfo.typeGroup = 'FullForms';
                latestInfo.redoGroup = 'FullForm';
            } else if(link.ContentDocument.Title.contains('IPCBR1_Wet_Signature')) {
                docTitle = 'IPCBR1 Wet';
                latestInfo.order = 5;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'WET';
            } else if (link.ContentDocument.Title.contains('IPC1394_Wet_Signature')) {
                docTitle = 'IPC1394 Wet';
                latestInfo.order = 6;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'WET';
            } else if(link.ContentDocument.Title.contains('Client Summary')) {
                docTitle = 'Client Summary';
                latestInfo.order = 7;
                latestInfo.typeGroup = 'DocuSign';
                latestInfo.redoGroup = 'Summary';
            } else if(link.ContentDocument.Title.contains('_Pink')) {
                docTitle = 'Pink Page';
                latestInfo.order = 1;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'Color';
            } else if(link.ContentDocument.Title.contains('_Yellow')) {
                docTitle = 'Yellow Page';
                latestInfo.order = 2;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'Color';
            }  else if(link.ContentDocument.Title.contains('_DWP')) {
                docTitle = 'DWP Authority';
                latestInfo.order = 8;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'DWP';
            } else if(link.ContentDocument.Title.contains('_Stage 1')) {
                // The ZIPs are saved as "<First>_<Last>_<Claim>_Stage 1" / "_Stage 2"
                docTitle = 'Stage 1 ZIP (wet-signature pack)';
                latestInfo.order = 9;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'ColectBig';
            } else if(link.ContentDocument.Title.contains('_Stage 2')) {
                docTitle = 'Stage 2 ZIP (Big Envelope)';
                latestInfo.order = 9;
                latestInfo.typeGroup = 'FullForms';
                latestInfo.redoGroup = 'ColectFullForm';
            } else if(link.ContentDocument.Title.contains('ENVELOPE_ZIP')) {
                docTitle = link.ContentDocument.Title;
                latestInfo.order = 9;
                latestInfo.typeGroup = '';
                latestInfo.redoGroup = 'ColectBig';
            } else if(link.ContentDocument.Title.contains('_FULL_FORM_ZIP')) {
                docTitle = link.ContentDocument.Title;
                latestInfo.order = 9;
                latestInfo.typeGroup = '';
                latestInfo.redoGroup = 'ColectFullForm';
            } else if(link.ContentDocument.Title.contains('IPC1394_Payment_Notes')) {
                docTitle = 'Payment Notes';
                latestInfo.order = 10;
                latestInfo.typeGroup = 'BigEnvelope';
                latestInfo.redoGroup = 'Color';
            } else if (link.ContentDocument.Title.contains('Mandate')) {
                docTitle = 'DD Mandate';
                latestInfo.order = 11;
                latestInfo.typeGroup = 'DocuSign';
                latestInfo.redoGroup = '';
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