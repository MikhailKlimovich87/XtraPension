@isTest
public class SendToPHReportControllerTest {
    @IsTest(seeAllData=true)
    static void getReportDataTest(){
        Test.startTest();
        SendToPHReportController.ResultDataWrapper result = SendToPHReportController.getReportData();
        Test.stopTest();
        Assert.isNotNull(result.activeUsers);
        Assert.areNotEqual(0,result.activeUsers.size());
        Assert.isNotNull(result.todayChanges);
    }
}