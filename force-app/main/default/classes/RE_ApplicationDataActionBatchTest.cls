@isTest
public class RE_ApplicationDataActionBatchTest {
    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c = 'Pension Keeper';
        insert testApplication;
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    /**
     * @description Verifies that when a Reapply__c record already exists for an
     *              Application__c, the batch does NOT create a new one.
     */
    @isTest
    static void testBatchSkipsApplicationsWithExistingReapply() {
        // Setup data already includes an Application with a Reapply record.
        List<Application__c> apps = [
            SELECT Id, (SELECT Id FROM Reapplies__r) FROM Application__c
        ];
        System.assert(!apps.isEmpty(), 'Expected at least one Application from test setup.');
        System.assert(
            !apps[0].Reapplies__r.isEmpty(),
            'Expected a Reapply__c record to already exist from the test setup.'
        );

        Integer reapplyCountBefore = [SELECT COUNT() FROM Reapply__c];

        Test.startTest();
        Database.executeBatch(new RE_ApplicationDataActionBatch());
        Test.stopTest();

        Integer reapplyCountAfter = [SELECT COUNT() FROM Reapply__c];
        System.assertEquals(
            reapplyCountBefore,
            reapplyCountAfter,
            'No new Reapply__c record should be created when one already exists.'
        );
    }

    /**
     * @description Verifies that when an Application__c has no Reapply__c record,
     *              the batch creates one for it.
     */
    @isTest
    static void testBatchCreatesReapplyWhenMissing() {
        // Build a brand-new Application without any Reapply__c record.
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];

        Application__c appWithoutReapply = TestDataFactory.createApplication(con.Id, false);
        appWithoutReapply.Status__c = 'Pension Keeper';
        insert appWithoutReapply;

        // Sanity check — no Reapply__c for this app yet.
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Reapply__c WHERE Application__c = :appWithoutReapply.Id],
            'Precondition failed: new application should not have a Reapply__c record.'
        );

        Test.startTest();
        Database.executeBatch(
            new RE_ApplicationDataActionBatch('Id = \'' + appWithoutReapply.Id + '\'')
        );
        Test.stopTest();

        Integer reapplyCount = [
            SELECT COUNT() FROM Reapply__c WHERE Application__c = :appWithoutReapply.Id
        ];
        System.assertEquals(
            1,
            reapplyCount,
            'Exactly one Reapply__c record should be created for the application missing one.'
        );
    }

    /**
     * @description Verifies that the batch respects the extra-condition WHERE clause
     *              and does not process applications that don't match.
     */
    @isTest
    static void testBatchWithExtraConditionFiltersScope() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];

        // Create two apps, both missing Reapply__c, but only one matches the filter.
        Application__c matchingApp = TestDataFactory.createApplication(con.Id, false);
        matchingApp.Status__c = 'Pension Keeper';
        insert matchingApp;

        Application__c nonMatchingApp = TestDataFactory.createApplication(con.Id, false);
        nonMatchingApp.Status__c = 'Deferred';
        insert nonMatchingApp;

        Test.startTest();
        Database.executeBatch(
            new RE_ApplicationDataActionBatch(
                'Id = \'' + matchingApp.Id + '\''
            )
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Reapply__c WHERE Application__c = :matchingApp.Id],
            'Matching application should have received a Reapply__c record.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Reapply__c WHERE Application__c = :nonMatchingApp.Id],
            'Non-matching application should NOT have received a Reapply__c record.'
        );
    }

    /**
     * @description Verifies that the no-arg constructor sets an empty extra condition
     *              and that the batch still runs successfully across all Applications.
     */
    @isTest
    static void testBatchDefaultConstructorProcessesAll() {
        // Remove existing Reapply__c records to force the batch to create them.
        List<Reapply__c> existing = [SELECT Id FROM Reapply__c];
        if (!existing.isEmpty()) {
            delete existing;
        }

        Integer appsWithoutReapply = [
            SELECT COUNT()
            FROM Application__c
            WHERE Id NOT IN (SELECT Application__c FROM Reapply__c)
        ];
        System.assert(appsWithoutReapply > 0, 'Expected at least one app without a Reapply__c.');

        Test.startTest();
        Database.executeBatch(new RE_ApplicationDataActionBatch());
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT()
            FROM Application__c
            WHERE Id NOT IN (SELECT Application__c FROM Reapply__c)
        ];
        System.assertEquals(
            0,
            remaining,
            'Default constructor should process every Application__c without a Reapply__c.'
        );
    }

    /**
     * @description Verifies the batch handles an empty scope gracefully
     *              (extra condition matches nothing).
     */
    @isTest
    static void testBatchWithNoMatchingRecords() {
        Integer reapplyCountBefore = [SELECT COUNT() FROM Reapply__c];

        Test.startTest();
        Database.executeBatch(
            new RE_ApplicationDataActionBatch('Id = \'001000000000000AAA\'')
        );
        Test.stopTest();

        Integer reapplyCountAfter = [SELECT COUNT() FROM Reapply__c];
        System.assertEquals(
            reapplyCountBefore,
            reapplyCountAfter,
            'No Reapply__c records should be created when the scope is empty.'
        );
    }

    /**
     * @description Verifies the batch processes a larger scope correctly
     *              by chaining multiple applications in one execution.
     */
    @isTest
    static void testBatchHandlesMultipleApplications() {
        // Remove all existing Reapply__c records.
        List<Reapply__c> existing = [SELECT Id FROM Reapply__c];
        if (!existing.isEmpty()) {
            delete existing;
        }

        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];

        List<Application__c> newApps = new List<Application__c>();
        for (Integer i = 0; i < 5; i++) {
            Application__c app = TestDataFactory.createApplication(con.Id, false);
            app.Status__c = 'Pension Keeper';
            newApps.add(app);
        }
        insert newApps;

        Test.startTest();
        Database.executeBatch(new RE_ApplicationDataActionBatch(), 200);
        Test.stopTest();

        Integer remaining = [
            SELECT COUNT()
            FROM Application__c
            WHERE Id NOT IN (SELECT Application__c FROM Reapply__c)
        ];
        System.assertEquals(
            0,
            remaining,
            'Every Application__c should have a corresponding Reapply__c after the batch.'
        );
    }
}