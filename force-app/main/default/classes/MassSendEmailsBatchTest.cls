@isTest
public class MassSendEmailsBatchTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }

    @IsTest
    static void executeMassSendEmails() {
        List<Application__c> testAppsBeforeUpdate = [
            SELECT Sent_Mass_Email_Message__c
            FROM Application__c
        ];
        Assert.areEqual(false, testAppsBeforeUpdate[0].Sent_Mass_Email_Message__c);
        Test.startTest();
        MassSendEmailsBatch ba= new MassSendEmailsBatch('LIMIT 1', 'Test Message', 'Forthcoming UK State Pension Callback');
        Id jobid= Database.executeBatch(ba,1);
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT Sent_Mass_Email_Message__c
            FROM Application__c
        ];
        Assert.areNotEqual(testAppsAfterUpdate[0].Sent_Mass_Email_Message__c, testAppsBeforeUpdate[0].Sent_Mass_Email_Message__c);
        Assert.areEqual(true, testAppsAfterUpdate[0].Sent_Mass_Email_Message__c);
    }
}