@isTest
public with sharing class HMRCAppealReplyCheckerSchedulerTest {

    @TestSetup
    public static void setup() {
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
        testApplication.Status__c = 'HMRC Appeal';
        insert testApplication;

        HMRC_Appeal_Reply__c testAppealReply = new HMRC_Appeal_Reply__c(
            Application__c = testApplication.Id,
            Sent_To_HMRC_Date__c = Date.today().addDays(-5),
            Status__c = 'Sent to HMRC'
        );
        insert testAppealReply;

    }

    @isTest
    public static void replyCheckerTest() {

        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour());

        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';

        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new HMRCAppealReplyCheckerScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedule Job Id must be not null');
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
}