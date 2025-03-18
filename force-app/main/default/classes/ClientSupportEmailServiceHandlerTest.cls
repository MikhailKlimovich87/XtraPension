@isTest
public with sharing class ClientSupportEmailServiceHandlerTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        insert testApplication;
    }

    @IsTest
    static void handleInboundEmailTest() {
        Application__c testApplicaition = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c,
                Email__c,
                Tracking_Number__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail() ;
        String subject = 'Test subject ' + testApplicaition.Name + ' - additional info';
        email.subject = subject;
        email.fromAddress = 'john.snow@gmail.com';
        email.plainTextBody = 'Test message';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>();
        Messaging.InboundEmail.BinaryAttachment testAttach = new Messaging.InboundEmail.BinaryAttachment();
        testAttach.body     = Blob.valueOf('124sawq21456789');
        testAttach.fileName = 'TestFile.jpg';
        email.binaryAttachments.add(testAttach);
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        List<EmailMessage> emailMessagesBeforeTest = [
            SELECT
                relatedToId,
                ToAddress,
                fromAddress
            FROM EmailMessage
            WHERE relatedToId = :testApplicaition.Id
        ];
        System.assertEquals(1, emailMessagesBeforeTest.size());
        Test.startTest();
        ClientSupportEmailServiceHandler testInbound = new ClientSupportEmailServiceHandler();
        testInbound.handleInboundEmail(email, env);
        Test.stopTest();
        List<EmailMessage> emailMessagesAfterTest = [
            SELECT
                relatedToId,
                ToAddress,
                fromAddress
            FROM EmailMessage
            WHERE relatedToId = :testApplicaition.Id
        ];
        System.assertEquals(2, emailMessagesAfterTest.size());
        if(!emailMessagesAfterTest.isEmpty() && emailMessagesAfterTest.size() > 1) {
            EmailMessage newEmailMessage = emailMessagesAfterTest[1];
            System.assertEquals(testInbound.ORG_WIDE_EMAIL_ADDRESS, newEmailMessage.ToAddress);
            System.assertEquals(testApplicaition.Email__c, newEmailMessage.fromAddress);
        } 
    }
}