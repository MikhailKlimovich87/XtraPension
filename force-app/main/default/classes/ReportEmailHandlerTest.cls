@isTest
public class ReportEmailHandlerTest {

    @IsTest(SeeAllData='true')
    static void myTestMethod1() {
        Test.startTest();
        ReportEmailHandler.sendReport(
            'Applications_With_Posted_Status_7ea',
	        new String[]{
                'test.user@gmail.com'
            },
            'Test'
        );
        Test.stopTest();
        Integer invocations = Limits.getEmailInvocations();
        System.assertEquals(0, invocations, 'An email should be sent');
    }
}