@isTest
public class VoluntaryContributionEmailServiceTest {
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
                Id,
                Name,
                Email__c
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
        VoluntaryContributionEmailServiceHandler testInbound = new VoluntaryContributionEmailServiceHandler();
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
        System.assertEquals(3, emailMessagesAfterTest.size());
    }
}