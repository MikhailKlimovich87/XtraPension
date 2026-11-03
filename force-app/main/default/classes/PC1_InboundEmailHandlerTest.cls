/**
 * Tests for PC1_InboundEmailHandler (client replies → the right record).
 * Added 2026-10-02 — the class had no test (0%).
 */
@IsTest
private class PC1_InboundEmailHandlerTest {

    private static Messaging.InboundEmail mail(String fromAddr, String subject, String body) {
        Messaging.InboundEmail e = new Messaging.InboundEmail();
        e.fromAddress = fromAddr;
        e.fromName = 'Client';
        e.subject = subject;
        e.plainTextBody = body;
        e.toAddresses = new List<String>{ 'clients@xtrapension.com' };
        e.headers = new List<Messaging.InboundEmail.Header>();
        return e;
    }

    private static Messaging.InboundEmail.Header header(String n, String v) {
        Messaging.InboundEmail.Header h = new Messaging.InboundEmail.Header();
        h.name = n;
        h.value = v;
        return h;
    }

    private static PC1_Application__c makeApp(String email) {
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'In', Last_Name__c = 'Box', Stage__c = 'New', Email__c = email);
        insert a;
        return a;
    }

    private static Messaging.InboundEmailResult run(Messaging.InboundEmail e) {
        return new PC1_InboundEmailHandler().handleInboundEmail(e, new Messaging.InboundEnvelope());
    }

    @IsTest static void routes_by_sender_and_keeps_attachments() {
        PC1_Application__c a = makeApp('client@example.org');
        Messaging.InboundEmail e = mail('client@example.org', 'My payslip', 'see attached');
        e.headers.add(header('Message-Id', '<abc@mail.example.org>'));
        Messaging.InboundEmail.BinaryAttachment att = new Messaging.InboundEmail.BinaryAttachment();
        att.fileName = 'payslip.pdf';
        att.body = Blob.valueOf('%PDF');
        e.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ att };

        System.assertEquals(true, run(e).success);
        EmailMessage em = [SELECT Id, RelatedToId, Incoming FROM EmailMessage WHERE FromAddress = 'client@example.org' LIMIT 1];
        System.assertEquals(a.Id, em.RelatedToId);
        System.assertEquals(1, [SELECT COUNT() FROM ContentVersion WHERE FirstPublishLocationId = :em.Id]);
    }

    @IsTest static void routes_by_thread_header() {
        PC1_Application__c a = makeApp('other@example.org');
        EmailMessage parent = new EmailMessage(Subject = 'Welcome', Incoming = false, Status = '3',
            MessageIdentifier = 'out-1@xtrapension.com', RelatedToId = a.Id, MessageDate = Datetime.now());
        insert parent;
        Messaging.InboundEmail e = mail('someone.new@example.org', 'Re: Welcome', 'thanks');
        e.headers.add(header('In-Reply-To', '<out-1@xtrapension.com>'));
        e.headers.add(header('References', '<x@y> <out-1@xtrapension.com>'));
        run(e);
        System.assertEquals(a.Id, [SELECT RelatedToId FROM EmailMessage WHERE FromAddress = 'someone.new@example.org'].RelatedToId);
    }

    @IsTest static void routes_by_verified_subject_nonce_only() {
        PC1_Application__c a = makeApp('nonce@example.org');
        insert new EmailMessage(Subject = 'Notice', Incoming = false, Status = '3', RelatedToId = a.Id, MessageDate = Datetime.now(),
            MessageIdentifier = 'PC00042-0123456789abcdef@xtrapension.com');
        run(mail('stranger@example.org', 'Re: [PC00042-0123456789abcdef] Notice', 'hi'));
        System.assertEquals(a.Id, [SELECT RelatedToId FROM EmailMessage WHERE FromAddress = 'stranger@example.org'].RelatedToId);

        // A forged token (unknown nonce) must not attach a stranger's mail to the record.
        run(mail('attacker@example.org', '[PC00042-ffffffffffffffff] change my bank', 'x'));
        System.assertEquals(null, [SELECT RelatedToId FROM EmailMessage WHERE FromAddress = 'attacker@example.org'].RelatedToId);
    }

    @IsTest static void unmatched_goes_to_triage_without_files() {
        Messaging.InboundEmail e = mail('nobody@example.org', null, 'hello');
        Messaging.InboundEmail.BinaryAttachment att = new Messaging.InboundEmail.BinaryAttachment();
        att.fileName = 'big.pdf';
        att.body = Blob.valueOf('x');
        e.binaryAttachments = new List<Messaging.InboundEmail.BinaryAttachment>{ att };
        run(e);
        EmailMessage em = [SELECT Id, RelatedToId, Subject FROM EmailMessage WHERE FromAddress = 'nobody@example.org'];
        System.assertEquals(null, em.RelatedToId);
        System.assertEquals('(no subject)', em.Subject);
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion WHERE FirstPublishLocationId = :em.Id], 'no storage for unrouted mail');
    }

    @IsTest static void noise_and_hmrc_are_dropped() {
        run(mail('robot@xtrapension.com', 'receipt', 'x'));
        run(mail('MAILER-DAEMON@google.com', 'bounce', 'x'));
        Messaging.InboundEmail h = mail('printing@hmrc.gov.uk', 'Letter', null);
        h.htmlBody = '<p>AppID: 123</p><p>Tracking No: 456</p>';
        run(h);
        System.assertEquals(0, [SELECT COUNT() FROM EmailMessage]);

        // A CLIENT quoting an HMRC letter is not dropped.
        PC1_Application__c a = makeApp('quoter@example.org');
        run(mail('quoter@example.org', 'fwd', 'AppID: 1 Tracking No: 2'));
        System.assertEquals(1, [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :a.Id]);
    }

    @IsTest static void failures_land_in_the_dlq() {
        // Subject > 3000 chars is trimmed; force a failure instead via a
        // FromAddress the EmailMessage insert rejects (over 1000 chars).
        Messaging.InboundEmail e = mail('a'.repeat(1100) + '@example.org', 'x', 'body');
        Messaging.InboundEmailResult r = run(e);
        System.assertEquals(true, r.success, 'never bounce the client');
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Inbound_Email_DLQ__c]);
    }

    @IsTest static void helpers() {
        System.assertEquals(null, PC1_InboundEmailHandler.stripHtml(null));
        System.assertEquals(null, PC1_InboundEmailHandler.serialiseHeaders(null));
        System.assertEquals(2, PC1_InboundEmailHandler.splitMessageIds('<a@b> <c@d>').size());
        System.assertEquals(0, PC1_InboundEmailHandler.splitMessageIds('').size());
        System.assertEquals(false, PC1_InboundEmailHandler.isHmrcPrintingHouseReply(null));
        System.assertEquals(null, PC1_InboundEmailHandler.routeBySubjectToken(''));
        System.assertEquals(null, PC1_InboundEmailHandler.routeBySubjectToken('no token here'));
        Messaging.InboundEmail e = mail('x@example.org', 's', 'b');
        e.headers.add(header('X-Test', '1'));
        System.assert(PC1_InboundEmailHandler.serialiseHeaders(e.headers).contains('X-Test: 1'));
    }
}