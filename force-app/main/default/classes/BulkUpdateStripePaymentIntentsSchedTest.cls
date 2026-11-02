@isTest
public class BulkUpdateStripePaymentIntentsSchedTest {
    @IsTest
    static void executeScheduleTest() {
        String cronEspression = '0 0 23 * * ?';
        Id jobId = System.schedule('Test Bulk Update Payment', cronEspression, new BulkUpdateStripePaymentIntentsScheduler());

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