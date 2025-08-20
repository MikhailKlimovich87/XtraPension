@isTest
public class UpdateLetterPdfTest {
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
        testApplication.Update_Letter_Template__c = '<div>Test messsage</div>';
        insert testApplication;
    }

    @IsTest
    static void generateUpdateLetterPDFTest() {
        List<Application__c> testApps = [
            SELECT
                Id,
                Update_Letter_Template__c
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.UpdateLetter;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        UpdateLetterPdf testUpdateLetter = new UpdateLetterPdf(stdController);
        Test.stopTest();
        System.assertNotEquals(null, testUpdateLetter);
        System.assertEquals(String.valueOf(testApps[0].Id), testUpdateLetter.MstrId);
    }
}