@isTest
public class SFTP_PK_ListFileUploaderSchedulerTest {
    @IsTest
    static void testScheduler() {
        Test.startTest();

        String cronExp = '0 0 0 15 3 ? 2027';

        System.schedule(
            'SFTP PK List File Uploader Scheduler Test',
            cronExp,
            new SFTP_PK_ListFileUploaderScheduler()
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
                'SFTP PK List File Uploader Scheduler Test'
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