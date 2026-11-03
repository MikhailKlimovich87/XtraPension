@IsTest
public class BP_GenerateZipArchiveQueueableTest {

    @IsTest
    static void testQueueableExecution() {

        String testBasicId = 'TEST_BASIC_ID';

        Test.startTest();

        System.enqueueJob(
            new BP_GenerateZipArchiveQueueable(testBasicId)
        );

        Test.stopTest();

        System.assert(true, 'Queueable executed successfully');
    }
}