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
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Disabled', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Homemaker', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Education', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Family Carer', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Self-Employed', true);
        Employer__c testEmployer = new Employer__c(
            Start_Date__c                  = Date.valueOf('2001-03-08'),
            End_Date__c                    = Date.valueOf('2005-02-09'),
            Type__c                        = 'UK Work',
            Type_Of_UK_Employment__c       = 'Self-Employed',
            Application__c                 = testApplication.Id
        );
        insert testEmployer;
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
        System.assertEquals(11, templates.htmlInfo.size());
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