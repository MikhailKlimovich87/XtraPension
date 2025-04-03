@isTest
public class DWPOldApplicationSchedulerHandlerTest {
    @TestSetup
    static void makeData(){
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        testApplication.Status__c = 'Posted';
        Date oldDate = Date.today().addYears(-66);
        testApplication.Date_Of_Birth__c = oldDate;
        insert testApplication;
    }

    @IsTest
    static void changeAppsStatusForOldAppsTest() {
        List<Application__c> appsBeforeUpdate = [
            SELECT Status__c
            FROM Application__c
            LIMIT 1
        ];
        Assert.areEqual('Posted', appsBeforeUpdate[0].Status__c);
        Test.startTest();
        DWPOldApplicationSchedulerHandler handler = new DWPOldApplicationSchedulerHandler();
        handler.changeAppsStatusForOldApps();
        Test.stopTest();
        List<Application__c> appsAfterUpdate = [
            SELECT Status__c
            FROM Application__c
            LIMIT 1
        ];
        Assert.areNotEqual('DWP Teleclaim', appsBeforeUpdate[0].Status__c);
        Assert.areNotEqual(appsAfterUpdate[0].Status__c, appsBeforeUpdate[0].Status__c);
    }
}