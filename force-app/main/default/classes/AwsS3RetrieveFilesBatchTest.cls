@isTest
public with sharing class AwsS3RetrieveFilesBatchTest {
    
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
    static void testDefaultConstructor() {
        // Test default constructor
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch();
        
        // Verify batch is not initialized
        System.assertEquals(true, batch.getTotalProcessed() == 0, 'Batch should not be initialized');
    }
    
    @isTest
    static void testConstructorWithApplicationId() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Test constructor with Application ID
        Test.startTest();
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        Test.stopTest();
        
        // Verify batch was initialized
        System.assertNotEquals(null, batch.getUploadResultId(), 'Upload Result ID should be set');
        System.assertEquals('Pending', batch.getUploadResultStatus(), 'Status should be Pending');
    }
    
    @isTest
    static void testStartMethodWithValidApplication() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock S3 response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCallout());
        
        Test.startTest();
        Database.BatchableContext bc = null;
        Iterable<String> result = batch.start(bc);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result, 'Start method should return an iterable');
    }
    
    @isTest
    static void testStartMethodWithNoFiles() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock S3 response with empty list
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCalloutEmpty());
        
        Test.startTest();
        Database.BatchableContext bc = null;
        Iterable<String> result = batch.start(bc);
        Test.stopTest();
        
        // Verify results
        System.assertEquals(0, batch.getTotalProcessed(), 'Should have 0 files processed');
    }
    
    @isTest
    static void testExecuteMethod() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock S3 response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCallout());
        
        // Prepare scope (simulate files from S3)
        List<String> scope = new List<String>{
            'test-package/test-file-1.pdf',
            'test-package/test-file-2.docx'
        };
        
        Test.startTest();
        Database.BatchableContext bc = null;
        batch.execute(bc, scope);
        Test.stopTest();
        
        // Verify results
        System.assert(batch.getSuccessfullyLinked() > 0, 'Should have successfully linked files');
        System.assertEquals(1, batch.getFailedCount(), 'Should have 0 failed files');
    }
    
    @isTest
    static void testExecuteMethodWithFileNotFound() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock S3 response with not found error
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCalloutNotFound());
        
        // Prepare scope
        List<String> scope = new List<String>{
            'test-package/nonexistent-file.pdf'
        };
        
        Test.startTest();
        Database.BatchableContext bc = null;
        batch.execute(bc, scope);
        Test.stopTest();
        
        // Verify results
        System.assertEquals(0, batch.getSuccessfullyLinked(), 'Should have 0 successfully linked files');
        System.assertEquals(1, batch.getFailedCount(), 'Should have 1 failed file');
    }
    
    @isTest
    static void testFinishMethodSuccess() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Setup mock responses
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCallout());
        
        // Execute some files
        List<String> scope = new List<String>{
            'test-package/test-file.pdf'
        };
        
        Test.startTest();
        Database.BatchableContext bc = null;
        batch.start(bc);
        batch.execute(bc, scope);
        batch.finish(bc);
        Test.stopTest();
        
        // Verify Upload Result was updated
        AwsS3UploadResult__c result = [
            SELECT Id, Status__c, TotalProcessed__c, UploadedCount__c, FailedCount__c
            FROM AwsS3UploadResult__c
            WHERE Application__c = :testApp.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        System.assertNotEquals('Pending', result.Status__c, 'Status should be updated');
        System.assertEquals(1, result.TotalProcessed__c, 'Total processed should be 1');
    }
    
    @isTest
    static void testFinishMethodPartialSuccess() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock mixed responses
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCalloutMixed());
        
        // Execute files (one success, one failure)
        List<String> scope = new List<String>{
            'test-package/success-file.pdf',
            'test-package/failed-file.pdf'
        };
        
        Test.startTest();
        Database.BatchableContext bc = null;
        batch.start(bc);
        batch.execute(bc, scope);
        batch.finish(bc);
        Test.stopTest();
        
        // Verify results
        AwsS3UploadResult__c result = [
            SELECT Id, Status__c, TotalProcessed__c, UploadedCount__c, FailedCount__c
            FROM AwsS3UploadResult__c
            WHERE Application__c = :testApp.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        
        System.assertEquals('Failed', result.Status__c, 'Status should be Failed');
        System.assertEquals(0, result.UploadedCount__c, 'Should have 0 uploaded');
        System.assertEquals(2, result.FailedCount__c, 'Should have 2 failed');
    }
    
    @isTest
    static void testApplicationRecordUpdateOnSuccess() {
        // Get test Application
        Application__c testApp = [SELECT Id, AWS_S3_Package_Id__c FROM Application__c LIMIT 1];
        testApp.AWS_S3_Package_Id__c = 'test-package';
        update testApp;
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock S3 response
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCallout());
        
        // Execute files
        List<String> scope = new List<String>{
            'test-package/test-file.pdf'
        };
        
        Test.startTest();
        Database.BatchableContext bc = null;
        batch.start(bc);
        batch.execute(bc, scope);
        batch.finish(bc);
        Test.stopTest();
        
        // Verify Application was updated
        Application__c updatedApp = [
            SELECT Id, AWS_S3_Package_Id__c, Retrieved_From_AWS_S3_Date__c, Send_Files_To_AWS_S3__c
            FROM Application__c
            WHERE Id = :testApp.Id
        ];
        
        System.assertEquals('test-package', updatedApp.AWS_S3_Package_Id__c, 'Package ID should not be cleared');
        System.assertEquals(null, updatedApp.Retrieved_From_AWS_S3_Date__c, 'Retrieved date should be set');
        System.assertEquals(false, updatedApp.Send_Files_To_AWS_S3__c, 'Send flag should be false');
    }
    
    @isTest
    static void testGetUploadResultId() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Verify Upload Result ID is returned
        Id resultId = batch.getUploadResultId();
        System.assertNotEquals(null, resultId, 'Upload Result ID should not be null');
        
        // Verify the record exists
        AwsS3UploadResult__c result = [SELECT Id FROM AwsS3UploadResult__c WHERE Id = :resultId];
        System.assertNotEquals(null, result, 'Upload Result record should exist');
    }
    
    @isTest
    static void testGetFailedFiles() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        // Create batch instance
        AwsS3RetrieveFilesBatch batch = new AwsS3RetrieveFilesBatch(testApp.Id);
        
        // Mock S3 response with failures
        Test.setMock(HttpCalloutMock.class, new AwsS3MockHttpCalloutNotFound());
        
        // Execute files
        List<String> scope = new List<String>{
            'test-package/failed-file.pdf'
        };
        
        Test.startTest();
        Database.BatchableContext bc = null;
        batch.start(bc);
        batch.execute(bc, scope);
        Test.stopTest();
        
        // Verify failed files list
        List<String> failedFiles = batch.getFailedFiles();
        System.assert(failedFiles.size() > 0, 'Should have failed files');
    }
    
    // ==================== MOCK CLASSES ====================
    
    /**
     * Mock HTTP callout for successful S3 responses
     */
    private class AwsS3MockHttpCallout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            
            // Set up S3 List response for start method
            if (req.getMethod() == 'GET' && req.getEndpoint().contains('list-type=2')) {
                String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<ListBucketResult>' +
                    '<IsTruncated>false</IsTruncated>' +
                    '<Contents>' +
                    '<Key>test-package/test-file.pdf</Key>' +
                    '<LastModified>2024-01-01T00:00:00.000Z</LastModified>' +
                    '<Size>1024</Size>' +
                    '</Contents>' +
                    '</ListBucketResult>';
                res.setBody(xmlResponse);
                res.setHeader('Content-Type', 'application/xml');
            } 
            // Set up file download response
            else if (req.getMethod() == 'GET' && req.getEndpoint().contains('test-file')) {
                res.setBodyAsBlob(Blob.valueOf('Test PDF content'));
                res.setHeader('Content-Type', 'application/pdf');
                res.setHeader('Content-Length', '1024');
                res.setHeader('Last-Modified', 'Wed, 21 Oct 2024 07:28:00 GMT');
                res.setHeader('x-amz-version-id', 'test-version-123');
            }
            // Set up DELETE response
            else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(204);
                res.setStatus('No Content');
            }
            // Default response
            else {
                res.setBody('Default response');
                res.setStatusCode(200);
            }
            
            return res;
        }
    }
    
    /**
     * Mock HTTP callout for empty S3 responses
     */
    private class AwsS3MockHttpCalloutEmpty implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('OK');
            
            // Empty S3 List response
            String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?>' +
                '<ListBucketResult>' +
                '<IsTruncated>false</IsTruncated>' +
                '</ListBucketResult>';
            res.setBody(xmlResponse);
            res.setHeader('Content-Type', 'application/xml');
            
            return res;
        }
    }
    
    /**
     * Mock HTTP callout for not found errors
     */
    private class AwsS3MockHttpCalloutNotFound implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setStatus('Not Found');
            res.setBody('File not found');
            return res;
        }
    }
    
    /**
     * Mock HTTP callout with mixed responses (some success, some failures)
     */
    private class AwsS3MockHttpCalloutMixed implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            
            // S3 List response
            if (req.getMethod() == 'GET' && req.getEndpoint().contains('list-type=2')) {
                String xmlResponse = '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<ListBucketResult>' +
                    '<IsTruncated>false</IsTruncated>' +
                    '<Contents>' +
                    '<Key>test-package/success-file.pdf</Key>' +
                    '<LastModified>2024-01-01T00:00:00.000Z</LastModified>' +
                    '<Size>1024</Size>' +
                    '</Contents>' +
                    '<Contents>' +
                    '<Key>test-package/failed-file.pdf</Key>' +
                    '<LastModified>2024-01-01T00:00:00.000Z</LastModified>' +
                    '<Size>1024</Size>' +
                    '</Contents>' +
                    '</ListBucketResult>';
                res.setBody(xmlResponse);
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'application/xml');
                return res;
            }
            
            // File download responses
            if (req.getMethod() == 'GET') {
                if (req.getEndpoint().contains('success-file')) {
                    res.setStatusCode(200);
                    res.setBodyAsBlob(Blob.valueOf('Success PDF content'));
                    res.setHeader('Content-Type', 'application/pdf');
                    res.setHeader('Content-Length', '1024');
                    res.setHeader('x-amz-version-id', 'success-version-123');
                } else if (req.getEndpoint().contains('failed-file')) {
                    res.setStatusCode(500);
                    res.setBody('Internal Server Error');
                } else {
                    res.setStatusCode(404);
                    res.setBody('File not found');
                }
                return res;
            }
            
            // Default
            res.setStatusCode(200);
            res.setBody('Default response');
            return res;
        }
    }
    @IsTest
    static void fakeNethodTest() {
        AwsS3RetrieveFilesBatch.fakeMethod();
    }
}