@isTest
public with sharing class GeneratePDFCalloutTest {
    @TestSetup
    static void setup() {
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
        ContentVersion testContentVersion = TestDataFactory.createTestContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        insert conDocLink;
        Agent__c testAgent = TestDataFactory.createAgent(true);
        testApplication.Agent__c = testAgent.Id;
        update testApplication;
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        TestDataFactory.createPayment(testApplication.Id, order.Id, true);
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @IsTest
    static void executeMethodTestCase1() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        GeneratePDFCallout testPdfCallout = new GeneratePDFCallout(testApps[0].Id);
        Test.startTest();
        Id jobId = System.enqueueJob(testPdfCallout);
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job Id must be not null');
        AsyncApexJob job = [
            SELECT
                Id,
                Status,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobID];
        System.assertEquals('Completed', job.Status, 'Job Status should be Completed');
        System.assertEquals(0, job.NumberOfErrors, 'NumberOfErrors should be 0');
    }

    @IsTest
    static void executeMethodTestCase2() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApp = testApps[0];
        TestDataFactory.createCF083ApplicationDocument(testApp.Id, true);
        TestDataFactory.createAgentApplicationDocument(testApp.Id, true);
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        GeneratePDFCallout testPdfCallout = new GeneratePDFCallout(testApp.Id);
        Test.startTest();
        Id jobId = System.enqueueJob(testPdfCallout);
        Test.stopTest();
        AsyncApexJob job = [
            SELECT
                Id,
                Status,
                NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobID];
        System.assertEquals('Completed', job.Status, 'Job Status should be Completed');
        System.assertEquals(0, job.NumberOfErrors, 'NumberOfErrors should be 0');
    }
}