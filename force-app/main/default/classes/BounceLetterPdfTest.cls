@isTest
public class BounceLetterPdfTest {
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
        testApplication.Bounce_Letter_Template__c = '<div>Test messsage</div>';
        insert testApplication;
    }

    @IsTest
    static void generateHRMCReplyPDFTest() {
        List<Application__c> testApps = [
            SELECT
                Id,
                Bounce_Letter_Template__c
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.BounceLetter;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        BounceLetterPdf testBounceLetter = new BounceLetterPdf(stdController);
        Test.stopTest();
        System.assertNotEquals(null, testBounceLetter);
        System.assertEquals(String.valueOf(testApps[0].Id), testBounceLetter.MstrId);
    }

}