/**
 * Tests for AA_MessageDispatcher (B3). HttpCalloutMock for Twilio and
 * Test.startTest/stopTest to force the Queueable to run.
 *
 * Coverage: render happy path, render unknown-token throw, dispatch email
 * happy path, dispatch dedup skip, blank recipient → Failed, unknown token
 * inside dispatch → Failed, SMS mocked → Sent, unknown-event → no-op.
 *
 * 2026-09-11 additions (the class sat at 67.9%): the attachment machinery
 * (static-resource PDFs materialised into the app's Files + linked to the
 * mirrored EmailMessage; per-app files by friendly title; the missing-file
 * guard), the Twilio failure branches, Simple-mode shell rendering and HTML
 * escaping, the call / decision / mandate / config tokens, helper CC, and the
 * nested-async (run-inline) path. Every test asserts the send log, the
 * EmailMessage mirror or the Twilio mirror row the val team actually sees.
 *
 * 2026-09-11 escape-once: a plain-text Simple email was HTML-escaping the
 * merge values twice (dispatcher pre-escape + simpleToHtml), so claimants read
 * "O&#39;Connor &amp; Sons". The escape_once_* tests pin one escape per path
 * and re-assert the injection guard on every path, including the one that no
 * longer pre-escapes.
 */
@IsTest
private class AA_MessageDispatcherTest {

