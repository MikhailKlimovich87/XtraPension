/**
 * ClientSupportEmailServiceHandler (clients@xtrapension.com) and the Claims (Basic__c): which claim an incoming email
 * is linked to (Claim__c) and what it is related to (RelatedToId). Order: the claim ref in the subject, the client's
 * email, the helper's or the bank account owner's email; several matches = the most recently created claim.
 */
@IsTest
private class ClaimEmailLinkTest {
    static final String APP_EMAIL = 'john.snow@gmail.com'; // TestDataFactory.createApplication

    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact person = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        insert TestDataFactory.createApplication(person.Id, false);
    }

    static Basic__c claim(String email, String helperEmail, String bankOwnerEmail) {
        Basic__c c = new Basic__c(
            Status__c = 'Form In Progress',
            First_Name__c = 'Ann',
            Email__c = email,
            Friend_Email__c = helperEmail,
            Bank_Account_Owner_Email__c = bankOwnerEmail
        );
        insert c;
        return [SELECT Id, Name, Status__c, Validation_Agent__c FROM Basic__c WHERE Id = :c.Id];
    }

    static Messaging.InboundEmailResult receive(String fromAddress, String subject, Boolean withAttachment) {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.fromAddress = fromAddress;
        email.fromName = 'Client';
        email.subject = subject;
        email.plainTextBody = 'Hello';
        email.htmlBody = '<p>Hello</p>';
        if (withAttachment) {
            Messaging.InboundEmail.BinaryAttachment file = new Messaging.InboundEmail.BinaryAttachment();
            file.fileName = 'passport.jpg';
            file.body = Blob.valueOf('jpg');
            email.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ file };
        }
        return new ClientSupportEmailServiceHandler().handleInboundEmail(email, new Messaging.InboundEnvelope());
    }

    static EmailMessage saved(String subject) {
        return [
            SELECT Id, RelatedToId, Application__c, Claim__c, Claim_Val_Agent__c, Claim_Status__c, Has_Related_Claim__c, Email_Message_Status__c
            FROM EmailMessage
            WHERE Subject = :subject
        ];
    }

    static Id applicationId() {
        return [SELECT Id FROM Application__c WHERE Email__c = :APP_EMAIL LIMIT 1].Id;
    }

    @IsTest
    static void subjectRefLinksTheClaimAndTheFormulasFollowIt() {
        Basic__c other = claim('other@example.com', null, null);
        Basic__c named = claim('named@example.com', null, null);
        String subject = 'Re: your claim ' + named.Name + ' - documents';
        Test.startTest();
        Messaging.InboundEmailResult r = receive('somebody@example.com', subject, false);
        Test.stopTest();
        System.assert(r.success);
        EmailMessage m = saved(subject);
        System.assertEquals(named.Id, m.Claim__c);
        System.assertEquals(named.Id, m.RelatedToId);
        System.assertEquals(null, m.Application__c);
        System.assertEquals(true, m.Has_Related_Claim__c);
        System.assertEquals(named.Status__c, m.Claim_Status__c);
        System.assertEquals(named.Validation_Agent__c, m.Claim_Val_Agent__c);
        System.assertNotEquals(null, m.Email_Message_Status__c);
        System.assertNotEquals(other.Id, m.Claim__c);
    }

    @IsTest
    static void subjectRefWinsOverTheApplicationForRelatedTo() {
        Basic__c named = claim('named@example.com', null, null);
        String subject = named.Name.toLowerCase() + ': my bank details';
        Test.startTest();
        receive(APP_EMAIL, subject, false);
        Test.stopTest();
        EmailMessage m = saved(subject);
        System.assertEquals(named.Id, m.Claim__c);
        System.assertEquals(named.Id, m.RelatedToId);
        System.assertEquals(applicationId(), m.Application__c, 'the application link stays as before');
    }

    @IsTest
    static void clientEmailLinksTheClaim() {
        Basic__c c = claim('ann.claim@example.com', null, null);
        Test.startTest();
        receive('ann.claim@example.com', 'Question', false);
        Test.stopTest();
        EmailMessage m = saved('Question');
        System.assertEquals(c.Id, m.Claim__c);
        System.assertEquals(c.Id, m.RelatedToId);
        System.assertEquals(null, m.Application__c);
    }

    @IsTest
    static void unknownRefInTheSubjectFallsBackToTheEmail() {
        Basic__c c = claim('ann.claim@example.com', null, null);
        Test.startTest();
        receive('ann.claim@example.com', 'About C99999, AC105000 and C1055000', false);
        Test.stopTest();
        EmailMessage m = saved('About C99999, AC105000 and C1055000');
        System.assertEquals(c.Id, m.Claim__c);
        System.assertEquals(c.Id, m.RelatedToId);
    }

    @IsTest
    static void helperEmailLinksTheClaim() {
        Basic__c c = claim('ann.claim@example.com', 'helper@example.com', null);
        Test.startTest();
        receive('helper@example.com', 'From the daughter', false);
        Test.stopTest();
        EmailMessage m = saved('From the daughter');
        System.assertEquals(c.Id, m.Claim__c);
        System.assertEquals(c.Id, m.RelatedToId);
    }

    @IsTest
    static void bankAccountOwnerEmailLinksTheClaim() {
        Basic__c c = claim('ann.claim@example.com', null, 'owner@example.com');
        Test.startTest();
        receive('owner@example.com', 'Bank', false);
        Test.stopTest();
        EmailMessage m = saved('Bank');
        System.assertEquals(c.Id, m.Claim__c);
        System.assertEquals(c.Id, m.RelatedToId);
    }

    @IsTest
    static void applicationAndClaimByEmailStayOnTheApplication() {
        Basic__c c = claim(APP_EMAIL, null, null);
        Test.startTest();
        receive(APP_EMAIL, 'Both products', false);
        Test.stopTest();
        EmailMessage m = saved('Both products');
        Id appId = applicationId();
        System.assertEquals(c.Id, m.Claim__c);
        System.assertEquals(appId, m.Application__c);
        System.assertEquals(appId, m.RelatedToId);
    }

    @IsTest
    static void severalMatchesTakeTheMostRecentClaim() {
        Basic__c older = claim('twice@example.com', null, null);
        Basic__c newer = claim('twice@example.com', null, null);
        Test.setCreatedDate(older.Id, Datetime.now().addDays(-30));
        Test.setCreatedDate(newer.Id, Datetime.now().addDays(-1));
        Test.startTest();
        receive('twice@example.com', 'Twice', false);
        Test.stopTest();
        System.assertEquals(newer.Id, saved('Twice').Claim__c);
    }

    @IsTest
    static void noMatchLeavesTheEmailUnlinked() {
        claim('ann.claim@example.com', 'helper@example.com', 'owner@example.com');
        Test.startTest();
        receive('stranger@example.com', 'Hello there', false);
        Test.stopTest();
        EmailMessage m = saved('Hello there');
        System.assertEquals(null, m.Claim__c);
        System.assertEquals(null, m.RelatedToId);
        System.assertEquals(null, m.Application__c);
        System.assertEquals(false, m.Has_Related_Claim__c);
    }

    @IsTest
    static void noSubjectStillMatchesByEmail() {
        Basic__c c = claim('ann.claim@example.com', null, null);
        Test.startTest();
        receive('ann.claim@example.com', null, false);
        Test.stopTest();
        EmailMessage m = saved('Empty');
        System.assertEquals(c.Id, m.Claim__c);
    }

    @IsTest
    static void noSenderAndNoSubjectIsSavedUnlinked() {
        claim('ann.claim@example.com', null, null);
        Test.startTest();
        Messaging.InboundEmailResult r = receive(null, null, false);
        Test.stopTest();
        System.assert(r.success);
        EmailMessage m = saved('Empty');
        System.assertEquals(null, m.Claim__c);
        System.assertEquals(null, m.RelatedToId);
    }

    @IsTest
    static void attachmentsStayOnTheEmailNotOnTheClaim() {
        Basic__c c = claim('ann.claim@example.com', null, null);
        Test.startTest();
        receive('ann.claim@example.com', 'My passport', true);
        Test.stopTest();
        EmailMessage m = saved('My passport');
        System.assertEquals(c.Id, m.Claim__c);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :m.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id]);
    }

    @IsTest
    static void docuSignAndOurOwnAddressAreIgnored() {
        claim('ann.claim@example.com', null, null);
        Test.startTest();
        Messaging.InboundEmailResult docusign = receive('dse@eumail.docusign.net', 'Completed', false);
        Messaging.InboundEmailResult ours = receive('clients@xtrapension.com', 'Completed', false);
        Test.stopTest();
        System.assertEquals(false, docusign.success);
        System.assertEquals(false, ours.success);
        System.assertEquals(0, [SELECT COUNT() FROM EmailMessage WHERE Subject = 'Completed']);
    }
}