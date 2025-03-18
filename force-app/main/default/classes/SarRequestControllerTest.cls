@isTest
public class SarRequestControllerTest {
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
    static void getEmailBodyTest(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];
        Test.startTest();
        String result = SarRequestController.sendSAREmail(app.Id);
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();
        Assert.areEqual(1, invocations);
        Assert.areEqual(true, Boolean.valueOf(result));
    }
}