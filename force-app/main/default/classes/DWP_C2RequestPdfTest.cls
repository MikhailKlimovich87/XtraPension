@isTest
public class DWP_C2RequestPdfTest {
    @TestSetup
    static void makeData(){
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        testApplication.DWP_C2_Request_Template__c = 'Test Top' + 
        'SPLIT=============' +
        'Test Bottom';
        insert testApplication;
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK','Homemaker', true);
    }

    @IsTest
    static void dwpC2RequestPdfTest(){
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];
        Test.startTest();
        PageReference pageRef = Page.DWP_C2Request;
        pageRef.getParameters().put('id', String.valueOf(app.Id));
        pageRef.getParameters().put('template', 'DWP_C2_Request_Template__c');
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(app);
        DWP_C2RequestPdf testDWP_C2Request = new DWP_C2RequestPdf(stdController);
        Test.stopTest();
    }
}