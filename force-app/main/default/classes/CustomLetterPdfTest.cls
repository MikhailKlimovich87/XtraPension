@isTest
public class CustomLetterPdfTest {
    @TestSetup
    static void makeData() {
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
    }

    @IsTest
    static void pdfActionTest(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.CustomLetter;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        CustomLetterPdf testCustomLetter = new CustomLetterPdf(stdController);
        PageReference testPageReference = testCustomLetter.pdfAction();
        Test.stopTest();
        System.assertNotEquals(null, testPageReference, 'PageReference is null');
        List<Application_Document__c> appDocs = [
            SELECT
                Type__c,
                File_Name__c,
                Application__c
            FROM Application_Document__c
            WHERE Application__c = :testApps[0].Id
        ];
        Application_Document__c currentAppDocs = appDocs[0];
        System.assertEquals('Custom Letter', currentAppDocs.Type__c, 'Incorrect application document type');
        System.assertEquals(testApps[0].Id, currentAppDocs.Application__c, 'Related application is wrong');
    }
}