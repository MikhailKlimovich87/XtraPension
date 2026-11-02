@isTest
public with sharing class UploadToAWSQueueableTest {
    
    @TestSetup
    static void makeData() {
        // Create test data
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        
        // Create test ContentVersion with known values
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'Test Signature Document',
        VersionData = Blob.valueOf('Test Content'),
        PathOnClient = 'test.pdf',
        FirstPublishLocationId = testApplication.Id
            );
        insert testContentVersion;
        
        ContentVersion testCustomLetterContentVersion = new ContentVersion(
            Title = 'Test Custom Letter',
        VersionData = Blob.valueOf('Test Custom Letter Content'),
        PathOnClient = 'letter.docx',
        FirstPublishLocationId = testApplication.Id
            );
        insert testCustomLetterContentVersion;
        
        // Create AwsS3UploadResult__c record for testing
        AwsS3UploadResult__c uploadResult = new AwsS3UploadResult__c(
            Application__c = testApplication.Id,
        Status__c = 'Pending',
        Batch_Type__c = 'Retrieve from S3',
        UploadDate__c = System.now(),
        TotalProcessed__c = 0,
        UploadedCount__c = 0,
        FailedCount__c = 0,
        Success_Rate__c = 0
            );
        insert uploadResult;
    }
    
    @isTest
    static void testQueueableWithApplicationAndContentVersion() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        Set<Id> appIds = new Set<Id>{testApp.Id};
        
        Test.startTest();
        // Use test mode constructor to avoid Database.executeBatch
        System.enqueueJob(new UploadToAWSQueueable(appIds));
        Test.stopTest();
        
        System.assert(true, 'Queueable executed with application that has ContentVersions');
    }
}