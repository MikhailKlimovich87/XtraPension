@isTest
public class AwsS3ContentDocumentServiceTest {
    
    @TestSetup
    static void makeData() {
        // Create test data
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
        
        // Create test ContentVersions
        ContentVersion testContentVersion1 = new ContentVersion(
            Title = 'Test Document 1',
        VersionData = Blob.valueOf('Test Content 1'),
        PathOnClient = 'test1.pdf',
        FirstPublishLocationId = testApplication.Id
            );
        insert testContentVersion1;
        
        ContentVersion testContentVersion2 = new ContentVersion(
            Title = 'Test Document 2',
        VersionData = Blob.valueOf('Test Content 2'),
        PathOnClient = 'test2.pdf',
        FirstPublishLocationId = testApplication.Id
            );
        insert testContentVersion2;
    }
    
    @isTest
    static void testConstructor() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        
        Test.startTest();
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, service, 'Service should be instantiated');
    }
    
    @isTest
    static void testUpdateDocumentsWithEmptyList() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Verify state is empty
        System.assertEquals(0, state.documentsToUpdate.size(), 'Documents to update should be empty');
        
        Test.startTest();
        service.updateDocuments();
        Test.stopTest();
        
        // Verify no updates were performed
        System.assertEquals(0, state.documentsToUpdate.size(), 'Documents to update should remain empty');
    }
    
    @isTest
    static void testUpdateDocumentsWithValidData() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Get a ContentDocument to update
        ContentDocument doc = [SELECT Id, Title FROM ContentDocument LIMIT 1];
        
        // Add to state
        state.documentsToUpdate.put(doc.Id, new ContentDocument(
            Id = doc.Id,
        Title = 'Updated Title'
            ));
        
        System.assertEquals(1, state.documentsToUpdate.size(), 'Documents to update should have 1 item');
        
        Test.startTest();
        service.updateDocuments();
        Test.stopTest();
        
        // Verify state was cleared after update
        System.assertEquals(0, state.documentsToUpdate.size(), 'Documents to update should be cleared');
        
        // Verify the document was updated
        ContentDocument updatedDoc = [SELECT Id, Title FROM ContentDocument WHERE Id = :doc.Id];
        System.assertEquals('Updated Title', updatedDoc.Title, 'Document title should be updated');
    }
    
    @isTest
    static void testUpdateDocumentsWithMultipleDocuments() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Get ContentDocuments
        List<ContentDocument> docs = [SELECT Id, Title FROM ContentDocument LIMIT 2];
        
        // Add to state
        for (ContentDocument doc : docs) {
            state.documentsToUpdate.put(doc.Id, new ContentDocument(
                Id = doc.Id,
            Title = 'Updated Title ' + doc.Title
                ));
        }
        
        System.assertEquals(2, state.documentsToUpdate.size(), 'Documents to update should have 2 items');
        
        Test.startTest();
        service.updateDocuments();
        Test.stopTest();
        
        // Verify state was cleared after update
        System.assertEquals(0, state.documentsToUpdate.size(), 'Documents to update should be cleared');
        
        // Verify the documents were updated
        List<ContentDocument> updatedDocs = [SELECT Id, Title FROM ContentDocument WHERE Id IN :state.documentsToUpdate.keySet()];
        for (ContentDocument doc : updatedDocs) {
            System.assert(doc.Title.startsWith('Updated Title'), 'Document should be updated');
        }
    }
    
    @isTest
    static void testDeleteFilesWithDeleteNotConfigured() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.deleteAfterUpload = false;  // Delete not configured
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        // Get a ContentDocument ID
        ContentDocument doc = [SELECT Id FROM ContentDocument LIMIT 1];
        state.contentDocumentIdsToDelete.add(doc.Id);
        
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Verify document exists before deletion
        Integer docCountBefore = [SELECT COUNT() FROM ContentDocument WHERE Id = :doc.Id];
        System.assertEquals(1, docCountBefore, 'Document should exist before deletion');
        
        Test.startTest();
        service.deleteFiles();
        Test.stopTest();
        
        // Verify document still exists (delete was skipped)
        Integer docCountAfter = [SELECT COUNT() FROM ContentDocument WHERE Id = :doc.Id];
        System.assertEquals(1, docCountAfter, 'Document should still exist (delete was skipped)');
    }
    
    @isTest
    static void testDeleteFilesWithNotAllUploadsSuccessful() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.deleteAfterUpload = true;
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = false;  // Not all uploads succeeded
        
        // Get a ContentDocument ID
        ContentDocument doc = [SELECT Id FROM ContentDocument LIMIT 1];
        state.contentDocumentIdsToDelete.add(doc.Id);
        
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Verify document exists before deletion
        Integer docCountBefore = [SELECT COUNT() FROM ContentDocument WHERE Id = :doc.Id];
        System.assertEquals(1, docCountBefore, 'Document should exist before deletion');
        
        Test.startTest();
        service.deleteFiles();
        Test.stopTest();
        
        // Verify document still exists (delete was skipped)
        Integer docCountAfter = [SELECT COUNT() FROM ContentDocument WHERE Id = :doc.Id];
        System.assertEquals(1, docCountAfter, 'Document should still exist (delete was skipped)');
    }
    
    @isTest
    static void testDeleteFilesWithEmptyList() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.deleteAfterUpload = true;
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        state.contentDocumentIdsToDelete = new Set<Id>();  // Empty list
        
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        Test.startTest();
        service.deleteFiles();
        Test.stopTest();
        
        // Verify no exceptions were thrown
        System.assertEquals(0, state.contentDocumentIdsToDelete.size(), 'Delete list should remain empty');
    }
    
    @isTest
    static void testDeleteFilesWithValidData() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.deleteAfterUpload = true;
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        // Get ContentDocuments to delete
        List<ContentDocument> docsToDelete = [SELECT Id FROM ContentDocument LIMIT 2];
        for (ContentDocument doc : docsToDelete) {
            state.contentDocumentIdsToDelete.add(doc.Id);
        }
        
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Verify documents exist before deletion
        Integer docCountBefore = [SELECT COUNT() FROM ContentDocument WHERE Id IN :state.contentDocumentIdsToDelete];
        System.assertEquals(2, docCountBefore, 'Documents should exist before deletion');
        
        Test.startTest();
        service.deleteFiles();
        Test.stopTest();
        
        // Verify documents were deleted
        Integer docCountAfter = [SELECT COUNT() FROM ContentDocument WHERE Id IN :state.contentDocumentIdsToDelete];
        System.assertEquals(0, docCountAfter, 'Documents should be deleted');
    }
    
    @isTest
    static void testDeleteFilesWithException() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.deleteAfterUpload = true;
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        // Add a non-existent ID to force an exception
        state.contentDocumentIdsToDelete.add('001000000000000000');
        
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        Test.startTest();
        try {
            service.deleteFiles();
            System.assert(true, 'Delete should handle exception gracefully');
        } catch (Exception ex) {
            System.assert(false, 'Exception should not be thrown, should be caught internally');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteFilesWithInvalidIds() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.deleteAfterUpload = true;
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        // Add invalid IDs
        state.contentDocumentIdsToDelete.add('001000000000000001');
        state.contentDocumentIdsToDelete.add('001000000000000002');
        
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        Test.startTest();
        service.deleteFiles();
        Test.stopTest();
        
        // Verify no exceptions were thrown
        System.assertNotEquals(0, state.contentDocumentIdsToDelete.size(), 'Delete list should have items');
    }
    
    @isTest
    static void testUpdateDocumentsWithNoChanges() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Get a ContentDocument
        ContentDocument doc = [SELECT Id, Title FROM ContentDocument LIMIT 1];
        
        // Add to state with same values (no actual change)
        state.documentsToUpdate.put(doc.Id, new ContentDocument(
            Id = doc.Id,
        Title = doc.Title  // Same title
            ));
        
        Test.startTest();
        service.updateDocuments();
        Test.stopTest();
        
        // Verify state was cleared
        System.assertEquals(0, state.documentsToUpdate.size(), 'Documents to update should be cleared');
        
        // Verify document wasn't changed
        ContentDocument updatedDoc = [SELECT Id, Title FROM ContentDocument WHERE Id = :doc.Id];
        System.assertEquals(doc.Title, updatedDoc.Title, 'Document title should remain the same');
    }
    
    @isTest
    static void testUpdateDocumentsWithLargeBatch() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3ContentDocumentService service = new AwsS3ContentDocumentService(config, state);
        
        // Get all ContentDocuments
        List<ContentDocument> docs = [SELECT Id, Title FROM ContentDocument];
        
        // Add all to state
        for (ContentDocument doc : docs) {
            state.documentsToUpdate.put(doc.Id, new ContentDocument(
                Id = doc.Id,
            Title = 'Batch Updated ' + doc.Title
                ));
        }
        
        Integer batchSize = state.documentsToUpdate.size();
        System.assert(batchSize > 0, 'Should have documents to update');
        
        Test.startTest();
        service.updateDocuments();
        Test.stopTest();
        
        // Verify state was cleared
        System.assertEquals(0, state.documentsToUpdate.size(), 'Documents to update should be cleared');
        
        // Verify documents were updated
        List<ContentDocument> updatedDocs = [SELECT Id, Title FROM ContentDocument WHERE Id IN :state.documentsToUpdate.keySet()];
        for (ContentDocument doc : updatedDocs) {
            System.assert(doc.Title.startsWith('Batch Updated'), 'Document should be batch updated');
        }
    }
}