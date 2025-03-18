@isTest
public class MainDocsGeneratorControllerTest {

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
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @IsTest
    static void generateDocsTest() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        List<Application__c> appsBeforeGenerateDocs = [
            SELECT
                Id,
                (SELECT ContentDocumentId FROM ContentDocumentLinks)
            FROM Application__c
        ];
        Application__c testApp = appsBeforeGenerateDocs[0];
        Assert.areEqual(0, testApp.ContentDocumentLinks.size());
        Test.startTest();
        MainDocsGeneratorController.generateDocs(testApp.Id);
        Test.stopTest();
        List<Application__c> appsAfterGenerateDocs = [
            SELECT
                Id,
                (SELECT ContentDocumentId FROM ContentDocumentLinks)
            FROM Application__c
        ];
        Application__c testAppAfterGeneration = appsAfterGenerateDocs[0];
        Assert.isNotNull(testAppAfterGeneration.ContentDocumentLinks);
        Assert.areNotEqual(0, testAppAfterGeneration.ContentDocumentLinks.size());
        Assert.areEqual(4, testAppAfterGeneration.ContentDocumentLinks.size());
    }
}