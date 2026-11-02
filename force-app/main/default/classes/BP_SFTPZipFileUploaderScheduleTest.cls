@IsTest
public class BP_SFTPZipFileUploaderScheduleTest {

    @IsTest
    static void testSchedulerExecute() {
        BP_SFTPZipFileUploaderSchedule scheduler =
            new BP_SFTPZipFileUploaderSchedule();
        Test.startTest();
        scheduler.execute(null);
        Test.stopTest();
        System.assert(true);
    }



    @IsTest
    static void testScheduledJob() {
        Test.startTest();
        String cron = '0 0 12 * * ?';
        System.schedule(
            'BP SFTP Upload Schedule Test',
            cron,
            new BP_SFTPZipFileUploaderSchedule()
        );
        Test.stopTest();
        CronTrigger job = [
            SELECT 
                Id,
                State,
                CronExpression
            FROM CronTrigger
            WHERE CronJobDetail.Name = 'BP SFTP Upload Schedule Test'
            LIMIT 1
        ];
        System.assertNotEquals(
            null,
            job.Id
        );
        System.assertEquals(
            cron,
            job.CronExpression
        );
    }
}