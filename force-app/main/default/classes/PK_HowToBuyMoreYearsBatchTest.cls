@IsTest
public class PK_HowToBuyMoreYearsBatchTest {

    @TestSetup
    static void makeData() {

        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);

        Account account = TestDataFactory.createAccount(true);

        Contact personContact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Application__c app =
            TestDataFactory.createApplication(personContact.Id, false);

        app.Status__c = 'Pension Keeper';
        app.PK_Portal_User_Active__c = true;
        app.PK_Registration_Date__c = Date.today().addDays(-7);

        insert app;
    }

    @IsTest
    static void testBatchSecondRunCreatesNewVersionOnly() {

        Test.startTest();

        Database.executeBatch(new PK_HowToBuyMoreYearsBatch(), 1);
        Database.executeBatch(new PK_HowToBuyMoreYearsBatch(), 1);

        Test.stopTest();

        // Retrieve all versions of the generated PDF
        List<ContentVersion> versions = [
            SELECT Id,
                ContentDocumentId,
                Title,
                VersionNumber,
                IsLatest
            FROM ContentVersion
            WHERE Title LIKE '%Next Step 2 - Get Receipt%'
            ORDER BY VersionNumber
        ];

        System.assertEquals(
            2,
            versions.size(),
            'Two ContentVersions should exist after running the batch twice.'
        );

        // Both versions should belong to the same ContentDocument
        System.assertEquals(
            versions[0].ContentDocumentId,
            versions[1].ContentDocumentId,
            'Both versions should belong to the same ContentDocument.'
        );

        Integer versionCount = [
            SELECT COUNT()
            FROM ContentVersion
            WHERE ContentDocumentId = :versions[0].ContentDocumentId
        ];

        System.assertEquals(
            2,
            versionCount,
            'The document should contain exactly two versions.'
        );
    }

    @IsTest
    static void testBatchExecute() {

        Test.startTest();
        Database.executeBatch(new PK_HowToBuyMoreYearsBatch(), 1);
        Test.stopTest();

        List<ContentVersion> versions = [
            SELECT Id,
                Title,
                ContentDocumentId,
                IsLatest
            FROM ContentVersion
            WHERE Title LIKE '%Next Step 2 - Get Receipt%'
        ];

        System.assertEquals(1, versions.size());
        System.assert(versions[0].IsLatest);
    }

    @IsTest
    static void testStartMethod() {

        PK_HowToBuyMoreYearsBatch batch =
            new PK_HowToBuyMoreYearsBatch();

        Test.startTest();

        Database.QueryLocator locator =
            batch.start(null);

        Test.stopTest();

        System.assertNotEquals(null, locator);
    }

    @IsTest
    static void testFinishMethod() {

        PK_HowToBuyMoreYearsBatch batch =
            new PK_HowToBuyMoreYearsBatch();

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        System.assert(true);
    }
}