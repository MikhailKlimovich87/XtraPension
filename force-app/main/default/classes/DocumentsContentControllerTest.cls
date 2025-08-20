@isTest
public class DocumentsContentControllerTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Last_UK_Employer_Name__c = 'London Taxi';
        testApplication.Last_UK_Employer_Start_Date__c = Date.valueOf('1997-05-08');
        testApplication.Last_UK_Employer_End_Date__c = Date.valueOf('1999-05-08');
        testApplication.Last_UK_Employer_Address__City__s = 'London';
        testApplication.Last_UK_Employer_Address__CountryCode__s = 'GB';
        testApplication.Last_UK_Employer_Address__Street__s = 'Test Street';
        testApplication.Last_UK_Employer_Address__PostalCode__s = 'aQd1As';
        insert testApplication;
        List<ContentDocumentLink> conDocLinks = new List<ContentDocumentLink>();
        ContentVersion testContentVersion = TestDataFactory.createTestForSignatureContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        conDocLinks.add(conDocLink);
        ContentVersion customLetterContentVersion = TestDataFactory.createTestCustomLetterContentVersion(true);
        Id customLetterContDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :customLetterContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink customLetterLink = new ContentDocumentLink();
        customLetterLink.LinkedEntityId = testApplication.Id;
        customLetterLink.ContentDocumentId = customLetterContDocId;
        conDocLinks.add(customLetterLink);
        insert conDocLinks;
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Unemployed', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Retired', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Education', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Illness', true);
        TestDataFactory.createApplicationDocument(testApplication.Id, true);
    }

    @IsTest
    static void getContentDocumentsTest(){
        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApp = apps[0];
        Test.startTest();
        DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments(testApp.Id);
        Test.stopTest();
        System.assertNotEquals(null, result.application, 'Application must be not empty');
        System.assertEquals('John', result.application.First_Name__c, 'Application First_Name__c must be John');
        System.assertEquals('Snow', result.application.Second_Name__c, 'Application Second_Name__c must be Snow');
        //System.assertEquals('London Taxi', result.lastUKEmployer.employerName, 'Last UK Employer Name must be London Taxi');
    }

    @isTest
    static void getContentDocumentsTestCase2(){
        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c testApp = apps[0];
        Employer__c testEmployer = [
            SELECT
                Type__c,
                Type_Of_After_UK_Employment__c
            FROM Employer__c
            WHERE Type__c = 'Work After UK'
            LIMIT 1
        ];
        testEmployer.Type_Of_After_UK_Employment__c = 'Self-Employed';
        update testEmployer;
        Test.startTest();
        DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments(testApp.Id);
        Test.stopTest();
        System.assertNotEquals(null, result.application, 'Application must be not empty');
        System.assertEquals('John', result.application.First_Name__c, 'Application First_Name__c must be John');
        System.assertEquals('Snow', result.application.Second_Name__c, 'Application Second_Name__c must be Snow');
        //System.assertEquals('London Taxi', result.lastUKEmployer.employerName, 'Last UK Employer Name must be London Taxi');
    }

    // @isTest
    // static void getAllDocumentsTest(){
    //     List<Application__c> apps = [
    //         SELECT Id
    //         FROM Application__c
    //     ];
    //     Application__c testApp = apps[0];
    //     Test.startTest();
    //     DocumentsContentController.AllDocumentsData result = DocumentsContentController.getAllDocuments(testApp.Id);
    //     Test.stopTest();
    //     System.assertNotEquals(null, result.allDocs, 'Result must be not empty');
    //     System.assertEquals(2, result.allDocs.size(), 'Number of documents must be 2');
    // }

    @isTest
    static void changeCustomLetterTest() {
        List<Application__c> apps = [
            SELECT
                Id,
                Last_UK_Employer_Address__City__s
            FROM Application__c
        ];
        List<Employer__c> employers = [
            SELECT
                Id,
                Start_Date__c,
                Employers_Address__City__s
            FROM Employer__c
            WHERE Type__c = 'Work After UK'
        ];
        Employer__c testEmployer = employers[0];
        Application__c testApp = apps[0];
        DocumentsContentController.CustomLetterData customLetter = new DocumentsContentController.CustomLetterData();
        customLetter.applicationId = testApp.Id;
        customLetter.freeformTextLine1 = 'Test';
        DocumentsContentController.ChangedDataWrapper changeData1 = new DocumentsContentController.ChangedDataWrapper();
        changeData1.employerId = testEmployer.Id;
        changeData1.fieldName = 'Start_Date__c';
        changeData1.value = '2010-03-10';
        customLetter.newEmployerData = new List<DocumentsContentController.ChangedDataWrapper>();
        customLetter.newEmployerData.add(changeData1);
        customLetter.newPreviousAddressData = new List<DocumentsContentController.ChangedDataWrapper>();
        Test.startTest();
        String result = DocumentsContentController.changeCustomLetter(customLetter);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result must be not empty');
        System.assert(Boolean.valueOf(result), 'Result must be true');
    }


    @isTest
    static void pdfActionTest() {
        List<Application__c> apps = [
            SELECT
                Id
            FROM Application__c
        ];
        Application__c testApp = apps[0];
        Test.startTest();
        String result = DocumentsContentController.pdfAction(testApp.Id);
        System.assertNotEquals(null, result, 'Result must be not empty');
        System.assertEquals('Success', result, 'Result must be true');
        Test.stopTest();
    }

    @isTest
    static void pdfActionCase2Test() {
        List<ContentDocument> customLetterDoc = [
            SELECT Id
            FROM ContentDocument
            WHERE Title LIKE '%CustomLetter%'
        ];
        delete customLetterDoc;
        List<Application__c> apps = [
            SELECT
                Id
            FROM Application__c
        ];
        Application__c testApp = apps[0];
        Test.startTest();
        String result = DocumentsContentController.pdfAction(testApp.Id);
        System.assertNotEquals(null, result, 'Result must be not empty');
        System.assertEquals('Success', result, 'Result must be true');
        Test.stopTest();
    }

    @IsTest
    static void sendHMRCResultTest(){
        List<Application__c> apps = [
            SELECT
                Id
            FROM Application__c
        ];
        Application__c testApp = apps[0];
        DocumentsContentController.ResultEmailDataWrapper testData = new DocumentsContentController.ResultEmailDataWrapper();
        testData.applicationId = testApp.Id;
        testData.htmlBody = '<div>test</div>';
        testData.subject = 'Test message';
        testData.documentsIds = new List<String>();
        Test.startTest();
        DocumentsContentController.SendEmailResultWrapper sendResult = DocumentsContentController.sendHMRCResult(testData);
        Test.stopTest();
        System.assertNotEquals(null, sendResult);
        System.assertEquals(true, sendResult.isSuccess);
    }
}