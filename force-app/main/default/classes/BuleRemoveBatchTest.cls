@isTest
public class BuleRemoveBatchTest {
    
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
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
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        List<ContentDocumentLink> beforeLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :testApps];
        
        // Verify documents exist before batch runs
        System.assert(beforeLinks.size() > 0, 'Test should have content document links');
        
        Test.startTest();
        String query = 'SELECT Id, (SELECT ContentDocumentId FROM ContentDocumentLinks) FROM Application__c';
        BuleRemoveBatch batch = new BuleRemoveBatch(query);
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify documents were deleted
        List<ContentDocumentLink> afterLinks = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :testApps];
        System.assertEquals(0, afterLinks.size(), 'All content document links should be deleted');
    }
    
    // @IsTest
    // static void testBatchExecutionWithNoDocuments() {
    //     // Delete all document links first
    //     delete [SELECT Id FROM ContentDocumentLink];
        
    //     Test.startTest();
    //     String query = 'SELECT Id, (SELECT ContentDocumentId FROM ContentDocumentLinks) FROM Application__c';
    //     BuleRemoveBatch batch = new BuleRemoveBatch(query);
    //     Database.executeBatch(batch);
    //     Test.stopTest();
        
    //     // Verify no errors occurred when no documents exist
    //     System.assert(true, 'Batch should complete successfully with no documents');
    // }
    
    // @IsTest
    // static void testBatchExecutionWithMoreThan200Apps() {
    //     // Create a large number of applications with documents (more than 200)
    //     List<Application__c> largeApps = new List<Application__c>();
    //     for (Integer i = 0; i < 250; i++) {
    //         largeApps.add(new Application__c(Name = 'Large Batch App ' + i));
    //     }
    //     insert largeApps;
        
    //     // Create and link documents
    //     List<ContentVersion> contentVersions = new List<ContentVersion>();
    //     List<ContentDocumentLink> documentLinks = new List<ContentDocumentLink>();
        
    //     for (Application__c app : largeApps) {
    //         ContentVersion cv = new ContentVersion(
    //             Title = 'Doc for ' + app.Name,
    //             PathOnClient = 'Doc.txt',
    //             VersionData = Blob.valueOf('Content'),
    //             IsMajorVersion = true
    //         );
    //         contentVersions.add(cv);
    //     }
    //     insert contentVersions;
        
    //     List<ContentVersion> insertedContentVersions = [
    //         SELECT Id, ContentDocumentId 
    //         FROM ContentVersion 
    //         WHERE Id IN :contentVersions
    //     ];
        
    //     for (Integer i = 0; i < largeApps.size(); i++) {
    //         ContentDocumentLink link = new ContentDocumentLink(
    //             LinkedEntityId = largeApps[i].Id,
    //             ContentDocumentId = insertedContentVersions[i].ContentDocumentId,
    //             ShareType = 'V'
    //         );
    //         documentLinks.add(link);
    //     }
    //     insert documentLinks;
        
    //     Test.startTest();
    //     String query = 'SELECT Id, (SELECT ContentDocumentId FROM ContentDocumentLinks) FROM Application__c';
    //     BuleRemoveBatch batch = new BuleRemoveBatch(query);
    //     Database.executeBatch(batch);
    //     Test.stopTest();
        
    //     // Verify that processing stopped at 200 apps as per the batch logic
    //     // This is a bit tricky to assert directly, but we can check that at least some were deleted
    //     Integer remainingLinks = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId IN :largeApps];
    //     System.assert(remainingLinks < 250, 'Some documents should have been deleted');
    // }
    
    @IsTest
    static void testConstructorAndStartMethod() {
        String testQuery = 'SELECT Id FROM Application__c LIMIT 1';
        BuleRemoveBatch batch = new BuleRemoveBatch(testQuery);
        
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();
        
        System.assertNotEquals(null, ql, 'QueryLocator should not be null');
    }
    
    @IsTest
    static void testFinishMethod() {
        // Just verify the finish method runs without errors
        BuleRemoveBatch batch = new BuleRemoveBatch('SELECT Id FROM Application__c');
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        System.assert(true, 'Finish method should complete successfully');
    }
}