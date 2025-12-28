@isTest
public class AgentSalesByCountryReportControllerTest {
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
        testApplication.Agent_Making_Sale__c = 'Megan';
        insert testApplication;
    }

    @isTest
    static void getAgentSalesAppsTest() {
        Test.startTest();
        AgentSalesByCountryReportController.AgentSalesWrapper result = AgentSalesByCountryReportController.getAgentSalesApps();
        Test.stopTest();
        System.assertNotEquals(null, result);
        for (AgentSalesByCountryReportController.DateDifferenceWrapper data : result.dateData) {
            if (data.name == 'Today') {
                Boolean isContainsNewApp = false;
                for (Integer item : data.countData) {
                    if (item == 1) {
                        isContainsNewApp = true;
                        break;
                    }
                }
                System.assertEquals(true, isContainsNewApp);
            }
        }
    }
}