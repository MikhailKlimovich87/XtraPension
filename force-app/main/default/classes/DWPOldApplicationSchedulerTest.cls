@isTest
public class DWPOldApplicationSchedulerTest {
    @IsTest
    static void schedulerTest(){
        Test.startTest();
        DWPOldApplicationScheduler testScheduler = new DWPOldApplicationScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test status Check', cronEspression, testScheduler);
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