@isTest
public class ReSubLetterPdfTest {
    @IsTest
    static void reSubLetterPdfTest(){
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
        Test.startTest();
        PageReference pageRef = Page.ReSubLetter;
        pageRef.getParameters().put('id', String.valueOf(testApplication.Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApplication);
        ReSubLetterPdf testReSubLetter = new ReSubLetterPdf(stdController);
        Test.stopTest();
    }
}