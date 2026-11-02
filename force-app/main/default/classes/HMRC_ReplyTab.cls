public with sharing class HMRC_ReplyTab {
    public static final String TEXT_RECOGNITION_URL = XtraPension_Data__c.getInstance().Text_Recognition_Link__c;
    public static final Map<String, String> TEXT_RECOGNITION_FIELDS =  new Map<String, String>{
        'niNumber' => 'National_Insurance_Number__c',
        'ourReference' => 'HMRC_Ref__c',
        'yourReference' => 'Name',
        'qualifyingYears' => 'Years_Of_Work_In_The_UK__c',
        'letterDate' => 'Letter_Date__c',
        'currentReplyType' => 'HMRC_Reply_Status__c',
        'letterDate' => 'Letter_Date__c',
        'shortfall' => 'Shortfall__c',
        'caseworker' => 'Caseworker__c',
        'xpReceivedDate' => 'XP_Received_Date__c',
        'appId' => 'Id'
    };

    @AuraEnabled
    public static UploadResultDataWrapper uploadFile(RequestData request) {
        System.debug('uploadFile called with request: ' + request);
        UploadResultDataWrapper result = new UploadResultDataWrapper();
        if (request == null || request.niNumber == null) {
            result.isSuccess = false;
            result.errorMessage = 'Incoming data is empty';
            return result;
        }
        List<Application__c> currApps = [
            SELECT
                Id,
                First_Name__c,
                Second_Name__c,
                Name,
                HMRC_Reply_Status__c,
                Years_Of_Work_In_The_UK__c,
                HMRC_Ref__c,
                Shortfall__c,
                Caseworker__c,
                XP_Received_Date__c,
                Status__c,
                Letter_Date__c
            FROM Application__c 
            WHERE National_Insurance_Number__c = :request.niNumber.fieldValue
        ];
        if (currApps.size() == 0) {
            result.isSuccess = false;
            result.errorMessage = 'Couldn\'t find any applications';
            return result;
        }
        try {
            Application__c app = currApps[0];
            ContentVersion cv = createContentVersion(
                request?.fileData.fieldValue,
                app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_' + request?.currentReplyType?.fieldValue + '.pdf'
            );
            ContentDocumentLink cdl = createContentLink(cv.Id, app.Id);

            app.Years_Of_Work_In_The_UK__c = request?.qualifyingYears?.fieldValue != null ? Decimal.valueOf(request?.qualifyingYears?.fieldValue) : null;
            app.HMRC_Ref__c = request?.ourReference?.fieldValue;
            app.HMRC_Reply_Status__c = request?.currentReplyType?.fieldValue == 'STATEMENT' || request?.currentReplyType?.fieldValue == 'VOLUNTARY NI PAYMENT RECEIPT' ?
                                            app.HMRC_Reply_Status__c :
                                            request?.currentReplyType?.fieldValue;
            app.Shortfall__c = request?.shortfall?.fieldValue;
            app.Caseworker__c = request?.caseworker?.fieldValue;
            app.Letter_Date__c = request?.letterDate?.fieldValue != null ? Date.valueOf(request?.letterDate?.fieldValue) : null;
            app.XP_Received_Date__c = request?.xpReceivedDate?.fieldValue == null ? null : Date.valueOf(request?.xpReceivedDate?.fieldValue);

            if (request?.moveToStatus?.fieldValue != null && request?.moveToStatus?.fieldValue != 'Not Move') {
                app.Status__c = request?.moveToStatus?.fieldValue;
            }
            update app;
            result.isSuccess = true;
            return result;
        } catch (Exception ex) {
            result.isSuccess = false;
            result.errorMessage = 'An error occurred while updating the application. Error message: ' + ex.getMessage();
            System.debug(ex.getMessage());
            return result;
        }
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
                System.debug('response.getBody(): ' + response.getBody());
                System.debug('1');
                ApiResponseWrapper apiResponse = (ApiResponseWrapper)JSON.deserialize(response.getBody(), ApiResponseWrapper.class);
                System.debug('2');
                System.debug(apiResponse);
                ExtractDataWrapper extractResult = convertApiResponseToExtractDataWrapper(apiResponse);
                if (extractResult != null && extractResult.extractedData != null && extractResult.extractedData.niNumber != null) {
                    System.debug('In IF');
                    List<Application__c> currApps = [
                        SELECT
                            Id,
                            HMRC_Reply_Status__c,
                            Years_Of_Work_In_The_UK__c,
                            HMRC_Ref__c,
                            Shortfall__c,
                            Caseworker__c,
                            XP_Received_Date__c,
                            Status__c,
                            Letter_Date__c,
                            National_Insurance_Number__c,
                            Name
                        FROM Application__c 
                        WHERE National_Insurance_Number__c = :extractResult.extractedData.niNumber.fieldValue
                    ];
                    if (currApps.size() == 0) {
                        System.debug('No applications found with NI Number: ' + extractResult.extractedData.niNumber);
                        result.isSuccess = false;
                        result.errorMessage = 'Couldn\'t find any applications';
                        return result;
                    }
                    System.debug('3');
                    Application__c app = currApps[0];
                    extractResult.extractedData.appId.fieldValue = app.Id;

                    for (String fieldName : TEXT_RECOGNITION_FIELDS.keySet()) {
                        System.debug('4');
                        String fieldValue;
                        switch on fieldName {
                            when 'niNumber' {
                                fieldValue = extractResult.extractedData.niNumber.fieldValue;
                            }
                            when 'ourReference' {
                                fieldValue = extractResult.extractedData.ourReference.fieldValue;
                            }
                            when 'yourReference' {
                                fieldValue = extractResult.extractedData.yourReference.fieldValue;
                            }
                            when 'qualifyingYears' {
                                fieldValue = extractResult.extractedData.qualifyingYears.fieldValue;
                            }
                            when 'letterDate' {
                                fieldValue = extractResult.extractedData.letterDate.fieldValue;
                            }
                            when 'currentReplyType' {
                                fieldValue = extractResult.extractedData.currentReplyType.fieldValue;
                            }
                            when 'shortfall' {
                                fieldValue = extractResult.extractedData.shortfall.fieldValue;
                            }
                            when 'caseworker' {
                                fieldValue = extractResult.extractedData.caseworker.fieldValue;
                            }
                            when 'xpReceivedDate' {
                                fieldValue = extractResult.extractedData.xpReceivedDate.fieldValue;
                            }
                            when 'appId' {
                                fieldValue = extractResult.extractedData.appId.fieldValue;
                            }
                        }
                            System.debug('5');
                            String sObjectFieldName = TEXT_RECOGNITION_FIELDS.get(fieldName);
                            String appFieldValue = String.valueOf(app.get(sObjectFieldName));
                            switch on fieldName {
                                when 'niNumber' {
                                    extractResult.extractedData.niNumber.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.niNumber.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'ourReference' {
                                    extractResult.extractedData.ourReference.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.ourReference.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'yourReference' {
                                    extractResult.extractedData.yourReference.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.yourReference.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'qualifyingYears' {
                                    extractResult.extractedData.qualifyingYears.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.qualifyingYears.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'letterDate' {
                                    extractResult.extractedData.letterDate.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.letterDate.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'currentReplyType' {
                                    extractResult.extractedData.currentReplyType.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.currentReplyType.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'shortfall' {
                                    extractResult.extractedData.shortfall.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.shortfall.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'caseworker' {
                                    extractResult.extractedData.caseworker.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.caseworker.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'xpReceivedDate' {
                                    extractResult.extractedData.xpReceivedDate.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.xpReceivedDate.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                                when 'appId' {
                                    extractResult.extractedData.appId.fieldValue = String.isBlank(fieldValue) ? appFieldValue : fieldValue;
                                    extractResult.extractedData.appId.isMatch = String.isNotBlank(fieldValue) ? true : false;
                                }
                            }
                    }                  
                }
                result.isSuccess = true;
                result.extractedData = extractResult.extractedData;
                System.debug('7');
            } else {
                System.debug('8');
                result.isSuccess = false;
                result.errorMessage = 'The external service returned an error: ' + response.getBody();
            } 
        } catch (Exception ex) {
            System.debug('Error calling external service: ' + ex);
            System.debug(ex.getLineNumber());
            result.isSuccess = false;
            result.errorMessage = 'An error occurred while calling the external service: ' + ex.getMessage();
        }
        return result;
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
        public FieldData currentReplyType {get; set;}
        @AuraEnabled
        public FieldData letterDate {get; set;}
        @AuraEnabled
        public FieldData shortfall {get; set;}
        @AuraEnabled
        public FieldData caseworker {get; set;}
        @AuraEnabled
        public FieldData moveToStatus {get; set;}
        @AuraEnabled
        public FieldData xpReceivedDate {get; set;}
        @AuraEnabled
        public FieldData niNumber {get; set;}
        @AuraEnabled
        public FieldData ourReference {get; set;}
        @AuraEnabled
        public FieldData yourReference {get; set;}
        @AuraEnabled
        public FieldData qualifyingYears {get; set;}
        @AuraEnabled
        public FieldData overseasReference {get; set;}
        @AuraEnabled
        public FieldData paymentReference {get; set;}
        @AuraEnabled
        public FieldData fileData {get; set;}
        @AuraEnabled
        public FieldData appId {get; set;}
    }

    public class FieldData {
        @AuraEnabled
        public String fieldValue {get; set;}
        @AuraEnabled
        public Boolean isMatch {get; set;}
    }

    public class UploadResultDataWrapper {
        @AuraEnabled
        public Boolean isSuccess {get; set;}
        @AuraEnabled
        public String errorMessage {get; set;}
    }

    private class FileWrapper { 
        public String base64 {get; set;}

        public FileWrapper(String fileData) {
            this.base64 = fileData;
        }
    }

    public class ExtractDataWrapper {
        @AuraEnabled
        public Boolean isSuccess {get; set;}
        @AuraEnabled
        public String errorMessage {get; set;}
        @AuraEnabled
        public RequestData extractedData {get; set;}
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

    // Convert API response to ExtractDataWrapper with FieldData objects
    private static ExtractDataWrapper convertApiResponseToExtractDataWrapper(ApiResponseWrapper apiResponse) {
        ExtractDataWrapper result = new ExtractDataWrapper();
        if (apiResponse == null || apiResponse.extractedData == null) {
            result.isSuccess = false;
            result.errorMessage = 'Invalid API response structure';
            return result;
        }
        RequestData extractedData = new RequestData();
        extractedData.niNumber = createFieldData(apiResponse.extractedData.niNumber);
        extractedData.ourReference = createFieldData(apiResponse.extractedData.ourReference);
        extractedData.yourReference = createFieldData(apiResponse.extractedData.yourReference);
        extractedData.letterDate = createFieldData(apiResponse.extractedData.letterDate);
        extractedData.qualifyingYears = createFieldData(apiResponse.extractedData.qualifyingYears);
        extractedData.currentReplyType = createFieldData(apiResponse.extractedData.currentReplyType);
        extractedData.shortfall = createFieldData(apiResponse.extractedData.shortfall);
        extractedData.caseworker = createFieldData(apiResponse.extractedData.caseworker);
        extractedData.xpReceivedDate = createFieldData(apiResponse.extractedData.xpReceivedDate);
        extractedData.overseasReference = createFieldData(apiResponse.extractedData.overseasReference);
        extractedData.paymentReference = createFieldData(apiResponse.extractedData.paymentReference);
        extractedData.appId = new FieldData(); // Initialize appId as empty, will be set later
        
        result.extractedData = extractedData;
        result.isSuccess = true;
        return result;
    }

    // Helper method to create FieldData from a string value
    private static FieldData createFieldData(String value) {
        FieldData fieldData = new FieldData();
        fieldData.fieldValue = value;
        fieldData.isMatch = false; // Will be set during comparison
        return fieldData;
    }
}