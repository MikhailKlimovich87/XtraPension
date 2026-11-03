@isTest
public class MovedFromHMRCReply1ReportControllerTest {
    @IsTest(seeAllData=true)
    static void getReportDataTest(){
        Test.startTest();
        MovedFromHMRCReply1ReportController.ResultDataWrapper result = MovedFromHMRCReply1ReportController.getReportData();
        Test.stopTest();
        Assert.isNotNull(result.activeUsers);
        Assert.areNotEqual(0,result.activeUsers.size());
        Assert.isNotNull(result.todayChanges);
    }
}