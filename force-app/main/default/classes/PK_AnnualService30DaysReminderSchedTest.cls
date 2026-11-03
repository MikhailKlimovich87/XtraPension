@isTest
public with sharing class PK_AnnualService30DaysReminderSchedTest {
    @IsTest
    static void reportEmailScheduleTest() {
        Test.startTest();
        PK_AnnualService30DaysReminderScheduler testScheduler = new PK_AnnualService30DaysReminderScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test send PK Annual Service email', cronEspression, testScheduler);
        Test.stopTest();
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId];

        System.assertNotEquals(null, ct);
        System.assertEquals('0 0 23 * * ?', ct.CronExpression);
        System.assertEquals(0, ct.TimesTriggered);
    }
}