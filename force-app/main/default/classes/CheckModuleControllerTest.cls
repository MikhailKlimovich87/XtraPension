@isTest
public class CheckModuleControllerTest {
    @testSetup
    static void setupTestData() {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }

    @isTest
    static void testGetApplicationNames() {
        Test.startTest();
        List<Application__c> apps = CheckModuleController.getApplicationNames();
        Test.stopTest();

        System.assert(!apps.isEmpty(), 'Should return at least one Application');
    }

    @isTest
    static void testCreateHMRCCheckRequestRecord() {
        List<Application__c> apps = [
            SELECT
                Id,
                Name
            FROM Application__c
            LIMIT 1
        ];
        // Create request JSON
        CheckModuleController.CheckRequest req = new CheckModuleController.CheckRequest();
        req.appName = apps[0].Name;
        req.notReceived = true;
        req.notes = 'Testing insert';
        req.sentDate = String.valueOf(Date.today());
        req.sentTo = 'Both';
        req.requestedCopy = 'Yes';
        req.c2 = false;
        req.workItem = false;
        req.badNINO = false;
        req.badInfo = false;
        req.processing = false;
        req.c3 = false;
        req.dwp = false;
        req.X64_8 = false;
        req.reject = false;
        req.appealLetterNotReceived = false;
        req.appealLetterReceived = false;
        req.paymentReceived = false;
        req.paymentNotReceived = false;
        req.dwpCall = false;

        CheckModuleController.CheckRequestWrapper testWrapper = new CheckModuleController.CheckRequestWrapper();
        testWrapper.checkReplies = new List<CheckModuleController.CheckRequest>();
        testWrapper.checkReplies.add(req);
        testWrapper.checkAgent = 'Vince';

        Test.startTest();
        List<HMRC_Check__c> results = CheckModuleController.createHMRCCheckRequestRecord(testWrapper);
        Test.stopTest();

        System.assertNotEquals(null, results, 'HMRC_Check__c should be inserted');
        Set<Id> ids = new Set<Id>();
        for (HMRC_Check__c request : results) {
            ids.add(request.Id);
        }
        List<HMRC_Check__c> createdRequests = [SELECT Id, Notes__c FROM HMRC_Check__c WHERE Id IN :ids];
        System.assertEquals(1, createdRequests.size());
    }

}