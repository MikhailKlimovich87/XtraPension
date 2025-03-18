public class UploadHMRCReplyController {

    @AuraEnabled
    public static String uploadFile(RequestData request) {
        if (request == null) {
            return null;
        }
        ContentVersion cv = createContentVersion(request?.fileData, request?.fileName);
        ContentDocumentLink cdl = createContentLink(cv.Id, request?.recordId);
        if (request?.recordId != null && request?.years != null && request?.ref != null) {
            update new Application__c (
                Id = request?.recordId,
                Years_Of_Work_In_The_UK__c = Decimal.valueOf(request?.years),
                HMRC_Ref__c = request?.ref,
                HMRC_Reply_Status__c = request?.typeOfReply,
                Shortfall__c = request?.shortfall,
                Caseworker__c = request?.caseworker
            );
        }
        if (cv == null || cdl == null) return null;
        return cdl.Id;
    }

    @testvisible
    private static ContentVersion createContentVersion(String base64, String filename) {
        ContentVersion cv = new ContentVersion();
        cv.VersionData = EncodingUtil.base64Decode(base64);
        cv.Title = filename;
        cv.PathOnClient = filename;
        try {
            insert cv;
            return cv;
        } catch(DMLException e) {
            System.debug(e);
            return null;
        }
    }

    @testvisible
    private static ContentDocumentLink createContentLink(String contentVersionId, String recordId) {
        if (contentVersionId == null || recordId == null) { return null; }
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id =: contentVersionId
            ].ContentDocumentId;
            cdl.LinkedEntityId = recordId;
            cdl.ShareType = 'V';
        try {
            insert cdl;
            return cdl;
        } catch(DMLException e) {
            System.debug(e);
            return null;
        }
    }

    public class RequestData {
        @AuraEnabled
        public String recordId {get; set;}
        @AuraEnabled
        public String fileData {get; set;}
        @AuraEnabled
        public String ref {get; set;}
        @AuraEnabled
        public String typeOfReply {get; set;}
        @AuraEnabled
        public String years {get; set;}
        @AuraEnabled
        public String fileName {get; set;}
        @AuraEnabled
        public String shortfall {get; set;}
        @AuraEnabled
        public String caseworker {get; set;}
    }
}