@isTest
public class MovedToQCApprovedReportControllerTest {
    @IsTest(seeAllData=true)
    static void getReportDataTest(){
        Test.startTest();
        MovedToQCApprovedReportController.ResultDataWrapper result = MovedToQCApprovedReportController.getReportData();
        Test.stopTest();
        Assert.isNotNull(result.activeUsers);
        Assert.areNotEqual(0,result.activeUsers.size());
        Assert.isNotNull(result.todayChanges);
    }
}