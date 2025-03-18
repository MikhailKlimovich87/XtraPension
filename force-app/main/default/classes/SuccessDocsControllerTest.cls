@isTest
public with sharing class SuccessDocsControllerTest {
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
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Next Step 1 - Pay HMRC';
        cv.PathOnClient = 'test';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        insert cv;
        ContentVersion cvAnnualService = new ContentVersion();
        cvAnnualService.Title = 'Annual Service';
        cvAnnualService.PathOnClient = 'test';
        cvAnnualService.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        insert cvAnnualService;
        ContentVersion cvBankTransfer = new ContentVersion();
        cvBankTransfer.Title = 'Bank Transfer';
        cvBankTransfer.PathOnClient = 'test';
        cvBankTransfer.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        insert cvBankTransfer;
        ContentVersion cvPrivatePensions = new ContentVersion();
        cvPrivatePensions.Title = 'Private Pensions';
        cvPrivatePensions.PathOnClient = 'test';
        cvPrivatePensions.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        insert cvPrivatePensions;
    }

    @IsTest
    static void generateDocsTestCase1(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApp = testApps[0];
        List<ContentDocumentLink> relatedDocsBeforeExecuteMethod = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApp.Id
            AND ContentDocument.Title LIKE '%Next Step 1 - Pay HMRC%'
        ];

        System.assertEquals(true, relatedDocsBeforeExecuteMethod.isEmpty());
        Test.startTest();
        SuccessDocsController.generateDocs(testApp.Id);
        Test.stopTest();
        List<ContentDocumentLink> relatedDocsAfterExecuteMethod = [
            SELECT 
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApp.Id
            AND ContentDocument.Title LIKE '%Next Step 1 - Pay HMRC%'
        ];
        System.assertEquals(false, relatedDocsAfterExecuteMethod.isEmpty());
    }

    @IsTest
    static void generateDocsTestCase2(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        List<ContentVersion> step1Docs =[
            SELECT
                Title,
                ContentDocumentId,
                VersionData
            FROM ContentVersion
            WHERE Title = :'Next Step 1 - Pay HMRC'
        ];
        System.assertEquals(1, step1Docs.size());
        Application__c testApp = testApps[0];
        ContentDocumentLink testConDocLink = new ContentDocumentLink();
        testConDocLink.LinkedEntityId = testApp.Id;
        testConDocLink.ContentDocumentId = step1Docs[0].ContentDocumentId;
        testConDocLink.shareType = 'V';
        testConDocLink.Visibility = 'AllUsers';
        insert testConDocLink;
        Test.startTest();
        SuccessDocsController.generateDocs(testApp.Id);
        Test.stopTest();
        List<ContentVersion> step1DocsAfterExecuteMethod =[
            SELECT
                Title,
                ContentDocumentId,
                VersionData
            FROM ContentVersion
            WHERE Title = :'Next Step 1 - Pay HMRC'
        ];
        System.assertEquals(1, step1DocsAfterExecuteMethod.size());
    }
}