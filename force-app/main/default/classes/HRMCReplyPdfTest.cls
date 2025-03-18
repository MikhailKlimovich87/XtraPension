@isTest
public with sharing class HRMCReplyPdfTest {
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
        testApplication.NINO_Template__c = '<div>Test messsage</div>';
        insert testApplication;
    }

    @IsTest
    static void generateHRMCReplyPDFTest() {
        List<Application__c> testApps = [
            SELECT
                Id,
                NINO_Template__c
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.HRMCReply;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        pageRef.getParameters().put('template', 'NINO_Template__c');
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        HRMCReplyPdf testHMRCReply = new HRMCReplyPdf(stdController);
        Test.stopTest();
        System.assertNotEquals(null, testHMRCReply);
        System.assertEquals(String.valueOf(testApps[0].Id), testHMRCReply.MstrId);
    }
}