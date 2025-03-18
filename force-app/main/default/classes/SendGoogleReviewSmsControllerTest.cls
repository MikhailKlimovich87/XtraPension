@isTest
public class SendGoogleReviewSmsControllerTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Google_Review_Send_Date__c = Date.today();
        testApplication.Send_Google_Review_SMS__c = true;
        insert testApplication;
        XtraPension_Data__c testData = TestDataFactory.createXtraPensionDataCustomSetting(false);
        testData.Twilio_Account__c = '123456789';
        testData.Twilio_Token__c = 'QWE4512456789';
        testData.Google_Review_Message_Body__c = 'Test message';
        insert testData;
    }

    @IsTest
    static void sendMessageCase1Test(){
        Test.setMock(HttpCalloutMock.class, new TwilioSuccessMessageMock());
        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApplication = apps[0];
        Test.startTest();
        SendGoogleReviewSmsController.SendSmsResult result = SendGoogleReviewSmsController.sendGoogleReviewMessage(testApplication.Id);
        Test.stopTest();
        Assert.areEqual('success', result.variant);
        Assert.areEqual('You\'ve successfully send sms message!', result.message);
        Assert.areEqual('Success result', result.title);

    }

    @IsTest
    static void sendMessageCase2Test(){
        Test.setMock(HttpCalloutMock.class, new TwilioErrorMessageMock());
        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApplication = apps[0];
        Test.startTest();
        SendGoogleReviewSmsController.SendSmsResult result = SendGoogleReviewSmsController.sendGoogleReviewMessage(testApplication.Id);
        Test.stopTest();
        Assert.areEqual('error', result.variant);
        Assert.areEqual('Message wasn\'t sent. Error: {"error":"test"}', result.message);
        Assert.areEqual('Error!', result.title);
    }

    private class TwilioSuccessMessageMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"status":"undelivered"' +
                '}');
            res.setStatusCode(201);
            return res;
        }
    }

    private class TwilioErrorMessageMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"error":"test"' +
                '}');
            res.setStatusCode(400);
            return res;
        }
    }
}