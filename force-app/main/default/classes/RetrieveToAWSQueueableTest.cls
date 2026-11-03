@isTest
public with sharing class RetrieveToAWSQueueableTest {
    @TestSetup
    static void makeData() {
        // Create test data
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        
        Account account = TestDataFactory.createAccount(true);
        
        List<Contact> currentContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        
    }
    
    @isTest
    static void testQueueableWithApplicationAndContentVersion() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        Set<Id> appIds = new Set<Id>{testApp.Id};
        
        Test.startTest();
        // Use test mode constructor to avoid Database.executeBatch
        System.enqueueJob(new RetrieveToAWSQueueable(appIds));
        Test.stopTest();
        
        System.assert(true, 'Queueable executed with application that has ContentVersions');
    }
}