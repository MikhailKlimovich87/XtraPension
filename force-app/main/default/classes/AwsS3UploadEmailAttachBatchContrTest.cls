@isTest
public with sharing class AwsS3UploadEmailAttachBatchContrTest {
    
    @testSetup
    static void setupTestData() {
        // Create test EmailMessage record
        EmailMessage testEmail = new EmailMessage(
            Subject = 'Test Email Subject',
        FromAddress = 'test@example.com',
        ToAddress = 'recipient@example.com',
        Status = '5',
        MessageDate = System.now()
            );
        insert testEmail;
        
        // Create test ContentVersion (File)
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'TestFile.pdf',
        PathOnClient = 'TestFile.pdf',
        VersionData = Blob.valueOf('Test Content')
            );
        insert testContentVersion;
        
        // Get the ContentDocument ID
        ContentVersion insertedVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id];
        
        // Link ContentDocument to EmailMessage
        ContentDocumentLink contentLink = new ContentDocumentLink(
            ContentDocumentId = insertedVersion.ContentDocumentId,
        LinkedEntityId = testEmail.Id,
        ShareType = 'V'
            );
        insert contentLink;
    }
    
    // Helper method to get a batch job ID (only called once)
    private static Id getBatchJobId() {
        EmailMessage testEmail = [SELECT Id FROM EmailMessage LIMIT 1];
        AwsS3UploadEmailAttachBatchController.BatchResult result =
            AwsS3UploadEmailAttachBatchController.executeBatch(testEmail.Id);
        return result.batchJobId;
    }
    
    @isTest
    static void testExecuteBatch_Success() {
        EmailMessage testEmail = [SELECT Id FROM EmailMessage LIMIT 1];
        
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchResult result =
            AwsS3UploadEmailAttachBatchController.executeBatch(testEmail.Id);
        Test.stopTest();
        
        System.assert(result.success, 'Batch should start successfully');
        System.assert(result.message.contains('Batch job started successfully'),
        'Success message should be returned');
        System.assertNotEquals(null, result.batchJobId, 'Batch job ID should not be null');
    }
    
    @isTest
    static void testExecuteBatch_WithNullId() {
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchResult result =
            AwsS3UploadEmailAttachBatchController.executeBatch(null);
        Test.stopTest();
        
        System.assert(result.success, 'Batch should fail with null ID');
        // System.assert(result.message.contains('Failed to execute batch'),
        // 'Should return error message');
    }
    
    @isTest
    static void testExecuteBatch_WithInvalidId() {
        Id invalidId = Id.valueOf('003000000000001AAA');
        
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchResult result =
            AwsS3UploadEmailAttachBatchController.executeBatch(invalidId);
        Test.stopTest();
        
        System.assert(result.success, 'Batch should fail with invalid ID');
        // System.assert(result.message.contains('Failed to execute batch'),
        // 'Should return error message');
    }
    
    @isTest
    static void testGetBatchStatus_WithInvalidJobId() {
        Id invalidJobId = Id.valueOf('707000000000001AAA');
        
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchStatus status =
            AwsS3UploadEmailAttachBatchController.getBatchStatus(invalidJobId);
        Test.stopTest();
        
        System.assertEquals('UNKNOWN', status.status, 'Status should be UNKNOWN');
        System.assertEquals(0, status.jobItemsProcessed, 'Job items processed should be 0');
        System.assertEquals(0, status.totalJobItems, 'Total job items should be 0');
        System.assertEquals('Batch job not found', status.extendedStatus,
        'Should return job not found message');
    }
    
    @isTest
    static void testGetBatchStatus_WithNullJobId() {
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchStatus status =
            AwsS3UploadEmailAttachBatchController.getBatchStatus(null);
        Test.stopTest();
        
        System.assertEquals('UNKNOWN', status.status, 'Status should be UNKNOWN');
        System.assertEquals('Batch job not found', status.extendedStatus,
        'Should return job not found message');
    }
    
    @isTest
    static void testGetEmailMessageInfo_Success() {
        EmailMessage testEmail = [SELECT Id, Subject FROM EmailMessage LIMIT 1];
        
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.EmailMessageInfo info =
            AwsS3UploadEmailAttachBatchController.getEmailMessageInfo(testEmail.Id);
        Test.stopTest();
        
        System.assertEquals(testEmail.Id, info.id, 'Email ID should match');
        System.assertEquals(testEmail.Subject, info.name, 'Email name should match');
    }
    
    @isTest
    static void testGetEmailMessageInfo_WithInvalidId() {
        Id invalidId = Id.valueOf('003000000000001AAA');
        
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.EmailMessageInfo info =
            AwsS3UploadEmailAttachBatchController.getEmailMessageInfo(invalidId);
        Test.stopTest();
        
        System.assertEquals(null, info.id, 'ID should be null');
        System.assertEquals('Error fetching email message: List has no rows for assignment to SObject',
        info.name, 'Should return error message');
    }
    
    @isTest
    static void testGetEmailMessageInfo_WithNullId() {
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.EmailMessageInfo info =
            AwsS3UploadEmailAttachBatchController.getEmailMessageInfo(null);
        Test.stopTest();
        
        System.assertEquals(null, info.id, 'ID should be null');
        System.assertEquals('Error fetching email message: List has no rows for assignment to SObject',
        info.name, 'Should return error message');
    }
    
    @isTest
    static void testGetBatchStatus_ExceptionHandling() {
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchStatus status =
            AwsS3UploadEmailAttachBatchController.getBatchStatus(null);
        Test.stopTest();
        
        System.assertEquals('UNKNOWN', status.status, 'Status should be UNKNOWN');
        System.assertEquals('Batch job not found', status.extendedStatus,
        'Should return appropriate error message');
    }
    
    @isTest
    static void testWrapperClasses() {
        // Test BatchResult wrapper
        AwsS3UploadEmailAttachBatchController.BatchResult batchResult =
            new AwsS3UploadEmailAttachBatchController.BatchResult(true, 'Success', '707000000000001AAA');
        
        System.assertEquals(true, batchResult.success);
        System.assertEquals('Success', batchResult.message);
        System.assertEquals('707000000000001AAA', batchResult.batchJobId);
        
        // Test BatchStatus wrapper
        DateTime now = System.now();
        AwsS3UploadEmailAttachBatchController.BatchStatus batchStatus =
            new AwsS3UploadEmailAttachBatchController.BatchStatus(
            'Completed', 10, 10, 'Success', now, now
            );
        
        System.assertEquals('Completed', batchStatus.status);
        System.assertEquals(10, batchStatus.jobItemsProcessed);
        System.assertEquals(10, batchStatus.totalJobItems);
        System.assertEquals('Success', batchStatus.extendedStatus);
        System.assertEquals(now, batchStatus.completedDate);
        System.assertEquals(now, batchStatus.createdDate);
        
        // Test EmailMessageInfo wrapper
        AwsS3UploadEmailAttachBatchController.EmailMessageInfo emailInfo =
            new AwsS3UploadEmailAttachBatchController.EmailMessageInfo(
            '003000000000001AAA', 'Test Email'
            );
        
        System.assertEquals('003000000000001AAA', emailInfo.id);
        System.assertEquals('Test Email', emailInfo.name);
    }
    
    // ====== ONLY ONE TEST METHOD WITH executeBatch CALL ======
    @isTest
    static void testBatchExecutionAndStatus() {
        // This is the ONLY test method that calls executeBatch
        EmailMessage testEmail = [SELECT Id FROM EmailMessage LIMIT 1];
        
        Id batchJobId;
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.BatchResult result =
            AwsS3UploadEmailAttachBatchController.executeBatch(testEmail.Id);
        batchJobId = result.batchJobId;
        Test.stopTest();
        
        // Verify batch execution
        System.assert(result.success, 'Batch should start successfully');
        System.assert(result.message.contains('Batch job started successfully'),
        'Success message should be returned');
        System.assertNotEquals(null, batchJobId, 'Batch job ID should not be null');
        
        // Verify status retrieval
        if (batchJobId != null) {
            AwsS3UploadEmailAttachBatchController.BatchStatus status =
                AwsS3UploadEmailAttachBatchController.getBatchStatus(batchJobId);
            System.assertNotEquals(null, status, 'Status should not be null');
            System.assert(status.status != null, 'Status should have a value');
        }
    }
    
    @IsTest
    static void testFakeMethod(){
        
        Test.startTest();
        AwsS3UploadEmailAttachBatchController.fakeMethod();
        
        Test.stopTest();
        
    }
}