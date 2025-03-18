@isTest
public with sharing class GoogleReviewSMSSchedulerTest {

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
        testApplication.Google_Review_Send_Email_Date_1__c = Date.today();
        insert testApplication;
        XtraPension_Data__c testData = TestDataFactory.createXtraPensionDataCustomSetting(false);
        testData.Twilio_Account__c = '123456789';
        testData.Twilio_Token__c = 'QWE4512456789';
        testData.Google_Review_Message_Body__c = 'Test message';
        insert testData;
    }

    @IsTest
    static void executeSchedulerTest(){
        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);

        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';

        Test.setMock(HttpCalloutMock.class, new TwilioMessageMock());

        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new GoogleReviewSMSScheduler());
        Test.stopTest();
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId
        ];
        System.assertEquals(scheduleTime, ct.CronExpression, 'CronExpression must be like scheduleTime');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');
    }

    private class TwilioMessageMock implements HttpCalloutMock {
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
}