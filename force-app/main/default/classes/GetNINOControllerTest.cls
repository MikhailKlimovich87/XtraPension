@isTest
public class GetNINOControllerTest {
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
        testApplication.Env_A_Number__c = 'Test123456';
        testApplication.Env_B_Number__c = 'Test123456789';
        testApplication.Envelop_A__c = 'Yes';
        testApplication.Envelop_B__c = 'Yes';
        testApplication.Envelop_A_Date__c = Date.valueOf('2023-01-02');
        testApplication.Envelop_B_Date__c = Date.valueOf('2024-01-01');
        insert testApplication;
    }

    @IsTest
    static void getApplicationDataTest(){
        Application__c testApp = [
            SELECT Id
            FROM Application__c
        ];
        Test.startTest();
        GetNINOController.NINODataResult result = GetNINOController.getApplicationData(testApp.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.isSuccess);
        System.assertNotEquals(null, result.application);
        System.assertEquals(null, result.errorMessage);
        System.assertEquals('Test123456', result.application.Env_A_Number__c);
        System.assertEquals('Test123456789', result.application.Env_B_Number__c);
    }

    @IsTest
    static void getApplicationDataCase2Test(){
        Test.startTest();
        GetNINOController.NINODataResult result = GetNINOController.getApplicationData('11111111');
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(false, result.isSuccess);
        System.assertEquals('Not exist app with this record Id ', result.errorMessage);
    }

    @IsTest
    static void saveNINOEnvelopsDataTest(){
        Application__c testApp = [
            SELECT Id
            FROM Application__c
        ];
        GetNINOController.NINOSaveData saveData = new GetNINOController.NINOSaveData();
            saveData.applicationId = testApp.Id;
            saveData.posted2Envs = 'Yes';
            saveData.envelopA = 'No';
            saveData.envelopB = 'No';
            saveData.postedEnvelopA = 'Yes';
            saveData.postedEnvelopB = 'Yes';
            saveData.dateEnvelopA = Date.valueOf('2023-02-03');
            saveData.dateEnvelopB = Date.valueOf('2024-01-02');
        Test.startTest();
        GetNINOController.NINODataResult result = GetNINOController.saveNINOEnvelopsData(saveData);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.isSuccess);
        System.assertNotEquals(null, result.application);
        Application__c testAppBeforeUpdate  = [
            SELECT
                Id,
                Envelop_A__c,
                Envelop_B__c
            FROM Application__c
            WHERE Id = :testApp.Id
        ];
        System.assertEquals('No', testAppBeforeUpdate.Envelop_A__c);
        System.assertEquals('No', testAppBeforeUpdate.Envelop_B__c);
    }

    @IsTest
    static void saveNINOEnvelopsDataCase2Test(){
        Application__c testApp = [
            SELECT Id
            FROM Application__c
        ];
        GetNINOController.NINOSaveData saveData = new GetNINOController.NINOSaveData();
            saveData.applicationId = testApp.Id;
            saveData.posted2Envs = 'Yes';
            saveData.envelopA = 'Test987654';
            saveData.envelopB = 'Test654321';
            saveData.postedEnvelopA = '111';
            saveData.postedEnvelopB = '222';
            saveData.dateEnvelopA = Date.valueOf('2023-02-03');
            saveData.dateEnvelopB = Date.valueOf('2024-01-02');
        Test.startTest();
        GetNINOController.NINODataResult result = GetNINOController.saveNINOEnvelopsData(saveData);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(false, result.isSuccess);
        System.assertNotEquals(null, result.application);
        System.assertNotEquals(null, result.errorMessage);
    }


    @IsTest
    static void saveNINOEnvelopsDataCase3Test(){
        Application__c testApp = [
            SELECT Id
            FROM Application__c
        ];
        GetNINOController.NINOSaveData saveData = new GetNINOController.NINOSaveData();
            saveData.applicationId = null;
            saveData.posted2Envs = 'Yes';
            saveData.envelopA = 'Test987654';
            saveData.envelopB = 'Test654321';
            saveData.postedEnvelopA = 'Yes';
            saveData.postedEnvelopB = 'Yes';
            saveData.dateEnvelopA = Date.valueOf('2023-02-03');
            saveData.dateEnvelopB = Date.valueOf('2024-01-02');
        Test.startTest();
        GetNINOController.NINODataResult result = GetNINOController.saveNINOEnvelopsData(saveData);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(false, result.isSuccess);
        System.assertEquals(null, result.application);
        System.assertEquals('Application Id is null.', result.errorMessage);
    }

    @IsTest
    static void generateGetNINOFileTest(){
        Application__c testApp = [
            SELECT Id
            FROM Application__c
        ];
        List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Id,
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CA5403%' AND
                  LinkedEntityId = :testApp.Id
        ];
        System.assertEquals(true, oldDocuments.isEmpty());
        Test.startTest();
        GetNINOController.generateGetNINOFile(testApp.Id);
        Test.stopTest();
        List<ContentDocumentLink> docsAfterExecuteTestMethod = [
            SELECT
                ContentDocument.Id,
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CA5403%' AND
                  LinkedEntityId = :testApp.Id
        ];
        System.assertEquals(false, docsAfterExecuteTestMethod.isEmpty());
        System.assertEquals(1, docsAfterExecuteTestMethod.size());
    }
}