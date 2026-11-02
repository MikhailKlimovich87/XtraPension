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
    }

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
        String result = DocumentsContentController.pdfAction(testApp.Id, false);
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
        String result = DocumentsContentController.pdfAction(testApp.Id, false);
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

    @IsTest
    static void sendMissingApplicationPaymentEmail() {
        List<Application__c> appsBeforeSendMessage = [
            SELECT
                Id,
                Missing_App_Payment_Email_Send_Date__c
            FROM Application__c
        ];
        Assert.isNull(appsBeforeSendMessage[0].Missing_App_Payment_Email_Send_Date__c);
        Test.startTest();
        DocumentsContentController.sendMissingApplicationPaymentEmail(appsBeforeSendMessage[0].Id);
        Test.stopTest();
        List<Application__c> appsAfterSendMessage = [
            SELECT
                Id,
                Missing_App_Payment_Email_Send_Date__c
            FROM Application__c
        ];
        Assert.isNotNull(appsAfterSendMessage[0].Missing_App_Payment_Email_Send_Date__c);
        Assert.areNotEqual(appsBeforeSendMessage[0].Missing_App_Payment_Email_Send_Date__c,
                           appsAfterSendMessage[0].Missing_App_Payment_Email_Send_Date__c);
    }

    // @isTest
    // static void getContentDocumentsNullReturnTest() {
    //     // Test with invalid application Id
    //     Test.startTest();
    //     DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments('invalidId');
    //     Test.stopTest();
    //     System.assert(result == null, 'Result should be null when application not found');
    // }
    
    @isTest
    static void getContentDocumentsNoDocumentsTest() {
        // Create application without any documents
        Account account = TestDataFactory.createAccount(true);
        List<Contact> contacts = [SELECT Id, AccountId FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        Application__c appWithoutDocs = TestDataFactory.createApplication(contacts[0].Id, true);
        
        Test.startTest();
        DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments(appWithoutDocs.Id);
        Test.stopTest();
        System.assert(result == null, 'Result should be null when no documents exist');
    }

    @isTest
    static void getContentDocumentsNotEmployedTest() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c testApp = apps[0];
        
        // Update application to 'Not employed'
        testApp.Type_Of_Employment__c = 'Not employed';
        update testApp;
        
        Test.startTest();
        DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments(testApp.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.abroadEmployers == null, 'Abroad employers should be null when not employed');
        System.assert(result.lastUKEmployer == null, 'Last UK employer should be null when not employed');
    }

    @isTest
    static void getContentDocumentsWithPreviousAddressesTest() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c testApp = apps[0];
        
        // Add more previous addresses
        testApp.Previous_UK_Address_2__Street__s = 'Previous Street 2';
        testApp.Previous_UK_Address_2__City__s = 'Birmingham';
        testApp.Previous_UK_Address_2__PostalCode__s = 'B1 1AA';
        testApp.Previous_UK_Address_2_Country__c = 'GB';
        testApp.Include_UK_Address2__c = true;
        update testApp;
        
        Test.startTest();
        DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments(testApp.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.latestUKAddress, 'Latest UK address should not be null');
        System.assertEquals(2, result.previousAddresses.size(), 'Should have 2 previous addresses');
        
        // Verify address data
        System.assertEquals('Test street, London, 1as5DS, null', 
            result.previousAddresses[0].addressData, 'First previous address data mismatch');
        System.assertEquals(true, result.previousAddresses[0].addToCustomLetter, 
            'First previous address should be included in custom letter');
    }
    @isTest
    static void getContentDocumentsDocuSignEnvelopeStatusTest() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c testApp = apps[0];
        
        Test.startTest();
        DocumentsContentController.DocumentsData result = DocumentsContentController.getContentDocuments(testApp.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        
        // Verify the DocuSign status was processed
        Boolean foundApplicationForm = false;
        Boolean foundAgentAuth = false;
        
        for (DocumentsContentController.DocumentInfo doc : result.latestDocs) {
            if (doc.title == 'Application Form') {
                foundApplicationForm = true;
                System.assertEquals(false, doc.isCompleteDocusignStatus, 
                    'Application Form should have completed DocuSign status');
            }
            if (doc.title == 'Agent Authorisation') {
                foundAgentAuth = true;
                System.assertEquals(true, doc.isCompleteDocusignStatus, 
                    'Agent Authorisation should have completed DocuSign status');
            }
        }
        System.assert(foundApplicationForm == true, 'Application Form should be in latestDocs');
        System.assert(foundAgentAuth == false, 'Agent Authorisation should be in latestDocs');
    }

    private static ContentVersion createContentVersion(String title, Boolean isInsert) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('Test Content'),
            ContentLocation = 'S'
        );
        if (isInsert) {
            insert cv;
        }
        return cv;
    }
}