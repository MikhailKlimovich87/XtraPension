@isTest
public with sharing class NextSteps2FileGeneratorBatchTest {

    @testSetup
    static void setupData() {

        // Create Account + Contact via your factory
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);

        Contact c = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        // Create Application
        Application__c app = TestDataFactory.createApplication(c.Id, false);
        app.Status__c = 'Pension Keeper';
        app.PK_Registration_Date__c = Date.today();
        app.PK_Sale_Agent__c = 'Megan';
        app.National_Insurance_Number__c = 'AB123456C';
        app.CurrencyIsoCode = 'EUR';
        app.PK_Portal_User_Active__c = true;

        insert app;
    }

    @isTest
    static void testBatchCreatesFile() {

        Application__c app = [
            SELECT Id, Name
            FROM Application__c
            LIMIT 1
        ];

        Test.startTest();
        Database.executeBatch(new NextSteps2FileGeneratorBatch(), 1);
        Test.stopTest();

        // Validate ContentVersion
        List<ContentVersion> versions = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
        ];

        System.assertEquals(
            1,
            versions.size(),
            'One ContentVersion should be created'
        );

        // FIXED QUERY
        List<ContentDocumentLink> links = [
            SELECT Id, LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id
        ];

        System.assertEquals(
            1,
            links.size(),
            'One ContentDocumentLink should be created'
        );

        System.assertEquals(
            app.Id,
            links[0].LinkedEntityId
        );
    }

    @isTest
    static void testBatchDoesNotDuplicateFile() {

        Application__c app = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];

        Test.startTest();

        // First batch run
        Database.executeBatch(new NextSteps2FileGeneratorBatch(), 1);

        // Second batch run
        Database.executeBatch(new NextSteps2FileGeneratorBatch(), 1);

        Test.stopTest();

        Integer versionCount = [
            SELECT COUNT()
            FROM ContentVersion
        ];

        System.assertEquals(
            2,
            versionCount,
            'Duplicate files should not be created'
        );
    }
}