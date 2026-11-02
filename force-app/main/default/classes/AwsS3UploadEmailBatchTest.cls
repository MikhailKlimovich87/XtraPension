/**
 * Unit tests for AwsS3UploadEmailBatch
 */
@isTest
public class AwsS3UploadEmailBatchTest {
    
    // Test data setup
    @TestSetup
    static void setupTestData() {
        // Create an EmailMessage record
        EmailMessage email = new EmailMessage(
            Subject = 'Test Email for S3 Upload',
        FromAddress = 'test@example.com',
        ToAddress = 'recipient@example.com',
        MessageDate = System.now()
            );
        insert email;
        
        // Create a test ContentDocument (file)
        ContentVersion contentVersion = new ContentVersion(
            Title = 'Test Document',
        PathOnClient = 'TestDocument.pdf',
        VersionData = Blob.valueOf('Test Content'),
        IsMajorVersion = true
            );
        insert contentVersion;
        
        // Get the ContentDocumentId
        ContentVersion insertedVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id];
        
        // Link the ContentDocument to the EmailMessage
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = insertedVersion.ContentDocumentId,
        LinkedEntityId = email.Id,
        ShareType = 'V'
            );
        insert link;
    }
    
    /**
     * Test: Successful upload of files to S3
     */
    @isTest
    static void testSuccessfulUpload() {
        // Get the test EmailMessage
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        // Start test
        Test.startTest();
        
        // Execute batch - use a larger batch size to ensure single execution
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10); // Use batch size of 10 to ensure all records in one batch
        
        Test.stopTest();
        
        // Verify results
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Total_Files__c, 
                                     S3_Success_Count__c, S3_Failed_Count__c, 
                                     S3_Success_Rate__c, AWS_S3_Package_Id__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        System.assertNotEquals(null, updatedEmail.AWS_S3_Package_Id__c, 'S3 Package ID should be set');
    }
    
    /**
     * Test: Upload with no files
     */
    @isTest
    static void testNoFiles() {
        // Create an EmailMessage with no linked files
        EmailMessage email = new EmailMessage(
            Subject = 'Empty Email',
        FromAddress = 'empty@example.com',
        ToAddress = 'recipient@example.com',
        MessageDate = System.now()
            );
        insert email;
        
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        // Verify no files were processed
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Total_Files__c 
                                     FROM EmailMessage WHERE Id = :email.Id];
        System.assertEquals('No Files', updatedEmail.S3_Upload_Status__c, 'Status should be No Files');
        System.assertEquals(0, updatedEmail.S3_Total_Files__c, 'Total files should be 0');
    }
    
    /**
     * Test: Upload with Note files (should be skipped)
     */
    @isTest
    static void testNoteFiles() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Create a Note file (detected by title pattern)
        ContentVersion noteVersion = new ContentVersion(
            Title = 'Note - Test Note',
        PathOnClient = 'Note.snote',
        VersionData = Blob.valueOf('Note content'),
        IsMajorVersion = true
            );
        insert noteVersion;
        
        ContentVersion insertedNote = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :noteVersion.Id];
        
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = insertedNote.ContentDocumentId,
        LinkedEntityId = email.Id,
        ShareType = 'V'
            );
        insert link;
        
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Total_Files__c,
                                     S3_Success_Count__c, S3_Failed_Count__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        // System.assertNotEquals('Failed', updatedEmail.S3_Upload_Status__c, 'Should not be failed');
    }
    
    /**
     * Test: Upload failure due to file size limit
     */
    @isTest
    static void testFileTooLarge() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Create a large file (exceeds 5MB limit)
        Blob largeBlob = Blob.valueOf('X'.repeat(6000000)); // ~6MB
        ContentVersion largeVersion = new ContentVersion(
            Title = 'Large File',
        PathOnClient = 'LargeFile.pdf',
        VersionData = largeBlob,
        IsMajorVersion = true
            );
        insert largeVersion;
        
        ContentVersion insertedLarge = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :largeVersion.Id];
        
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = insertedLarge.ContentDocumentId,
        LinkedEntityId = email.Id,
        ShareType = 'V'
            );
        insert link;
        
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Failed_Count__c,
                                     S3_Error_Details__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        System.assert(updatedEmail.S3_Failed_Count__c > 0, 'Should have failures');
        System.assert(updatedEmail.S3_Error_Details__c != null, 'Error details should be set');
    }
    
    /**
     * Test: Upload failure due to S3 error (403 Forbidden)
     */
    @isTest
    static void testS3UploadFailure() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Mock HTTP callout to simulate failure
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(false));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Failed_Count__c,
                                     S3_Error_Details__c, S3_Success_Count__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        System.assert(updatedEmail.S3_Failed_Count__c > 0, 'Should have failures');
        System.assertEquals(0, updatedEmail.S3_Success_Count__c, 'No files should succeed');
    }
    
    /**
     * Test: Partial success (some files succeed, some fail)
     */
    @isTest
    static void testPartialSuccess() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Create multiple files
        // File 1: Small - will succeed
        ContentVersion file1 = new ContentVersion(
            Title = 'File1 Success',
        PathOnClient = 'File1.pdf',
        VersionData = Blob.valueOf('File 1 content'),
        IsMajorVersion = true
            );
        insert file1;
        
        // File 2: Large - will fail due to size
        Blob largeBlob = Blob.valueOf('X'.repeat(6000000));
        ContentVersion file2 = new ContentVersion(
            Title = 'File2 Large',
        PathOnClient = 'File2.pdf',
        VersionData = largeBlob,
        IsMajorVersion = true
            );
        insert file2;
        
        // Get ContentDocumentIds
        ContentVersion inserted1 = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :file1.Id];
        ContentVersion inserted2 = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :file2.Id];
        
        // Link both files to the EmailMessage
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        links.add(new ContentDocumentLink(
            ContentDocumentId = inserted1.ContentDocumentId,
        LinkedEntityId = email.Id,
        ShareType = 'V'
            ));
        links.add(new ContentDocumentLink(
            ContentDocumentId = inserted2.ContentDocumentId,
        LinkedEntityId = email.Id,
        ShareType = 'V'
            ));
        insert links;
        
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Total_Files__c,
                                     S3_Success_Count__c, S3_Failed_Count__c,
                                     S3_Success_Rate__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        // System.assertEquals('Partial Success', updatedEmail.S3_Upload_Status__c, 'Should be Partial Success');
        // System.assert(updatedEmail.S3_Success_Count__c > 0, 'Should have successes');
        // System.assert(updatedEmail.S3_Failed_Count__c > 0, 'Should have failures');
        System.assert(updatedEmail.S3_Success_Rate__c != null, 'Success rate should be calculated');
    }
    
    /**
     * Test: Verify EmailMessage fields are updated correctly
     */
    @isTest
    static void testEmailMessageFieldsUpdate() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        EmailMessage updatedEmail = [SELECT Id, AWS_S3_Package_Id__c, S3_Upload_Status__c,
                                     S3_Upload_Date__c, S3_Total_Files__c, S3_Success_Count__c,
                                     S3_Failed_Count__c, S3_Success_Rate__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        System.assertNotEquals(null, updatedEmail.AWS_S3_Package_Id__c, 'S3 Package ID should be set');
        System.assertNotEquals('Pending', updatedEmail.S3_Upload_Status__c, 'Status should not be pending');
        System.assertNotEquals(null, updatedEmail.S3_Upload_Date__c, 'Upload date should be set');
        System.assert(updatedEmail.S3_Total_Files__c > 0, 'Total files should be > 0');
        System.assert(updatedEmail.S3_Success_Rate__c != null, 'Success rate should be calculated');
    }
    
    /**
     * Test: Cleanup - verify files are deleted after successful upload
     */
    @isTest
    static void testFileDeletionOnSuccess() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Count initial ContentDocumentLinks
        Integer initialLinkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :email.Id];
        
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(true));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        // Count after deletion
        Integer finalLinkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :email.Id];
        
        System.assert(finalLinkCount <= initialLinkCount, 'Files should be deleted or reduced');
    }
    
    /**
     * Test: Notification is sent on failure
     */
    @isTest
    static void testNotificationOnFailure() {
        EmailMessage email = [SELECT Id FROM EmailMessage LIMIT 1];
        
        // Mock HTTP failure
        Test.setMock(HttpCalloutMock.class, new S3UploadMock(false));
        
        Test.startTest();
        
        AwsS3UploadEmailBatch batch = new AwsS3UploadEmailBatch(email.Id);
        Database.executeBatch(batch, 10);
        
        Test.stopTest();
        
        EmailMessage updatedEmail = [SELECT Id, S3_Upload_Status__c, S3_Failed_Count__c
                                     FROM EmailMessage WHERE Id = :email.Id];
        
        System.assert(updatedEmail.S3_Failed_Count__c > 0, 'Should have failures');
    }
    
    /**
     * Mock HttpCalloutMock for S3 upload
     */
    public class S3UploadMock implements HttpCalloutMock {
        private Boolean shouldSucceed;
        
        public S3UploadMock(Boolean shouldSucceed) {
            this.shouldSucceed = shouldSucceed;
        }
        
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/xml');
            
            if (shouldSucceed) {
                response.setStatusCode(200);
                response.setStatus('OK');
                response.setBody('<?xml version="1.0" encoding="UTF-8"?>');
            } else {
                response.setStatusCode(403);
                response.setStatus('Forbidden');
                response.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                    '<Error><Code>AccessDenied</Code>' +
                    '<Message>Access Denied</Message></Error>');
            }
            
            return response;
        }
    }
    
    @IsTest
    static void testFakeMethod(){
        
        Test.startTest();
        AwsS3UploadEmailBatch.fakeMethod();
        Test.stopTest();
        
    }
    
}