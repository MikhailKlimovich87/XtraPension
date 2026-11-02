@isTest
public class DWP_HMRC_C2_RejectionPdfTest {
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
        testApplication.C2_Client_Rejection_Template__c = '<div>Test messsage</div>';
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
        PageReference pageRef = Page.DWP_HMRC_C2_Rejection;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        DWP_HMRC_C2_RejectionPdf testReply = new DWP_HMRC_C2_RejectionPdf(stdController);
        Test.stopTest();
        System.assertNotEquals(null, testReply);
        System.assertEquals(String.valueOf(testApps[0].Id), testReply.MstrId);
    }
}