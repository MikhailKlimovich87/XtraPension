@isTest
public class CustomSummerPdfTest {
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
    static void generateClientSummaryTest(){
        List<Application__c> testApps = [
            SELECT
                Id,
                First_Name__c
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.ClientSummary;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        CustomSummerPdf testCustomSummer = new CustomSummerPdf(stdController);
        CustomSummerPdf.generateClientSummary(testApps[0].Id);
        Test.stopTest();
        List<ContentDocumentLink> relatedContentDocuments = [
            SELECT
                Id,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE
                LinkedEntityId = :testApps[0].Id AND
                ContentDocument.Title LIKE '%ClientSummary%'
        ];
        System.assertNotEquals(0, relatedContentDocuments.size(), 'Didn\'t create client letter documente');
        System.assert(relatedContentDocuments[0].ContentDocument.Title.contains(testApps[0].First_Name__c), 'ClientLetter title must contains Application First Name field');
    }
}