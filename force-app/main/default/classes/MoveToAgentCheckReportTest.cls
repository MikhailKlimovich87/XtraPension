@isTest
public class MoveToAgentCheckReportTest {
    @IsTest(seeAllData=true)
    static void getReportDataTest(){
        Test.startTest();
        MoveToAgentCheckReport.ResultDataWrapper result = MoveToAgentCheckReport.getReportData();
        Test.stopTest();
        Assert.isNotNull(result.activeUsers);
        Assert.areNotEqual(0,result.activeUsers.size());
        Assert.isNotNull(result.todayChanges);
    }
}