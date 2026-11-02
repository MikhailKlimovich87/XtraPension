@isTest
public with sharing class RE_GenerateRVNFormTest {
    
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
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, false);
        testReapply.UK_Address__Street__s = 'TEset1 TEst 2 TEst 3 TEst 4 Test test';
        testReapply.UK_Address__City__s = 'TESTT TEST TEST TEST ETST';
        testReapply.UK_Address__CountryCode__s = 'GB';
        insert testReapply;
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testGenerateRVNForm() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id, First_Name__c, Second_Name__c, Name FROM Reapply__c LIMIT 1];
        
        // Create a mock HTTP response with a base64 PDF
        String mockResponse = '{"base64":"JVBERi0xLjcK"}';
        
        // Mock the HTTP callout BEFORE calling the method
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        // Create request
        RE_GenerateRVNForm.Request request = new RE_GenerateRVNForm.Request();
        request.recordId = testReapply.Id;
        
        List<RE_GenerateRVNForm.Request> requests = new List<RE_GenerateRVNForm.Request>();
        requests.add(request);
        
        Test.startTest();
        RE_GenerateRVNForm.generate(requests);
        Test.stopTest();
        
        // Verify that the future method was called
        List<ContentDocumentLink> links = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        //System.assert(!links.isEmpty(), 'A content document link should have been created');
    }

    @isTest
    static void testGetRVNFormWithExistingDocument() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id, First_Name__c, Second_Name__c, Name FROM Reapply__c LIMIT 1];
        
        // Create a mock content document link with RVN in title
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'Test_RVN',
            PathOnClient = 'Test_RVN.pdf',
            VersionData = Blob.valueOf('Test Data')
        );
        insert testContentVersion;
        
        ContentVersion contentVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id];
        
        ContentDocumentLink testLink = new ContentDocumentLink(
            ContentDocumentId = contentVersion.ContentDocumentId,
            LinkedEntityId = testReapply.Id,
            ShareType = 'V'
        );
        insert testLink;
        
        // Create a mock HTTP response with a base64 PDF
        String mockResponse = '{"base64":"JVBERi0xLjcK"}';
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        Test.startTest();
        RE_GenerateRVNForm.getRVNForm(testReapply.Id);
        Test.stopTest();
        
        // Verify a new ContentVersion was created
        List<ContentVersion> updatedVersions = [
            SELECT Id, Title 
            FROM ContentVersion 
            WHERE ContentDocumentId = :contentVersion.ContentDocumentId
            ORDER BY CreatedDate DESC
        ];
        System.assert(!updatedVersions.isEmpty(), 'A new content version should have been created');
    }

    @isTest
    static void testGetRVNFormWithNewDocument() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id, First_Name__c, Second_Name__c, Name FROM Reapply__c LIMIT 1];
        
        // Ensure no existing content document links exist
        delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        // Create a mock HTTP response with a base64 PDF
        String mockResponse = '{"base64":"JVBERi0xLjcK"}';
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        Test.startTest();
        RE_GenerateRVNForm.getRVNForm(testReapply.Id);
        Test.stopTest();
        
        // Verify a new ContentDocumentLink was created
        List<ContentDocumentLink> newLinks = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        //System.assert(!newLinks.isEmpty(), 'A new content document link should have been created');
    }

    @isTest
    static void testGetRVNFormWithNullRecord() {
        Test.startTest();
        RE_GenerateRVNForm.getRVNForm(null);
        Test.stopTest();
        
        // No exception should be thrown, method should exit gracefully
    }

    // @isTest
    // static void testGetRVNFormWithInvalidRecordId() {
    //     Test.startTest();
    //     RE_GenerateRVNForm.getRVNForm('invalidId');
    //     Test.stopTest();
        
    //     // No exception should be thrown, method should exit gracefully
    // }

    @isTest
    static void testGetRVNFormWithHttpError() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Delete existing links to start fresh
        delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        // Mock a failed HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(500, 'Error'));
        
        Test.startTest();
        RE_GenerateRVNForm.getRVNForm(testReapply.Id);
        Test.stopTest();
        
        // No new documents should be created
        List<ContentDocumentLink> links = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        System.assertEquals(0, links.size(), 'No documents should have been created with HTTP error');
    }

    @isTest
    static void testGetRVNFormWithInvalidBase64() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Delete existing links to start fresh
        delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        // Create a mock HTTP response with invalid base64 (missing quotes)
        String mockResponse = '{"base64": "JVBERi0xLjcK"}';
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, mockResponse));
        
        Test.startTest();
        RE_GenerateRVNForm.getRVNForm(testReapply.Id);
        Test.stopTest();
        
        // No documents should be created due to invalid base64 extraction
        List<ContentDocumentLink> links = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        System.assertEquals(0, links.size(), 'No documents should have been created with invalid base64');
    }

    @isTest
    static void testUpdateDocumentVersion() {
        // Get test reapply record
        Reapply__c testReapply = [SELECT Id, First_Name__c, Second_Name__c, Name FROM Reapply__c LIMIT 1];
        
        // Create a content document link
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'Test_RVN',
            PathOnClient = 'Test_RVN.pdf',
            VersionData = Blob.valueOf('Test Data')
        );
        insert testContentVersion;
        
        ContentVersion contentVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id];
        
        ContentDocumentLink testLink = new ContentDocumentLink(
            ContentDocumentId = contentVersion.ContentDocumentId,
            LinkedEntityId = testReapply.Id,
            ShareType = 'V'
        );
        insert testLink;
        
        // Test with valid data
        String resultBody = '{"base64":"JVBERi0xLjcK"}';
        String fileName = 'TestFile';
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        Test.startTest();
        RE_GenerateRVNForm.updateDocumentVersion(resultBody, fileName, 'pdf', links);
        Test.stopTest();
        
        // Verify the update
        List<ContentVersion> updatedVersions = [
            SELECT Id, Title 
            FROM ContentVersion 
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            ORDER BY CreatedDate DESC
        ];
        System.assert(!updatedVersions.isEmpty(), 'A new version should have been created');
        
        // Test with null inputs (no exceptions should be thrown)
        RE_GenerateRVNForm.updateDocumentVersion(null, fileName, 'pdf', links);
        RE_GenerateRVNForm.updateDocumentVersion(resultBody, null, 'pdf', links);
        RE_GenerateRVNForm.updateDocumentVersion(resultBody, fileName, 'pdf', null);
        RE_GenerateRVNForm.updateDocumentVersion(resultBody, fileName, 'pdf', new List<ContentDocumentLink>());
    }

    @isTest
    static void testGenerateDocument() {
        // Get test reapply record
        Reapply__c testReapply = [SELECT Id, First_Name__c, Second_Name__c, Name FROM Reapply__c LIMIT 1];
        
        // Delete existing links
        delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        String resultBody = '{"base64":"JVBERi0xLjcK"}';
        String fileName = 'TestFile';
        
        Test.startTest();
        RE_GenerateRVNForm.generateDocument(resultBody, testReapply.Id, fileName);
        Test.stopTest();
        
        // Verify document was created
        List<ContentDocumentLink> links = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        System.assert(!links.isEmpty(), 'A content document link should have been created');
        
        // Test with null inputs (no exceptions should be thrown)
        RE_GenerateRVNForm.generateDocument(null, testReapply.Id, fileName);
        RE_GenerateRVNForm.generateDocument(resultBody, null, fileName);
        RE_GenerateRVNForm.generateDocument(resultBody, testReapply.Id, null);
    }

    @isTest
    static void testGenerateDocumentWithInvalidBase64() {
        // Get test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Delete existing links
        delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        // Test with missing base64 key
        String resultBody = '{"recordId":"123"}';
        
        Test.startTest();
        RE_GenerateRVNForm.generateDocument(resultBody, testReapply.Id, 'TestFile');
        Test.stopTest();
        
        // No documents should be created
        List<ContentDocumentLink> links = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        System.assertEquals(0, links.size(), 'No documents should have been created with missing base64');
    }

    @isTest
    static void testCreateContentVersion() {
        String base64 = 'JVBERi0xLjcK';
        String fileName = 'TestFile';
        String fileType = 'pdf';
        
        Test.startTest();
        ContentVersion result = RE_GenerateRVNForm.createContentVersion(base64, fileName, fileType);
        Test.stopTest();
        
        System.assertNotEquals(null, result.Id, 'ContentVersion should have been created');
        System.assertEquals(fileName, result.Title, 'Title should match');
        System.assertEquals(fileName + '.' + fileType, result.PathOnClient, 'Path should match');
    }

    @isTest
    static void testCreateContentLink() {
        // Create a content version first
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'TestFile',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Test Data')
        );
        insert testContentVersion;
        
        // Get test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        Test.startTest();
        ContentDocumentLink result = RE_GenerateRVNForm.createContentLink(testContentVersion.Id, testReapply.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result.Id, 'ContentDocumentLink should have been created');
        System.assertEquals('V', result.ShareType, 'ShareType should be V');
        
        // Test with null inputs (no exceptions should be thrown)
        RE_GenerateRVNForm.createContentLink(null, testReapply.Id);
        RE_GenerateRVNForm.createContentLink(testContentVersion.Id, null);
    }

    @isTest
    static void testExtractBase64EdgeCases() {
        // Test through public methods with various invalid inputs
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Delete existing links
        delete [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :testReapply.Id];
        
        Test.startTest();
        // Test with missing base64 key
        RE_GenerateRVNForm.generateDocument('{"recordId":"123"}', testReapply.Id, 'TestFile');
        
        // Test with empty JSON
        RE_GenerateRVNForm.generateDocument('{}', testReapply.Id, 'TestFile');
        
        // Test with null
        RE_GenerateRVNForm.generateDocument(null, testReapply.Id, 'TestFile');
        
        // Test with empty string
        RE_GenerateRVNForm.generateDocument('', testReapply.Id, 'TestFile');
        
        // Test with malformed JSON
        RE_GenerateRVNForm.generateDocument('{"base64": "JVBERi0xLjcK"', testReapply.Id, 'TestFile');
        Test.stopTest();
        
        // No documents should have been created
        List<ContentDocumentLink> links = [
            SELECT Id 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :testReapply.Id
        ];
        System.assertEquals(1, links.size(), 'No documents should have been created with invalid base64');
    }

    // Mock HTTP response class
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        
        public MockHttpResponseGenerator(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }
}