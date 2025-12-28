@isTest
public class PrintingHouseReplyModalControllerTest {
    @TestSetup
    static void makeData(){
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Agent_Making_Sale__c = 'None';
        insert testApplication;

        ContentVersion cv1 = new ContentVersion(
            Title = 'TestFile1.pdf',
            PathOnClient = 'TestFile1.pdf',
            VersionData = Blob.valueOf('Test Content 1'),
            IsMajorVersion = true
        );
        ContentVersion cv2 = new ContentVersion(
            Title = 'REPLY_File2.docx',
            PathOnClient = 'REPLY_File2.docx',
            VersionData = Blob.valueOf('Test Content 2'),
            IsMajorVersion = true
        );
        ContentVersion cv3 = new ContentVersion(
            Title = 'TestFile3.txt',
            PathOnClient = 'TestFile3.txt',
            VersionData = Blob.valueOf('Test Content 3'),
            IsMajorVersion = true
        );
        insert new List<ContentVersion>{cv1, cv2, cv3};

        // Get ContentDocumentIds
        List<ContentVersion> cvs = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv1.Id OR Id = :cv2.Id OR Id = :cv3.Id];
        Map<String, Id> contentDocIds = new Map<String, Id>();
        for(ContentVersion cv : cvs) {
            if(cv.Title == 'TestFile1.pdf') contentDocIds.put('cv1', cv.ContentDocumentId);
            if(cv.Title == 'REPLY_File2.docx') contentDocIds.put('cv2', cv.ContentDocumentId);
            if(cv.Title == 'TestFile3.txt') contentDocIds.put('cv3', cv.ContentDocumentId);
        }

        // Create ContentDocumentLinks to link files to Application
        List<ContentDocumentLink> cdLinks = new List<ContentDocumentLink>();
        for(Id docId : contentDocIds.values()) {
            cdLinks.add(new ContentDocumentLink(
                LinkedEntityId = testApplication.Id,
                ContentDocumentId = docId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        System.debug(cdLinks.size());
        insert cdLinks;
    }

    @IsTest
    static void testSendDocs_Success() {
        // Get test data
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        ContentVersion cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Title = 'TestFile1' LIMIT 1];

        List<Id> attachFiles = new List<Id>{cv.ContentDocumentId};
        Id fileIdToHMRC = cv.ContentDocumentId;

        Test.startTest();
        PrintingHouseReplyModalController.ResultWrapper result =
            PrintingHouseReplyModalController.sendDocs(testApp.Id, attachFiles, fileIdToHMRC);
        Test.stopTest();

        // Assertions
        System.assert(result.isSent, 'Should return isSent = true');
        System.assertEquals(null, result.errorMessage, 'Should not have error message');

        // Verify Application status was updated
        Application__c updatedApp = [SELECT Id, Status__c FROM Application__c WHERE Id = :testApp.Id];
        System.assertEquals('HMRC Appeal', updatedApp.Status__c, 'Application status should be updated to HMRC Appeal');

        // Verify HMRC_Appeal_Reply__c was created
        List<HMRC_Appeal_Reply__c> replies = [SELECT Id, Application__c, Client_Attach_File_Ids__c
                                             FROM HMRC_Appeal_Reply__c
                                             WHERE Application__c = :testApp.Id];
        System.assertEquals(1, replies.size(), 'Should create one HMRC Appeal Reply record');

        // Verify ContentDocumentLink was created
        List<ContentDocumentLink> cdLinks = [SELECT Id, LinkedEntityId, ContentDocumentId
                                            FROM ContentDocumentLink
                                            WHERE LinkedEntityId = :replies[0].Id];
        System.assertEquals(1, cdLinks.size(), 'Should create ContentDocumentLink to HMRC Appeal Reply');
        System.assertEquals(fileIdToHMRC, cdLinks[0].ContentDocumentId, 'Should link correct file');
    }

    @IsTest
    static void testSendEmail_Success() {
        // Create test data
        String toAddress = 'test@example.com';
        String subject = 'Test Subject';
        String body = '<p>Test Body</p>';
        // Get ContentDocumentId for attachment
        ContentVersion cv = [SELECT ContentDocumentId, Title FROM ContentVersion WHERE Title = 'TestFile1' LIMIT 1];
        List<Id> contentDocumentIds = new List<Id>{cv.ContentDocumentId};
        Test.startTest();
        // Mock the email sending
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        // Call the method - should not throw exception
        try {
            PrintingHouseReplyModalController.sendEmail(toAddress, subject, body, contentDocumentIds);
            System.assert(true, 'Email sent successfully');
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendEmail_EmptyRecipient() {
        String toAddress = '';
        String subject = 'Test Subject';
        String body = '<p>Test Body</p>';
        List<Id> contentDocumentIds = new List<Id>();

        Test.startTest();
        try {
            PrintingHouseReplyModalController.sendEmail(toAddress, subject, body, contentDocumentIds);
            System.assert(false, 'Should have thrown exception for empty recipient');
        } catch (AuraHandledException e) {
            System.assertEquals('Script-thrown exception', e.getMessage(), 'Should throw correct exception message');
        }
        Test.stopTest();
    }

        // Test getAvailableDocuments method
    @IsTest
    static void testGetAvailableDocuments() {
        // Get test Application
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        PrintingHouseReplyModalController.InitialFilesWrapper wrapper =
            PrintingHouseReplyModalController.getAvailableDocuments(testApp.Id);
        Test.stopTest();

        // Assertions
        System.assertNotEquals(null, wrapper, 'Wrapper should not be null');
        System.assertEquals(3, wrapper.allAvailableFiles.size(), 'Should return 3 files');
        System.assertEquals(1, wrapper.replyFiles.size(), 'Should return 1 reply file');

        // Verify reply file contains 'REPLY' in title
        for(ContentDocumentLink link : wrapper.replyFiles) {
            System.assert(link.ContentDocument.Title.contains('REPLY'),
                'Reply file should contain REPLY in title: ' + link.ContentDocument.Title);
        }
    }

    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true}');
            res.setStatusCode(200);
            return res;
        }
    }
}