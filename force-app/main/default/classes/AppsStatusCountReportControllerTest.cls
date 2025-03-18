@isTest
public class AppsStatusCountReportControllerTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }

    @IsTest
    static void getAppStatusCountTest() {
        Test.startTest();
        AppsStatusCountReportController.StatusDataCounter result = AppsStatusCountReportController.getAppStatusCount();
        Test.stopTest();
        System.assertEquals(24, result.statusData.size());
        for (AppsStatusCountReportController.StatusDataWrapper wrapper : result.statusData) {
            if (wrapper.statusName == 'Form In Progress') {
                System.assertEquals(1, wrapper.count);
            }
        }

    }
}