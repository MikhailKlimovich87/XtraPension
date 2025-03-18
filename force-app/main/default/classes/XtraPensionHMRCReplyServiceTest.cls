@isTest
public class XtraPensionHMRCReplyServiceTest {
    @TestSetup
    static void setup(){
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
    }

    @IsTest
    static void handleInboundEmailTestCase1() {
        Application__c testApplicaition = [
            SELECT
                National_Insurance_Number__c,
                Email__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        String subject = testApplicaition.National_Insurance_Number__c + ' - REJECT';
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        email.plainTextBody = '';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        Messaging.InboundEmail.BinaryAttachment attachment = new Messaging.InboundEmail.BinaryAttachment();
        attachment.body = blob.valueOf('Test attachment');
        attachment.fileName = 'textfileone.txt';
        attachment.mimeTypeSubType = 'text/plain';
        email.binaryAttachments = new Messaging.inboundEmail.BinaryAttachment[] { attachment };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        List<ContentDocumentLink> testDocumentsBeforeUpdate = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplicaition.Id AND
                  ContentDocument.Title LIKE '%REJECT%'
        ];
        System.assertEquals(0, testDocumentsBeforeUpdate.size(), 'Before receive email application mustn\'t have HMRC reply result file');
        Test.startTest();
        XtraPensionHMRCReplyService testService = new XtraPensionHMRCReplyService();
        testService.handleInboundEmail(email, env);
        Test.stopTest();
        List<ContentDocumentLink> testDocumentsAfterUpdate = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplicaition.Id AND
                  ContentDocument.Title LIKE '%REJECT%'
        ];
        System.assertNotEquals(null, testDocumentsAfterUpdate, 'After receive email application must have HMRC reply result file');
    }

    @IsTest
    static void handleInboundEmailTestCase2() {
        Application__c testApplicaition = [
            SELECT
                National_Insurance_Number__c,
                Email__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail() ;
        String subject = testApplicaition.National_Insurance_Number__c + ' - UNKNOWN';
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        email.plainTextBody = '';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        Messaging.InboundEmail.BinaryAttachment attachment = new Messaging.InboundEmail.BinaryAttachment();
        attachment.body = blob.valueOf('Test attachment');
        attachment.fileName = 'textfileone.txt';
        attachment.mimeTypeSubType = 'text/plain';
        email.binaryAttachments = new Messaging.inboundEmail.BinaryAttachment[] { attachment };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        List<ContentDocumentLink> testDocumentsBeforeUpdate = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplicaition.Id AND
                  ContentDocument.Title LIKE '%UNKNOWN%'
        ];
        System.assertEquals(0, testDocumentsBeforeUpdate.size(), 'Before receive email application mustn\'t have HMRC reply result file');
        Test.startTest();
        XtraPensionHMRCReplyService testService = new XtraPensionHMRCReplyService();
        testService.handleInboundEmail(email, env);
        Test.stopTest();
        List<ContentDocumentLink> testDocumentsAfterUpdate = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplicaition.Id AND
                  ContentDocument.Title LIKE '%UNKNOWN%'
        ];
        System.assertNotEquals(null, testDocumentsAfterUpdate, 'After receive email application must have HMRC reply result file');
    }

    @IsTest
    static void handleInboundEmailTestCase3() {
        Application__c testApplicaition = [
            SELECT
                National_Insurance_Number__c,
                Email__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail() ;
        String subject = testApplicaition.National_Insurance_Number__c + ' - APPROVED';
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        email.plainTextBody = '';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        Messaging.InboundEmail.BinaryAttachment attachment = new Messaging.InboundEmail.BinaryAttachment();
        attachment.body = blob.valueOf('Test attachment');
        attachment.fileName = 'textfileone.txt';
        attachment.mimeTypeSubType = 'text/plain';
        email.binaryAttachments = new Messaging.inboundEmail.BinaryAttachment[] { attachment };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        List<ContentDocumentLink> testDocumentsBeforeUpdate = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplicaition.Id AND
                  ContentDocument.Title LIKE '%APPROVED%'
        ];
        System.assertEquals(0, testDocumentsBeforeUpdate.size(), 'Before receive email application mustn\'t have HMRC reply result file');
        Test.startTest();
        XtraPensionHMRCReplyService testService = new XtraPensionHMRCReplyService();
        testService.handleInboundEmail(email, env);
        Test.stopTest();
        List<ContentDocumentLink> testDocumentsAfterUpdate = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplicaition.Id AND
                  ContentDocument.Title LIKE '%APPROVED%'
        ];
        System.assertNotEquals(null, testDocumentsAfterUpdate, 'After receive email application must have HMRC reply result file');
    }
}