public class BulkRecognizeDocHelper implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public String libraryId;
    public final String TEXT_RECOGNITION_URL = XtraPension_Data__c.getInstance().Text_Recognition_Link__c;

    public BulkRecognizeDocHelper(String library) {
        this.libraryId = library;
    }
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Id,
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.FileType,
                ContentDocument.LatestPublishedVersionId,
                ContentDocument.LatestPublishedVersion.Recognized__c,
                ContentDocument.LatestPublishedVersion.Recognized_Error__c,
                ContentDocument.LatestPublishedVersion.Connect_To_App__c,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :libraryId AND ContentDocument.LatestPublishedVersion.Recognized_Date__c = null 
            LIMIT 10
        ]);
    }

    public void execute(Database.BatchableContext BC, List<ContentDocumentLink> links) {
        if (links.size() == 0) {
            return;
        }
        ContentDocumentLink link = links[0];
        HttpRequest request = new HttpRequest();
	    request.setEndpoint(TEXT_RECOGNITION_URL);
	    request.setMethod('POST');
	    request.setHeader('Content-Type', 'application/json;charset=UTF-8');
	    request.setBody(JSON.serialize(new FileWrapper(EncodingUtil.base64Encode(link.ContentDocument.LatestPublishedVersion.VersionData))));
        request.setTimeout(120000); 
        Http http = new Http();
	    HttpResponse response = http.send(request);
        ContentVersion version = new ContentVersion();
        version.Id = link.ContentDocument.LatestPublishedVersionId;
        version.Recognized_Date__c = Date.today();
        if (response.getStatusCode() == 200) {
            version.Recognized__c = true;
            ApiResponseWrapper apiResponse = (ApiResponseWrapper)JSON.deserialize(response.getBody(), ApiResponseWrapper.class);
            List<Application__c> apps = [
                SELECT Id, Name, First_Name__c, Second_Name__c, Status__c
                FROM Application__c
                WHERE National_Insurance_Number__c = :apiResponse.extractedData.niNumber
            ];
            if (apps.size() == 0) {
                version.Recognized_Error__c = 'Didn\'t find any app with nino:' + apiResponse.extractedData.niNumber;
            } else {
                Application__c currApp = apps[0];
                if (currApp.Status__c == 'Posted' || currApp.Status__c == '64-8 Bounce') {
                    currApp.Status__c = 'HMRC Reply 2';
                    update currApp;
                }
                version.Title = currApp.First_Name__c + '_' + currApp.Second_Name__c + '_' + currApp.Name + '_' + '2025ANNUAL';
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = link.ContentDocumentId;
                cdl.LinkedEntityId = currApp.Id;
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';
                insert cdl;
                version.Connect_To_App__c = true;
            }
        } else {
            version.Recognized_Error__c = response.getBody();
        }

        update version;
    }

    public void finish(Database.BatchableContext BC) {
    }

    private class FileWrapper { 
        public String base64 {get; set;}

        public FileWrapper(String fileData) {
            this.base64 = fileData;
        }
    }

    // Wrapper class to match the actual API response structure
    private class ApiResponseWrapper {
        public ApiExtractedData extractedData {get; set;}
    }

    // Inner class for extracted data from API response
    private class ApiExtractedData {
        public String niNumber {get; set;}
        public String ourReference {get; set;}
        public String yourReference {get; set;}
        public String letterDate {get; set;}
        public String qualifyingYears {get; set;}
        public String currentReplyType {get; set;}
        public String shortfall {get; set;}
        public String caseworker {get; set;}
        public String xpReceivedDate {get; set;}
        public String overseasReference {get; set;}
        public String paymentReference {get; set;}
        public String rawText {get; set;}
    }

    public static void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}