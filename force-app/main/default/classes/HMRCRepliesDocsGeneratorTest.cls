@isTest
public with sharing class HMRCRepliesDocsGeneratorTest {

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
        Application__c testApp = TestDataFactory.createApplication(personContactId, false);
        testApp.DWP_Status_Check_Template__c = '<p>Test 1</p>';
        testApp.Appeal_Template__c = '<p>Test 2</p>';
        insert testApp;
    }

    @IsTest
    static void genetateDWPDocTestCase1() {
        List<Application__c> apps = [
            SELECT Appeal_Template__c,
                    (SELECT ContentDocument.Title
                     FROM ContentDocumentLinks
                     WHERE ContentDocument.Title LIKE '%DWPStatusCheck%')
            FROM Application__c
            LIMIT 1
        ];
        Application__c currApp = apps[0];
        Assert.areEqual(0, currApp.ContentDocumentLinks.size());
        Test.startTest();
        System.enqueueJob(new HMRCRepliesDocsGenerator(currApp.Id, 'DWP_Status_Check_Template__c'));
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%DWPStatusCheck%')
            FROM Application__c
            WHERE Id = :currApp.Id
            LIMIT 1
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];
        Assert.areEqual(1, appAfterUpdate.ContentDocumentLinks.size());
    }

    @IsTest
    static void genetateDWPDocTestCase2() {
        List<Application__c> apps = [
            SELECT Appeal_Template__c,
                    (SELECT ContentDocument.Title
                     FROM ContentDocumentLinks
                     WHERE ContentDocument.Title LIKE '%APPEAL reply%')
            FROM Application__c
            LIMIT 1
        ];
        Application__c currApp = apps[0];
        Assert.areEqual(0, currApp.ContentDocumentLinks.size());
        Test.startTest();
        System.enqueueJob(new HMRCRepliesDocsGenerator(currApp.Id, 'Appeal_Template__c'));
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%APPEAL reply%')
            FROM Application__c
            WHERE Id = :currApp.Id
            LIMIT 1
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];
        Assert.areEqual(1, appAfterUpdate.ContentDocumentLinks.size());
    }

    @IsTest
    static void genetateCertifiedDocTest() {
        List<Application__c> apps = [
            SELECT (SELECT ContentDocument.Title
                    FROM ContentDocumentLinks
                    WHERE ContentDocument.Title LIKE '%CerifiedDoc%')
            FROM Application__c
            LIMIT 1
        ];
        Application__c currApp = apps[0];
        Assert.areEqual(0, currApp.ContentDocumentLinks.size());
        Test.startTest();
        System.enqueueJob(new HMRCRepliesDocsGenerator(currApp.Id, 'Certified_Doc_Template__c'));
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%CerifiedDoc%')
            FROM Application__c
            WHERE Id = :currApp.Id
            LIMIT 1
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];
        Assert.areEqual(1, appAfterUpdate.ContentDocumentLinks.size());
    }
}