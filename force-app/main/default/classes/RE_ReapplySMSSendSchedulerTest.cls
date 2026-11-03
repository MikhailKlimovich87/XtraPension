@isTest
public without sharing class RE_ReapplySMSSendSchedulerTest {
    @IsTest
    static void testScheduler() {
        Test.startTest();

        String cronExp = '0 0 0 15 3 ? 2027';

        System.schedule(
            'RE Reapply SMS Send Scheduler Test',
            cronExp,
            new RE_ReapplySMSSendScheduler()
        );

        Test.stopTest();

        List<CronTrigger> cronTriggers = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                State
            FROM CronTrigger
            WHERE CronJobDetail.Name =
                'RE Reapply SMS Send Scheduler Test'
        ];

        System.assertEquals(
            1,
            cronTriggers.size(),
            'Scheduler job should exist'
        );

        System.assertEquals(
            cronExp,
            cronTriggers[0].CronExpression
        );
    }
}