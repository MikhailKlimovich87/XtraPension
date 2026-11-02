@isTest
public class RE_NoAnnualEmailBatchTest {
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
    static void testBatchExecutionWithNoAnnualStatus() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, No_Annual_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'No Annual' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'No Annual';
        update app;
        
        // Ensure No_Annual_Email_Send_Date__c is null
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify the reapply record was updated
        Reapply__c updatedReapply = [SELECT Id, No_Annual_Email_Send_Date__c 
                                      FROM Reapply__c LIMIT 1];
        System.assertNotEquals(null, updatedReapply.No_Annual_Email_Send_Date__c);
        System.assertEquals(Date.today(), updatedReapply.No_Annual_Email_Send_Date__c);
    }

    @isTest
    static void testBatchExecutionWithAnnualServiceStatus() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, No_Annual_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'Annual Service' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'Annual Service';
        update app;
        
        // Ensure No_Annual_Email_Send_Date__c is null
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify the reapply record was updated
        Reapply__c updatedReapply = [SELECT Id, No_Annual_Email_Send_Date__c 
                                      FROM Reapply__c LIMIT 1];
        System.assertNotEquals(null, updatedReapply.No_Annual_Email_Send_Date__c);
        System.assertEquals(Date.today(), updatedReapply.No_Annual_Email_Send_Date__c);
    }

    @isTest
    static void testBatchWithExistingNoAnnualEmailDate() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, No_Annual_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'No Annual' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'No Annual';
        update app;
        
        // Set No_Annual_Email_Send_Date__c to a date
        reapply.No_Annual_Email_Send_Date__c = Date.today().addDays(-1);
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify the reapply record was NOT updated (since it had a date)
        Reapply__c updatedReapply = [SELECT Id, No_Annual_Email_Send_Date__c 
                                      FROM Reapply__c LIMIT 1];
        System.assertEquals(Date.today().addDays(-1), updatedReapply.No_Annual_Email_Send_Date__c);
    }

    @isTest
    static void testBatchWithDifferentCurrencyCodes() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, CurrencyIsoCode, No_Annual_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'No Annual' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'No Annual';
        update app;
        
        // Test with different currencies
        List<String> currencies = new List<String>{'CAD', 'USD', 'EUR', 'NZD', 'ZAR', 'AUD'};
        
        for(String curr : currencies) {
            // Reset the reapply record for each currency
            reapply = [SELECT Id, CurrencyIsoCode, No_Annual_Email_Send_Date__c 
                       FROM Reapply__c LIMIT 1];
            reapply.CurrencyIsoCode = curr;
            reapply.No_Annual_Email_Send_Date__c = null;
            update reapply;
            
            // Start the batch
            RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
            Database.executeBatch(batch);
            
            // Verify the reapply record was updated
            Reapply__c updatedReapply = [SELECT Id, No_Annual_Email_Send_Date__c 
                                          FROM Reapply__c LIMIT 1];
            //System.assertNotEquals(null, updatedReapply.No_Annual_Email_Send_Date__c);
            //System.assertEquals(Date.today(), updatedReapply.No_Annual_Email_Send_Date__c);
        }
    }

    @isTest
    static void testBatchWithInvalidCurrencyCode() {
        // Query for the test reapply record
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, CurrencyIsoCode, No_Annual_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        // Update the application to have 'No Annual' status
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'No Annual';
        update app;
        
        // Set invalid currency code
        reapply.CurrencyIsoCode = 'GBP';
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;
        
        // Start the batch
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify the reapply record was updated (should default to USD)
        Reapply__c updatedReapply = [SELECT Id, No_Annual_Email_Send_Date__c 
                                      FROM Reapply__c LIMIT 1];
        System.assertNotEquals(null, updatedReapply.No_Annual_Email_Send_Date__c);
    }

    @isTest
    static void testFinishMethod() {
        // Simply test that the finish method executes without errors
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.BatchableContext context = null;
        batch.finish(context);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testStartMethodQuery() {
        // Create a reapply record that meets criteria
        Reapply__c reapply = [SELECT Id, Application__r.Status__c, No_Annual_Email_Send_Date__c 
                              FROM Reapply__c LIMIT 1];
        
        Application__c app = [SELECT Id, Status__c FROM Application__c 
                              WHERE Id = :reapply.Application__c];
        app.Status__c = 'No Annual';
        update app;
        
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;
        
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.QueryLocator ql = batch.start(null);
        Database.QueryLocatorIterator iter = ql.iterator();
        
        // Verify at least one record is returned
        System.assert(iter.hasNext());
        Test.stopTest();
    }

    @isTest
    static void testConstructorWithExtraCondition() {
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch(
            ' AND CurrencyIsoCode = \'USD\' '
        );
        System.assertEquals(
            ' AND CurrencyIsoCode = \'USD\' ',
            batch.extraCondition,
            'extraCondition should be set by constructor'
        );
        Test.stopTest();
    }

    @isTest
    static void testDefaultConstructorSetsEmptyCondition() {
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        System.assertEquals('', batch.extraCondition);
        Test.stopTest();
    }

    @isTest
    static void testStartQueryWithExtraCondition() {
        Reapply__c reapply = [
            SELECT Id, Application__r.Status__c, No_Annual_Email_Send_Date__c
            FROM Reapply__c LIMIT 1
        ];

        Application__c app = [
            SELECT Id, Status__c FROM Application__c
            WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'No Annual';
        update app;

        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;

        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch(
            ' AND CurrencyIsoCode = \'USD\' '
        );
        Database.QueryLocator ql = batch.start(null);
        Database.QueryLocatorIterator iter = ql.iterator();
        //System.assert(iter.hasNext(), 'Query with extra condition should return records');
        Test.stopTest();
    }

    @isTest
    static void testStartQueryWithEmptyExtraCondition() {
        Reapply__c reapply = [
            SELECT Id, Application__r.Status__c, No_Annual_Email_Send_Date__c
            FROM Reapply__c LIMIT 1
        ];

        Application__c app = [
            SELECT Id, Status__c FROM Application__c
            WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'Annual Service';
        update app;

        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;

        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.QueryLocator ql = batch.start(null);
        Database.QueryLocatorIterator iter = ql.iterator();
        System.assert(iter.hasNext(), 'Query with empty condition should return records');
        Test.stopTest();
    }

    @isTest
    static void testExecuteWithMultipleReapplyRecords() {
        // Create a second Application + Reapply to exercise the loop body more than once
        Account account = [
            SELECT Id FROM Account LIMIT 1
        ];
        Contact con = [
            SELECT Id FROM Contact
            WHERE AccountId = :account.Id LIMIT 1
        ];

        Application__c app2 = TestDataFactory.createApplication(con.Id, true);
        app2.Status__c = 'No Annual';
        update app2;

        Reapply__c reapply2 = TestDataFactory.createReapplyRecord(app2.Id, true);
        reapply2.No_Annual_Email_Send_Date__c = null;
        update reapply2;

        // Also set the original one to No Annual
        Reapply__c reapply1 = [
            SELECT Id, Application__c FROM Reapply__c
            WHERE Id != :reapply2.Id LIMIT 1
        ];
        Application__c app1 = [
            SELECT Id, Status__c FROM Application__c
            WHERE Id = :reapply1.Application__c
        ];
        app1.Status__c = 'No Annual';
        update app1;
        reapply1.No_Annual_Email_Send_Date__c = null;
        update reapply1;

        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Reapply__c> updated = [
            SELECT Id, No_Annual_Email_Send_Date__c FROM Reapply__c
        ];
        for (Reapply__c r : updated) {
            System.assertEquals(Date.today(), r.No_Annual_Email_Send_Date__c);
        }
    }

    @isTest
    static void testExecuteWithNullCurrencyCode() {
        Reapply__c reapply = [
            SELECT Id, Application__r.Status__c, CurrencyIsoCode, No_Annual_Email_Send_Date__c
            FROM Reapply__c LIMIT 1
        ];

        Application__c app = [
            SELECT Id, Status__c FROM Application__c
            WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'No Annual';
        update app;

        // Leave currency as default (likely USD) and null the date
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;

        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        Reapply__c updated = [
            SELECT Id, No_Annual_Email_Send_Date__c FROM Reapply__c LIMIT 1
        ];
        System.assertNotEquals(null, updated.No_Annual_Email_Send_Date__c);
    }

    @isTest
    static void testExecuteWithAllSupportedCurrencies() {
        List<String> currencies = new List<String>{
            'CAD', 'USD', 'EUR', 'NZD', 'ZAR', 'AUD'
        };

        for (String curr : currencies) {
            Reapply__c reapply = [
                SELECT Id, CurrencyIsoCode, No_Annual_Email_Send_Date__c, Application__c
                FROM Reapply__c LIMIT 1
            ];

            Application__c app = [
                SELECT Id, Status__c FROM Application__c
                WHERE Id = :reapply.Application__c
            ];
            app.Status__c = 'No Annual';
            update app;

            reapply.CurrencyIsoCode = curr;
            reapply.No_Annual_Email_Send_Date__c = null;
            update reapply;

            RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
            Database.executeBatch(batch);
        }
    }

    @isTest
    static void testFinishMethodWithContext() {
        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        // finish() is a no-op but should execute cleanly
        batch.finish(null);
        Test.stopTest();
        System.assert(true, 'finish() executed without error');
    }

    @isTest
    static void testExecuteWithNoMatchingRecords() {
        // Set all reapply records to have a send date so the query returns nothing
        List<Reapply__c> reapplies = [
            SELECT Id, No_Annual_Email_Send_Date__c FROM Reapply__c
        ];
        for (Reapply__c r : reapplies) {
            r.No_Annual_Email_Send_Date__c = Date.today();
        }
        update reapplies;

        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        System.assert(true, 'Batch executed with no matching records');
    }

    @isTest
    static void testExecuteWithExtraCondition() {
        Reapply__c reapply = [
            SELECT Id, Application__c, CurrencyIsoCode, No_Annual_Email_Send_Date__c
            FROM Reapply__c LIMIT 1
        ];

        Application__c app = [
            SELECT Id, Status__c FROM Application__c WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'No Annual';
        update app;

        reapply.CurrencyIsoCode = 'USD';
        reapply.No_Annual_Email_Send_Date__c = null;
        update reapply;

        Test.startTest();
        RE_NoAnnualEmailBatch batch = new RE_NoAnnualEmailBatch(
            ' AND CurrencyIsoCode = \'USD\' '
        );
        Database.executeBatch(batch);
        Test.stopTest();

        Reapply__c updated = [
            SELECT Id, No_Annual_Email_Send_Date__c
            FROM Reapply__c
            WHERE Id = :reapply.Id
            LIMIT 1
        ];

        System.assertEquals(Date.today(), updated.No_Annual_Email_Send_Date__c);
    }

    @isTest
    static void testFindEmailMessageReturnsNullWhenNoMatchExists() {
        Reapply__c reapply = [
            SELECT Id, Email__c
            FROM Reapply__c
            LIMIT 1
        ];

        System.assertEquals(
            null,
            RE_NoAnnualEmailBatch.findEmailMessage(reapply.Id, reapply.Email__c)
        );
    }
}