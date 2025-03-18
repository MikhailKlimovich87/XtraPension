@isTest
public class GetNINOPdfTest {
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
        TestDataFactory.createEmployer(
            testApplication.Id,
            'UK Work',
            'Self-Employed',
            true
        );
    }

    @IsTest
    static void generateGetNINOPdfTest(){
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Test.startTest();
        PageReference pageRef = Page.NINOData;
        pageRef.getParameters().put('id', String.valueOf(testApps[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testApps[0]);
        GetNINOPdf testGetNINO = new GetNINOPdf(stdController);
        Test.stopTest();
        System.assertNotEquals(null, testGetNINO);
        System.assertEquals(String.valueOf(testApps[0].Id), testGetNINO.MstrId);
    }
}