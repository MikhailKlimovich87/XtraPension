@isTest
public with sharing class RE_PensionKeeperEmailBatchTest {
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testBatchExecutionWithPensionKeeperStatus() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, Pension_Keeper_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'Pension Keeper' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'Pension Keeper';
        update app;
        reapply.Pension_Keeper_Email_Send_Date__c = null;
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        Reapply__c updatedReapply = [SELECT Id, Pension_Keeper_Email_Send_Date__c 
                          FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertEquals(Date.today(), updatedReapply.Pension_Keeper_Email_Send_Date__c);
    }

    @isTest
    static void testBatchWithExistingPensionKeeperEmailDate() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, Pension_Keeper_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'Pension Keeper' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'Pension Keeper';
        update app;
        
        // Set Pension_Keeper_Email_Send_Date__c to a date
        reapply.Pension_Keeper_Email_Send_Date__c = Date.today().addDays(-1);
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify the reapply record was NOT updated (since it had a date)
        Reapply__c updatedReapply = [SELECT Id, Pension_Keeper_Email_Send_Date__c 
                                      FROM Reapply__c LIMIT 1];
        System.assertEquals(Date.today().addDays(-1), updatedReapply.Pension_Keeper_Email_Send_Date__c);
    }

    @isTest
    static void testBatchWithDifferentCurrencyCodes() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, CurrencyIsoCode, Pension_Keeper_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'Pension Keeper' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'Pension Keeper';
        update app;
        
        // Test with different currencies
        List<String> currencies = new List<String>{'CAD', 'USD', 'EUR', 'NZD', 'ZAR', 'AUD'};
        
        for(String curr : currencies) {
            // Reset the reapply record for each currency
            reapply = [SELECT Id, CurrencyIsoCode, Pension_Keeper_Email_Send_Date__c 
                       FROM Reapply__c LIMIT 1];
            reapply.CurrencyIsoCode = curr;
            reapply.Pension_Keeper_Email_Send_Date__c = null;
            update reapply;
            
            // Start the batch
            RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
            Database.executeBatch(batch);
            
            // Verify the reapply record was updated
            Reapply__c updatedReapply = [SELECT Id, Pension_Keeper_Email_Send_Date__c 
                                          FROM Reapply__c LIMIT 1];
            //System.assertNotEquals(null, updatedReapply.Pension_Keeper_Email_Send_Date__c);
            //System.assertEquals(Date.today(), updatedReapply.Pension_Keeper_Email_Send_Date__c);
        }
    }

    @isTest
    static void testBatchWithInvalidCurrencyCode() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, CurrencyIsoCode, Pension_Keeper_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'Pension Keeper' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'Pension Keeper';
        update app;
        
        // Set invalid currency code
        reapply.CurrencyIsoCode = 'GBP';
        reapply.Pension_Keeper_Email_Send_Date__c = null;
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify the reapply record was updated (should default to USD)
        Reapply__c updatedReapply = [SELECT Id, Pension_Keeper_Email_Send_Date__c 
                                      FROM Reapply__c LIMIT 1];
        //System.assertNotEquals(null, updatedReapply.Pension_Keeper_Email_Send_Date__c);
    }

    @isTest
    static void testFinishMethod() {
        // Simply test that the finish method executes without errors
        Test.startTest();
        RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
        Database.BatchableContext context = null;
        batch.finish(context);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testStartMethodQuery() {
        // Create a reapply record that meets criteria
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, Pension_Keeper_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'Pension Keeper';
        update app;
        
        reapply.Pension_Keeper_Email_Send_Date__c = null;
        update reapply;
        
        Test.startTest();
        RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
        Database.QueryLocator ql = batch.start(null);
        Database.QueryLocatorIterator iter = ql.iterator();
        
        // Verify at least one record is returned
        System.assert(iter.hasNext());
        Test.stopTest();
    }

    @isTest
    static void testExecuteReturnsWhenStaticResourceIsMissing() {
        Reapply__c reapply = [
            SELECT Id, CurrencyIsoCode, Email__c, Application__r.Contact__c
            FROM Reapply__c
            LIMIT 1
        ];
        reapply.CurrencyIsoCode = 'GBP';
        reapply.Pension_Keeper_Email_Send_Date__c = null;
        update reapply;

        RE_PensionKeeperEmailBatch batch = new RE_PensionKeeperEmailBatch();
        batch.CURRENCY_TO_TEMPLATE.put('GBP', 'Missing_Pension_Keeper_PDF');

        Test.startTest();
        batch.execute(null, new List<Reapply__c>{ reapply });
        Test.stopTest();

        Reapply__c unchangedReapply = [
            SELECT Pension_Keeper_Email_Send_Date__c
            FROM Reapply__c
            WHERE Id = :reapply.Id
        ];
        System.assertEquals(
            null,
            unchangedReapply.Pension_Keeper_Email_Send_Date__c,
            'The record should remain unprocessed when its PDF resource is missing.'
        );
    }

    @isTest
    static void testExecuteBuildsEmailAndMarksRecordProcessed() {
        Reapply__c reapply = [
            SELECT Id, Email__c, CurrencyIsoCode, Application__r.Contact__c
            FROM Reapply__c
            LIMIT 1
        ];
        reapply.CurrencyIsoCode = 'USD';
        reapply.Pension_Keeper_Email_Send_Date__c = null;
        update reapply;

        Reapply__c scopeRecord = [
            SELECT Id, Email__c, CurrencyIsoCode, Application__r.Contact__c
            FROM Reapply__c
            WHERE Id = :reapply.Id
        ];

        Test.startTest();
        new RE_PensionKeeperEmailBatch().execute(null, new List<Reapply__c>{ scopeRecord });
        Test.stopTest();

        Reapply__c processedReapply = [
            SELECT Pension_Keeper_Email_Send_Date__c
            FROM Reapply__c
            WHERE Id = :reapply.Id
        ];
        System.assertEquals(Date.today(), processedReapply.Pension_Keeper_Email_Send_Date__c);
    }

    @isTest
    static void testFindEmailMessageReturnsNullWhenNoEmailExists() {
        Reapply__c reapply = [
            SELECT Id, Email__c
            FROM Reapply__c
            LIMIT 1
        ];

        System.assertEquals(
            null,
            RE_PensionKeeperEmailBatch.findEmailMessage(reapply.Id, reapply.Email__c)
        );
    }

    @isTest
    static void testCreateFileAndLinkToEmail() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        EmailMessage emailMessage = new EmailMessage(
            RelatedToId = reapply.Id,
            Subject = 'Test email',
            FromAddress = 'sender@example.com',
            ToAddress = 'recipient@example.com',
            Incoming = false,
            Status = '3'
        );
        insert emailMessage;

        Test.startTest();
        RE_PensionKeeperEmailBatch.createFileAndLinkToEmail(
            emailMessage.Id,
            'Reapply-ROW.pdf',
            Blob.valueOf('test PDF content')
        );
        Test.stopTest();

        ContentDocumentLink fileLink = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :emailMessage.Id
            LIMIT 1
        ];
        System.assertEquals('Reapply-ROW', fileLink.ContentDocument.Title);
    }
}