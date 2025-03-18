@isTest
public class ContentVersionTriggerTest {

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
    static void linkFileToApplicationDocumentCase1Test() {
        Application__c testApplication = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        ContentVersion testContentVersion = TestDataFactory.createTestContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        Test.startTest();
        insert conDocLink;
        Test.stopTest();
        List<Application_Document__c> testAppDocAfterInsert = [
            SELECT Id
            FROM Application_Document__c
            LIMIT 1
        ];
        System.assertNotEquals(null, testAppDocAfterInsert);
        List<ContentDocumentLink> testLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contDocId AND
                  LinkedEntityId = :testAppDocAfterInsert[0].Id
        ];
        System.assertNotEquals(null, testLinks);
    }

    @IsTest
    static void linkFileToApplicationDocumentCase2Test() {
        Application__c testApplication = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application_Document__c testAppDoc = TestDataFactory.createCF083ApplicationDocument(testApplication.Id, true);
        ContentVersion testContentVersion = TestDataFactory.createTestForSignatureContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        Test.startTest();
        insert conDocLink;
        Test.stopTest();
        List<ContentDocumentLink> testLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contDocId AND
                  LinkedEntityId = :testAppDoc.Id
        ];
        System.assertNotEquals(null, testLinks);
    }
}