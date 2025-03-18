@isTest
public class BlanketSMSSchedulerTest {
    @TestSetup
    static void makeData() {
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
        testApplication.Status__c = 'Posted';
        insert testApplication;
        TestDataFactory.createHMRCSMSScheduleDate(true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
        TestDataFactory.createHMRCSMSScheduleDate(true);
    }

    @IsTest
    static void executeScheduleTest() {
        String cronEspression = '0 0 23 * * ?';
        Test.startTest();
		Id jobId = System.schedule('Test send Blanket SMS', cronEspression, new BlanketSMSScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job Id must be not null');
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(cronEspression, ct.CronExpression);
    }
}