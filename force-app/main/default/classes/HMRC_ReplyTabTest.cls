@isTest
public with sharing class HMRC_ReplyTabTest {

    @TestSetup
    static void makeData() {
        // Create custom setting using TestDataFactory
        XtraPension_Data__c customSetting = TestDataFactory.createXtraPensionDataCustomSetting(false);
        customSetting.Text_Recognition_Link__c = 'https://test-text-recognition-api.com/recognize';
        insert customSetting;

        // Create test Application using TestDataFactory
        Application__c testApp = TestDataFactory.createApplication(null, false);
        testApp.National_Insurance_Number__c = 'AB123456C';
        testApp.HMRC_Ref__c = 'HMRC123';
        testApp.Years_Of_Work_In_The_UK__c = 10;
        testApp.Letter_Date__c = Date.today();
        insert testApp;
    }

    @isTest
    static void testUploadFile_Success() {
        // Given
        Application__c testApp = [SELECT Id, National_Insurance_Number__c FROM Application__c LIMIT 1];

        HMRC_ReplyTab.RequestData request = new HMRC_ReplyTab.RequestData();
        request.niNumber = new HMRC_ReplyTab.FieldData();
        request.niNumber.fieldValue = testApp.National_Insurance_Number__c;
        request.currentReplyType = new HMRC_ReplyTab.FieldData();
        request.currentReplyType.fieldValue = 'BADNINO';
        request.qualifyingYears = new HMRC_ReplyTab.FieldData();
        request.qualifyingYears.fieldValue = '15';
        request.ourReference = new HMRC_ReplyTab.FieldData();
        request.ourReference.fieldValue = 'NEW_REF_123';
        request.letterDate = new HMRC_ReplyTab.FieldData();
        request.letterDate.fieldValue = '2024-01-15';
        request.shortfall = new HMRC_ReplyTab.FieldData();
        request.shortfall.fieldValue = 'Yes';
        request.caseworker = new HMRC_ReplyTab.FieldData();
        request.caseworker.fieldValue = 'Test Caseworker';
        request.xpReceivedDate = new HMRC_ReplyTab.FieldData();
        request.xpReceivedDate.fieldValue = '2024-01-20';
        request.moveToStatus = new HMRC_ReplyTab.FieldData();
        request.moveToStatus.fieldValue = 'Pension Keeper';
        request.fileData = new HMRC_ReplyTab.FieldData();
        request.fileData.fieldValue = EncodingUtil.base64Encode(Blob.valueOf('Test PDF Content'));

        // When
        Test.startTest();
        HMRC_ReplyTab.UploadResultDataWrapper result = HMRC_ReplyTab.uploadFile(request);
        Test.stopTest();

        // Then
        System.assertEquals(true, result.isSuccess, 'Upload should be successful');
        System.assertEquals(null, result.errorMessage, 'No error message should be present');

        // Verify Application was updated
        Application__c updatedApp = [SELECT Id, Years_Of_Work_In_The_UK__c, HMRC_Ref__c, HMRC_Reply_Status__c,
                                    Shortfall__c, Caseworker__c, Status__c, Letter_Date__c, XP_Received_Date__c
                                    FROM Application__c WHERE Id = :testApp.Id];
        System.assertEquals(15, updatedApp.Years_Of_Work_In_The_UK__c, 'Qualifying years should be updated');
        System.assertEquals('NEW_REF_123', updatedApp.HMRC_Ref__c, 'HMRC reference should be updated');
        System.assertEquals('BADNINO', updatedApp.HMRC_Reply_Status__c, 'Reply status should be updated');
        System.assertEquals('Yes', updatedApp.Shortfall__c, 'Shortfall should be updated');
        System.assertEquals('Test Caseworker', updatedApp.Caseworker__c, 'Caseworker should be updated');
        System.assertEquals('Pension Keeper', updatedApp.Status__c, 'Status should be updated');
        System.assertEquals(Date.valueOf('2024-01-20'), updatedApp.XP_Received_Date__c, 'XP received date should be updated');

        // Verify ContentVersion was created
        List<ContentVersion> cvList = [SELECT Id, Title FROM ContentVersion WHERE Title LIKE '%BADNINO%'];
        System.assertEquals(1, cvList.size(), 'ContentVersion should be created');
        System.assert(cvList[0].Title.contains('BADNINO'), 'ContentVersion title should contain the reply type');
    }

    @isTest
    static void testUploadFile_NullRequest() {
        // When
        Test.startTest();
        HMRC_ReplyTab.UploadResultDataWrapper result = HMRC_ReplyTab.uploadFile(null);
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Upload should fail');
        System.assertEquals('Incoming data is empty', result.errorMessage, 'Correct error message should be returned');
    }

    @isTest
    static void testUploadFile_NullNiNumber() {
        // Given
        HMRC_ReplyTab.RequestData request = new HMRC_ReplyTab.RequestData();
        request.niNumber = null;

        // When
        Test.startTest();
        HMRC_ReplyTab.UploadResultDataWrapper result = HMRC_ReplyTab.uploadFile(request);
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Upload should fail');
        System.assertEquals('Incoming data is empty', result.errorMessage, 'Correct error message should be returned');
    }

    @isTest
    static void testUploadFile_NoApplicationFound() {
        // Given
        HMRC_ReplyTab.RequestData request = new HMRC_ReplyTab.RequestData();
        request.niNumber = new HMRC_ReplyTab.FieldData();
        request.niNumber.fieldValue = 'INVALID_NI';

        // When
        Test.startTest();
        HMRC_ReplyTab.UploadResultDataWrapper result = HMRC_ReplyTab.uploadFile(request);
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Upload should fail');
        System.assertEquals('Couldn\'t find any applications', result.errorMessage, 'Correct error message should be returned');
    }

    @isTest
    static void testGetTextRecognitionData_BlankBase64() {
        // When
        Test.startTest();
        HMRC_ReplyTab.ExtractDataWrapper result = HMRC_ReplyTab.getTextRecognitionData('');
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Text recognition should fail');
        System.assertEquals('The file data is missing', result.errorMessage, 'Correct error message should be returned');
    }

    @isTest
    static void testGetTextRecognitionData_SuccessfulRecognition() {
        // Given
        Application__c testApp = [SELECT Id, National_Insurance_Number__c, Name, HMRC_Ref__c, Years_Of_Work_In_The_UK__c FROM Application__c LIMIT 1];

        // Mock the HTTP response - matches the actual API response format
        String mockResponse = '{"extractedData":{"niNumber":"' + testApp.National_Insurance_Number__c + '","ourReference":"HMRC123","yourReference":"","qualifyingYears":"10","letterDate":"2024-01-15","currentReplyType":"","shortfall":"","caseworker":"","xpReceivedDate":"","overseasReference":"","paymentReference":"","rawText":""}}';

        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(mockResponse, 200));

        // When
        Test.startTest();
        HMRC_ReplyTab.ExtractDataWrapper result = HMRC_ReplyTab.getTextRecognitionData('dGVzdCBiYXNlNjQ='); // 'test base64' encoded
        Test.stopTest();

        // Then
        System.assertEquals(true, result.isSuccess, 'Text recognition should be successful');
        System.assertEquals(null, result.errorMessage);
        System.assertNotEquals(null, result.extractedData, 'Extracted data should not be null');
        System.assertEquals(testApp.National_Insurance_Number__c, result.extractedData.niNumber.fieldValue, 'NI Number should be populated');
        System.assertEquals(true, result.extractedData.niNumber.isMatch, 'NI Number should match');
        // Fields that match the application record should have isMatch = true
        System.assertEquals('HMRC123', result.extractedData.ourReference.fieldValue, 'Our reference should be filled from response');
        System.assertEquals(true, result.extractedData.ourReference.isMatch, 'Our reference should match');
        System.assertEquals('10', result.extractedData.qualifyingYears.fieldValue, 'Qualifying years should be filled from response');
        System.assertEquals(true, result.extractedData.qualifyingYears.isMatch, 'Qualifying years should match');
    }

    @isTest
    static void testGetTextRecognitionData_NoApplicationFound() {
        // Given - Mock response with NI number that doesn't exist
        String mockResponse = '{"extractedData":{"niNumber":"NONEXISTENT","ourReference":"","yourReference":"","qualifyingYears":"","letterDate":"","currentReplyType":"","shortfall":"","caseworker":"","xpReceivedDate":"","overseasReference":"","paymentReference":"","rawText":""}}';

        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(mockResponse, 200));

        // When
        Test.startTest();
        HMRC_ReplyTab.ExtractDataWrapper result = HMRC_ReplyTab.getTextRecognitionData('dGVzdCBiYXNlNjQ=');
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Text recognition should fail');
        System.assertEquals('Couldn\'t find any applications', result.errorMessage, 'Correct error message should be returned');
    }

    @isTest
    static void testGetTextRecognitionData_ExternalServiceError() {
        // Given - Mock error response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator('Service Unavailable', 500));

        // When
        Test.startTest();
        HMRC_ReplyTab.ExtractDataWrapper result = HMRC_ReplyTab.getTextRecognitionData('dGVzdCBiYXNlNjQ=');
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Text recognition should fail');
        System.assert(result.errorMessage.contains('The external service returned an error'), 'Correct error message should be returned');
    }

    @isTest
    static void testGetTextRecognitionData_ExceptionHandling() {
        // Given - Mock exception
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator('', 0)); // This will cause an exception

        // When
        Test.startTest();
        HMRC_ReplyTab.ExtractDataWrapper result = HMRC_ReplyTab.getTextRecognitionData('dGVzdCBiYXNlNjQ=');
        Test.stopTest();

        // Then
        System.assertEquals(false, result.isSuccess, 'Text recognition should fail');
        //System.assert(result.errorMessage.contains('An error occurred while calling the external service'), 'Correct error message should be returned');
    }

    // Mock HTTP Response Generator
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private String responseBody;
        private Integer statusCode;

        public MockHttpResponseGenerator(String responseBody, Integer statusCode) {
            this.responseBody = responseBody;
            this.statusCode = statusCode;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setBody(responseBody);
            res.setStatusCode(statusCode);
            return res;
        }
    }
}