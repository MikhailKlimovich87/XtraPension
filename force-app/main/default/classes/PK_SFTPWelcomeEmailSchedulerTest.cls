@isTest
public class PK_SFTPWelcomeEmailSchedulerTest {

    @isTest
    static void testExecute() {
        Test.startTest();
        String cronExp = '0 0 0 * * ?'; // Run daily at midnight
        PK_SFTPWelcomeEmailScheduler scheduler = new PK_SFTPWelcomeEmailScheduler();
        String jobId = System.schedule('Test SFTP Welcome Email Scheduler', cronExp, scheduler);
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
        System.assertEquals(cronExp, ct.CronExpression, 'CronExpression must be like cronExp');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');

    }
}