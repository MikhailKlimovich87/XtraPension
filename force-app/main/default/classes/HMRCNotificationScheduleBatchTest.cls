@isTest
public class HMRCNotificationScheduleBatchTest {
    @TestSetup
    static void makeData() {
        List<Product2> testProducts = TestDataFactory.createProductsWithPrices();
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
        testApplication.Status__c = '64-8 Bounce';
        insert testApplication;
        XtraPension_Data__c testData = TestDataFactory.createXtraPensionDataCustomSetting(false);
        testData.Twilio_Account__c = '123456789456123';
        testData.Twilio_Token__c = '9874512457';
        insert testData;
        TestDataFactory.createHMRCSMSScheduleDate(true);
    }

    @IsTest
    static void methodName(){
        List<HMRC_SMS_Schedule_Date__c> testScheduleDates = [
            SELECT
                Id,
                Email_Body__c,
                Email_Subject__c,
                SMS_message__c,
                Processed_Application_Names__c,
                Execute_Date__c
            FROM HMRC_SMS_Schedule_Date__c
            WHERE Execute_Date__c = TODAY
            LIMIT 1
        ];
        Test.setMock(HttpCalloutMock.class, new TwilioSuccessMessageMock());
        List<TwilioSF__Message__c> twilioMessagesBeforeSend = [
            SELECT Id
            FROM TwilioSF__Message__c
        ];
        Assert.areEqual(0, twilioMessagesBeforeSend.size());
        Test.startTest();
        HMRCNotificationScheduleBatch schedulerBatch = new HMRCNotificationScheduleBatch(testScheduleDates[0]);
        Database.executeBatch(schedulerBatch, 1);
        Test.stopTest();
        List<TwilioSF__Message__c> twilioMessagesAfterSend = [
            SELECT Id
            FROM TwilioSF__Message__c
        ];
        Assert.areEqual(1, twilioMessagesAfterSend.size());
    }

    private class TwilioSuccessMessageMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"sid":"123456",' +
                    '"status":"sent",' +
                    '"direction":"test"' +
                '}'
            );
            res.setStatusCode(201);
            return res;
        }
    }
}