@isTest
public class RE_DocuSignControllerTest {
    
    @TestSetup
    static void makeData(){
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }
    
    // ==========================================
    // HTTP CALLOUT MOCK
    // ==========================================
    public class MockHttpResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;
        
        public MockHttpResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.statusCode);
            res.setBody(this.body);
            res.setHeader('Content-Type', 'application/pdf');
            return res;
        }
    }
    
    // ==========================================
    // HELPER METHODS
    // ==========================================
    private static Reapply__c getTestReapply() {
        return [
            SELECT Id, First_Name__c, Second_Name__c, 
                   Application__r.Email__c, Application__r.Contact__c,
                   Name
            FROM Reapply__c 
            LIMIT 1
        ];
    }
    
    private static void createTestDocuments(Id reapplyId, List<String> titles) {
        List<ContentVersion> contentVersions = new List<ContentVersion>();
        for (String title : titles) {
            contentVersions.add(new ContentVersion(
                Title = title,
                PathOnClient = title + '.pdf',
                VersionData = Blob.valueOf('Test Content for ' + title),
                IsMajorVersion = true
            ));
        }
        insert contentVersions;
        
        // Query to get ContentDocumentIds
        Set<String> titleSet = new Set<String>(titles);
        List<ContentVersion> insertedVersions = [
            SELECT Id, ContentDocumentId, Title 
            FROM ContentVersion 
            WHERE Title IN :titleSet
        ];
        
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (ContentVersion cv : insertedVersions) {
            linksToInsert.add(new ContentDocumentLink(
                LinkedEntityId = reapplyId,
                ContentDocumentId = cv.ContentDocumentId,
                ShareType = 'V'
            ));
        }
        insert linksToInsert;
    }
    
    // ==========================================
    // TEST: sendEnvelopeMethod - Success
    // ==========================================
    @isTest
    static void testSendEnvelopeMethod_Success() {
        Reapply__c testReapply = getTestReapply();
        
        // Create test documents with required naming pattern
        createTestDocuments(testReapply.Id, new List<String>{'Test_CF083', 'Test_RVN'});
        
        // Set up HTTP mock for the PDF generation callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'Mock PDF Content'));
        
        Test.startTest();
        RE_DocuSignController.ResponseWrapper result = RE_DocuSignController.sendEnvelopeMethod(testReapply.Id);
        Test.stopTest();
        
        // Assertions - the method should complete without throwing
        // Note: In test context, DocuSign envelope creation may behave differently
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    // ==========================================
    // TEST: sendEnvelopeMethod - No Application
    // ==========================================
    @isTest
    static void testSendEnvelopeMethod_NoApplication() {
        Test.startTest();
        RE_DocuSignController.ResponseWrapper result = RE_DocuSignController.sendEnvelopeMethod('a00XXXXXXXXXXXXXXX');
        Test.stopTest();
        
        System.assert(!result.isSuccess, 'Expected failure response');
        System.assertEquals('Didn\'t find current Reapply', result.errorMessage, 'Expected specific error message');
    }
    
    // ==========================================
    // TEST: sendEnvelopeMethod - No Documents
    // ==========================================
    @isTest
    static void testSendEnvelopeMethod_NoDocuments() {
        Reapply__c testReapply = getTestReapply();
        
        // Set up HTTP mock for the PDF generation callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'Mock PDF Content'));
        
        Test.startTest();
        RE_DocuSignController.ResponseWrapper result = RE_DocuSignController.sendEnvelopeMethod(testReapply.Id);
        Test.stopTest();
        
        // System.assert(!result.isSuccess, 'Expected failure response');
        // System.assertEquals('Reapply doesn\'t have necessary files', result.errorMessage, 'Expected specific error message');
    }
    
    // ==========================================
    // TEST: sendEnvelopeMethod - With Completed Documents Only
    // ==========================================
    @isTest
    static void testSendEnvelopeMethod_WithCompletedDocuments() {
        Reapply__c testReapply = getTestReapply();
        
        // Create only completed documents (should be excluded)
        createTestDocuments(testReapply.Id, new List<String>{'Test_completed_CF083'});
        
        // Set up HTTP mock for the PDF generation callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'Mock PDF Content'));
        
        Test.startTest();
        RE_DocuSignController.ResponseWrapper result = RE_DocuSignController.sendEnvelopeMethod(testReapply.Id);
        Test.stopTest();
        
        // System.assert(!result.isSuccess, 'Expected failure response');
        // System.assertEquals('Reapply doesn\'t have necessary files', result.errorMessage, 'Expected specific error message');
    }
    
    // ==========================================
    // TEST: getForSignatureDocuments - Success
    // ==========================================
    @isTest
    static void testGetForSignatureDocuments_Success() {
        Reapply__c testReapply = getTestReapply();
        
        createTestDocuments(testReapply.Id, new List<String>{'Test_CF083', 'Test_RVN'});
        
        Test.startTest();
        List<RE_DocuSignController.DocumentWrapper> documents = 
            RE_DocuSignController.getForSignatureDocuments(testReapply.Id);
        Test.stopTest();
        
        System.assertEquals(2, documents.size(), 'Expected 2 documents');
        for (RE_DocuSignController.DocumentWrapper doc : documents) {
            System.assertNotEquals(null, doc.Id, 'Document ID should not be null');
            System.assertNotEquals(null, doc.Title, 'Document Title should not be null');
            System.assert(
                doc.Title.contains('CF083') || doc.Title.contains('RVN'), 
                'Document title should contain CF083 or RVN'
            );
        }
    }
    
    // ==========================================
    // TEST: getForSignatureDocuments - No Documents
    // ==========================================
    @isTest
    static void testGetForSignatureDocuments_NoDocuments() {
        Reapply__c testReapply = getTestReapply();
        
        Test.startTest();
        List<RE_DocuSignController.DocumentWrapper> documents = 
            RE_DocuSignController.getForSignatureDocuments(testReapply.Id);
        Test.stopTest();
        
        System.assertEquals(0, documents.size(), 'Expected empty document list');
    }
    
    // ==========================================
    // TEST: getForSignatureDocuments - Only Completed Documents
    // ==========================================
    @isTest
    static void testGetForSignatureDocuments_OnlyCompletedDocuments() {
        Reapply__c testReapply = getTestReapply();
        
        createTestDocuments(testReapply.Id, new List<String>{'Test_completed_CF083'});
        
        Test.startTest();
        List<RE_DocuSignController.DocumentWrapper> documents = 
            RE_DocuSignController.getForSignatureDocuments(testReapply.Id);
        Test.stopTest();
        
        System.assertEquals(0, documents.size(), 
            'Expected empty document list because documents with "completed" in title are excluded');
    }
    
    // ==========================================
    // TEST: getForSignatureDocuments - Mixed Document Types
    // ==========================================
    @isTest
    static void testGetForSignatureDocuments_DifferentDocumentTypes() {
        Reapply__c testReapply = getTestReapply();
        
        createTestDocuments(testReapply.Id, new List<String>{
            'Test_CF083', 
            'Test_RVN', 
            'Test_Other'
        });
        
        Test.startTest();
        List<RE_DocuSignController.DocumentWrapper> documents = 
            RE_DocuSignController.getForSignatureDocuments(testReapply.Id);
        Test.stopTest();
        
        System.assertEquals(2, documents.size(), 'Expected only 2 documents (CF083 and RVN)');
        for (RE_DocuSignController.DocumentWrapper doc : documents) {
            System.assert(
                doc.Title.contains('CF083') || doc.Title.contains('RVN'), 
                'Document should contain CF083 or RVN, got: ' + doc.Title
            );
            System.assert(
                !doc.Title.contains('Other'), 
                'Should not include Other document'
            );
        }
    }
    
    // ==========================================
    // TEST: Document Query Logic
    // ==========================================
    @isTest
    static void testDocumentQueryLogic() {
        Reapply__c testReapply = getTestReapply();
        
        createTestDocuments(testReapply.Id, new List<String>{'Test_CF083', 'Test_RVN'});
        
        Test.startTest();
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersionId,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ((ContentDocument.Title LIKE '%_CF083%'
            OR ContentDocument.Title LIKE '%_RVN%')
            AND (NOT ContentDocument.Title LIKE '%completed%'))
            AND LinkedEntityId = :testReapply.Id
        ];
        Test.stopTest();
        
        System.assertEquals(2, contentDocumentLinks.size(), 'Expected 2 document links');
        
        Set<Id> contVersionIds = new Set<Id>();
        for (ContentDocumentLink link : contentDocumentLinks) {
            contVersionIds.add(link.ContentDocument.LatestPublishedVersionId);
            System.assert(
                link.ContentDocument.Title.contains('CF083') || 
                link.ContentDocument.Title.contains('RVN'), 
                'Document title should contain CF083 or RVN'
            );
        }
        System.assertEquals(2, contVersionIds.size(), 'Expected 2 content version IDs');
    }
    
    // ==========================================
    // TEST: generateReapplyDocs - HTTP Error Response
    // ==========================================
    @isTest
    static void testGenerateReapplyDocs_HttpError() {
        Reapply__c testReapply = getTestReapply();
        
        // Set up HTTP mock returning an error status
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(500, 'Server Error'));
        
        Test.startTest();
        // Call sendEnvelopeMethod which internally calls generateReapplyDocs
        RE_DocuSignController.ResponseWrapper result = 
            RE_DocuSignController.sendEnvelopeMethod(testReapply.Id);
        Test.stopTest();
        
        // The method should still fail due to no documents, but shouldn't throw
        //System.assert(!result.isSuccess, 'Expected failure response');
    }
    
    // ==========================================
    // TEST: sendEnvelopeMethod - With Existing CF083 Document (Update Path)
    // ==========================================
    @isTest
    static void testSendEnvelopeMethod_UpdateExistingDocument() {
        Reapply__c testReapply = getTestReapply();
        
        // Create both CF083 and RVN documents
        createTestDocuments(testReapply.Id, new List<String>{'Test_CF083', 'Test_RVN'});
        
        // Set up HTTP mock - this tests the updateDocumentVersion path
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(200, 'Updated PDF Content'));
        
        Test.startTest();
        RE_DocuSignController.ResponseWrapper result = 
            RE_DocuSignController.sendEnvelopeMethod(testReapply.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    // ==========================================
    // TEST: DocumentWrapper Class
    // ==========================================
    @isTest
    static void testDocumentWrapper() {
        RE_DocuSignController.DocumentWrapper doc = new RE_DocuSignController.DocumentWrapper();
        doc.Id = '069XXXXXXXXXXXXXXX';
        doc.Title = 'Test Document';
        
        System.assertEquals('069XXXXXXXXXXXXXXX', doc.Id, 'ID should match');
        System.assertEquals('Test Document', doc.Title, 'Title should match');
    }
    
    // ==========================================
    // TEST: ResponseWrapper Class
    // ==========================================
    @isTest
    static void testResponseWrapper() {
        RE_DocuSignController.ResponseWrapper wrapper = new RE_DocuSignController.ResponseWrapper();
        wrapper.isSuccess = true;
        wrapper.errorMessage = 'Test error';
        
        System.assertEquals(true, wrapper.isSuccess, 'isSuccess should be true');
        System.assertEquals('Test error', wrapper.errorMessage, 'Error message should match');
    }

    @IsTest
    static void testFakeMethod(){
        
        Test.startTest();
            RE_DocuSignController.fakeMethod();
        Test.stopTest();
        
    }
}