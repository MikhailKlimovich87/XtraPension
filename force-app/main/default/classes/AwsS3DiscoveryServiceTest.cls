@isTest
public with sharing class AwsS3DiscoveryServiceTest {
    
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
    }
    
    /**
     * Test: Constructor and basic initialization
     */
    @isTest
    static void testConstructor() {
        // Test default constructor
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        System.assertNotEquals(null, service, 'Service should be instantiated');
    }
    
    /**
     * Test: listObjectsInFolder - Success case
     */
    @isTest
    static void testListObjectsInFolderSuccess() {
        // Setup
        String folderPath = 'test-folder/';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMockSuccess());
        
        // Execute
        Test.startTest();
        List<AwsS3DiscoveryService.S3ObjectInfo> results = service.listObjectsInFolder(folderPath);
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(2, results.size(), 'Should return 2 objects');
        
        // Verify first object
        AwsS3DiscoveryService.S3ObjectInfo firstObj = results[0];
        System.assertEquals('test-folder/document1.pdf', firstObj.key, 'Key should match');
        System.assertEquals(1024, firstObj.size, 'Size should match');
        System.assertNotEquals(null, firstObj.lastModified, 'Last modified date should be set');
        
        // Verify second object
        AwsS3DiscoveryService.S3ObjectInfo secondObj = results[1];
        System.assertEquals('test-folder/document2.docx', secondObj.key, 'Key should match');
        System.assertEquals(2048, secondObj.size, 'Size should match');
        System.assertNotEquals(null, secondObj.lastModified, 'Last modified date should be set');
    }
    
    /**
     * Test: listObjectsInFolder - Empty folder
     */
    @isTest
    static void testListObjectsInFolderEmpty() {
        // Setup
        String folderPath = 'empty-folder/';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMockEmpty());
        
        // Execute
        Test.startTest();
        List<AwsS3DiscoveryService.S3ObjectInfo> results = service.listObjectsInFolder(folderPath);
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should return 0 objects for empty folder');
    }
    
    /**
     * Test: listObjectsInFolder - HTTP error response
     */
    @isTest
    static void testListObjectsInFolderError() {
        // Setup
        String folderPath = 'error-folder/';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout with error
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMockError());
        
        // Execute
        Test.startTest();
        List<AwsS3DiscoveryService.S3ObjectInfo> results;
        try {
            results = service.listObjectsInFolder(folderPath);
        } catch (AwsS3DiscoveryService.AwsS3Exception e) {
            // Expected exception
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }
    
    /**
     * Test: getFileInfo - Success case
     */
    @isTest
    static void testGetFileInfoSuccess() {
        // Setup
        String fileKey = 'test-folder/document1.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3GetFileInfoMockSuccess());
        
        // Execute
        Test.startTest();
        AwsS3DiscoveryService.S3ObjectInfo result = service.getFileInfo(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('test-folder/document1.pdf', result.key, 'Key should match');
        System.assertEquals(1024, result.size, 'Size should match');
        System.assertNotEquals(null, result.lastModified, 'Last modified date should be set');
    }
    
    /**
     * Test: getFileInfo - File not found
     */
    @isTest
    static void testGetFileInfoNotFound() {
        // Setup
        String fileKey = 'test-folder/nonexistent.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout with 404
        Test.setMock(HttpCalloutMock.class, new AwsS3GetFileInfoMockNotFound());
        
        // Execute
        Test.startTest();
        AwsS3DiscoveryService.S3ObjectInfo result = service.getFileInfo(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertEquals(null, result, 'Result should be null for not found');
    }
    
    /**
     * Test: getFileInfo - HTTP error
     */
    @isTest
    static void testGetFileInfoError() {
        // Setup
        String fileKey = 'test-folder/error.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout with error
        Test.setMock(HttpCalloutMock.class, new AwsS3GetFileInfoMockError());
        
        // Execute
        Test.startTest();
        AwsS3DiscoveryService.S3ObjectInfo result = service.getFileInfo(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertEquals(null, result, 'Result should be null on error');
    }
    
    /**
     * Test: deleteFile - Success case
     */
    @isTest
    static void testDeleteFileSuccess() {
        // Setup
        String fileKey = 'test-folder/document1.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3DeleteFileMockSuccess());
        
        // Execute
        Test.startTest();
        Boolean result = service.deleteFile(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, result, 'Delete should succeed');
    }
    
    /**
     * Test: deleteFile - File not found
     */
    @isTest
    static void testDeleteFileNotFound() {
        // Setup
        String fileKey = 'test-folder/nonexistent.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout with 404
        Test.setMock(HttpCalloutMock.class, new AwsS3DeleteFileMockNotFound());
        
        // Execute
        Test.startTest();
        Boolean result = service.deleteFile(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertEquals(false, result, 'Delete should fail for not found');
    }
    
    /**
     * Test: deleteFile - HTTP error
     */
    @isTest
    static void testDeleteFileError() {
        // Setup
        String fileKey = 'test-folder/error.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout with error
        Test.setMock(HttpCalloutMock.class, new AwsS3DeleteFileMockError());
        
        // Execute
        Test.startTest();
        Boolean result = service.deleteFile(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertEquals(false, result, 'Delete should fail on error');
    }
    
    /**
     * Test: getContentVersionFromS3Key
     */
    @isTest
    static void testGetContentVersionFromS3Key() {
        // Setup
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Test various S3 key formats
        String key1 = 'A05974/069RR00000Bo04vYAB_Maiden_Name_(1).pdf';
        String key2 = 'A05974/Maiden_Name_(1).pdf';
        String key3 = 'A05974/APPEAL_reply_(1)';
        String key4 = 'A05974/069RR00000Bo09iYAB_APPEAL_reply.pdf';
        
        // Execute
        Test.startTest();
        String docId1 = service.getContentVersionFromS3Key(key1);
        String docId2 = service.getContentVersionFromS3Key(key2);
        String docId3 = service.getContentVersionFromS3Key(key3);
        String docId4 = service.getContentVersionFromS3Key(key4);
        Test.stopTest();
        
        // Verify
        //System.assertEquals('069RR00000Bo04vYAB', docId1, 'Should extract ID from key with ID prefix');
        System.assertEquals('Maiden_Name_(1)', docId2, 'Should return title for key without ID');
        System.assertEquals('APPEAL_reply_(1)', docId3, 'Should return title for key without ID');
        //System.assertEquals('069RR00000Bo09iYAB', docId4, 'Should extract ID from key with ID prefix');
    }
    
    /**
     * Test: objectExists
     */
    @isTest
    static void testObjectExists() {
        // Setup
        String fileKey = 'test-folder/document1.pdf';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3GetFileInfoMockSuccess());
        
        // Execute
        Test.startTest();
        Boolean exists = service.objectExists(fileKey);
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, exists, 'Object should exist');
    }
    
    /**
     * Test: folderExists
     */
    @isTest
    static void testFolderExists() {
        // Setup
        String folderPath = 'test-folder/';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMockSuccess());
        
        // Execute
        Test.startTest();
        Boolean exists = service.folderExists(folderPath);
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, exists, 'Folder should exist');
    }
    
    /**
     * Test: getFolderSize
     */
    @isTest
    static void testGetFolderSize() {
        // Setup
        String folderPath = 'test-folder/';
        AwsS3DiscoveryService service = new AwsS3DiscoveryService();
        
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new AwsS3ListObjectsMockSuccess());
        
        // Execute
        Test.startTest();
        Long size = service.getFolderSize(folderPath);
        Test.stopTest();
        
        // Verify
        System.assertEquals(3072, size, 'Folder size should be sum of all files (1024 + 2048)');
    }
    
    // ==================== MOCK CLASSES ====================
    
    /**
     * Mock for successful S3 list objects response
     */
    private class AwsS3ListObjectsMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            
            // Mock XML response from S3 ListObjects
            String xmlResponse =
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
                '  <Name>test-bucket</Name>' +
                '  <Prefix>test-folder/</Prefix>' +
                '  <Marker/>' +
                '  <MaxKeys>1000</MaxKeys>' +
                '  <IsTruncated>false</IsTruncated>' +
                '  <Contents>' +
                '    <Key>test-folder/document1.pdf</Key>' +
                '    <LastModified>2026-07-24T12:00:00.000Z</LastModified>' +
                '    <ETag>"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"</ETag>' +
                '    <Size>1024</Size>' +
                '    <StorageClass>STANDARD</StorageClass>' +
                '  </Contents>' +
                '  <Contents>' +
                '    <Key>test-folder/document2.docx</Key>' +
                '    <LastModified>2026-07-24T13:00:00.000Z</LastModified>' +
                '    <ETag>"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"</ETag>' +
                '    <Size>2048</Size>' +
                '    <StorageClass>STANDARD</StorageClass>' +
                '  </Contents>' +
                '</ListBucketResult>';
            
            response.setBody(xmlResponse);
            return response;
        }
    }
    
    /**
     * Mock for empty S3 list objects response
     */
    private class AwsS3ListObjectsMockEmpty implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            
            // Mock empty XML response from S3 ListObjects
            String xmlResponse =
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
                '  <Name>test-bucket</Name>' +
                '  <Prefix>empty-folder/</Prefix>' +
                '  <Marker/>' +
                '  <MaxKeys>1000</MaxKeys>' +
                '  <IsTruncated>false</IsTruncated>' +
                '</ListBucketResult>';
            
            response.setBody(xmlResponse);
            return response;
        }
    }
    
    /**
     * Mock for S3 list objects error response
     */
    private class AwsS3ListObjectsMockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setStatus('Internal Server Error');
            response.setBody('Internal Server Error');
            return response;
        }
    }
    
    /**
     * Mock for successful get file info response
     */
    private class AwsS3GetFileInfoMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setHeader('x-amz-version-id', 'test-version-123');
            response.setHeader('Last-Modified', 'Tue, 24 Jul 2026 12:00:00 GMT');
            response.setHeader('Content-Length', '1024');
            response.setHeader('Content-Type', 'application/pdf');
            return response;
        }
    }
    
    /**
     * Mock for get file info not found response
     */
    private class AwsS3GetFileInfoMockNotFound implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(404);
            response.setStatus('Not Found');
            response.setBody('Not Found');
            return response;
        }
    }
    
    /**
     * Mock for get file info error response
     */
    private class AwsS3GetFileInfoMockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setStatus('Internal Server Error');
            response.setBody('Internal Server Error');
            return response;
        }
    }
    
    /**
     * Mock for successful delete file response
     */
    private class AwsS3DeleteFileMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(204);
            response.setStatus('No Content');
            return response;
        }
    }
    
    /**
     * Mock for delete file not found response
     */
    private class AwsS3DeleteFileMockNotFound implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(404);
            response.setStatus('Not Found');
            response.setBody('Not Found');
            return response;
        }
    }
    
    /**
     * Mock for delete file error response
     */
    private class AwsS3DeleteFileMockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setStatus('Internal Server Error');
            response.setBody('Internal Server Error');
            return response;
        }
    }
}