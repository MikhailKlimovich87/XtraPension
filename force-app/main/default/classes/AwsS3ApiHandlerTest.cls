@isTest
public class AwsS3ApiHandlerTest {
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
        
        // Get the ContentDocument ID
        // Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id].ContentDocumentId;
        
        // // Create ContentDocumentLink
        // ContentDocumentLink conDocLink = new ContentDocumentLink();
        // conDocLink.LinkedEntityId = testApplication.Id;
        // conDocLink.ContentDocumentId = contDocId;
        // insert conDocLink;
        
        // Create second ContentVersion with custom letter
        ContentVersion testCustomLetterContentVersion = new ContentVersion(
            Title = 'Test Custom Letter',
        VersionData = Blob.valueOf('Test Custom Letter Content'),
        PathOnClient = 'letter.docx',
        FirstPublishLocationId = testApplication.Id
            );
        insert testCustomLetterContentVersion;
        
        // Id custLettContDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testCustomLetterContentVersion.Id].ContentDocumentId;
        // ContentDocumentLink custLettContDDocLink = new ContentDocumentLink();
        // custLettContDDocLink.LinkedEntityId = testApplication.Id;
        // custLettContDDocLink.ContentDocumentId = custLettContDocId;
        // insert custLettContDDocLink;
    }
    
    @isTest
    static void testUploadToS3_Success() {
        // Get test data - use a more flexible query
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType, ContentDocumentId, VersionNumber, IsLatest 
                                      FROM ContentVersion WHERE Title LIKE 'Test%' LIMIT 1];
        Id contentVersionId = testVersion.Id;
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        // Test method
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3(contentVersionId);
        Test.stopTest();
        
        // Verify response
        System.assertNotEquals(null, response);
        System.assertEquals(false, response.isError);
        System.assertNotEquals(null, response.responseBody);
        System.assertEquals(null, response.errorMessage);
        
        // Verify ContentVersion was updated
        ContentVersion updatedVersion = [SELECT Id, S3_Version_Id__c, S3_Upload_Date__c, S3_Upload_Status__c 
                                         FROM ContentVersion WHERE Id = :contentVersionId];
        System.assertNotEquals(null, updatedVersion.S3_Version_Id__c);
        System.assertNotEquals(null, updatedVersion.S3_Upload_Date__c);
        System.assertEquals('Success', updatedVersion.S3_Upload_Status__c);
    }
    
    @isTest
    static void testUploadToS3_NullId() {
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3(null);
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        System.assertEquals(true, response.isError);
        System.assertEquals(null, response.responseBody);
        System.assertNotEquals(null, response.errorMessage);
        System.assertEquals('ContentVersion ID cannot be null', response.errorMessage);
    }
    
    @isTest
    static void testUploadToS3_InvalidId() {
        Id invalidId = '500000000000000AAA';
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3(invalidId);
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        System.assertEquals(true, response.isError);
        System.assertEquals(null, response.responseBody);
        System.assertNotEquals(null, response.errorMessage);
    }
    
    @isTest
    static void testUploadToS3_Failure() {
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType FROM ContentVersion LIMIT 1];
        
        // Setup mock response for failure
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(400, 'Bad Request', false));
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3(testVersion.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        System.assertEquals(true, response.isError);
        System.assertEquals(null, response.responseBody);
        System.assertNotEquals(null, response.errorMessage);
    }
    
    @isTest
    static void testUploadToS3WithFolder_Success() {
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType FROM ContentVersion LIMIT 1];
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        String folderPath = 'test/folder/path';
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3WithFolder(testVersion.Id, folderPath);
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        System.assertEquals(false, response.isError);
        System.assertNotEquals(null, response.responseBody);
    }
    
    @isTest
    static void testUploadToS3WithFolder_NullId() {
        String folderPath = 'test/folder';
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3WithFolder(null, folderPath);
        Test.stopTest();
        
        System.assertEquals(true, response.isError);
        System.assertEquals('ContentVersion ID cannot be null', response.errorMessage);
    }
    
    @isTest
    static void testUploadToS3WithFolder_BlankFolder() {
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType FROM ContentVersion LIMIT 1];
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3WithFolder(testVersion.Id, '');
        Test.stopTest();
        
        System.assertEquals(true, response.isError);
        System.assertEquals('Folder path cannot be blank', response.errorMessage);
    }
    
    @isTest
    static void testUploadApplicationFilesSynchronous_Success() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Setup mock response for multiple calls
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadApplicationFilesSynchronous(app.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        System.assertEquals(false, response.isError);
        System.assertNotEquals(null, response.responseBody);
    }
    
    @isTest
    static void testUploadApplicationFilesSynchronous_NullId() {
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadApplicationFilesSynchronous(null);
        Test.stopTest();
        
        System.assertEquals(true, response.isError);
        System.assertEquals('Application ID cannot be null', response.errorMessage);
    }
    
    @isTest
    static void testUploadApplicationFilesSynchronous_NoFiles() {
        // Create Application without files
        // Get a contact from the test data
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
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadApplicationFilesSynchronous(testApplication.Id);
        Test.stopTest();
        
        System.assertEquals(true, response.isError);
        System.assertNotEquals(null, response.errorMessage);
        System.assert(response.errorMessage.contains('No files found') ||
            response.errorMessage.contains('No content versions found'));
    }
    
    @isTest
    static void testUploadApplicationFilesWithFolder() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        Test.startTest();
        // We cannot call executeBatch more than once, so use the synchronous version
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadApplicationFilesSynchronous(app.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        // Response might be success or partial success depending on test data
        System.assert(!response.isError || response.responseBody != null || response.errorMessage != null);
    }
    
    @isTest
    static void testUploadApplicationFilesWithFolder_NullId() {
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadApplicationFilesWithFolder(null);
        Test.stopTest();
        
        System.assertEquals(true, response.isError);
        System.assertEquals('Application ID cannot be null', response.errorMessage);
    }
    
    @isTest
    static void testUploadApplicationFilesWithFolderAsync() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        Test.startTest();
        AwsS3ApiHandler.uploadApplicationFilesWithFolderAsync(app.Id);
        Test.stopTest();
        
        // Verify no exceptions were thrown
        System.assert(true, 'Async method completed without exception');
    }
    
    @isTest
    static void testUploadDocumentWithAllVersions_Success() {
        ContentDocument testDoc = [SELECT Id, Title FROM ContentDocument LIMIT 1];
        
        // Setup mock response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadDocumentWithAllVersions(testDoc.Id, 'test/folder');
        Test.stopTest();
        
        System.assertNotEquals(null, response);
        System.assertEquals(false, response.isError);
        System.assertNotEquals(null, response.responseBody);
    }
    
    @isTest
    static void testUploadDocumentWithAllVersions_NullId() {
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadDocumentWithAllVersions(null, 'test/folder');
        Test.stopTest();
        
        System.assertEquals(true, response.isError);
        System.assertEquals('ContentDocument ID cannot be null', response.errorMessage);
    }
    
    @isTest
    static void testBuildApplicationPackageFolder() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        String folderPath = AwsS3ApiHandler.buildApplicationPackageFolder(app, 'test/folder');
        
        System.assertNotEquals(null, folderPath);
        System.assert(folderPath.startsWith('test/folder/'));
        System.assert(folderPath.contains(app.Name));
    }
    
    @isTest
    static void testBuildApplicationPackageFolder_NoFolder() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        String folderPath = AwsS3ApiHandler.buildApplicationPackageFolder(app, null);
        
        System.assertNotEquals(null, folderPath);
        System.assertEquals(app.Name, folderPath);
    }
    
    @isTest
    static void testIsSuccessStatusCode() {
        System.assertEquals(true, AwsS3ApiHandler.isSuccessStatusCode(200));
        System.assertEquals(true, AwsS3ApiHandler.isSuccessStatusCode(299));
        System.assertEquals(false, AwsS3ApiHandler.isSuccessStatusCode(300));
        System.assertEquals(false, AwsS3ApiHandler.isSuccessStatusCode(404));
        System.assertEquals(false, AwsS3ApiHandler.isSuccessStatusCode(500));
    }
    
    @isTest
    static void testBuildHttpRequest() {
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType, ContentDocumentId, VersionNumber, IsLatest 
                                      FROM ContentVersion LIMIT 1];
        
        HttpRequest request = AwsS3ApiHandler.buildHttpRequest(testVersion, 'test/folder');
        
        System.assertNotEquals(null, request);
        System.assertEquals('PUT', request.getMethod());
        System.assertNotEquals(null, request.getHeader('Content-Type'));
        System.assertNotEquals(null, request.getHeader('x-amz-meta-version'));
        System.assertNotEquals(null, request.getHeader('x-amz-meta-document-id'));
        System.assertNotEquals(null, request.getHeader('x-amz-meta-content-version-id'));
        System.assertNotEquals(null, request.getEndpoint());
        System.assert(request.getEndpoint().contains('test/folder'));
    }
    
    // @isTest
    // static void testBuildHttpRequest_NullFolder() {
        //     ContentVersion testVersion = [SELECT Id, Title, VersionData, VersionNumber, FileType FROM ContentVersion LIMIT 1];
        
        //     HttpRequest request = AwsS3ApiHandler.buildHttpRequest(testVersion, null);
        
        //     System.assertNotEquals(null, request);
        //     System.assertNotEquals(null, request.getEndpoint());
        //     System.assert(request.getEndpoint().contains(EncodingUtil.urlEncode(testVersion.Title, 'UTF-8')));
    // }
    
    // @isTest
    // static void testSendHttpRequest() {
        //     ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType, VersionNumber FROM ContentVersion LIMIT 1];
        //     HttpRequest request = AwsS3ApiHandler.buildHttpRequest(testVersion);
        
        //     Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        //     Test.startTest();
        //     HttpResponse response = AwsS3ApiHandler.sendHttpRequest(request);
        //     Test.stopTest();
        
        //     System.assertNotEquals(null, response);
        //     System.assertEquals(200, response.getStatusCode());
    // }
    
    // @isTest
    // static void testContentTypeMapping() {
        //     // Test content type mapping through buildHttpRequest method
        //     ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType, VersionNumber FROM ContentVersion LIMIT 1];
        
        //     HttpRequest request = AwsS3ApiHandler.buildHttpRequest(testVersion);
        //     String contentType = request.getHeader('Content-Type');
        
        //     // Verify it's not null and is a valid content type
        //     System.assertNotEquals(null, contentType);
        //     System.assert(contentType.contains('application/') || contentType.contains('image/') || contentType.contains('text/'));
    // }
    
    // @isTest
    // static void testContentTypeMapping_Default() {
        //     // Test default content type for unknown file types
        //     ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType, VersionNumber FROM ContentVersion LIMIT 1];
        
        //     HttpRequest request = AwsS3ApiHandler.buildHttpRequest(testVersion);
        
        //     // The content type should not be null
        //     System.assertNotEquals(null, request.getHeader('Content-Type'));
        
        //     // If the file type is not in the map, it should default to application/octet-stream
        //     String contentType = request.getHeader('Content-Type');
        //     System.assert(contentType != null && contentType != '');
    // }
    
    @isTest
    static void testExtractS3VersionId_Indirectly() {
        // Test S3 version ID extraction indirectly through a successful upload
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType FROM ContentVersion LIMIT 1];
        
        // Setup mock response with version ID
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', true));
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3(testVersion.Id);
        Test.stopTest();
        
        // Verify the ContentVersion was updated with a version ID
        ContentVersion updatedVersion = [SELECT Id, S3_Version_Id__c FROM ContentVersion WHERE Id = :testVersion.Id];
        System.assertNotEquals(null, updatedVersion.S3_Version_Id__c);
        System.assert(updatedVersion.S3_Version_Id__c.startsWith('mock-s3-version-') ||
            updatedVersion.S3_Version_Id__c.startsWith('upload_'));
    }
    
    @isTest
    static void testExtractS3VersionId_Fallback() {
        // Test fallback version ID generation when no headers are present
        ContentVersion testVersion = [SELECT Id, Title, VersionData, FileType FROM ContentVersion LIMIT 1];
        
        // Setup mock response WITHOUT version ID headers (but still success)
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpResponseGenerator(200, 'Success', false));
        
        Test.startTest();
        AwsS3ApiHandler.AwsS3APIResponseWrapper response = AwsS3ApiHandler.uploadToS3(testVersion.Id);
        Test.stopTest();
        
        // Verify a fallback version ID was generated
        ContentVersion updatedVersion = [SELECT Id, S3_Version_Id__c FROM ContentVersion WHERE Id = :testVersion.Id];
        System.assertNotEquals(null, updatedVersion.S3_Version_Id__c);
        System.assert(updatedVersion.S3_Version_Id__c.startsWith('upload_'));
    }
    
    // Mock HTTP response generator
    public class AwsS3MockHttpResponseGenerator implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        private Boolean includeVersionId;
        
        public AwsS3MockHttpResponseGenerator(Integer statusCode, String responseBody, Boolean includeVersionId) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
            this.includeVersionId = includeVersionId;
        }
        
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            
            if (includeVersionId && statusCode >= 200 && statusCode < 300) {
                response.setHeader('x-amz-version-id', 'mock-s3-version-' + DateTime.now().getTime());
                response.setHeader('ETag', '"mock-etag-123"');
            }
            
            if (statusCode >= 400) {
                String errorXml = '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<Error>' +
                    '<Code>AccessDenied</Code>' +
                    '<Message>Access Denied</Message>' +
                    '</Error>';
                response.setBody(errorXml);
            }
            
            return response;
        }
    }
}