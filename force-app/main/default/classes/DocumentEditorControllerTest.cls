@isTest
public with sharing class DocumentEditorControllerTest {
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
    static void getEmailTemplateDataTest(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Test.startTest();
        DocumentEditorController.EditModalWrapper templates = DocumentEditorController.getEmailTemplateData(testApps[0].Id);
        Test.stopTest();
        System.assertNotEquals(true, templates.htmlInfo.isEmpty());
        System.assertEquals(9, templates.htmlInfo.size());
    }

    @IsTest
    static void generateHMRCReplyFileTest(){
        DocumentEditorController.MessageData testData = new DocumentEditorController.MessageData();
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        testData.applicationId = testApps[0].Id;
        testData.fieldValue    = '<div>Test Info</div>';
        testData.typeOfTemplate = 'NINO';
        Test.startTest();
        Id resultId = DocumentEditorController.generateHMRCReplyFile(testData);
        Test.stopTest();
        System.assertNotEquals(null, resultId);

    }
}