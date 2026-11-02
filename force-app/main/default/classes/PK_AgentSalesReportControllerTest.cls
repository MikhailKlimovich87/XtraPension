@isTest
public with sharing class PK_AgentSalesReportControllerTest {
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
        testApplication.PK_Sale_Agent__c = 'Megan';
        insert testApplication;
    }

    @isTest
    static void getAgentSalesAppsTest() {
        Test.startTest();
        PK_AgentSalesReportController.AgentSalesWrapper result = PK_AgentSalesReportController.getAgentSalesApps();
        Test.stopTest();
        System.assertNotEquals(null, result);
        for (PK_AgentSalesReportController.DateDifferenceWrapper data : result.dateData) {
            if (data.name == 'Today') {
                Boolean isContainsNewApp = false;
                for (Integer item : data.countData) {
                    if (item == 1) {
                        isContainsNewApp = true;
                        break;
                    }
                }
                System.assertEquals(false, isContainsNewApp);
            }
        }
    }
}