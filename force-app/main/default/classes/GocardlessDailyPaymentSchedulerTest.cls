@isTest
public class GocardlessDailyPaymentSchedulerTest {
    @IsTest
    static void reportEmailScheduleTest() {
        Test.startTest();
        GocardlessDailyPaymentScheduler testScheduler = new GocardlessDailyPaymentScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test charge direct debit payment', cronEspression, testScheduler);
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