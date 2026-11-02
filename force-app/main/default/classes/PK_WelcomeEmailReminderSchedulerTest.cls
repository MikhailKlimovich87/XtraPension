@isTest
public class PK_WelcomeEmailReminderSchedulerTest {

    @IsTest
    static void testScheduler() {

        Test.startTest();

        String cronExp = '0 0 0 15 3 ? 2027';

        System.schedule(
            'PK Welcome Email Reminder Scheduler Test',
            cronExp,
            new PK_WelcomeEmailReminderScheduler()
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
                'PK Welcome Email Reminder Scheduler Test'
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

        AsyncApexJob batchJob = [
            SELECT
                Id,
                JobType,
                Status
            FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertEquals(
            'Queued',
            batchJob.Status
        );
    }
}