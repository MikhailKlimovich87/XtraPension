@isTest
public class SalesByCountryReportControllerTest {
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
        testApplication.Current_Address_Abroad_Country__c = 'USA';
        insert testApplication;
    }

    @IsTest
    static void getSalesByCountryAppsTest(){
        Test.startTest();
        SalesByCountryReportController.SalesByCountriesWrapper wrapper = SalesByCountryReportController.getSalesByCountryApps();
        Test.stopTest();
        Assert.areNotEqual(null, wrapper);
        for (SalesByCountryReportController.DateDifferenceWrapper data : wrapper.dateData) {
            if (data.name == 'Today') {
                Boolean isContainsNewApp = false;
                for (Integer item : data.countData) {
                    if (item == 1) {
                        isContainsNewApp = true;
                        break;
                    }
                }
                Assert.areEqual(true, isContainsNewApp);
            }
        }
    }
}