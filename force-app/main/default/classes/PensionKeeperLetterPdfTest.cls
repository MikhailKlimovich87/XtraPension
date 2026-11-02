@isTest
public with sharing class PensionKeeperLetterPdfTest {
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
    }

    @IsTest
    static void pensionKeeperLetterPdfTest(){
        List<Application__c> apps = [
            SELECT 
                Id
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.PensionKeeperLetter;
        pageRef.getParameters().put('id', String.valueOf(apps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(apps[0]);
        PensionKeeperLetterPdf testPensionKeeperLetter = new PensionKeeperLetterPdf(stdController);
        Test.stopTest();
    }
}