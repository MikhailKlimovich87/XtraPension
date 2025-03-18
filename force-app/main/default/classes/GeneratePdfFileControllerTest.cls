@isTest
public class GeneratePdfFileControllerTest {
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
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Employed', true);
        TestDataFactory.createCF083ApplicationDocument(testApplication.Id, true);
        TestDataFactory.createAgentApplicationDocument(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @IsTest
    static void getApplicationTest() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApp = testApps[0];
        Test.startTest();
        GeneratePdfFileController.ApplicationDocsWrapper result = GeneratePdfFileController.getApplication(testApp.Id);
        Test.stopTest();
        List<ContentDocumentLink> contentDocumLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApp.Id
        ];
        Id cf083ContDocumId;
        Id agentContDocumId;
        for (ContentDocumentLink link : contentDocumLinks) {
            if (link.ContentDocument.Title.contains('CF083')) {
                cf083ContDocumId = link.ContentDocumentId;
            }
            if (link.ContentDocument.Title.contains('64-8')) {
                agentContDocumId = link.ContentDocumentId;
            }
        }
        System.assertNotEquals(null, result, 'ApplicationDocsWrapper must be not null');
        System.assertEquals('Success', result.status, 'Status must be Success');
        System.assert(result.cf83DocLink.contains(cf083ContDocumId), 'CF083 file link must contains content document link');
        System.assert(result.agentDocLink.contains(agentContDocumId), 'Agent file link must contains content document link');
    }
}