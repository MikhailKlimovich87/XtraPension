@isTest
public with sharing class DailyPaymentSchedulerTest {
    @IsTest
    static void schedulerTest(){
        Test.startTest();
        DailyPaymentScheduler testScheduler = new DailyPaymentScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test daily payment', cronEspression, testScheduler);
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