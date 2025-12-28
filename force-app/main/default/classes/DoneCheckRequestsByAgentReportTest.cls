@isTest
public class DoneCheckRequestsByAgentReportTest {
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
        testApplication.Check_Agent__c = 'Daniel';
        insert testApplication;
        HMRC_Check__c testHMRCCheck = TestDataFactory.createHMRC_Check(testApplication.Id, true);
    }

    @isTest
    static void getCheckAgentsDataTest() {
        Test.startTest();
        DoneCheckRequestsByAgentReportController.AgentAppsWrapper result = DoneCheckRequestsByAgentReportController.getCheckAgentsData();
        Test.stopTest();
        System.assertNotEquals(null, result);
        for (DoneCheckRequestsByAgentReportController.DateDifferenceWrapper data : result.dateData) {
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