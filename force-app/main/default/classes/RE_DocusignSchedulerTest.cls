@isTest
public with sharing class RE_DocusignSchedulerTest {
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, false);
        testReapply.Status__c = 'Form Completed';
        testReapply.Form_Complete_Date__c = Date.today().addDays(-3);
        insert testReapply;
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @IsTest
    static void checkStatusSuccesResultTest(){
        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);
        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';
        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new RE_DocusignScheduler());
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