    // Twilio 201 Created shape.
    private class TwilioOkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(201);
            r.setHeader('Content-Type', 'application/json');
            r.setBody('{"sid":"SMtestx000000000000000000000000001",'
                    + '"status":"queued","to":"+441234567890",'
                    + '"from":"+447476900311","body":"hi"}');
            return r;
        }
    }

    // Twilio answering with an arbitrary status/body (error + non-JSON branches).
    private class TwilioStatusMock implements HttpCalloutMock {
        private Integer status;
        private String  body;
        TwilioStatusMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    // Twilio unreachable: Http.send() throws.
    private class TwilioDownMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('connection refused');
        }
    }

    private static void seedTwilioCreds() {
        insert new XtraPension_Data__c(
            SetupOwnerId       = UserInfo.getOrganizationId(),
            Twilio_Account__c  = 'ACtestaccount',
            Twilio_Token__c    = 'testtoken'
        );
    }

    // XtraPension contact constants — query-then-upsert so the fixture is
    // deterministic whether or not the org-default row is visible to the test.
    private static void seedConfig(String phone, String email, String whatsapp, String office) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.XP_Phone__c    = phone;
        cfg.XP_Email__c    = email;
        cfg.XP_WhatsApp__c = whatsapp;
        cfg.XP_Office__c   = office;
        upsert cfg;
    }

    private static AA_Application__c makeApp(String email, String phone) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Alice',
            Last_Name__c  = 'Test',
            Stage__c      = 'New',
            Email__c      = email,
            Phone__c      = phone
        );
        insert a;
        // Re-query so the auto-number Name is populated — Apex does NOT refresh
        // auto-number fields on the in-memory sObject after insert, which is why
        // render_resolves_known_tokens saw a null Name (audit 2026-08-28).
        return [
            SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c
            FROM AA_Application__c WHERE Id = :a.Id
        ];
    }

    private static AA_Message_Template__c makeTemplate(
            String channel, String triggerEvent, String subject, String body) {
        AA_Message_Template__c t = new AA_Message_Template__c(
            Channel__c              = channel,
            Trigger_Event__c        = triggerEvent,
            Active__c               = true,
            Subject_Template__c     = subject,
            Body_Template__c        = body
        );
        insert t;
        return t;
    }

    // A Simple-mode template: Content_Text__c is what renders; Body_Template__c
    // is ignored on the send path.
    private static AA_Message_Template__c makeSimpleTemplate(
            String channel, String triggerEvent, String subject, String contentText) {
        AA_Message_Template__c t = new AA_Message_Template__c(
            Channel__c              = channel,
            Trigger_Event__c        = triggerEvent,
            Active__c               = true,
            Subject_Template__c     = subject,
            Content_Mode__c         = 'Simple',
            Content_Text__c         = contentText,
            Body_Template__c        = 'IGNORED IN SIMPLE MODE'
        );
        insert t;
        return t;
    }

    // A claimant whose first name carries the characters naive HTML handling
    // gets wrong: an apostrophe (every O'Connor on the books), an ampersand
    // and — when a test asks for it — live markup. {{FirstName}} exercises it.
    private static AA_Application__c makeAppNamed(String firstName) {
        AA_Application__c app = makeApp('recipient@example.com', '+441234567890');
        app.First_Name__c = firstName;
        update app;
        return app;
    }

    // The single send log an application must have after a one-template dispatch.
    private static AA_Message_Send_Log__c soleLog(Id appId) {
        List<AA_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c, External_Id__c, Rendered_Subject__c
              FROM AA_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size(), 'exactly one send log expected for the application');
        return logs[0];
    }

    private static Integer twilioRows(Id appId) {
        return [SELECT COUNT() FROM TwilioSF__Message__c WHERE TwilioSF__SF_Parent_Record_Id__c = :String.valueOf(appId)];
    }

    // The EmailMessage mirror the Email Messages tab shows.
    private static List<EmailMessage> mirrored(Id appId) {
        return [SELECT Id, Subject, CcAddress, ToAddress, Status FROM EmailMessage WHERE RelatedToId = :appId];
    }

    private static Set<Id> docsLinkedTo(Id entityId) {
        Set<Id> out = new Set<Id>();
        for (ContentDocumentLink l : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :entityId]) {
            out.add(l.ContentDocumentId);
        }
        return out;
    }

    // A file already sitting in the application's Files (as Node's mandate
    // upload or a previous send would leave it).
    private static ContentVersion addAppFile(Id appId, String title, String pathOnClient) {
        ContentVersion cv = new ContentVersion(
            Title = title, PathOnClient = pathOnClient,
            VersionData = Blob.valueOf('%PDF-1.4 ' + title), FirstPublishLocationId = appId);
        insert cv;
        return [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id];
    }

    // Lets a test call dispatch() from a @future context (System.isFuture()).
    @future
    private static void dispatchFromFuture(Id appId, String triggerEvent) {
        AA_MessageDispatcher.dispatch(appId, triggerEvent);
    }

    // ─── render ─────────────────────────────────────────────────────

    @IsTest static void render_resolves_known_tokens() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created',
            'Hi {{FirstName}}', 'Ref {{ApplicationRef}} — issued {{IssueDate}}.');

        Test.startTest();
        AA_MessageDispatcher.Rendered r =
            AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assertEquals('Hi Alice', r.subject);
        System.assert(r.body.contains('Ref ' + app.Name), 'ApplicationRef fill: ' + r.body);
        System.assert(r.body.contains('issued '),         'IssueDate fill: ' + r.body);
        System.assert(!r.body.contains('{{'),             'No unresolved tokens: ' + r.body);
    }

    @IsTest static void render_unknown_token_throws() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created',
            'x', 'Hello {{NopeToken}}');

        Boolean threw = false;
        try {
            Test.startTest();
            AA_MessageDispatcher.render(tpl.Id, app.Id);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Unknown token must throw AuraHandledException');
    }

    // {{FeeAmount}} must be the real Fee_Amount__c (20% of the ANNUAL award),
    // and the Bacs-notice trio must describe the NEXT pending installment, not
    // the last charged one. Until 2026-09-09 FeeAmount was a PC1 placeholder
    // string, so every money email read "£[fee amount, calculated post-award]".
    // A higher-rate-sized award (£5,740.80) so the fee crosses £1,000 and the
    // thousands separator is exercised through the real token path.
    @IsTest static void render_fee_tokens_come_from_award_and_next_pending_installment() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        app.Award_Amount__c = 5740.80;         // annual award → fee 1,148.16
        app.Fee_Plan_Installments__c = 3;
        update app;
        // #1 already charged (submitted), #2 is the next pending row, #3 later.
        Date nextDue = Date.today().addDays(5);
        insert new List<AA_Fee_Installment__c>{
            new AA_Fee_Installment__c(Application__c = app.Id, Installment_Number__c = 1,
                Scheduled_Date__c = Date.today().addDays(-25), Amount__c = 382.72,
                Payment_Status__c = 'submitted', Charged_At__c = Datetime.now().addDays(-25)),
            new AA_Fee_Installment__c(Application__c = app.Id, Installment_Number__c = 2,
                Scheduled_Date__c = nextDue, Amount__c = 382.72,
                Payment_Status__c = 'pending'),
            new AA_Fee_Installment__c(Application__c = app.Id, Installment_Number__c = 3,
                Scheduled_Date__c = Date.today().addDays(35), Amount__c = 382.72,
                Payment_Status__c = 'pending')
        };
        // SMS channel: this pins token values only. An Advanced plain-text EMAIL
        // body is wrapped in the shell since 2026-10-02 (F77).
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Bacs_Advance_Notice', 's',
            'fee={{FeeAmount}}|next={{FeeNextInstallmentNumber}}/{{FeeInstallmentTotal}}:{{FeeNextInstallmentAmount}}'
            + '|on={{FeeNextInstallmentDate}}|last={{FeeInstallmentNumber}}:{{FeeInstallmentAmount}}');

        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        // Expected date built the same timezone-free way as the dispatcher (GMT
        // in, GMT out) so the assertion cannot drift with the running user's TZ.
        String expectedDate = Datetime.newInstanceGmt(nextDue, Time.newInstance(0, 0, 0, 0)).formatGmt('dd/MM/yyyy');
        System.assertEquals('fee=1,148.16|next=2/3:382.72|on=' + expectedDate + '|last=1:382.72', r.body);
    }

    // Integrator 2026-10-02: a 'paused' row (Do Not Contact hold) was never
    // charged, so it is never the "current" instalment of a receipt. Before,
    // `Payment_Status__c != 'pending'` picked it when no row had been charged.
    @IsTest static void render_paused_row_is_not_the_current_charged_instalment() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        app.Award_Amount__c = 800;
        app.Fee_Plan_Installments__c = 2;
        update app;
        insert new List<AA_Fee_Installment__c>{
            new AA_Fee_Installment__c(Application__c = app.Id, Installment_Number__c = 1,
                Scheduled_Date__c = Date.today().addDays(10), Amount__c = 80,
                Payment_Status__c = 'paused'),
            new AA_Fee_Installment__c(Application__c = app.Id, Installment_Number__c = 2,
                Scheduled_Date__c = Date.today().addDays(40), Amount__c = 80,
                Payment_Status__c = 'paused')
        };
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Fee_Receipt_Installment', 's',
            'last={{FeeInstallmentNumber}}:{{FeeInstallmentAmount}}');
        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();
        System.assertEquals('last=:', r.body, 'no instalment has been charged yet');
    }

    // Client-facing money must read "1,148.16" whoever runs the send: a bare
    // String.valueOf(setScale(2)) has no thousands separator, and
    // Decimal.format() follows the running user's locale and trims zeros.
    // money() is the one place every money token is formatted.
    @IsTest static void money_groups_thousands_and_keeps_two_decimals() {
        System.assertEquals('',             AA_MessageDispatcher.money(null));
        System.assertEquals('0.00',         AA_MessageDispatcher.money(0));
        System.assertEquals('800.00',       AA_MessageDispatcher.money(800));
        System.assertEquals('999.50',       AA_MessageDispatcher.money(999.5));
        System.assertEquals('1,000.00',     AA_MessageDispatcher.money(1000));
        System.assertEquals('1,148.16',     AA_MessageDispatcher.money(1148.16));
        System.assertEquals('1,234,567.89', AA_MessageDispatcher.money(1234567.89));
        System.assertEquals('-1,234.50',    AA_MessageDispatcher.money(-1234.5));
    }

    // A Date has no timezone; the token must print the calendar day as stored,
    // never the previous/next day for a user outside Europe/London.
    @IsTest static void ukDate_prints_the_stored_day_as_ddMMyyyy() {
        System.assertEquals('',           AA_MessageDispatcher.ukDate(null));
        System.assertEquals('05/09/2026', AA_MessageDispatcher.ukDate(Date.newInstance(2026, 9, 5)));
        System.assertEquals('31/12/2026', AA_MessageDispatcher.ukDate(Date.newInstance(2026, 12, 31)));
    }

    // Pre-award the fee tokens must be EMPTY, not "0.00": Fee_Amount__c is a
    // BlankAsZero formula, so guarding on it alone would print "£0.00".
    @IsTest static void render_fee_tokens_blank_before_award() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Custom_Manual', 's',
            'fee=[{{FeeAmount}}] next=[{{FeeNextInstallmentAmount}}] on=[{{FeeNextInstallmentDate}}]');

        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assertEquals('fee=[] next=[] on=[]', r.body);
    }

    // ─── render: call / decision / mandate / agent / config tokens ───

    @IsTest static void render_call_tokens_come_from_the_latest_schedule_in_uk_time() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        Datetime slot = Datetime.now().addDays(3);
        insert new AA_Call_Schedule__c(Application__c = app.Id, Scheduled_At__c = slot, Status__c = 'Pending');
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Call_Reminder_Morning_Of', null, 'at {{CallTime}} on {{CallDate}}');

        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assertEquals('at ' + slot.format('HH:mm', 'Europe/London') + ' on ' + slot.format('dd/MM/yyyy', 'Europe/London'), r.body,
            'CallTime/CallDate must render the scheduled slot in Europe/London');
    }

    @IsTest static void render_decision_due_mandate_and_agent_tokens() {
        // Built in one insert: Stage_Changed_At__c is overwritten by the stage
        // trigger on UPDATE, and 'Submitted' requires a DWP reference.
        AA_Application__c app = new AA_Application__c(
            First_Name__c = 'Alice', Last_Name__c = 'Test', Phone__c = '+441234567890',
            Stage__c = 'Submitted', DWP_Reference__c = 'JT 12 34 56 A',
            Stage_Changed_At__c = Datetime.newInstanceGmt(2026, 1, 15, 10, 0, 0),
            Sales_Agent__c = 'Sean', Val_Agent__c = 'Ciara',
            DD_Mandate_Id__c = 'MD0001', DD_Mandate_Status__c = 'active',
            DD_Mandate_Created_At__c = Datetime.newInstanceGmt(2026, 1, 10, 9, 30, 0),
            CurrencyIsoCode = 'GBP'
        );
        insert app;
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Custom_Manual', null,
            'due={{DecisionDueDate}}|m={{MandateId}}/{{MandateStatus}}/{{MandateCreatedAt}}'
            + '|s={{Stage}}|sa={{SalesAgent}}|va={{ValAgent}}|ref={{DWPReference}}');

        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assertEquals('due=15/04/2026|m=MD0001/active/10/01/2026|s=Submitted|sa=Sean|va=Ciara|ref=JT 12 34 56 A', r.body,
            'DecisionDueDate = Stage_Changed_At__c + 3 months while Submitted; mandate/agent tokens from the application');
    }

    @IsTest static void render_xp_contact_tokens_come_from_config() {
        seedConfig('+44 20 7946 0000', 'help@test.invalid', '+44 7700 900000', 'Cork, Ireland');
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Custom_Manual', null,
            'p={{XPPhone}}|e={{XPEmail}}|w={{XPWhatsApp}}|o={{XPOffice}}');

        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);

        System.assertEquals('p=+44 20 7946 0000|e=help@test.invalid|w=+44 7700 900000|o=Cork, Ireland', r.body,
            'the XP contact tokens must come from AA_Config__c, not the hard-coded fallbacks');
    }

    // ─── render: Simple mode shell + HTML escaping ───────────────────

    @IsTest static void render_simple_email_wraps_shell_and_simple_sms_stays_plain() {
        seedConfig('+44 20 7946 0000', 'help@test.invalid', '+44 7700 900000', 'Cork');
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c email = new AA_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Custom_Manual',
            Active__c = true, Subject_Template__c = 's', Content_Mode__c = 'Simple',
            Content_Text__c = 'Hi {{FirstName}}, call {{XPPhone}}', Body_Template__c = 'IGNORED ON SEND');
        AA_Message_Template__c sms = new AA_Message_Template__c(Channel__c = 'SMS', Trigger_Event__c = 'Custom_Manual',
            Active__c = true, Content_Mode__c = 'Simple', Content_Text__c = 'Hi {{FirstName}}', Body_Template__c = 'IGNORED');
        insert new List<AA_Message_Template__c>{ email, sms };

        Test.startTest();
        AA_MessageDispatcher.Rendered e = AA_MessageDispatcher.render(email.Id, app.Id);
        AA_MessageDispatcher.Rendered s = AA_MessageDispatcher.render(sms.Id, app.Id);
        Test.stopTest();

        System.assert(e.body.startsWith('<!DOCTYPE html>'), 'Simple email content must be wrapped in the AA_Email_Shell: ' + e.body.left(80));
        System.assert(e.body.contains('<p style="margin:0 0 12px 0;">Hi Alice, call +44 20 7946 0000</p>'),
            'merged content must become a shell paragraph: ' + e.body);
        System.assert(!e.body.contains('IGNORED ON SEND'), 'Body_Template__c must be ignored in Simple mode');
        System.assert(!e.body.contains('{{'), 'shell footer tokens must be resolved: ' + e.body);
        System.assert(e.body.contains('help@test.invalid'), 'the footer XPEmail must come from AA_Config__c');
        System.assertEquals('Hi Alice', s.body, 'a Simple SMS must be the merged plain text with no shell');
    }

    // Client-controlled values (First_Name__c etc.) can never inject markup
    // into an email body or the mirrored EmailMessage (audit 2026-08-28);
    // subject and SMS are plain text and must stay verbatim.
    @IsTest static void render_escapes_values_in_email_body_but_not_subject_or_sms() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        app.First_Name__c = 'Ann <b>&';
        update app;
        AA_Message_Template__c email = makeTemplate('Email', 'Custom_Manual', 'Hi {{FirstName}}', 'Hi {{FirstName}}');
        AA_Message_Template__c sms   = makeTemplate('SMS',   'Custom_Manual', null,               'Hi {{FirstName}}');

        Test.startTest();
        AA_MessageDispatcher.Rendered e = AA_MessageDispatcher.render(email.Id, app.Id);
        AA_MessageDispatcher.Rendered s = AA_MessageDispatcher.render(sms.Id, app.Id);
        Test.stopTest();

        // An Advanced plain-text email now goes through the shell (F77): the
        // value is escaped once by simpleToHtml and never becomes markup.
        System.assert(e.body.contains('Hi Ann &lt;b&gt;&amp;'), 'client-controlled values must be HTML-escaped in an email body: ' + e.body);
        System.assert(!e.body.contains('<b>&'), 'INJECTION - the value rendered as live markup: ' + e.body);
        System.assertEquals('Hi Ann <b>&',           e.subject, 'the subject is plain text and must not be escaped');
        System.assertEquals('Hi Ann <b>&',           s.body,    'SMS is plain text and must not be escaped');
    }

    // ─── render: escape exactly once per path (fix 2026-09-11) ───────
    //
    // Until 2026-09-11 every Email render pre-escaped the merge values, and a
    // PLAIN-TEXT Simple template was then escaped again by simpleToHtml, so
    // the claimant read the literal "O&#39;Connor &amp; Sons" in the email.
    // Each path must escape once — and the injection guard (audit 2026-08-28)
    // must still hold on every one of them. NB this org's escapeHtml4() also
    // encodes the apostrophe (&#39;), simpleToHtml's own escape does not.

    private static final String HOSTILE_NAME = 'O\'Connor & Sons';

    @IsTest static void escape_once_simple_plain_text_email_escapes_the_name_once() {
        AA_Application__c app = makeAppNamed(HOSTILE_NAME);
        AA_Message_Template__c tpl = makeSimpleTemplate('Email', 'Custom_Manual', 'Hi {{FirstName}}',
            'Dear {{FirstName}},\n\nYour **{{FirstName}}** claim is in.');

        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assert(r.body.contains('<p style="margin:0 0 12px 0;">Dear O\'Connor &amp; Sons,</p>'),
            'the name must be escaped exactly once, by simpleToHtml: ' + r.body);
        System.assert(r.body.contains('<strong>O\'Connor &amp; Sons</strong>'),
            '**bold** must still work around a raw value: ' + r.body);
        System.assert(!r.body.contains('&amp;amp;'), 'DOUBLE ESCAPE - the claimant would read "&amp;": ' + r.body);
        System.assert(!r.body.contains('&amp;#39;') && !r.body.contains('&#39;'),
            'the plain-text path must not touch the apostrophe: ' + r.body);
        System.assertEquals('Hi ' + HOSTILE_NAME, r.subject, 'the subject is plain text: the raw characters survive');
    }

    // The plain-text path no longer pre-escapes, so this is the test that
    // proves it is still safe: markup in the value must come out as inert text
    // AND must not flip the template into the trust-as-HTML branch (the verdict
    // is taken on the template, never on the merged string).
    @IsTest static void escape_once_simple_plain_text_email_neutralises_markup_in_values() {
        AA_Application__c app = makeAppNamed('<p>' + HOSTILE_NAME + '</p><script>alert(1)</script><b>bold</b>');
        AA_Message_Template__c tpl = makeSimpleTemplate('Email', 'Custom_Manual', 's', 'Dear {{FirstName}}');

        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);

        System.assert(r.body.contains('Dear &lt;p&gt;O\'Connor &amp; Sons&lt;/p&gt;&lt;script&gt;alert(1)&lt;/script&gt;&lt;b&gt;bold&lt;/b&gt;'),
            'every tag in the value must be escaped to inert text: ' + r.body);
        System.assert(!r.body.contains('<script>') && !r.body.contains('<b>bold</b>'),
            'INJECTION - a client value rendered as live markup: ' + r.body);
        System.assert(!r.body.contains('&amp;lt;') && !r.body.contains('&amp;amp;'), 'DOUBLE ESCAPE: ' + r.body);
    }

    @IsTest static void escape_once_simple_html_email_escapes_values_once_and_neutralises_markup() {
        AA_Application__c app = makeAppNamed(HOSTILE_NAME + ' <script>alert(1)</script><b>bold</b>');
        // Rich text as the aaMessageTemplates editor saves it.
        AA_Message_Template__c tpl = makeSimpleTemplate('Email', 'Custom_Manual', 's',
            '<p>Dear {{FirstName}},</p><p>Thank you.</p>');

        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);

        System.assert(r.body.contains('<p>Dear O&#39;Connor &amp; Sons &lt;script&gt;alert(1)&lt;/script&gt;&lt;b&gt;bold&lt;/b&gt;,</p><p>Thank you.</p>'),
            'the rich-text template stays HTML and the value is escaped exactly once (escapeHtml4): ' + r.body);
        System.assert(!r.body.contains('<script>') && !r.body.contains('<b>bold</b>'),
            'INJECTION - a client value rendered as live markup: ' + r.body);
        System.assert(!r.body.contains('&amp;amp;') && !r.body.contains('&amp;#39;') && !r.body.contains('&amp;lt;'),
            'DOUBLE ESCAPE: ' + r.body);
    }

    @IsTest static void escape_once_advanced_email_escapes_values_once_and_neutralises_markup() {
        AA_Application__c app = makeAppNamed(HOSTILE_NAME + ' <b>bold</b>');
        AA_Message_Template__c tpl = makeTemplate('Email', 'Custom_Manual', 'Hi {{FirstName}}', '<p>Dear {{FirstName}}</p>');

        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);

        System.assertEquals('<p>Dear O&#39;Connor &amp; Sons &lt;b&gt;bold&lt;/b&gt;</p>', r.body,
            'Advanced has no later escape pass, so the values are escaped here, once');
        System.assertEquals('Hi O\'Connor & Sons <b>bold</b>', r.subject, 'the subject stays raw');
    }

    @IsTest static void escape_once_sms_and_subject_keep_the_raw_characters() {
        AA_Application__c app = makeAppNamed(HOSTILE_NAME);
        AA_Message_Template__c smsSimple   = makeSimpleTemplate('SMS', 'Custom_Manual', null, 'Hi {{FirstName}}');
        AA_Message_Template__c smsAdvanced = makeTemplate('SMS', 'Custom_Manual', null, 'Hi {{FirstName}}');
        AA_Message_Template__c email       = makeSimpleTemplate('Email', 'Custom_Manual', 'Re: {{FirstName}}', 'x');

        Test.startTest();
        AA_MessageDispatcher.Rendered a = AA_MessageDispatcher.render(smsSimple.Id, app.Id);
        AA_MessageDispatcher.Rendered b = AA_MessageDispatcher.render(smsAdvanced.Id, app.Id);
        AA_MessageDispatcher.Rendered e = AA_MessageDispatcher.render(email.Id, app.Id);
        Test.stopTest();

        System.assertEquals('Hi O\'Connor & Sons', a.body,    'a Simple SMS is plain text: no entities');
        System.assertEquals('Hi O\'Connor & Sons', b.body,    'an Advanced SMS is plain text: no entities');
        System.assertEquals('Re: O\'Connor & Sons', e.subject, 'the email subject is plain text: no entities');
    }

    // The mirrored EmailMessage is what the val team opens when a claimant
    // rings about an email, so pin the artefact there too, end to end.
    @IsTest static void escape_once_dispatch_simple_plain_text_email_mirrors_the_name_escaped_once() {
        AA_Application__c app = makeAppNamed(HOSTILE_NAME);
        makeSimpleTemplate('Email', 'Application_Submitted_DWP', 'Hi {{FirstName}}', 'Dear {{FirstName}}, your claim is in.');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'send must succeed: ' + log.Error_Message__c);
        System.assertEquals('Hi O\'Connor & Sons', log.Rendered_Subject__c, 'the logged subject is plain text');
        List<EmailMessage> ems = [SELECT Subject, HtmlBody FROM EmailMessage WHERE RelatedToId = :app.Id];
        System.assertEquals(1, ems.size(), 'the sent email must be mirrored');
        System.assertEquals('Hi O\'Connor & Sons', ems[0].Subject);
        System.assert(ems[0].HtmlBody.contains('Dear O\'Connor &amp; Sons, your claim is in.'),
            'the mirrored HTML must carry the name escaped once: ' + ems[0].HtmlBody);
        System.assert(!ems[0].HtmlBody.contains('&amp;amp;') && !ems[0].HtmlBody.contains('&#39;'),
            'DOUBLE ESCAPE in the mirrored email: ' + ems[0].HtmlBody);
    }

    // The HTML-vs-plain verdict lives in ONE place (AA_EmailShellRenderer) and
    // the dispatcher consumes it; pin the contract both sides depend on.
    @IsTest static void escape_once_looksLikeHtml_is_the_shared_verdict_and_the_renderer_honours_it() {
        System.assert(!AA_EmailShellRenderer.looksLikeHtml(null), 'null is not HTML');
        System.assert(!AA_EmailShellRenderer.looksLikeHtml('Dear {{FirstName}}, **welcome** & thanks'),
            'tokens, markdown and a bare & are not HTML');
        System.assert(AA_EmailShellRenderer.looksLikeHtml('<p>Dear {{FirstName}}</p>'), 'a rich-text paragraph is HTML');
        System.assert(AA_EmailShellRenderer.looksLikeHtml('x <b>y</b>'), 'any alphabetic tag counts');

        // One-arg forms auto-detect on the string itself: plain text is escaped, HTML is trusted.
        System.assertEquals('<p style="margin:0 0 12px 0;">a &amp; <strong>b</strong></p>',
            AA_EmailShellRenderer.simpleToHtml('a & **b**'));
        System.assertEquals('<p>a &amp; b</p>', AA_EmailShellRenderer.simpleToHtml('<p>a &amp; b</p>'));
        System.assert(AA_EmailShellRenderer.wrap('a & b').contains('<p style="margin:0 0 12px 0;">a &amp; b</p>'),
            'wrap(String) keeps auto-detect for preview callers');
        // A supplied verdict wins over the string's own shape: the same tagged
        // string, declared plain, is escaped - this is what keeps a raw client
        // value from choosing the pipeline.
        System.assertEquals('<p style="margin:0 0 12px 0;">&lt;p&gt;a &amp; b&lt;/p&gt;</p>',
            AA_EmailShellRenderer.simpleToHtml('<p>a & b</p>', false));
        System.assert(AA_EmailShellRenderer.wrap('<b>x</b>', false).contains('&lt;b&gt;x&lt;/b&gt;'),
            'wrap(String, false) must escape even content that looks like HTML');
        System.assertEquals('<b>x</b>', AA_EmailShellRenderer.simpleToHtml('<b>x</b>', true),
            'simpleToHtml(String, true) must trust the (already pre-escaped) content');
    }

    @IsTest static void render_rejects_null_ids() {
        AA_Application__c app = makeApp('a@b.com', null);
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Custom_Manual', null, 'x');
        Boolean noTemplate = false, noApp = false;
        try { AA_MessageDispatcher.render(null, app.Id); } catch (AuraHandledException e) { noTemplate = true; }
        try { AA_MessageDispatcher.render(tpl.Id, null); } catch (AuraHandledException e) { noApp = true; }
        System.assert(noTemplate && noApp, 'render must reject a null templateId or appId');
    }

    @IsTest static void friendlyDocTitle_builds_the_org_file_naming_convention() {
        AA_Application__c app = makeApp('a@b.com', null);
        app.First_Name__c = ' Alice ';
        app.Last_Name__c  = 'Test';
        System.assertEquals(app.Name + '_Alice_Test_Welcome Guide', AA_MessageDispatcher.friendlyDocTitle(app, 'AA_Welcome_Guide'),
            'AA_ prefix dropped, underscores become spaces, names trimmed');
        System.assertEquals(app.Name + '_Alice_Test_Custom Doc', AA_MessageDispatcher.friendlyDocTitle(app, 'Custom Doc'),
            'non-AA_ titles are kept as-is');
        System.assertEquals('AA_Mandate', AA_MessageDispatcher.friendlyDocTitle(null, 'AA_Mandate'), 'no app → raw title');
        System.assertEquals(null, AA_MessageDispatcher.friendlyDocTitle(app, null), 'a blank title is returned unchanged');
    }

    // ─── dispatch: email happy path ─────────────────────────────────

    @IsTest static void dispatch_email_writes_sent_log() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Application_Submitted_DWP',
            'Welcome {{FirstName}}', 'Hi {{FullName}}');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        Id appId = app.Id;
        List<AA_Message_Send_Log__c> logs = [
            SELECT Status__c, Channel__c, Rendered_Subject__c, Application__c, Template__c, External_Id__c
              FROM AA_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size(), 'One log row expected');
        System.assertEquals('Sent',                  logs[0].Status__c);
        System.assertEquals('Email',                 logs[0].Channel__c);
        System.assertEquals('recipient@example.com', logs[0].External_Id__c);
        System.assertEquals('Welcome Alice',         logs[0].Rendered_Subject__c);
    }

    // ─── dispatch: dedup skip ───────────────────────────────────────

    @IsTest static void dispatch_dedups_within_window() {
        AA_Application__c app = makeApp('r@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created', 'x', 'y');

        insert new AA_Message_Send_Log__c(
            Template__c    = tpl.Id,
            Application__c = app.Id,
            Channel__c     = 'Email',
            Status__c      = 'Sent',
            Sent_At__c     = Datetime.now().addMinutes(-30)
        );

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<AA_Message_Send_Log__c> skipped = [
            SELECT Status__c FROM AA_Message_Send_Log__c
             WHERE Application__c = :appId AND Status__c = 'Skipped-Deduped'];
        System.assertEquals(1, skipped.size(), 'A Skipped-Deduped row should be written');
    }

    // ─── dispatch: blank email → Failed row ─────────────────────────

    @IsTest static void dispatch_email_missing_recipient_logs_failed() {
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('Email', 'Intake_Created', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<AA_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM AA_Message_Send_Log__c
             WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failed', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('Email__c'),
            'Error should mention missing Email__c: ' + logs[0].Error_Message__c);
    }

    // ─── dispatch: unknown-token → Failed (production path) ─────────

    @IsTest static void dispatch_unknown_token_logs_failed() {
        AA_Application__c app = makeApp('a@b.com', null);
        makeTemplate('Email', 'Intake_Created', 's', 'Hi {{NotAToken}}');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<AA_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM AA_Message_Send_Log__c
             WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failed', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('NotAToken'),
            'Error should mention the bad token: ' + logs[0].Error_Message__c);
    }

    // ─── dispatch: SMS happy path with mocked Twilio ────────────────

    @IsTest static void dispatch_sms_uses_twilio_and_logs_sent() {
        seedTwilioCreds();
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}} ref {{ApplicationRef}}');

        Test.setMock(HttpCalloutMock.class, new TwilioOkMock());
        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<AA_Message_Send_Log__c> logs = [
            SELECT Status__c, External_Id__c
              FROM AA_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Sent',                                   logs[0].Status__c);
        System.assertEquals('SMtestx000000000000000000000000001',     logs[0].External_Id__c);
    }

    // ─── dispatch: unknown trigger event → no-op ────────────────────

    @IsTest static void dispatch_unknown_event_writes_nothing() {
        AA_Application__c app = makeApp('a@b.com', null);
        makeTemplate('Email', 'Intake_Created', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Nonexistent_Event_XYZ');
        Test.stopTest();

        Id appId = app.Id;
        Integer n = [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(0, n, 'No templates matched; no logs expected');
    }

    // ─── dispatch: null args → no-op ────────────────────────────────

    @IsTest static void dispatch_null_inputs_are_safe() {
        AA_Application__c app = makeApp('a@b.com', null);
        System.assertEquals(null, AA_MessageDispatcher.dispatch((Id) null, 'x'));
        System.assertEquals(null, AA_MessageDispatcher.dispatch(new Set<Id>(), 'x'));
        System.assertEquals(null, AA_MessageDispatcher.dispatch(new Set<Id>{ app.Id }, null));
    }

    // ─── dispatch: static-resource attachment → email + Files + mirror ──

    @IsTest static void dispatch_email_attaches_static_pdf_and_files_it_on_the_app_and_the_mirror() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Application_Submitted_DWP', 'Docs {{FirstName}}', 'Hi {{FullName}}');
        tpl.Attachment_Static_Resource_Name__c = 'AA_Welcome_Guide, AA_Welcome_Guide'; // duplicate + space: must attach once
        update tpl;

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'an email with a static attachment must send: ' + log.Error_Message__c);
        System.assertEquals(null, log.Error_Message__c, 'a present static resource must not be reported missing');

        String friendly = AA_MessageDispatcher.friendlyDocTitle(app, 'AA_Welcome_Guide');
        System.assertEquals(app.Name + '_Alice_Test_Welcome Guide', friendly);
        List<ContentDocumentLink> onApp = [
            SELECT ContentDocumentId FROM ContentDocumentLink
             WHERE LinkedEntityId = :app.Id AND ContentDocument.Title = :friendly];
        System.assertEquals(1, onApp.size(), 'the static PDF must be materialised ONCE into the application\'s Files under its friendly title');

        List<EmailMessage> ems = mirrored(app.Id);
        System.assertEquals(1, ems.size(), 'the sent email must be mirrored as an EmailMessage on the application');
        System.assertEquals('Docs Alice', ems[0].Subject);
        System.assertEquals('3', ems[0].Status, 'the mirror must end up Sent (3) after the attachments are linked');
        System.assert(docsLinkedTo(ems[0].Id).contains(onApp[0].ContentDocumentId), 'the mirror EmailMessage must link the attached PDF');
    }

    @IsTest static void dispatch_email_reuses_an_existing_friendly_titled_file_instead_of_duplicating() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');
        tpl.Attachment_Static_Resource_Name__c = 'AA_Welcome_Guide';
        update tpl;
        String friendly = AA_MessageDispatcher.friendlyDocTitle(app, 'AA_Welcome_Guide');
        ContentVersion existing = addAppFile(app.Id, friendly, friendly + '.pdf'); // a previous send already filed it

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        System.assertEquals('Sent', soleLog(app.Id).Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :app.Id AND ContentDocument.Title = :friendly],
            'a later send must reuse the file already on the application, not create a duplicate');
        List<EmailMessage> ems = mirrored(app.Id);
        System.assertEquals(1, ems.size());
        System.assert(docsLinkedTo(ems[0].Id).contains(existing.ContentDocumentId), 'the mirror must link the pre-existing document');
    }

    // ─── dispatch: per-app file attachment (Attach_App_File_Titles__c) ──

    @IsTest static void dispatch_email_attaches_the_apps_own_file_by_friendly_title() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'DD_Mandate_Confirmed', 'Mandate {{MandateId}}', 'b');
        tpl.Attach_App_File_Titles__c = 'AA_Mandate';
        update tpl;
        String friendly = AA_MessageDispatcher.friendlyDocTitle(app, 'AA_Mandate');
        System.assertEquals(app.Name + '_Alice_Test_Mandate', friendly, 'AA_ prefix stripped, underscores to spaces');
        ContentVersion mandate = addAppFile(app.Id, friendly, 'mandate.pdf');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'DD_Mandate_Confirmed');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'the per-app PDF was present, so the email must send: ' + log.Error_Message__c);
        System.assertEquals(null, log.Error_Message__c, 'no attachment may be reported missing');
        List<EmailMessage> ems = mirrored(app.Id);
        System.assertEquals(1, ems.size());
        System.assert(docsLinkedTo(ems[0].Id).contains(mandate.ContentDocumentId), 'the mirror must link the application\'s own PDF');
    }

    // Fernando's rule (2026-08-18): never ship an email whose per-app PDF has
    // not landed yet. The 'Skipped-Missing-Attachment' row, the held SMS and
    // the ops alert are pinned by held_email_holds_the_same_event_sms_and_alerts_ops;
    // the re-send once the file lands by AA_WelcomePackWatchdogTest. This
    // test pins the core guarantee: no email goes out.
    @IsTest static void dispatch_email_with_missing_per_app_file_does_not_send() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'DD_Mandate_Confirmed', 's', 'b');
        tpl.Attach_App_File_Titles__c = 'AA_Mandate';
        update tpl;

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'DD_Mandate_Confirmed');
        Test.stopTest();

        System.assertEquals(0, mirrored(app.Id).size(), 'an email missing its per-app PDF must NOT be sent');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :app.Id AND Status__c = 'Sent'],
            'no Sent log may be written for a skipped email');
    }

    // A missing STATIC resource is a config error, not a race: the email still
    // ships and the gap is recorded on the log.
    @IsTest static void dispatch_email_with_missing_static_resource_still_sends_and_records_it() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');
        tpl.Attachment_Static_Resource_Name__c = 'AA_Does_Not_Exist';
        update tpl;

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'a missing static resource must not block the send');
        System.assertEquals('Attachment(s) not found: static:AA_Does_Not_Exist', log.Error_Message__c, 'the missing resource must be recorded');
        System.assertEquals(1, mirrored(app.Id).size(), 'the email still goes out and is mirrored');
    }

    // ─── dispatch: Simple email goes out as HTML with a text fallback ──

    @IsTest static void dispatch_simple_email_sends_html_with_a_plain_text_fallback() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        insert new AA_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Application_Submitted_DWP',
            Active__c = true, Subject_Template__c = 'Hi {{FirstName}}', Content_Mode__c = 'Simple',
            Content_Text__c = 'Hello **{{FirstName}}**, your ref is {{ApplicationRef}}.', Body_Template__c = 'mirror');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        System.assertEquals('Sent', soleLog(app.Id).Status__c);
        List<EmailMessage> ems = [SELECT HtmlBody, TextBody FROM EmailMessage WHERE RelatedToId = :app.Id];
        System.assertEquals(1, ems.size(), 'the sent email must be mirrored');
        System.assert(ems[0].HtmlBody != null && ems[0].HtmlBody.startsWith('<!DOCTYPE html>'),
            'a Simple email must go out as the HTML shell, not plain text');
        System.assert(ems[0].HtmlBody.contains('<strong>Alice</strong>'), '**bold** markdown must become <strong>: ' + ems[0].HtmlBody);
        System.assert(ems[0].TextBody != null && !ems[0].TextBody.contains('<'),
            'the plain-text fallback must have every tag stripped: ' + ems[0].TextBody);
        System.assert(ems[0].TextBody.contains('your ref is ' + app.Name), 'the plain-text fallback must keep the merged words: ' + ems[0].TextBody);
    }

    // ─── dispatch: helper CC + bulk (two apps, one Queueable) ────────

    @IsTest static void dispatch_ccs_helper_unless_it_is_the_clients_own_address() {
        AA_Application__c withHelper = makeApp('client1@example.com', null);
        withHelper.Helper_Email__c = 'helper@example.com';
        AA_Application__c sameAddress = makeApp('client2@example.com', null);
        sameAddress.Helper_Email__c = 'CLIENT2@example.com';
        update new List<AA_Application__c>{ withHelper, sameAddress };
        makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(new Set<Id>{ withHelper.Id, sameAddress.Id }, 'Application_Submitted_DWP');
        Test.stopTest();

        System.assertEquals('Sent', soleLog(withHelper.Id).Status__c);
        System.assertEquals('Sent', soleLog(sameAddress.Id).Status__c, 'a bulk dispatch must write one log per application');
        List<EmailMessage> a = mirrored(withHelper.Id);
        List<EmailMessage> b = mirrored(sameAddress.Id);
        System.assertEquals(1, a.size());
        System.assertEquals(1, b.size());
        System.assertEquals('helper@example.com', a[0].CcAddress, 'the designated helper must be CC\'d');
        System.assertEquals('client1@example.com', a[0].ToAddress);
        System.assertEquals(null, b[0].CcAddress, 'a helper address equal to the client\'s own (any case) must not be CC\'d');
    }

    // ─── dispatch: SMS failure branches ─────────────────────────────

    @IsTest static void dispatch_sms_without_twilio_credentials_logs_failed() {
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}}');
        Test.setMock(HttpCalloutMock.class, new TwilioDownMock()); // must never be reached

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Failed', log.Status__c);
        System.assert(log.Error_Message__c.contains('credentials'), 'the log must say the Twilio credentials are missing: ' + log.Error_Message__c);
        System.assertEquals(0, twilioRows(app.Id), 'no TwilioSF mirror row without a send');
    }

    @IsTest static void dispatch_sms_http_error_logs_failed_with_status() {
        seedTwilioCreds();
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}}');
        Test.setMock(HttpCalloutMock.class, new TwilioStatusMock(400, '{"code":21211,"message":"Invalid To number"}'));

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Failed', log.Status__c);
        System.assert(log.Error_Message__c.startsWith('Twilio: HTTP 400'), 'the status code must be recorded: ' + log.Error_Message__c);
        System.assert(log.Error_Message__c.contains('21211'), 'the Twilio body must be recorded for diagnosis');
        System.assertEquals(0, twilioRows(app.Id), 'no TwilioSF mirror row for a failed send');
    }

    @IsTest static void dispatch_sms_non_json_response_logs_failed() {
        seedTwilioCreds();
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi');
        Test.setMock(HttpCalloutMock.class, new TwilioStatusMock(201, '<html>gateway</html>'));

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Failed', log.Status__c, 'a 2xx without a JSON body must not count as sent');
        System.assert(log.Error_Message__c.contains('non-JSON'), log.Error_Message__c);
        System.assertEquals(null, log.External_Id__c, 'no SID without a parsable response');
    }

    @IsTest static void dispatch_sms_unreachable_twilio_logs_failed() {
        seedTwilioCreds();
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi');
        Test.setMock(HttpCalloutMock.class, new TwilioDownMock());

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Failed', log.Status__c, 'a callout exception must become a Failed log, not an aborted Queueable');
        System.assert(log.Error_Message__c.contains('unreachable'), log.Error_Message__c);
    }

    @IsTest static void dispatch_sms_missing_phone_logs_failed() {
        seedTwilioCreds();
        AA_Application__c app = makeApp('a@b.com', null);
        makeTemplate('SMS', 'Intake_Created', null, 'Hi');
        Test.setMock(HttpCalloutMock.class, new TwilioDownMock()); // must never be reached

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Failed', log.Status__c);
        System.assert(log.Error_Message__c.contains('Phone__c'), 'the log must name the missing field: ' + log.Error_Message__c);
    }

    @IsTest static void dispatch_sms_success_mirrors_a_twilio_row() {
        seedTwilioCreds();
        AA_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}}');
        Test.setMock(HttpCalloutMock.class, new TwilioOkMock());

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        List<TwilioSF__Message__c> rows = [
            SELECT TwilioSF__Message_SID__c, TwilioSF__To_Number__c, TwilioSF__Body__c, TwilioSF__Direction__c
              FROM TwilioSF__Message__c WHERE TwilioSF__SF_Parent_Record_Id__c = :String.valueOf(app.Id)];
        System.assertEquals(1, rows.size(), 'a sent SMS must be mirrored into TwilioSF__Message__c for the conversation view');
        System.assertEquals('SMtestx000000000000000000000000001', rows[0].TwilioSF__Message_SID__c);
        System.assertEquals('+441234567890', rows[0].TwilioSF__To_Number__c);
        System.assertEquals('Hi Alice', rows[0].TwilioSF__Body__c, 'the mirrored body is the rendered text');
        System.assertEquals('outbound-api', rows[0].TwilioSF__Direction__c);
    }

    // ═══════════════ audit 2026-10-02 (comms cluster) ═══════════════

    // F77: an Advanced (Body_Template__c) email whose body is plain text used
    // to go out as text/plain with HTML-escaped values and literal ** markers.
    @IsTest static void advanced_plain_text_email_is_wrapped_and_escaped_once() {
        AA_Application__c app = makeAppNamed(HOSTILE_NAME);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Application_Submitted_DWP', 's',
            'Hello **{{FirstName}}**,\n\nWe have submitted your application.');

        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(tpl.Id, app.Id);

        System.assert(r.body.startsWith('<!DOCTYPE html>'), 'must be wrapped in the AA_Email_Shell: ' + r.body.left(80));
        System.assert(r.body.contains('<strong>O\'Connor &amp; Sons</strong>'), '**bold** works and the name is escaped once: ' + r.body);
        System.assert(!r.body.contains('**') && !r.body.contains('&#39;') && !r.body.contains('&amp;amp;'), r.body);
    }

    // F54/F70: a Do Not Contact client gets no automated message...
    @IsTest static void do_not_contact_suppresses_client_messages_with_a_log() {
        AA_Application__c app = makeApp('recipient@example.com', '+441234567890');
        app.Do_Not_Contact__c = true;
        update app;
        makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertNotEquals('Sent', log.Status__c);
        System.assert(log.Error_Message__c.startsWith('Suppressed: Do_Not_Contact__c'), log.Error_Message__c);
        System.assertEquals(0, mirrored(app.Id).size(), 'no email may go to a Do Not Contact client');
    }

    // ...not even the Bacs advance notice. Owner decision 2026-10-02: Do Not
    // Contact pauses fee collection, so there is no collection to announce and
    // the old Bacs exception went. Stage 'Awarded' so the stage gate is not
    // what stops it.
    @IsTest static void do_not_contact_gets_no_bacs_advance_notice_either() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        app.Do_Not_Contact__c = true;
        app.Stage__c = 'Awarded';
        update app;
        makeTemplate('Email', 'Bacs_Advance_Notice', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Bacs_Advance_Notice');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertNotEquals('Sent', log.Status__c, 'a Do Not Contact client gets no automated message of any kind');
        System.assert(log.Error_Message__c.startsWith('Suppressed: Do_Not_Contact__c'), log.Error_Message__c);
        System.assertEquals(0, mirrored(app.Id).size());
    }

    // ─── stage gates (owner decision 2026-10-02) ────────────────────

    // A refused claim never gets a fee, Bacs or Direct Debit message, whatever
    // sends it.
    @IsTest static void money_messages_are_blocked_once_the_claim_is_refused() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        app.Stage__c = 'Closed - Refused';
        update app;
        makeTemplate('Email', 'Bacs_Advance_Notice', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Bacs_Advance_Notice');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertNotEquals('Sent', log.Status__c);
        System.assert(log.Error_Message__c.startsWith('Suppressed: Bacs_Advance_Notice'), log.Error_Message__c);
        System.assertEquals(0, mirrored(app.Id).size(), 'no Bacs notice may go to a refused client');
    }

    // The allow-lists themselves: a fee is only noticed post-award; the final
    // receipt still goes after the case closes as paid; Direct Debit messages
    // go while the claim is open, never after a refusal; unknown stages block.
    @IsTest static void stage_allow_lists_follow_the_stage_model() {
        Map<String, Set<String>> a = AA_MessageDispatcher.ALLOWED_STAGES;
        Set<String> collection = a.get(AA_MessageDispatcher.CATEGORY_BY_EVENT.get('Bacs_Advance_Notice'));
        System.assert(collection.contains('Awarded') && collection.contains('Fee Charged'));
        System.assert(!collection.contains('New') && !collection.contains('Closed - Refused')
            && !collection.contains('Closed - Paid') && !collection.contains('DD Chargeback'), String.valueOf(collection));
        Set<String> outcome = a.get(AA_MessageDispatcher.CATEGORY_BY_EVENT.get('Fee_Receipt'));
        System.assert(outcome.contains('Closed - Paid') && !outcome.contains('Closed - Refused'));
        Set<String> dd = a.get(AA_MessageDispatcher.CATEGORY_BY_EVENT.get('DD_Mandate_Confirmed'));
        System.assert(dd.contains('Awaiting First Call') && dd.contains('Awarded') && !dd.contains('Closed - Refused'));
        System.assertEquals(dd, a.get(AA_MessageDispatcher.CATEGORY_BY_EVENT.get('Intake_Created')),
            'the welcome pack carries the mandate, so it is gated like a Direct Debit message');
        for (String cat : a.keySet()) {
            System.assert(!a.get(cat).contains(null), cat + ' must not allow a blank stage');
        }
        System.assertEquals(null, AA_MessageDispatcher.CATEGORY_BY_EVENT.get('Call_Reminder_Morning_Of'), 'non-money events are not gated');
    }

    // W4-1 (wave 4): the public stage-gate helpers the fee scheduler uses so it
    // never charges in a stage where the Bacs notice is blocked. The MR stage
    // after a lower-rate award is the concrete case: no notice, so no charge.
    @IsTest static void public_stage_gate_helpers_match_the_dispatch_gate() {
        System.assert(AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', 'Awarded'));
        System.assert(AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', 'Fee Charged'));
        for (String s : new List<String>{ 'Mandatory Reconsideration Requested', 'Appeal Lodged',
                'Needs Human', 'Submitted', 'Closed - Refused', 'DD Chargeback', 'Closed - Paid', '', null }) {
            System.assert(!AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', s), 'Bacs notice must be blocked in "' + s + '"');
        }
        System.assert(AA_MessageDispatcher.stageAllows('Call_Reminder_Morning_Of', null), 'an ungated event is allowed in any stage');
        System.assertEquals(null, AA_MessageDispatcher.allowedStagesFor('Call_Reminder_Morning_Of'));

        Set<String> fee = AA_MessageDispatcher.allowedStagesFor('Bacs_Advance_Notice');
        System.assertEquals(AA_MessageDispatcher.ALLOWED_STAGES.get('FeeCollection'), fee);
        fee.add('Mandatory Reconsideration Requested');
        System.assert(!AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', 'Mandatory Reconsideration Requested'),
            'allowedStagesFor returns a copy: changing it must not widen the gate');
    }

    // The concrete case from the W4-1 finding, at dispatch level: the notice is
    // not sent in the MR stage (so the scheduler must not charge there either).
    @IsTest static void bacs_notice_is_blocked_while_a_reconsideration_is_open() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        app.Stage__c = 'Mandatory Reconsideration Requested';
        update app;
        makeTemplate('Email', 'Bacs_Advance_Notice', 's', 'b');

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Bacs_Advance_Notice');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertNotEquals('Sent', log.Status__c);
        System.assert(log.Error_Message__c.startsWith('Suppressed: Bacs_Advance_Notice'), log.Error_Message__c);
        System.assertEquals(0, mirrored(app.Id).size());
    }

    // ─── SMS opt-out (owner decision 2026-10-02) ────────────────────

    // STOP = SMS only: the SMS of the event is skipped and logged, its email
    // still goes.
    @IsTest static void sms_opt_out_skips_sms_only() {
        seedTwilioCreds();
        AA_Application__c app = makeApp('recipient@example.com', '+441234567890');
        app.SMS_Opt_Out__c = true;
        update app;
        makeTemplate('SMS', 'Application_Submitted_DWP', null, 'Hi {{FirstName}}');
        makeTemplate('Email', 'Application_Submitted_DWP', 'Submitted', 'b');
        Test.setMock(HttpCalloutMock.class, new TwilioOkMock());

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        System.assertEquals(0, twilioRows(app.Id), 'no SMS after a STOP');
        AA_Message_Send_Log__c smsLog = [SELECT Status__c, Error_Message__c FROM AA_Message_Send_Log__c
            WHERE Application__c = :app.Id AND Channel__c = 'SMS'];
        System.assertNotEquals('Sent', smsLog.Status__c);
        System.assert(smsLog.Error_Message__c.startsWith('Suppressed: SMS_Opt_Out__c'), smsLog.Error_Message__c);
        System.assertEquals(1, [SELECT COUNT() FROM AA_Message_Send_Log__c
            WHERE Application__c = :app.Id AND Channel__c = 'Email' AND Status__c = 'Sent'], 'email is not affected by STOP');
    }

    // ─── DWP decision messages on stage change (owner decision 2026-10-02) ─

    @IsTest static void moving_to_awarded_sends_the_approved_message() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        makeTemplate('Email', 'Application_Approved_by_DWP', 'Good news', 'b');

        Test.startTest();
        update new AA_Application__c(Id = app.Id, Stage__c = 'Awarded');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'send log: ' + log.Error_Message__c);
        System.assertEquals('Good news', log.Rendered_Subject__c);
    }

    @IsTest static void moving_to_closed_refused_sends_the_rejected_message() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        makeTemplate('Email', 'Application_Rejected_by_DWP', 'About your decision', 'b');
        makeTemplate('Email', 'Application_Approved_by_DWP', 'Good news', 'b');

        Test.startTest();
        update new AA_Application__c(Id = app.Id, Stage__c = 'Closed - Refused');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'send log: ' + log.Error_Message__c);
        System.assertEquals('About your decision', log.Rendered_Subject__c);
    }

    // Once per application: an award recorded again (e.g. back from a change
    // of circumstances review) does not tell the client twice, even days later.
    @IsTest static void the_approved_message_goes_once_per_application() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        app.Stage__c = 'Change of Circumstances Review';
        update app;
        AA_Message_Template__c tpl = makeTemplate('Email', 'Application_Approved_by_DWP', 'Good news', 'b');
        insert new AA_Message_Send_Log__c(Template__c = tpl.Id, Application__c = app.Id, Channel__c = 'Email',
            Status__c = 'Sent', Sent_At__c = Datetime.now().addDays(-40));

        Test.startTest();
        update new AA_Application__c(Id = app.Id, Stage__c = 'Awarded');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :app.Id AND Status__c = 'Sent'],
            'the 40-day-old Sent row must stop a second approval message');
        System.assertEquals(1, [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :app.Id AND Status__c = 'Skipped-Deduped']);
        System.assertEquals(0, mirrored(app.Id).size());
    }

    // No active template for the event: nothing is enqueued at all.
    @IsTest static void stage_outcome_without_a_template_enqueues_nothing() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        Test.startTest();
        update new AA_Application__c(Id = app.Id, Stage__c = 'Awarded');
        System.assertEquals(0, Limits.getQueueableJobs(), 'no empty dispatcher job');
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :app.Id]);
    }

    // ─── <!--if:Token--> blocks (W3-5) ───────────────────────────────

    @IsTest static void conditional_block_shows_only_when_the_token_has_a_value() {
        Map<String, String> vals = new Map<String, String>{ 'ClientFormUrl' => 'https://x.test/f?t=1', 'Empty' => '' };
        System.assertEquals('a[L]b', AA_MessageDispatcher.applyConditionals('a<!--if:ClientFormUrl-->[L]<!--endif:ClientFormUrl-->b', vals));
        System.assertEquals('ab', AA_MessageDispatcher.applyConditionals('a<!-- if:Empty -->\n[L]\n<!-- endif:Empty -->b', vals));
        System.assertEquals('no markers', AA_MessageDispatcher.applyConditionals('no markers', vals));
        Boolean threw = false;
        try { AA_MessageDispatcher.applyConditionals('<!--if:Typo-->x<!--endif:Typo-->', vals); }
        catch (AA_MessageDispatcher.RenderException e) { threw = true; }
        System.assert(threw, 'an unknown token in a condition must fail the render like resolve() does');
    }

    // The welcome's form-link paragraph disappears while the record is unsigned
    // and carries the signed link once it is.
    @IsTest static void form_link_paragraph_follows_the_signature() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created', 's',
            '<html><body><p>Hi</p><!--if:ClientFormUrl--><p><a href="{{ClientFormUrl}}">link</a></p><!--endif:ClientFormUrl--></body></html>');
        update new AA_Application__c(Id = app.Id, Signature__c = 'UNCONFIGURED');
        String unsigned = AA_MessageDispatcher.render(tpl.Id, app.Id).body;
        System.assert(!unsigned.contains('href') && unsigned.contains('<p>Hi</p>'), unsigned);

        update new AA_Application__c(Id = app.Id, Signature__c = 'sig123');
        String signed = AA_MessageDispatcher.render(tpl.Id, app.Id).body;
        System.assert(signed.contains('href="') && signed.contains('/form/client/') && signed.contains('?t=sig123'), signed);
    }

    // F73: the intro SMS ("check your email shortly") waits for its email, and
    // ops is told the email is held.
    @IsTest static void held_email_holds_the_same_event_sms_and_alerts_ops() {
        seedTwilioCreds();
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        AA_Config__c cfg = rows.isEmpty() ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId()) : new AA_Config__c(Id = rows[0].Id);
        cfg.Admin_Alert_Email__c = 'ops@example.test';
        upsert cfg;
        AA_Application__c app = makeApp('recipient@example.com', '+441234567890');
        AA_Message_Template__c sms = makeTemplate('SMS', 'Intake_Created', null, 'Check your email shortly');
        AA_Message_Template__c email = makeTemplate('Email', 'Intake_Created', 'Welcome', 'b');
        email.Attach_App_File_Titles__c = 'Mandate';
        update email;
        Test.setMock(HttpCalloutMock.class, new TwilioOkMock());

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        System.assertEquals(0, twilioRows(app.Id), 'the SMS must not go while its email is held');
        System.assertEquals(2, [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :app.Id AND Status__c = 'Skipped-Missing-Attachment'],
            'both the email and the SMS are logged as held');
        System.assertNotEquals(null, AA_HandoffService.lastOpsEmail, 'ops must be told a client email is held');
        System.assert(AA_HandoffService.lastOpsEmail.getPlainTextBody().contains(app.Name), AA_HandoffService.lastOpsEmail.getPlainTextBody());
    }

    // F73: a missing personalised Welcome Guide is replaced by the generic
    // static one instead of holding the whole welcome email.
    @IsTest static void missing_per_app_welcome_guide_falls_back_to_the_static_pdf() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        AA_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created', 'Welcome', 'b');
        tpl.Attach_App_File_Titles__c = 'Welcome Guide';
        update tpl;

        Test.startTest();
        AA_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'the generic Welcome Guide must stand in: ' + log.Error_Message__c);
        System.assert(log.Error_Message__c.contains('fallback-static:AA_Welcome_Guide'), log.Error_Message__c);
        System.assertEquals('AA_Welcome_Guide', AA_MessageDispatcher.staticFallbackName('Welcome Guide'));
        System.assertEquals('AA_Mandate', AA_MessageDispatcher.staticFallbackName('AA_Mandate'));

        // W2 review of F73: the generic PDF must not pose as the personalised
        // one. It is filed as "<AppName>_Welcome Guide (general copy)", never
        // under the personal title, which loadAppFiles and the watchdog's
        // readiness check would otherwise take for the real per-app render.
        String personal = AA_MessageDispatcher.friendlyDocTitle(app, 'Welcome Guide');
        String general  = app.Name + '_Welcome Guide (general copy)';
        System.assertEquals(0, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :app.Id AND ContentDocument.Title = :personal],
            'the generic copy must not be filed under the personalised title');
        List<ContentDocumentLink> onApp = [SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id AND ContentDocument.Title = :general];
        System.assertEquals(1, onApp.size(), 'the generic copy is filed once, marked as a general copy');
        List<EmailMessage> ems = mirrored(app.Id);
        System.assertEquals(1, ems.size());
        System.assert(docsLinkedTo(ems[0].Id).contains(onApp[0].ContentDocumentId), 'the mirror links the general copy that went out');
    }

    // W2 review of F73: the client sees a generic file name for a stand-in.
    @IsTest static void fallback_file_name_is_generic() {
        System.assertEquals('XtraPension Service Agreement.pdf', AA_MessageDispatcher.fallbackFileName('Service Agreement'));
        System.assertEquals('XtraPension Welcome Guide.pdf', AA_MessageDispatcher.fallbackFileName('AA_Welcome_Guide'));
        AA_Application__c app = makeApp('a@b.com', null);
        System.assertEquals(app.Name + '_Service Agreement (general copy)',
            AA_MessageDispatcher.staticCvTitle(app, AA_MessageDispatcher.FALLBACK_MARK + 'AA_Service_Agreement'));
        System.assertEquals(AA_MessageDispatcher.friendlyDocTitle(app, 'AA_Service_Agreement'),
            AA_MessageDispatcher.staticCvTitle(app, 'AA_Service_Agreement'), 'a configured static keeps its personal title');
    }

    // F74: the sender is the clients@ Org-Wide Email Address when it exists.
    @IsTest static void clients_owea_is_looked_up_by_address() {
        List<OrgWideEmailAddress> o = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :AA_MessageDispatcher.CLIENT_FROM_ADDRESS LIMIT 1];
        System.assertEquals(o.isEmpty() ? null : o[0].Id, AA_MessageDispatcher.loadClientsOwea());
    }

    // F71: a call moved EARLIER must be the one the reminder states.
    @IsTest static void call_tokens_prefer_the_next_pending_slot_over_a_later_cancelled_one() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        Datetime oldSlot = Datetime.now().addDays(3);
        AA_Call_Schedule__c old = new AA_Call_Schedule__c(Application__c = app.Id, Scheduled_At__c = oldSlot, Status__c = 'Pending');
        insert old;
        update new AA_Call_Schedule__c(Id = old.Id, Status__c = 'Cancelled', Cancelled_At__c = Datetime.now());
        Datetime newSlot = Datetime.now().addDays(1);
        insert new AA_Call_Schedule__c(Application__c = app.Id, Scheduled_At__c = newSlot, Status__c = 'Pending');

        Map<Id, Datetime> m = AA_MessageDispatcher.loadLatestCalls(new Set<Id>{ app.Id });
        System.assertEquals(newSlot, m.get(app.Id), 'the rescheduled (earlier) Pending call must win over the cancelled later one');
    }

    // F179: {{ClientFormUrl}} is the signed link, blank while unsigned.
    @IsTest static void client_form_url_token_is_blank_until_signed() {
        AA_Application__c app = makeApp('a@b.com', '+441234567890');
        AA_Message_Template__c tpl = makeTemplate('SMS', 'Custom_Manual', null, '[{{ClientFormUrl}}]');
        update new AA_Application__c(Id = app.Id, Signature__c = 'UNCONFIGURED');
        System.assertEquals('[]', AA_MessageDispatcher.render(tpl.Id, app.Id).body, 'an unsigned link must never be sent');

        update new AA_Application__c(Id = app.Id, Signature__c = 'sig123');
        String body = AA_MessageDispatcher.render(tpl.Id, app.Id).body;
        System.assert(body.contains('/form/client/') && body.contains('?t=sig123'), body);
    }

    // ─── dispatch from a @future runs inline (no nested enqueue) ─────

    @IsTest static void dispatch_from_future_context_runs_inline() {
        AA_Application__c app = makeApp('recipient@example.com', null);
        // Fee_Charged is stage-gated (owner decision 2026-10-02): post-award only.
        update new AA_Application__c(Id = app.Id, Stage__c = 'Fee Charged');
        makeTemplate('Email', 'Fee_Charged', 'Fee {{FirstName}}', 'b');

        Test.startTest();
        dispatchFromFuture(app.Id, 'Fee_Charged');
        Test.stopTest();

        AA_Message_Send_Log__c log = soleLog(app.Id);
        System.assertEquals('Sent', log.Status__c, 'a dispatch from @future must run the send inline (an enqueue is illegal there)');
        System.assertEquals('Fee Alice', log.Rendered_Subject__c);
    }
}