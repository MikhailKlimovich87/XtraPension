@isTest
public class GetReceiptPdfTest {
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
    static void pdfActionTest(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.GetReceipt;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        GetReceiptPdf testGetReceipt = new GetReceiptPdf(stdController);
        Test.stopTest();
        System.assertNotEquals(null, testGetReceipt.appObj);
        System.assertEquals(testApps[0].Id, testGetReceipt.appObj.Id);
    }
}