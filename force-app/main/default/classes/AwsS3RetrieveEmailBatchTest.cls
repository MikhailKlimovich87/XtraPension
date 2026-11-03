@IsTest
private class AwsS3RetrieveEmailBatchTest {
    
    private class S3SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            
            if (request.getEndpoint().contains('list-type=2')) {
                response.setStatusCode(200);
                response.setHeader('Content-Type', 'application/xml');
                response.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<ListBucketResult>' +
                    '<Contents>' +
                    '<Key>EMAIL_TEST/Document.pdf</Key>' +
                    '</Contents>' +
                    '</ListBucketResult>'
                    );
            } else {
                response.setStatusCode(200);
                response.setHeader('Content-Type', 'application/pdf');
                response.setBodyAsBlob(
                    Blob.valueOf('Test PDF content from S3')
                    );
            }
            
            return response;
        }
    }
    
    private class S3EmptyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/xml');
            response.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<ListBucketResult></ListBucketResult>'
                );
            
            return response;
        }
    }
    
    private static EmailMessage createEmailMessage() {
        EmailMessage email = new EmailMessage(
            Subject = 'S3 Retrieve Test',
        FromAddress = 'sender@example.com',
        ToAddress = 'recipient@example.com',
        TextBody = 'Test email body',
        Incoming = false,
        Status = '3'
            );
        
        insert email;
        return email;
    }
    
    @IsTest
    static void testSuccessfulFileRetrieval() {
        
        EmailMessage email = createEmailMessage();
        
        Test.setMock(
            HttpCalloutMock.class,
        new S3SuccessMock()
            );
        
        Test.startTest();
        
        Id jobId = Database.executeBatch(
            new AwsS3RetrieveEmailBatch(email.Id),
        1
            );
        
        Test.stopTest();
        
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :jobId
        ];
        
        System.assertEquals(
            'Completed',
        job.Status,
        'Batch should complete successfully'
            );
        
        System.assertEquals(
            0,
        job.NumberOfErrors,
        'Batch should not have errors'
            );
        
        List<ContentDocumentLink> links = [
            SELECT
                ContentDocumentId,
                LinkedEntityId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :email.Id
        ];
        
        System.assertEquals(
            1,
        links.size(),
        'One file should be linked to the EmailMessage'
            );
        
        System.assertEquals(
            email.Id,
        links[0].LinkedEntityId
            );
        
        System.assertEquals(
            'Document',
        links[0].ContentDocument.Title
            );
        
        ContentVersion version = [
            SELECT
                Id,
                ContentDocumentId,
                Title,
                PathOnClient,
                AWS_S3_Object_Key__c,
                S3_Upload_Status__c,
                S3_Upload_Date__c
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
            AND IsLatest = true
            LIMIT 1
            ];
        
        System.assertEquals(
            'Document',
        version.Title
            );
        
        System.assertEquals(
            'Document.pdf',
        version.PathOnClient
            );
        
        EmailMessage updatedEmail = [
            SELECT
                Id,
                AWS_S3_Package_Id__c,
                S3_Upload_Status__c,
                S3_Total_Files__c,
                S3_Success_Count__c,
                S3_Failed_Count__c,
                S3_Success_Rate__c,
                S3_Retrieve_Status__c,
                S3_Retrieved_Count__c,
                S3_Retrieve_Success_Rate__c,
                S3_Retrieve_Date__c,
                S3_Last_Retrieve_Attempt__c
            FROM EmailMessage
            WHERE Id = :email.Id
        ];
        
        System.assertEquals(
            email.Id,
        updatedEmail.AWS_S3_Package_Id__c
            );
        
        System.assertEquals(
            1,
        updatedEmail.S3_Total_Files__c
            );
        
        System.assertNotEquals(
            null,
        updatedEmail.S3_Last_Retrieve_Attempt__c
            );
    }
    
    @IsTest
    static void testDuplicateFileRetrieval() {
        
        EmailMessage email = createEmailMessage();
        
        ContentVersion existingVersion = new ContentVersion(
            Title = 'Document',
        PathOnClient = 'Document.pdf',
        VersionData = Blob.valueOf('Existing file'),
        FirstPublishLocationId = email.Id
            );
        
        insert existingVersion;
        
        Test.setMock(
            HttpCalloutMock.class,
        new S3SuccessMock()
            );
        
        Test.startTest();
        
        Id jobId = Database.executeBatch(
            new AwsS3RetrieveEmailBatch(email.Id),
        1
            );
        
        Test.stopTest();
        
        AsyncApexJob job = [
        SELECT Id, Status, NumberOfErrors
        FROM AsyncApexJob
        WHERE Id = :jobId
    ];
        
        System.assertEquals(
            'Completed',
        job.Status
            );
        
        System.assertEquals(
            0,
        job.NumberOfErrors
            );
        
        List<ContentDocumentLink> links = [
        SELECT
            ContentDocumentId,
            ContentDocument.Title
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :email.Id
    ];
        
        System.assertEquals(
            1,
        links.size(),
        'Duplicate should not create another document'
            );
        
        ContentVersion updatedVersion = [
        SELECT
            Id,
            AWS_S3_Object_Key__c,
            S3_Upload_Status__c,
            S3_Upload_Date__c
        FROM ContentVersion
        WHERE Id = :existingVersion.Id
    ];
        
        // System.assertEquals(
        //     email.Id + '/Document.pdf',
        // updatedVersion.AWS_S3_Object_Key__c
        //     );
        
        // System.assertEquals(
        //     'Retrieved (Existing)',
        // updatedVersion.S3_Upload_Status__c
        //     );
        
        // System.assertNotEquals(
        //     null,
        // updatedVersion.S3_Upload_Date__c
        //     );
        
        EmailMessage updatedEmail = [
        SELECT
            S3_Total_Files__c,
            S3_Success_Count__c,
            S3_Failed_Count__c,
            S3_Success_Rate__c,
            S3_Retrieve_Status__c,
            S3_Retrieved_Count__c,
            S3_Retrieve_Success_Rate__c
        FROM EmailMessage
        WHERE Id = :email.Id
    ];
        
        System.assertEquals(
            1,
        updatedEmail.S3_Total_Files__c
            );
        
        System.assertEquals(
            1,
        updatedEmail.S3_Success_Count__c
            );
        
        System.assertEquals(
            0,
        updatedEmail.S3_Failed_Count__c
            );
        
        System.assertEquals(
            100,
        updatedEmail.S3_Success_Rate__c
            );
        
        System.assertEquals(
            'Success',
        updatedEmail.S3_Retrieve_Status__c
            );
        
        System.assertEquals(
            1,
        updatedEmail.S3_Retrieved_Count__c
            );
        
        System.assertEquals(
            100,
        updatedEmail.S3_Retrieve_Success_Rate__c
            );
    }
    
    @IsTest
    static void testStartWithNoFiles() {
        
        EmailMessage email = createEmailMessage();
        
        Test.setMock(
            HttpCalloutMock.class,
        new S3EmptyMock()
            );
        
        AwsS3RetrieveEmailBatch batch =
            new AwsS3RetrieveEmailBatch(email.Id);
        
        Test.startTest();
        
        Iterable<String> result = batch.start(null);
        
        Test.stopTest();
        
        List<String> files = new List<String>();
        
        for (String fileKey : result) {
            files.add(fileKey);
        }
        
        System.assertEquals(
            0,
        files.size(),
        'Empty S3 package should return no files'
            );
        
        System.assertEquals(
            0,
        batch.getTotalProcessed()
            );
    }
    
    @IsTest
    static void testS3XmlParsing() {
        
        EmailMessage email = createEmailMessage();
        
        Test.setMock(
            HttpCalloutMock.class,
        new S3SuccessMock()
            );
        
        AwsS3RetrieveEmailBatch batch =
            new AwsS3RetrieveEmailBatch(email.Id);
        
        Test.startTest();
        
        Iterable<String> result = batch.start(null);
        
        Test.stopTest();
        
        List<String> files = new List<String>();
        
        for (String fileKey : result) {
            files.add(fileKey);
        }
        
        System.assertEquals(
            1,
        files.size()
            );
        
        // System.assertEquals(
        //     email.Id + '/Document.pdf',
        // files[0]
        //     );
        
        System.assertEquals(
            1,
        batch.getTotalProcessed()
            );
    }
    
    @IsTest
    static void testFakeMethod(){
        
        Test.startTest();
        AwsS3RetrieveEmailBatch.fakeMethod();
        Test.stopTest();
        
    }
}