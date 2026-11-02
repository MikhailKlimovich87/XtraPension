public class UploadHMRCReplyController {
    public static final String TEXT_RECOGNITION_URL = XtraPension_Data__c.getInstance().Text_Recognition_Link__c;

    @AuraEnabled
    public static String uploadFile(RequestData request) {
        if (request == null) {
            return null;
        }
        ContentVersion cv = createContentVersion(request?.fileData, request?.fileName);
        ContentDocumentLink cdl = createContentLink(cv.Id, request?.recordId);
        List<Application__c> apps = [
            SELECT 
                HMRC_Reply_Status__c,
                Letter_Date__c
            FROM Application__c
            WHERE Id = :request.recordId
            LIMIT 1
        ];
        if (apps.size() == 0) {
            return null;
        }
        if (request?.recordId != null) {
            Application__c updatedApp = new Application__c (
                Id = request?.recordId,
                Years_Of_Work_In_The_UK__c = request?.years != null ? Decimal.valueOf(request?.years) : null,
                HMRC_Ref__c = request?.ref,
                HMRC_Reply_Status__c = request?.typeOfReply == 'STATEMENT' ||
                                       request?.typeOfReply == 'VOLUNTARY NI PAYMENT RECEIPT' ||
                                       request?.typeOfReply == 'BadStatement' ?
                                            apps[0].HMRC_Reply_Status__c :
                                            request?.typeOfReply,
                Shortfall__c = request?.shortfall,
                Caseworker__c = request?.caseworker,
                XP_Received_Date__c = request?.xpReceivedDate == null ? null : Date.valueOf(request?.xpReceivedDate)
            );
            if (request?.letterDate != null) {
                updatedApp.Letter_Date__c = Date.valueOf(request?.letterDate);
            }
            if (request?.status != null) {
                updatedApp.Status__c = request?.status;
            }
            update updatedApp;
        }
        if (cv == null || cdl == null) return null;
        return cdl.Id;
    }

    @AuraEnabled
    public static ExtractDataWrapper getTextRecognitionData(String base64) {
        ExtractDataWrapper result = new ExtractDataWrapper();
        if(String.isBlank(base64)) {
            result.isSuccess = false;
            result.errorMessage = 'The file data is missing';
            return result;
        }
        try {
          HttpRequest request = new HttpRequest();
          request.setEndpoint(TEXT_RECOGNITION_URL);
          request.setMethod('POST');
          request.setHeader('Content-Type', 'application/json;charset=UTF-8');
          request.setBody(JSON.serialize(new FileWrapper(base64)));
            request.setTimeout(120000); 
            Http http = new Http();
          HttpResponse response = http.send(request);
            if (response.getStatusCode() == 200) {
                ExtractDataWrapper extractResult = (ExtractDataWrapper)JSON.deserialize(response.getBody(), ExtractDataWrapper.class);
                result.isSuccess = true;
                result.extractedData = extractResult.extractedData;
            } else {
                result.isSuccess = false;
                result.errorMessage = 'The external service returned an error: ' + response.getBody();
            } 
        } catch (Exception ex) {
            result.isSuccess = false;
            result.errorMessage = 'An error occurred while calling the external service: ' + ex.getMessage();
        }
        return result;
    }

    private class FileWrapper { 
        public String base64 {get; set;}

        public FileWrapper(String fileData) {
            this.base64 = fileData;
        }
    }

    public class ResponseWrapper { 
        @AuraEnabled
        public String niNumber {get; set;}
        @AuraEnabled
        public String ourReference {get; set;}
        @AuraEnabled
        public String yourReference {get; set;}
        @AuraEnabled
        public String qualifyingYears {get; set;}
        @AuraEnabled
        public String overseasReference {get; set;}
        @AuraEnabled
        public String paymentReference {get; set;}
    }

    public class ExtractDataWrapper {
        @AuraEnabled
        public Boolean isSuccess {get; set;}
        @AuraEnabled
        public String errorMessage {get; set;}
        @AuraEnabled
        public ResponseWrapper extractedData {get; set;}
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
        @AuraEnabled
        public String status {get; set;}
        @AuraEnabled
        public String letterDate {get; set;}
        @AuraEnabled
        public String xpReceivedDate {get; set;}
    }
}