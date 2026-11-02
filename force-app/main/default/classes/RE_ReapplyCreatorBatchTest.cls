@isTest
public class RE_ReapplyCreatorBatchTest {
    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact contact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Application__c application = TestDataFactory.createApplication(contact.Id, false);
        application.Status__c = 'Pension Keeper';
        insert application;
        TestDataFactory.createEmployer(application.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(application.Id, 'Work After UK', 'Career Break', true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testSkipsApplicationWithoutStatusChangeHistory() {
        Application__c application = [
            SELECT Id, Status__c
            FROM Application__c
            LIMIT 1
        ];

        List<Application__History> statusHistory = [
            SELECT Id
            FROM Application__History
            WHERE ParentId = :application.Id AND Field = 'Status__c'
        ];
        System.assertEquals(0, statusHistory.size(), 'A newly inserted record has no status history.');

        RE_ReapplyCreatorBatch batch = new RE_ReapplyCreatorBatch();
        System.assertNotEquals(null, batch.start(null), 'The batch should provide a query locator.');

        Test.startTest();
        batch.execute(null, new List<Application__c>{ application });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Reapply__c WHERE Application__c = :application.Id],
            'An application without status history must not create a Reapply.'
        );
    }

    @isTest
    static void testExecuteWithEmptyScope() {
        Test.startTest();
        new RE_ReapplyCreatorBatch().execute(null, new List<Application__c>());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Reapply__c]);
    }

    @isTest
    static void testCreatesBatchReapplyForMatchingStatusAt45Days() {
        Application__c application = [
            SELECT Id, Status__c
            FROM Application__c
            LIMIT 1
        ];
        Datetime statusChangedAt = Datetime.newInstance(
            Date.today().addDays(-45),
            Time.newInstance(12, 0, 0, 0)
        );

        Test.startTest();
        RE_ReapplyCreatorBatch.processApplications(
            new List<Application__c>{ application },
            new Map<Id, String>{ application.Id => application.Status__c },
            new Map<Id, Datetime>{ application.Id => statusChangedAt }
        );
        Test.stopTest();

        Reapply__c createdReapply = [
            SELECT CreatedFromReapplyCreatorBatch__c
            FROM Reapply__c
            WHERE Application__c = :application.Id
            LIMIT 1
        ];
        System.assertEquals(true, createdReapply.CreatedFromReapplyCreatorBatch__c);
    }

    @isTest
    static void testSkipsRecentStatusChange() {
        Application__c application = [
            SELECT Id, Status__c
            FROM Application__c
            LIMIT 1
        ];

        RE_ReapplyCreatorBatch.processApplications(
            new List<Application__c>{ application },
            new Map<Id, String>{ application.Id => application.Status__c },
            new Map<Id, Datetime>{ application.Id => Datetime.now() }
        );

        System.assertEquals(0, [SELECT COUNT() FROM Reapply__c WHERE Application__c = :application.Id]);
    }

    @isTest
    static void testSkipsHistoryThatDoesNotMatchCurrentStatus() {
        Application__c application = [
            SELECT Id, Status__c
            FROM Application__c
            LIMIT 1
        ];
        Datetime oldStatusChangedAt = Datetime.newInstance(
            Date.today().addDays(-46),
            Time.newInstance(12, 0, 0, 0)
        );

        RE_ReapplyCreatorBatch.processApplications(
            new List<Application__c>{ application },
            new Map<Id, String>{ application.Id => 'No Annual' },
            new Map<Id, Datetime>{ application.Id => oldStatusChangedAt }
        );

        System.assertEquals(0, [SELECT COUNT() FROM Reapply__c WHERE Application__c = :application.Id]);
    }
}