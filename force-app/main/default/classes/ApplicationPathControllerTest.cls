@isTest
public class ApplicationPathControllerTest {

    @TestSetup
    static void makeData(){
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
    static void saveAppStatusTest(){
        List<Application__c> appsBeforeUpdate = [
            SELECT 
                Id,
                Status__c,
                Agent_Status__c
            FROM Application__c
        ];
        Application__c testAppBeforeUpdate = appsBeforeUpdate[0];
        Assert.areEqual('Form In Progress', testAppBeforeUpdate.Status__c);
        Test.startTest();
            ApplicationPathController.saveAppStatus('Fix', testAppBeforeUpdate.Id);
        Test.stopTest();
        List<Application__c> appsAfterUpdate = [
            SELECT 
                Status__c,
                Agent_Status__c
            FROM Application__c
        ];
        Application__c testAppAfterUpdate = appsAfterUpdate[0];

        Assert.areNotEqual(testAppAfterUpdate.Status__c, testAppBeforeUpdate.Status__c);
        Assert.areEqual('Fix', testAppAfterUpdate.Status__c);
        Assert.areEqual('Fix', testAppAfterUpdate.Agent_Status__c);
    }
}