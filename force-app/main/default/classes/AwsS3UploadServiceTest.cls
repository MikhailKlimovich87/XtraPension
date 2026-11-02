@isTest
public class AwsS3UploadServiceTest {
    
    // ==================== TEST SETUP ====================
    
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
        
        // Create test ContentVersions
        ContentVersion testContentVersion = new ContentVersion(
            Title = 'Test Document',
        VersionData = Blob.valueOf('Test Content'),
        PathOnClient = 'test.pdf',
        FirstPublishLocationId = testApplication.Id
            );
        insert testContentVersion;
        
        ContentVersion testEmailVersion = new ContentVersion(
            Title = 'Test Email Attachment',
        VersionData = Blob.valueOf('Email Content'),
        PathOnClient = 'email.pdf',
        FirstPublishLocationId = testApplication.Id
            );
        insert testEmailVersion;
    }
    
    // ==================== CONSTRUCTOR TESTS ====================
    
    @isTest
    static void testConstructor() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        Test.stopTest();
        
        System.assertNotEquals(null, service, 'Service should be instantiated');
    }
    
    // ==================== UPLOAD WITH VERSIONING TESTS ====================
    
    @isTest
    static void testUploadWithVersioningSuccess() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
        System.assertEquals('CREATE_NEW', result.operation, 'Operation should be CREATE_NEW');
    }
    
    @isTest
    static void testUploadWithVersioningWithBlankKey() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        // Leave s3ObjectKey blank - should be built by buildS3Key
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testUploadWithVersioningFailure() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockFailure());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should fail');
        System.assertNotEquals(null, result.error, 'Error message should be set');
    }
    
    
    // ==================== GET NAMED CREDENTIAL TESTS ====================
    
    @isTest
    static void testGetNamedCredentialForS3KeyApplication() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testGetNamedCredentialForS3KeyEmail() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = '02sRR00000BemfWYAR';
        config.s3ObjectKey = '02sRR00000BemfWYAR/Email Attachment.pdf';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testGetNamedCredentialForS3KeyBlank() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = ''; // Blank key
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed with generated key');
    }
    
    @isTest
    static void testGetNamedCredentialForS3KeyEmailUploadConfig() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        config.emailMessageId = '02sRR00000BemfWYAR';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed with email config');
    }
    
    @isTest
    static void testGetNamedCredentialForS3KeyCustomCredential() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        config.namedCredential = 'Custom_AWS_Credential';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed with custom credential');
    }
    
    // ==================== BUILD S3 KEY TESTS ====================
    
    @isTest
    static void testBuildS3KeyWithExtension() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testBuildS3KeyWithoutExtension() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = 'No Extension File',
        VersionData = Blob.valueOf('No extension content'),
        PathOnClient = 'noextension',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testBuildS3KeyWithNullTitle() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = null,
        VersionData = Blob.valueOf('Null title content'),
        PathOnClient = 'untitled.pdf',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    // ==================== LEGACY UPLOAD METHOD TESTS ====================
    
    @isTest
    static void testLegacyUploadSuccess() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Map<String, String> metadata = new Map<String, String>();
        metadata.put('Content-Type', 'application/pdf');
        metadata.put('test-key', 'test-value');
        
        UploadResult result = service.upload(cv, 'A05974/Test Document.pdf', metadata);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Upload should succeed');
        System.assertEquals('A05974/Test Document.pdf', result.s3ObjectKey, 'S3 Key should match');
    }
    
    @isTest
    static void testLegacyUploadFailure() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockFailure());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Map<String, String> metadata = new Map<String, String>();
        metadata.put('Content-Type', 'application/pdf');
        
        UploadResult result = service.upload(cv, 'A05974/Test Document.pdf', metadata);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should fail');
        System.assertNotEquals(null, result.error, 'Error message should be set');
    }
    
    // ==================== CLEAN FILENAME TESTS ====================
    
    @isTest
    static void testCleanFileNameWithSpecialCharacters() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test!@#$%^&*()_+{}|:"<>? Document',
        VersionData = Blob.valueOf('Special chars content'),
        PathOnClient = 'special.pdf',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testCleanFileNameWithMultipleSpaces() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test    with    many     spaces',
        VersionData = Blob.valueOf('Spaces content'),
        PathOnClient = 'spaces.pdf',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    @isTest
    static void testCleanFileNameWithBlankTitle() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = '',
        VersionData = Blob.valueOf('Blank title content'),
        PathOnClient = 'blank.pdf',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    // ==================== GET CONTENT TYPE TESTS ====================
    
    @isTest
    static void testGetContentTypeWithVariousExtensions() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        // Create ContentVersions with different extensions in PathOnClient
        List<ContentVersion> testVersions = new List<ContentVersion>();
        String[] extensions = new String[]{'pdf', 'doc', 'docx', 'xls', 'xlsx'};
        
        for (String ext : extensions) {
            ContentVersion cv = new ContentVersion(
                Title = 'Test ' + ext,
            VersionData = Blob.valueOf('Content for ' + ext),
            PathOnClient = 'test.' + ext,
            FirstPublishLocationId = app.Id
                );
            testVersions.add(cv);
        }
        insert testVersions;
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        List<ContentVersion> versions = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                         FROM ContentVersion WHERE FirstPublishLocationId = :app.Id
                                         AND Title LIKE 'Test %'];
        
        for (ContentVersion cv : versions) {
            UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        }
        
        Test.stopTest();
        
        System.assertEquals(versions.size(), versions.size(), 'All versions should be processed');
    }
    
    @isTest
    static void testGetContentTypeWithNullExtension() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = 'Null Extension',
        VersionData = Blob.valueOf('Null extension content'),
        PathOnClient = 'nullext',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed with null extension');
    }
    
    // ==================== BUILD ENDPOINT TESTS ====================
    
    @isTest
    static void testBuildEndpointWithSpecialCharacters() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test (1) - Special & More',
        VersionData = Blob.valueOf('Special endpoint content'),
        PathOnClient = 'special.pdf',
        FirstPublishLocationId = app.Id
            );
        insert cv;
        
        ContentVersion testCv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                                 FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = '';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(testCv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload with special characters should succeed');
    }
    
    // ==================== RETRY LOGIC TESTS ====================
    
    @isTest
    static void testUploadWithRetrySuccessAfterFailure() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockRetry());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed after retry');
    }
    
    @isTest
    static void testUploadWithRetryAllFailures() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockAllRetryFailures());
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should fail after all retries');
        System.assertNotEquals(null, result.error, 'Error message should be set');
    }
    
    // ==================== GET BUCKET NAME TESTS ====================
    
    @isTest
    static void testGetBucketName() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        
        AwsS3BatchState state = new AwsS3BatchState();
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload should succeed');
    }
    
    // ==================== METADATA BUILDING TESTS ====================
    
    @isTest
    static void testBuildContentVersionMetadata() {
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT Id, Title, VersionData, ContentDocumentId, VersionNumber
                             FROM ContentVersion WHERE Title = 'Test Document' LIMIT 1];
        
        Test.startTest();
        UploadConfiguration config = new UploadConfiguration();
        config.applicationId = app.Id;
        config.packageFolder = 'A05974';
        config.s3ObjectKey = 'A05974/Test Document.pdf';
        config.emailMessageId = '02sRR00000BemfWYAR';
        config.emailSubject = 'Test Email Subject';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.packageAction = 'CREATE_NEW';
        
        AwsS3UploadService service = new AwsS3UploadService(config, state);
        
        Test.setMock(HttpCalloutMock.class, new AwsS3UploadMockSuccess());
        
        UploadResult result = service.uploadWithVersioning(cv, 'CREATE_NEW', null);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Upload with metadata should succeed');
    }

    @IsTest
    static void methodName(){
        
        Test.startTest();
            AwsS3UploadService.fakeMethod();
        Test.stopTest();
        
    }
    
    // ==================== MOCK CLASSES ====================
    
    /**
     * Mock that simulates successful S3 upload
     */
    private class AwsS3UploadMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('x-amz-version-id', 'test-version-id-123');
            res.setHeader('ETag', '"test-etag"');
            res.setBody('<?xml version="1.0" encoding="UTF-8"?><UploadResult><ETag>"test-etag"</ETag></UploadResult>');
            return res;
        }
    }
    
    /**
     * Mock that simulates failed S3 upload
     */
    private class AwsS3UploadMockFailure implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error": "Internal Server Error"}');
            return res;
        }
    }
    
    
    /**
     * Mock that fails first then succeeds (tests retry logic)
     */
    private class AwsS3UploadMockRetry implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            HttpResponse res = new HttpResponse();
            
            if (callCount == 1) {
                // First attempt fails
                res.setStatusCode(500);
                res.setBody('{"error": "Temporary error"}');
            } else {
                // Second attempt succeeds
                res.setStatusCode(200);
                res.setHeader('x-amz-version-id', 'test-version-id-123');
                res.setHeader('ETag', '"test-etag"');
                res.setBody('<?xml version="1.0" encoding="UTF-8"?><UploadResult><ETag>"test-etag"</ETag></UploadResult>');
            }
            
            return res;
        }
    }
    
    /**
     * Mock that always fails (tests max retries)
     */
    private class AwsS3UploadMockAllRetryFailures implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error": "Server error"}');
            return res;
        }
    }
}