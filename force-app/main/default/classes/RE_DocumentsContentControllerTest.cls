@isTest
public with sharing class RE_DocumentsContentControllerTest {
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
    static void testGetContentDocuments_WithCF083Completed() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create ContentVersion and ContentDocumentLink for CF083 completed
        ContentVersion cv = createContentVersion('Test_CF083_completed.pdf');
        List<ContentVersion> insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        createContentDocumentLink(insertedCV[0].ContentDocumentId, testReapply.Id);

        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(testReapply.Id);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.latestDocs.size());
        System.assertEquals('CF083', result.latestDocs[0].title);
        System.assertEquals('Completed', result.latestDocs[0].typeGroup);
        System.assertEquals('Completed', result.latestDocs[0].redoGroup);
        System.assertEquals(1, result.latestDocs[0].order);
        System.assertEquals(true, result.latestDocs[0].isAgentAuthorisation);
        System.assertNotEquals(null, result.latestDocs[0].createdDate);
    }

    @isTest
    static void testGetContentDocuments_WithRVNCompleted() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create ContentVersion and ContentDocumentLink for RVN completed
        ContentVersion cv = createContentVersion('Test_RVN_completed.pdf');
        List<ContentVersion> insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        createContentDocumentLink(insertedCV[0].ContentDocumentId, testReapply.Id);
        
        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(testReapply.Id);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.latestDocs.size());
        System.assertEquals('RVN', result.latestDocs[0].title);
        System.assertEquals('Completed', result.latestDocs[0].typeGroup);
        System.assertEquals('Completed', result.latestDocs[0].redoGroup);
        System.assertEquals(1, result.latestDocs[0].order);
        System.assertEquals(true, result.latestDocs[0].isAgentAuthorisation);
    }

    @isTest
    static void testGetContentDocuments_WithCF083Reapply() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create ContentVersion and ContentDocumentLink for CF083 (not completed)
        ContentVersion cv = createContentVersion('Test_CF083.pdf');
        List<ContentVersion> insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        createContentDocumentLink(insertedCV[0].ContentDocumentId, testReapply.Id);
        
        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(testReapply.Id);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.latestDocs.size());
        System.assertEquals('CF083', result.latestDocs[0].title);
        System.assertEquals('Reapply', result.latestDocs[0].typeGroup);
        System.assertEquals('Reapply', result.latestDocs[0].redoGroup);
        System.assertEquals(1, result.latestDocs[0].order);
    }

    @isTest
    static void testGetContentDocuments_WithRVNReapply() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create ContentVersion and ContentDocumentLink for RVN (not completed)
        ContentVersion cv = createContentVersion('Test_RVN.pdf');
        List<ContentVersion> insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        createContentDocumentLink(insertedCV[0].ContentDocumentId, testReapply.Id);
        
        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(testReapply.Id);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.latestDocs.size());
        System.assertEquals('RVN', result.latestDocs[0].title);
        System.assertEquals('Reapply', result.latestDocs[0].typeGroup);
        System.assertEquals('Reapply', result.latestDocs[0].redoGroup);
        System.assertEquals(1, result.latestDocs[0].order);
    }

    // @isTest
    // static void testGetContentDocuments_WithMultipleDocuments() {
    //     // Get the test reapply record
    //     Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
    //     // Create multiple ContentVersions
    //     ContentVersion cv1 = createContentVersion('Test_CF083_completed.pdf');
    //     ContentVersion cv2 = createContentVersion('Test_RVN_completed.pdf');
    //     ContentVersion cv3 = createContentVersion('Test_CF083.pdf');
        
    //     // Link all documents to the reapply record
    //     createContentDocumentLink(cv1.ContentDocumentId, testReapply.Id);
    //     createContentDocumentLink(cv2.ContentDocumentId, testReapply.Id);
    //     createContentDocumentLink(cv3.ContentDocumentId, testReapply.Id);
        
    //     Test.startTest();
    //     RE_DocumentsContentController.DocumentsData result = 
    //         RE_DocumentsContentController.getContentDocuments(testReapply.Id);
    //     Test.stopTest();
        
    //     // Verify results
    //     System.assertNotEquals(null, result);
    //     System.assertEquals(3, result.latestDocs.size());
        
    //     // Verify sorting by order
    //     for (RE_DocumentsContentController.DocumentInfo doc : result.latestDocs) {
    //         System.assertEquals(1, doc.order);
    //     }
    // }

    @isTest
    static void testGetContentDocuments_NoDocuments() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Delete any existing ContentDocumentLinks
        List<ContentDocumentLink> existingLinks = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        if (!existingLinks.isEmpty()) {
            delete existingLinks;
        }
        
        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(testReapply.Id);
        Test.stopTest();
        
        // Verify results
        System.assertEquals(null, result);
    }

    @isTest
    static void testGetContentDocuments_WithUnrelatedDocument() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create ContentVersion with unrelated title
        ContentVersion cv = createContentVersion('Test_Unrelated_Document.pdf');
        List<ContentVersion> insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        createContentDocumentLink(insertedCV[0].ContentDocumentId, testReapply.Id);
        
        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(testReapply.Id);
        Test.stopTest();
        
        // Verify results - document should be included but with empty title
        System.assertNotEquals(null, result);
        System.assertEquals(1, result.latestDocs.size());
        System.assertEquals('', result.latestDocs[0].title);
        System.assertEquals(null, result.latestDocs[0].typeGroup);
        System.assertEquals(null, result.latestDocs[0].redoGroup);
    }

    // @isTest
    // static void testGetContentDocuments_WithNullRecordId() {
    //     Test.startTest();
    //     RE_DocumentsContentController.DocumentsData result = 
    //         RE_DocumentsContentController.getContentDocuments(null);
    //     Test.stopTest();
        
    //     // Verify results
    //     System.assertEquals(null, result);
    // }

    @isTest
    static void testGetContentDocuments_WithInvalidRecordId() {
        // Create an invalid ID
        Id invalidId = Id.valueOf('a0B000000000001');
        
        Test.startTest();
        RE_DocumentsContentController.DocumentsData result = 
            RE_DocumentsContentController.getContentDocuments(invalidId);
        Test.stopTest();
        
        // Verify results
        System.assertEquals(null, result);
    }

    @isTest
    static void testDocumentInfoCompareTo() {
        // Create DocumentInfo objects
        RE_DocumentsContentController.DocumentInfo doc1 = new RE_DocumentsContentController.DocumentInfo();
        doc1.order = 1;
        
        RE_DocumentsContentController.DocumentInfo doc2 = new RE_DocumentsContentController.DocumentInfo();
        doc2.order = 2;
        
        RE_DocumentsContentController.DocumentInfo doc3 = new RE_DocumentsContentController.DocumentInfo();
        doc3.order = 1;
        
        // Test compareTo
        System.assertEquals(-1, doc1.compareTo(doc2));
        System.assertEquals(1, doc2.compareTo(doc1));
        System.assertEquals(0, doc1.compareTo(doc3));
    }

    // Helper methods
    private static ContentVersion createContentVersion(String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title,
            VersionData = Blob.valueOf('Test PDF Content'),
            IsMajorVersion = true
        );
        insert cv;
        return cv;
    }

    private static void createContentDocumentLink(Id contentDocumentId, Id linkedEntityId) {
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V'
        );
        insert cdl;
    }
}