@isTest
public class MovedFromAgentCallReportControllerTest {
    @IsTest(seeAllData=true)
    static void getReportDataTest(){
        Test.startTest();
        MovedFromAgentCallReportController.ResultDataWrapper result = MovedFromAgentCallReportController.getReportData();
        Test.stopTest();
        Assert.isNotNull(result.activeUsers);
        Assert.areNotEqual(0,result.activeUsers.size());
        Assert.isNotNull(result.todayChanges);
    }
}