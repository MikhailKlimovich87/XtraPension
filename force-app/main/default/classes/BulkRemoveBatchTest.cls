@isTest
public class BulkRemoveBatchTest {

    @TestSetup
    static void makeData() {
        //TestDataFactory.createProductsWithPrices();
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Monthly Updates', 'Success'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
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
        testApplication.Status__c = 'Posted';
        insert testApplication;
        ContentVersion testContentVersion = TestDataFactory.createTestContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        insert conDocLink;
    }

    @IsTest
    static void testBatchExecutionWithDocuments() {
        // Query for test data to get the actual IDs
        Map<Id,Application__c> testApps = new Map<Id,Application__c>([SELECT Id FROM Application__c]);
        List<ContentDocumentLink> beforeLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :testApps.keySet()];

        // Verify documents exist before batch runs
        System.assert(beforeLinks.size() > 0, 'Test should have content document links');

        Test.startTest();
        String query = 'SELECT Id, LinkedEntity.Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN (SELECT Id FROM Application__c)';
        BulkRemoveBatch batch = new BulkRemoveBatch(query);
        Database.executeBatch(batch);
        Test.stopTest();

        // Verify documents were deleted
        List<ContentDocumentLink> afterLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :testApps.keySet()];
        System.assertEquals(0, afterLinks.size(), 'All content document links should be deleted');
    }

    @IsTest
    static void testConstructorAndStartMethod() {
        String testQuery = 'SELECT Id FROM Application__c LIMIT 1';
        BulkRemoveBatch batch = new BulkRemoveBatch(testQuery);

        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql, 'QueryLocator should not be null');
    }

    @IsTest
    static void testFinishMethod() {
        // Just verify the finish method runs without errors
        BulkRemoveBatch batch = new BulkRemoveBatch('SELECT Id FROM Application__c');

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        System.assert(true, 'Finish method should complete successfully');
    }
}