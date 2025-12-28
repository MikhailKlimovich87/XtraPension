@isTest
public with sharing class CheckAgentDistributorSchedulerTest {
    @IsTest
    static void executeScheduleTest() {
        String cronEspression = '0 0 23 * * ?';
        Test.startTest();
		Id jobId = System.schedule('Test assign Check Agents to App', cronEspression, new CheckAgentDistributorScheduler());
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