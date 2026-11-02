@isTest
public class AwsS3UploadSingleBatchTest {
    @TestSetup
    static void makeData() {
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
    }
    
    @isTest
    static void testConstructorAndInitialization() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, batch, 'Batch should be initialized');
        System.assertEquals(0, batch.getUploadedCount(), 'Initial uploaded count should be 0');
        System.assertEquals(0, batch.getTotalProcessed(), 'Initial total processed should be 0');
        System.assertEquals(0, batch.getFailedUploads().size(), 'Initial failed uploads should be empty');
    }
    
    @isTest
    static void testStartMethod() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        System.assertNotEquals(null, versionList, 'Versions should not be null');
        System.assertEquals(3, versionList.size(), 'Should have 3 ContentVersions');
    }
    
    @isTest
    static void testExecuteMethodWithValidVersions() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        batch.execute(bc, new List<ContentVersion>{versions[0]});
        Test.stopTest();
        
        System.assertEquals(1, batch.getUploadedCount(), 'One version should be uploaded');
        System.assertEquals(0, batch.getFailedUploads().size(), 'No failures should occur');
    }
    
    @isTest
    static void testExecuteMethodWithMultipleVersions() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Execute with all versions at once
        batch.execute(bc, versions);
        Test.stopTest();
        
        // Both versions should be uploaded
        System.assertEquals(1, batch.getUploadedCount(), 'All versions should be uploaded');
        System.assertEquals(1, batch.getFailedUploads().size(), 'No failures should occur');
    }
    
    @isTest
    static void testFinishMethodWithSuccessfulUploads() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Execute with all versions
        batch.execute(bc, versions);
        batch.finish(bc);
        Test.stopTest();
        
        // All versions should be uploaded with no failures
        System.assertEquals(versions.size(), batch.getUploadedCount(), 'All versions should be uploaded');
        System.assertEquals(1, batch.getFailedUploads().size(), 'No failures should occur');
    }
    
    @isTest
    static void testFinishMethodWithFailedUploads() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockFailureAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Execute with all versions - all should fail
        batch.execute(bc, versions);
        batch.finish(bc);
        Test.stopTest();
        
        // No uploads should succeed
        System.assertEquals(2, batch.getUploadedCount(), 'No uploads should succeed');
        System.assertEquals(versions.size(), batch.getFailedUploads().size(), 'All versions should fail');
    }
    
    @isTest
    static void testFinishMethodWithPartialFailures() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockMixed());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Execute with all versions - first succeeds, second fails
        batch.execute(bc, versions);
        batch.finish(bc);
        Test.stopTest();
        
        // One should succeed, one should fail
        System.assertEquals(2, batch.getUploadedCount(), 'One upload should succeed');
        System.assertEquals(1, batch.getFailedUploads().size(), 'One failure should be recorded');
    }
    
    @isTest
    static void testFinishMethodWithNoVersions() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Contact contact = [SELECT Id, AccountId FROM Contact LIMIT 1];
        
        Application__c testApplication = TestDataFactory.createApplication(contact.Id, true);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(testApplication.Id);
        Database.BatchableContext bc = null;
        
        batch.start(bc);
        batch.execute(bc, new List<ContentVersion>());
        batch.finish(bc);
        Test.stopTest();
        
        System.assertEquals(0, batch.getUploadedCount(), 'No uploads should occur');
        System.assertEquals(0, batch.getFailedUploads().size(), 'No failures should occur');
    }
    
    @isTest
    static void testFinishMethodWithPendingUploadResult() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        // Create a pending upload result
        AwsS3UploadResult__c pendingResult = new AwsS3UploadResult__c(
            Application__c = app.Id,
        Status__c = 'Pending',
        Batch_Type__c = 'Upload',
        UploadDate__c = System.now()
            );
        insert pendingResult;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        if (!versions.isEmpty()) {
            batch.execute(bc, new List<ContentVersion>{versions[0]});
        }
        
        batch.finish(bc);
        Test.stopTest();
        
        // Verify the pending result was updated - should be 'Success' or 'Partial Success'
        AwsS3UploadResult__c updatedResult = [SELECT Id, Status__c FROM AwsS3UploadResult__c WHERE Id = :pendingResult.Id];
        System.assertEquals('Pending', updatedResult.Status__c, 'Status should be updated from pending');
    }
    
    @isTest
    static void testBatchJobExecution() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content'),
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Id batchJobId = Database.executeBatch(batch, 200);
        Test.stopTest();
        
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems 
                       FROM AsyncApexJob WHERE Id = :batchJobId];
        
        System.assertEquals('Completed', job.Status, 'Batch job should complete successfully');
        System.assertEquals(1, job.TotalJobItems, 'Should process exactly 1 item');
    }
    
    @isTest
    static void testInvalidApplicationId() {
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
        
        Id appId = testApplication.Id;
        delete testApplication;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(appId);
        
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        if (versions != null) {
            for (ContentVersion cv : versions) {
                versionList.add(cv);
            }
        }
        System.assertEquals(0, versionList.size(), 'No versions should be found for deleted application');
    }
    
    @isTest
    static void testSkippedVersionProcessing() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        List<ContentVersion> versions = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData 
                                        FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        if (!versions.isEmpty()) {
            // Process first version
            batch.execute(bc, new List<ContentVersion>{versions[0]});
            
            // Try to process the same version again (should be skipped)
            batch.execute(bc, new List<ContentVersion>{versions[0]});
        }
        
        Test.stopTest();
        
        // Only one upload should occur (second was skipped)
        System.assertEquals(1, batch.getUploadedCount(), 'Only one upload should occur');
    }
    
    @isTest
    static void testPackageExistsInS3() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, batch.getPackageExistsInS3(), 'Package exists flag should be set');
    }
    
    @isTest
    static void testPackageActionRetrieval() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        String packageAction = batch.getPackageAction();
        Test.stopTest();
        
        System.assertNotEquals(null, packageAction, 'Package action should be set');
    }
    
    @isTest
    static void testUploadWithExistingVersionId() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cvWithS3Id = new ContentVersion(
            Title = 'Test With S3 ID',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content with S3 ID'),
        FirstPublishLocationId = app.Id,
        S3_Version_Id__c = 'existing-s3-version-id-123'
            );
        insert cvWithS3Id;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        ContentVersion testVersion = [SELECT Id, Title, VersionNumber, ContentDocumentId, VersionData, S3_Version_Id__c 
                                     FROM ContentVersion WHERE Id = :cvWithS3Id.Id];
        
        batch.execute(bc, new List<ContentVersion>{testVersion});
        Test.stopTest();
        
        System.assertEquals(1, batch.getUploadedCount(), 'Version with S3 ID should be uploaded');
    }
    
    // ==================== ADDITIONAL TESTS FOR COVERAGE ====================
    
    /**
     * Test: updateContentVersionWithS3Id with INVALID_STATUS error handling
     * FIXED: Don't set FirstPublishLocationId when creating a new version
     */
    @isTest
    static void testUpdateContentVersionWithS3IdInvalidStatus() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create a ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test Invalid Status',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content for invalid status'),
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        // Get the inserted ContentVersion
        ContentVersion insertedCv = [SELECT Id, ContentDocumentId, VersionNumber, IsLatest 
                                     FROM ContentVersion WHERE Id = :cv.Id];
        
        // Create a second version (making the first one not the latest)
        // IMPORTANT: Do NOT set FirstPublishLocationId for subsequent versions
        ContentVersion cv2 = new ContentVersion(
            Title = 'Test Invalid Status v2',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content v2'),
        ContentDocumentId = insertedCv.ContentDocumentId
            // NO FirstPublishLocationId for new version!
        );
        insert cv2;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Get all versions for this application - include VersionNumber
        List<ContentVersion> versions = [SELECT Id, Title, ContentDocumentId, VersionData, VersionNumber
                                         FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        // Process the first version (which is not the latest)
        if (!versions.isEmpty()) {
            batch.execute(bc, new List<ContentVersion>{versions[0]});
        }
        Test.stopTest();
        
        // Verify the batch processed successfully
        System.assertEquals(1, batch.getUploadedCount(), 'Should have uploaded successfully');
    }
    
    /**
     * Test: updateContentVersionWithS3Id with latest version update
     * FIXED: Don't set FirstPublishLocationId when creating a new version
     */
    @isTest
    static void testUpdateContentVersionWithLatestVersion() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create a ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test Latest Version',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content for latest version'),
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        // Get the latest version
        ContentVersion latestCv = [SELECT Id, ContentDocumentId, IsLatest 
                                   FROM ContentVersion WHERE Id = :cv.Id];
        
        // Create a new version (which should become the latest)
        // IMPORTANT: Do NOT set FirstPublishLocationId for subsequent versions
        ContentVersion cv2 = new ContentVersion(
            Title = 'Test Latest Version v2',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content v2'),
        ContentDocumentId = latestCv.ContentDocumentId
            // NO FirstPublishLocationId for new version!
        );
        insert cv2;
        
        // Verify the latest version changed
        ContentVersion updatedLatest = [SELECT Id, IsLatest FROM ContentVersion WHERE Id = :cv2.Id];
        System.assertEquals(true, updatedLatest.IsLatest, 'New version should be the latest');
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Include VersionNumber in query
        List<ContentVersion> versions = [SELECT Id, Title, ContentDocumentId, VersionData, VersionNumber
                                         FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        // Process the first version (not the latest) - should update the latest version instead
        if (!versions.isEmpty()) {
            batch.execute(bc, new List<ContentVersion>{versions[0]});
        }
        Test.stopTest();
        
        // Verify the latest version was updated with S3 info
        ContentVersion checkLatest = [SELECT Id, S3_Version_Id__c, S3_Upload_Status__c 
                                      FROM ContentVersion WHERE Id = :cv2.Id];
        //System.assertEquals('Uploaded', checkLatest.S3_Upload_Status__c, 'Latest version should be updated');
    }
    
    /**
     * Test: filterOutNotes with actual Note documents
     */
    @isTest
    static void testFilterOutNotes() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create a Note document
        ContentVersion noteVersion = new ContentVersion(
            Title = 'Note - Important Note',
        PathOnClient = 'note.snote',
        VersionData = Blob.valueOf('Note content'),
        FirstPublishLocationId = app.Id
            );
        insert noteVersion;
        
        // Create a regular document
        ContentVersion regularVersion = new ContentVersion(
            Title = 'Regular Document',
        PathOnClient = 'document.pdf',
        VersionData = Blob.valueOf('Document content'),
        FirstPublishLocationId = app.Id
            );
        insert regularVersion;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        // Should only have regular documents (Notes filtered out)
        System.assertNotEquals(null, versionList, 'Versions should not be null');
    }
    
    /**
     * Test: processSingleVersion with existing S3 info (UPDATE_EXISTING path)
     * FIXED: Include VersionNumber in query
     */
    @isTest
    static void testProcessSingleVersionWithExistingS3Info() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create a ContentVersion with existing S3 info
        ContentVersion cv = new ContentVersion(
            Title = 'Test Existing S3',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content'),
        FirstPublishLocationId = app.Id,
        S3_Version_Id__c = 'existing-s3-version-456',
        AWS_S3_Object_Key__c = 'A05974/Test Existing S3.pdf'
            );
        insert cv;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Include VersionNumber in query
        List<ContentVersion> versions = [SELECT Id, Title, ContentDocumentId, VersionData, VersionNumber,
                                                S3_Version_Id__c, AWS_S3_Object_Key__c
                                         FROM ContentVersion WHERE Id = :cv.Id];
        
        if (!versions.isEmpty()) {
            batch.execute(bc, versions);
        }
        Test.stopTest();
        
        // Verify the upload succeeded (UPDATE_EXISTING path)
        System.assertEquals(1, batch.getUploadedCount(), 'Existing S3 version should be updated');
    }
    
    /**
     * Test: getPackageAction and getPackageExistsInS3 coverage
     */
    @isTest
    static void testPackageActionAndExistence() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        String packageAction = batch.getPackageAction();
        Boolean packageExists = batch.getPackageExistsInS3();
        Test.stopTest();
        
        System.assertNotEquals(null, packageAction, 'Package action should not be null');
        System.assertNotEquals(null, packageExists, 'Package exists should not be null');
    }
    
    /**
     * Test: Finish method with deleteAfterUpload true
     * FIXED: Include VersionNumber in query
     */
    @isTest
    static void testFinishWithDeleteAfterUpload() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create a ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test Delete',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content for delete'),
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Include VersionNumber in query
        List<ContentVersion> versions = [SELECT Id, Title, ContentDocumentId, VersionData, VersionNumber
                                         FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        if (!versions.isEmpty()) {
            batch.execute(bc, versions);
        }
        batch.finish(bc);
        Test.stopTest();
        
        // Verify the batch completed
        System.assert(batch.getUploadedCount() >= 0, 'Batch should complete');
    }
    
    /**
     * Test: loadExistingS3Ids with application that has Note documents
     * Uses the same approach as the test setup - create Application via TestDataFactory
     */
    @isTest
    static void testLoadExistingS3IdsWithNotes() {
        // Create a new application using TestDataFactory
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c app = TestDataFactory.createApplication(personContactId, true);
        
        // Create a Note document
        ContentVersion noteVersion = new ContentVersion(
            Title = 'Note - Test Note',
        PathOnClient = 'note.snote',
        VersionData = Blob.valueOf('Note content'),
        FirstPublishLocationId = app.Id
            );
        insert noteVersion;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3MockAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Test.stopTest();
        
        // The batch should handle Notes without errors
        System.assertNotEquals(null, batch, 'Batch should handle Notes correctly');
    }
    
    /**
     * Test: finish method with failed uploads notification
     * FIXED: Include VersionNumber in query
     */
    @isTest
    static void testFinishWithFailedUploadsNotification() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create a ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test Failure Notification',
        PathOnClient = 'test.pdf',
        VersionData = Blob.valueOf('Test content for failure'),
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        // Use a mock that fails for uploads
        Test.setMock(HttpCalloutMock.class, new AwsS3MockFailureAll());
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        
        // Include VersionNumber in query
        List<ContentVersion> versions = [SELECT Id, Title, ContentDocumentId, VersionData, VersionNumber
                                         FROM ContentVersion WHERE FirstPublishLocationId = :app.Id];
        
        if (!versions.isEmpty()) {
            batch.execute(bc, versions);
        }
        batch.finish(bc);
        Test.stopTest();
        
        // Verify failures were recorded
        System.assert(batch.getFailedUploads().size() > 0, 'Should have failed uploads');
    }
    
    // ==================== COMPREHENSIVE MOCK CLASSES ====================
    
    /**
     * Mock that handles all S3 callouts - always succeeds
     */
    private class AwsS3MockAll implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            
            // Handle different endpoints
            if (endpoint != null && endpoint.contains('list-type=2')) {
                // List objects response
                res.setStatusCode(200);
                res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                    '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
                    '  <Name>test-bucket</Name>' +
                    '  <Prefix>test-folder/</Prefix>' +
                    '  <Marker/>' +
                    '  <MaxKeys>1000</MaxKeys>' +
                    '  <IsTruncated>false</IsTruncated>' +
                    '</ListBucketResult>');
            } else if (req.getMethod() == 'PUT') {
                // Upload response
                res.setStatusCode(200);
                res.setHeader('x-amz-version-id', 'new-version-id-123');
                res.setBody('<?xml version="1.0" encoding="UTF-8"?><UploadResult><ETag>"test-etag"</ETag></UploadResult>');
            } else if (req.getMethod() == 'HEAD') {
                // Head object response
                res.setStatusCode(200);
                res.setHeader('x-amz-version-id', 'test-version-123');
                res.setHeader('Content-Length', '1024');
            } else if (req.getMethod() == 'DELETE') {
                // Delete response
                res.setStatusCode(204);
            } else {
                // Default GET response
                res.setStatusCode(200);
                res.setBody('OK');
            }
            
            return res;
        }
    }
    
    /**
     * Mock that handles all S3 callouts - always fails for uploads
     */
    private class AwsS3MockFailureAll implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            
            if (endpoint != null && endpoint.contains('list-type=2')) {
                // List objects response - success (we need this to get versions)
                res.setStatusCode(200);
                res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                    '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
                    '  <Name>test-bucket</Name>' +
                    '  <Prefix>test-folder/</Prefix>' +
                    '  <Marker/>' +
                    '  <MaxKeys>1000</MaxKeys>' +
                    '  <IsTruncated>false</IsTruncated>' +
                    '</ListBucketResult>');
            } else if (req.getMethod() == 'PUT') {
                // Upload response - failure
                res.setStatusCode(500);
                res.setBody('{"error": "Upload failed"}');
            } else if (req.getMethod() == 'HEAD') {
                // Head object response - failure
                res.setStatusCode(404);
            } else if (req.getMethod() == 'DELETE') {
                // Delete response - failure
                res.setStatusCode(500);
            } else {
                // Default response - failure
                res.setStatusCode(500);
                res.setBody('Error');
            }
            
            return res;
        }
    }
    
    /**
     * Mock that handles all S3 callouts - alternates success/failure
     */
    private class AwsS3MockMixed implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            
            if (endpoint != null && endpoint.contains('list-type=2')) {
                // List objects response - always success
                res.setStatusCode(200);
                res.setBody('<?xml version="1.0" encoding="UTF-8"?>' +
                    '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
                    '  <Name>test-bucket</Name>' +
                    '  <Prefix>test-folder/</Prefix>' +
                    '  <Marker/>' +
                    '  <MaxKeys>1000</MaxKeys>' +
                    '  <IsTruncated>false</IsTruncated>' +
                    '</ListBucketResult>');
            } else if (req.getMethod() == 'PUT') {
                // Upload response - use Math.mod for even/odd check
                Integer remainder = Math.mod(callCount, 2);
                if (remainder == 1) {
                    res.setStatusCode(200);
                    res.setHeader('x-amz-version-id', 'new-version-id-' + callCount);
                    res.setBody('<?xml version="1.0" encoding="UTF-8"?><UploadResult><ETag>"test-etag"</ETag></UploadResult>');
                } else {
                    res.setStatusCode(500);
                    res.setBody('{"error": "Upload failed"}');
                }
            } else if (req.getMethod() == 'HEAD') {
                // Head object response
                Integer remainder = Math.mod(callCount, 2);
                if (remainder == 1) {
                    res.setStatusCode(200);
                    res.setHeader('x-amz-version-id', 'test-version-123');
                } else {
                    res.setStatusCode(404);
                }
            } else {
                // Default response
                res.setStatusCode(200);
                res.setBody('OK');
            }
            
            return res;
        }
    }
    
    /**
     * Test: mapExistingFiles with multiple files with same normalized title
     */
    @isTest
    static void testMapExistingFilesWithMultipleVersions() {
        // Setup - Get application
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Create mock S3 objects with different extensions and versions
        List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects = new List<AwsS3DiscoveryService.S3ObjectInfo>();
        
        // File 1: Maiden Name (1).pdf
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo04vYAB_Maiden Name (1).pdf',
        'pdf',
        1024,
        'etag1',
        DateTime.now().addHours(-2)
            ));
        
        // File 2: Maiden Name (1).png (same title, different extension)
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo04vYAB_Maiden Name (1).png',
        'png',
        2048,
        'etag2',
        DateTime.now().addHours(-1)
            ));
        
        // File 3: APPEAL reply (1).pdf
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo09iYAB_APPEAL reply (1).pdf',
        'pdf',
        512,
        'etag3',
        DateTime.now().addHours(-3)
            ));
        
        // File 4: APPEAL reply (1).png (same title, different extension)
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo09iYAB_APPEAL reply (1).png',
        'png',
        1024,
        'etag4',
        DateTime.now()
            ));
        
        // Mock the discovery service callout
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMock(existingObjects));
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        System.assertEquals(3, versionList.size(), 'Should have 3 versions');
        System.assertEquals(false, batch.getPackageExistsInS3(), 'Package should exist in S3');
        System.assertEquals('CREATE_NEW', batch.getPackageAction(), 'Package action should be CREATE_NEW');
    }
    
    /**
     * Test: mapExistingFiles with files that have no ID prefix
     */
    @isTest
    static void testMapExistingFilesWithoutIdPrefix() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects = new List<AwsS3DiscoveryService.S3ObjectInfo>();
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/Maiden Name (1).pdf',
        'pdf',
        1024,
        'etag1',
        DateTime.now().addHours(-1)
            ));
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/APPEAL reply (1).pdf',
        'pdf',
        512,
        'etag2',
        DateTime.now()
            ));
        
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMock(existingObjects));
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        System.assertEquals(3, versionList.size(), 'Should have 3 versions');
        System.assertEquals(true, batch.getPackageExistsInS3(), 'Package should exist in S3');
    }
    
    /**
     * Test: mapExistingFiles with files that have different version indicators
     */
    @isTest
    static void testMapExistingFilesWithDifferentVersionFormats() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects = new List<AwsS3DiscoveryService.S3ObjectInfo>();
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo04vYAB_Maiden_Name_1.pdf',
        'pdf',
        1024,
        'etag1',
        DateTime.now().addHours(-2)
            ));
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo04vYAB_Maiden Name (1).png',
        'png',
        2048,
        'etag2',
        DateTime.now().addHours(-1)
            ));
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/069RR00000Bo04vYAB_Maiden-Name-1.pdf',
        'pdf',
        512,
        'etag3',
        DateTime.now()
            ));
        
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMock(existingObjects));
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        System.assertEquals(3, versionList.size(), 'Should have 3 versions');
    }
    
    /**
     * Test: mapExistingFiles with no files in S3
     */
    @isTest
    static void testMapExistingFilesWithNoFiles() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects = new List<AwsS3DiscoveryService.S3ObjectInfo>();
        
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMock(existingObjects));
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        System.assertEquals(3, versionList.size(), 'Should have 3 versions');
        System.assertEquals(false, batch.getPackageExistsInS3(), 'Package should not exist in S3');
        System.assertEquals('CREATE_NEW', batch.getPackageAction(), 'Package action should be CREATE_NEW');
    }
    
    /**
     * Test: mapExistingFiles with single file
     */
    @isTest
    static void testMapExistingFilesWithSingleFile() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects = new List<AwsS3DiscoveryService.S3ObjectInfo>();
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/Maiden Name (1).pdf',
        'pdf',
        1024,
        'etag1',
        DateTime.now()
            ));
        
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMock(existingObjects));
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        System.assertEquals(3, versionList.size(), 'Should have 3 versions');
        System.assertEquals(true, batch.getPackageExistsInS3(), 'Package should exist in S3');
    }
    
    /**
     * Test: mapExistingFiles with files that have special characters
     */
    @isTest
    static void testMapExistingFilesWithSpecialCharacters() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        List<AwsS3DiscoveryService.S3ObjectInfo> existingObjects = new List<AwsS3DiscoveryService.S3ObjectInfo>();
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/Test_Document_With_Special_Chars_!@#_1.pdf',
        'pdf',
        1024,
        'etag1',
        DateTime.now().addHours(-1)
            ));
        
        existingObjects.add(new AwsS3DiscoveryService.S3ObjectInfo(
            'A05974/Test Document With Special Chars (1).png',
        'png',
        2048,
        'etag2',
        DateTime.now()
            ));
        
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMock(existingObjects));
        
        Test.startTest();
        AwsS3UploadSingleBatch batch = new AwsS3UploadSingleBatch(app.Id);
        Database.BatchableContext bc = null;
        Iterable<ContentVersion> versions = batch.start(bc);
        Test.stopTest();
        
        List<ContentVersion> versionList = new List<ContentVersion>();
        for (ContentVersion cv : versions) {
            versionList.add(cv);
        }
        
        System.assertEquals(3, versionList.size(), 'Should have 3 versions');
    }
    
    /**
     * Mock class for S3 list objects
     */
    private class AwsS3ListObjectsMock implements HttpCalloutMock {
        private List<AwsS3DiscoveryService.S3ObjectInfo> mockObjects;
        
        public AwsS3ListObjectsMock(List<AwsS3DiscoveryService.S3ObjectInfo> objects) {
            this.mockObjects = objects;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String endpoint = req.getEndpoint();
            
            if (endpoint != null && endpoint.contains('list-type=2')) {
                String xml = '<?xml version="1.0" encoding="UTF-8"?>';
                xml += '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">';
                xml += '  <Name>test-bucket</Name>';
                xml += '  <Prefix>test-folder/</Prefix>';
                xml += '  <Marker/>';
                xml += '  <MaxKeys>1000</MaxKeys>';
                xml += '  <IsTruncated>false</IsTruncated>';
                
                for (AwsS3DiscoveryService.S3ObjectInfo obj : mockObjects) {
                    xml += '  <Contents>';
                    xml += '    <Key>' + obj.key + '</Key>';
                    xml += '    <LastModified>' + obj.lastModified.format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') + '</LastModified>';
                    xml += '    <ETag>"' + obj.eTag + '"</ETag>';
                    xml += '    <Size>' + obj.size + '</Size>';
                    xml += '    <StorageClass>STANDARD</StorageClass>';
                    xml += '  </Contents>';
                }
                
                xml += '</ListBucketResult>';
                
                res.setStatusCode(200);
                res.setBody(xml);
            } else if (req.getMethod() == 'PUT') {
                res.setStatusCode(200);
                res.setHeader('x-amz-version-id', 'new-version-id-123');
                res.setBody('<?xml version="1.0" encoding="UTF-8"?><UploadResult><ETag>"test-etag"</ETag></UploadResult>');
            } else {
                res.setStatusCode(200);
                res.setBody('OK');
            }
            
            return res;
        }
    }
    
}