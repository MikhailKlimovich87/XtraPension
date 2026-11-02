@isTest
public class UploadHMRCReplyControllerTest {
    @TestSetup
    static void makeData(){
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }

    @IsTest
    static void uploadFileTest() {
        List<Application__c> testApps = [
            SELECT
                Id,
                Years_Of_Work_In_The_UK__c,
                HMRC_Ref__c,
                HMRC_Reply_Status__c
            FROM Application__c
            LIMIT 1
        ];
        if (testApps.isEmpty()) {
            return;
        }
        Application__c currApp = testApps[0];
        UploadHMRCReplyController.RequestData data = new UploadHMRCReplyController.RequestData();
        data.recordId = currApp.Id;
        data.years = '5.2';
        data.typeOfReply = 'DWP';
        data.fileName = 'Test.pdf';
        data.fileData = 'Unit Test Attachment Body';
        data.ref = 'ICW/Test';

        String testCDL = UploadHMRCReplyController.uploadFile(data);
        Assert.isNotNull(testCDL);
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                Years_Of_Work_In_The_UK__c,
                HMRC_Ref__c,
                HMRC_Reply_Status__c
            FROM Application__c
            WHERE Id = :currApp.Id
            LIMIT 1
        ];
        Application__c currAppAfterUpdate = testAppsAfterUpdate[0];
        Assert.areNotEqual(currApp.Years_Of_Work_In_The_UK__c, currAppAfterUpdate.Years_Of_Work_In_The_UK__c);
        Assert.areNotEqual(currApp.HMRC_Ref__c, currAppAfterUpdate.HMRC_Ref__c);
        Assert.areNotEqual(currApp.HMRC_Reply_Status__c, currAppAfterUpdate.HMRC_Reply_Status__c);
        Assert.areEqual('DWP', currAppAfterUpdate.HMRC_Reply_Status__c);
        Assert.areEqual('ICW/Test', currAppAfterUpdate.HMRC_Ref__c);
        Assert.areEqual(5.2, currAppAfterUpdate.Years_Of_Work_In_The_UK__c);
    }

    @IsTest
    static void getTextRecognitionDataSuccessTest() {
        Test.setMock(HttpCalloutMock.class, new HMRCTextRecognitionSuccessMock());
        XtraPension_Data__c testData = new XtraPension_Data__c();
        testData.Text_Recognition_Link__c = 'https://xtrapension.herokuapp.com/api/v1/test/pdf/upload-pdf';
        insert testData;

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('dummy file content'));
        Test.startTest();
            UploadHMRCReplyController.ExtractDataWrapper response = UploadHMRCReplyController.getTextRecognitionData(base64Content);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response wrapper should not be null');
        System.assertEquals(true, response.isSuccess, 'Expected callout to be successful');
        System.assertEquals(null, response.errorMessage, 'No error message is expected on success');
        System.assertNotEquals(null, response.extractedData, 'Extracted data should be returned');
        System.assertEquals('QQ123456C', response.extractedData.niNumber);
        System.assertEquals('OURREF', response.extractedData.ourReference);
        System.assertEquals('YOURREF', response.extractedData.yourReference);
        System.assertEquals('35', response.extractedData.qualifyingYears);
        System.assertEquals('OVREF', response.extractedData.overseasReference);
        System.assertEquals('PAYREF', response.extractedData.paymentReference);
    }

    private class HMRCTextRecognitionSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"isSuccess":true,"extractedData":{"niNumber":"QQ123456C","ourReference":"OURREF","yourReference":"YOURREF","qualifyingYears":"35","overseasReference":"OVREF","paymentReference":"PAYREF"}}');
            return res;
        }
    }
}