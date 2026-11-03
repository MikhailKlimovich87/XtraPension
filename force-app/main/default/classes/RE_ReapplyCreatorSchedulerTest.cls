@isTest
public class RE_ReapplyCreatorSchedulerTest {
    @IsTest
    static void reportEmailScheduleTest() {
        Test.startTest();
        RE_ReapplyCreatorScheduler testScheduler = new RE_ReapplyCreatorScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test create Reapply', cronEspression, testScheduler);
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