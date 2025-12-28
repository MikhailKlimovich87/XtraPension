@isTest
public class HMRCNotificationSchedulerTest {

    @TestSetup
    static void makeData() {
        TestDataFactory.createHMRCSMSScheduleDate(true);
    }

    @IsTest
    static void sendHMRCNotificationTest() {
        String cronEspression = '0 0 23 * * ?';
        Test.startTest();
		Id jobId = System.schedule('Test send hmrc notification', cronEspression, new HMRCNotificationScheduler());
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