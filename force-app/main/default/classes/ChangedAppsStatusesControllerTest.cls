@isTest
public class ChangedAppsStatusesControllerTest {
    @TestSetup
    static void makeData(){
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        Date todayDate = Date.today();
        Date currentMonthStartDate = todayDate.toStartOfMonth();
        Date currentWeekStartDate = todayDate.toStartOfWeek();
        Date lastMonthStartDate = currentMonthStartDate.addMonths(-1);
        Date lastWeekStartDate = currentWeekStartDate.addDays(-7);
        testApplication.Agent_Check_Changed_Date__c = Date.today();
        testApplication.HMRC_Reply_2_Changed_Date__c = lastWeekStartDate.addDays(1);
        testApplication.Quality_Control_Changed_Date__c =lastMonthStartDate.addDays(1);
        insert testApplication;
    }

    @IsTest
    static void getAppsStatusChangedDataTest() {
        Test.startTest();
        ChangedAppsStatusesController.ApplicationStatusWrapper result = ChangedAppsStatusesController.getAppsStatusChangedData();
        Test.stopTest();
        System.assertEquals(24, result.statusData.size());
        for (ChangedAppsStatusesController.StatusWrapper status : result.statusData) {
            if (status.name == 'Form In Progress') {
                System.assertEquals(1, status.quantityPerCurrentMonth);
                System.assertEquals(0, status.quantityPerLastMonth);
                System.assertEquals(0, status.quantityPerLastWeek);
                System.assertEquals(1, status.quantityPerThisWeek);
            }
        }

    }
}