/**
 * Tests for PC1_MessageDispatcher (B3). HttpCalloutMock for Twilio and
 * Test.startTest/stopTest to force the Queueable to run.
 *
 * Coverage: render happy path, render unknown-token throw, dispatch email
 * happy path, dispatch dedup skip, blank recipient → Failed, unknown token
 * inside dispatch → Failed, SMS mocked → Sent, unknown-event → no-op.
 */
@IsTest
private class PC1_MessageDispatcherTest {

    // Audit R6 H11 — must-not-be-called mock. Any HTTP callout inside the
    // opt-out path proves the gate failed. Test-fails immediately.
    private class TwilioForbiddenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assert(false, 'SMS opt-out gate failed — Twilio was called for opted-out app');
            return null;
        }
    }

    // Twilio 201 Created shape.
    private class TwilioOkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(201);
            r.setHeader('Content-Type', 'application/json');
            r.setBody('{"sid":"SMtestx000000000000000000000000001",'
                    + '"status":"queued","to":"+441234567890",'
                    + '"from":"+447476907490","body":"hi"}');
            return r;
        }
    }

    private static void seedTwilioCreds() {
        insert new XtraPension_Data__c(
            SetupOwnerId       = UserInfo.getOrganizationId(),
            Twilio_Account__c  = 'ACtestaccount',
            Twilio_Token__c    = 'testtoken'
        );
    }

    private static PC1_Application__c makeApp(String email, String phone) {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Alice',
            Last_Name__c  = 'Test',
            Stage__c      = 'New',
            Email__c      = email,
            Phone__c      = phone
        );
        insert a;
        // Re-query: Name is an auto-number the DB assigns on insert, and the
        // in-memory sObject never learns it. Without this the ApplicationRef
        // assertion compared against "Ref null" and failed for a test reason.
        return [SELECT Id, Name, First_Name__c, Last_Name__c, Email__c, Phone__c
                  FROM PC1_Application__c WHERE Id = :a.Id];
    }

    private static PC1_Message_Template__c makeTemplate(
            String channel, String triggerEvent, String subject, String body) {
        PC1_Message_Template__c t = new PC1_Message_Template__c(
            Channel__c              = channel,
            Trigger_Event__c        = triggerEvent,
            Active__c               = true,
            Subject_Template__c     = subject,
            Body_Template__c        = body
        );
        insert t;
        return t;
    }

    // ─── render ─────────────────────────────────────────────────────

    @IsTest static void render_resolves_known_tokens() {
        PC1_Application__c app = makeApp('a@b.com', '+441234567890');
        PC1_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created',
            'Hi {{FirstName}}', 'Ref {{ApplicationRef}} — issued {{IssueDate}}.');

        Test.startTest();
        PC1_MessageDispatcher.Rendered r =
            PC1_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assertEquals('Hi Alice', r.subject);
        System.assert(r.body.contains('Ref ' + app.Name), 'ApplicationRef fill: ' + r.body);
        System.assert(r.body.contains('issued '),         'IssueDate fill: ' + r.body);
        System.assert(!r.body.contains('{{'),             'No unresolved tokens: ' + r.body);
    }

    @IsTest static void render_unknown_token_throws() {
        PC1_Application__c app = makeApp('a@b.com', '+441234567890');
        PC1_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created',
            'x', 'Hello {{NopeToken}}');

        Boolean threw = false;
        try {
            Test.startTest();
            PC1_MessageDispatcher.render(tpl.Id, app.Id);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Unknown token must throw AuraHandledException');
    }

    // ─── dispatch: email happy path ─────────────────────────────────

    @IsTest static void dispatch_email_writes_sent_log() {
        PC1_Application__c app = makeApp('recipient@example.com', null);
        PC1_Message_Template__c tpl = makeTemplate('Email', 'Application_Submitted_DWP',
            'Welcome {{FirstName}}', 'Hi {{FullName}}');

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Channel__c, Rendered_Subject__c, Application__c, Template__c, External_Id__c
              FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size(), 'One log row expected');
        System.assertEquals('Sent',                  logs[0].Status__c);
        System.assertEquals('Email',                 logs[0].Channel__c);
        System.assertEquals('recipient@example.com', logs[0].External_Id__c);
        System.assertEquals('Welcome Alice',         logs[0].Rendered_Subject__c);
    }

    // ─── dispatch: dedup skip ───────────────────────────────────────

    @IsTest static void dispatch_dedups_within_window() {
        PC1_Application__c app = makeApp('r@example.com', null);
        PC1_Message_Template__c tpl = makeTemplate('Email', 'Intake_Created', 'x', 'y');

        insert new PC1_Message_Send_Log__c(
            Template__c    = tpl.Id,
            Application__c = app.Id,
            Channel__c     = 'Email',
            Status__c      = 'Sent',
            Sent_At__c     = Datetime.now().addMinutes(-30)
        );

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> skipped = [
            SELECT Status__c FROM PC1_Message_Send_Log__c
             WHERE Application__c = :appId AND Status__c = 'Skipped-Deduped'];
        System.assertEquals(1, skipped.size(), 'A Skipped-Deduped row should be written');
    }

    // ─── dispatch: blank email → Failed row ─────────────────────────

    @IsTest static void dispatch_email_missing_recipient_logs_failed() {
        PC1_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('Email', 'Intake_Created', 's', 'b');

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c
             WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failed', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('Email__c'),
            'Error should mention missing Email__c: ' + logs[0].Error_Message__c);
    }

    // ─── dispatch: unknown-token → Failed (production path) ─────────

    @IsTest static void dispatch_unknown_token_logs_failed() {
        PC1_Application__c app = makeApp('a@b.com', null);
        makeTemplate('Email', 'Intake_Created', 's', 'Hi {{NotAToken}}');

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c
             WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failed', logs[0].Status__c);
        System.assert(logs[0].Error_Message__c.contains('NotAToken'),
            'Error should mention the bad token: ' + logs[0].Error_Message__c);
    }

    // ─── dispatch: SMS happy path with mocked Twilio ────────────────

    @IsTest static void dispatch_sms_uses_twilio_and_logs_sent() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp(null, '+441234567890');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}} ref {{ApplicationRef}}');

        Test.setMock(HttpCalloutMock.class, new TwilioOkMock());
        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, External_Id__c
              FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Sent',                                   logs[0].Status__c);
        System.assertEquals('SMtestx000000000000000000000000001',     logs[0].External_Id__c);
    }

    // ─── dispatch: SMS opt-out path (audit R6 H11) ──────────────────
    // Root cause of H11 was "PECR gate added without a test" — Status__c
    // 'Skipped' was written to the restricted picklist causing DML error.
    // This test guards against that class recurring: (a) no Twilio callout
    // is made; (b) the send-log Status__c is exactly 'Skipped-OptOut'
    // (a value that must exist in the picklist); (c) Error_Message__c
    // names the reason so ops can see why nothing was sent.

    @IsTest static void dispatch_sms_skipped_when_opt_out_true() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp(null, '+441234567890');
        app.SMS_OptOut__c = true;
        app.SMS_OptOut_At__c = Datetime.now();
        update app;
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}}');

        // Mock that FAILS if called — an opted-out send must never hit Twilio.
        Test.setMock(HttpCalloutMock.class, new TwilioForbiddenMock());

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c
              FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size(), 'One send-log expected (Skipped-OptOut path)');
        System.assertEquals('Skipped-OptOut', logs[0].Status__c,
            'Status__c must be the exact picklist value — not "Skipped" (which would DML-fail)');
        System.assert(logs[0].Error_Message__c != null && logs[0].Error_Message__c.contains('SMS_OptOut'),
            'Error_Message__c must explain the block: ' + logs[0].Error_Message__c);
    }

    // ─── dispatch: unknown trigger event → no-op ────────────────────

    @IsTest static void dispatch_unknown_event_writes_nothing() {
        PC1_Application__c app = makeApp('a@b.com', null);
        makeTemplate('Email', 'Intake_Created', 's', 'b');

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Nonexistent_Event_XYZ');
        Test.stopTest();

        Id appId = app.Id;
        Integer n = [SELECT COUNT() FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(0, n, 'No templates matched; no logs expected');
    }

    // ─── dispatch: null args → no-op ────────────────────────────────

    @IsTest static void dispatch_null_inputs_are_safe() {
        PC1_Application__c app = makeApp('a@b.com', null);
        System.assertEquals(null, PC1_MessageDispatcher.dispatch((Id) null, 'x'));
        System.assertEquals(null, PC1_MessageDispatcher.dispatch(new Set<Id>(), 'x'));
        System.assertEquals(null, PC1_MessageDispatcher.dispatch(new Set<Id>{ app.Id }, null));
    }

    // ─── fee tokens (2026-10-02) ────────────────────────────────────
    // Until 2026-10-02 {{FeeAmount}} was a hardcoded placeholder, so the Bacs
    // advance notice told clients "we'll collect £[fee amount, calculated
    // post-award]". No test exercised it, which is how it shipped.

    private static PC1_Application__c makeAwardedApp(Decimal award) {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Bea', Last_Name__c = 'Fee', Stage__c = 'New',
            Email__c = 'fee@example.com', Award_Amount__c = award);
        insert a;
        return [SELECT Id, Name, First_Name__c, Last_Name__c FROM PC1_Application__c WHERE Id = :a.Id];
    }

    @IsTest static void fee_tokens_render_real_amounts_and_date() {
        PC1_Application__c app = makeAwardedApp(8000);          // fee = 1600.00
        insert new PC1_Fee_Installment__c(
            Application__c = app.Id, Installment_Number__c = 1, Amount__c = 533.34,
            Scheduled_Date__c = Date.newInstance(2026, 10, 5), Payment_Status__c = 'paid');
        insert new PC1_Fee_Installment__c(
            Application__c = app.Id, Installment_Number__c = 2, Amount__c = 533.33,
            Scheduled_Date__c = Date.newInstance(2026, 11, 5), Payment_Status__c = 'pending');
        insert new PC1_Fee_Installment__c(
            Application__c = app.Id, Installment_Number__c = 3, Amount__c = 533.33,
            Scheduled_Date__c = Date.newInstance(2026, 12, 5), Payment_Status__c = 'pending');
        PC1_Message_Template__c tpl = makeTemplate('Email', 'Bacs_Advance_Notice', 's',
            'Collect {{NextChargeAmount}} on {{NextChargeDate}} of {{FeeAmount}}');

        Test.startTest();
        PC1_MessageDispatcher.Rendered r = PC1_MessageDispatcher.render(tpl.Id, app.Id);
        Test.stopTest();

        System.assert(r.body.contains('1600.00'), 'total fee: ' + r.body);
        System.assert(r.body.contains('533.33'), 'next installment amount: ' + r.body);
        System.assert(r.body.contains('5 November 2026'),
            'the NEXT pending installment (Nov), not the paid one (Oct): ' + r.body);
        System.assert(!r.body.contains('[fee amount'), 'placeholder must never render: ' + r.body);
    }

    @IsTest static void fee_token_missing_fails_instead_of_sending() {
        // No award recorded → no fee. A Bacs notice must NOT go out without an
        // amount; the send has to fail loudly and name the token.
        PC1_Application__c app = makeApp('nofee@example.com', null);
        makeTemplate('Email', 'Bacs_Advance_Notice', 's', 'We will collect {{FeeAmount}}');

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Bacs_Advance_Notice');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failed', logs[0].Status__c, 'must not be Sent');
        System.assert(logs[0].Error_Message__c.contains('FeeAmount'),
            'the log must name the missing token: ' + logs[0].Error_Message__c);
    }

    // ─── welcome attachments (2026-10-02) ───────────────────────────
    // Files are stored as "{AppName}_{First}_{Last}_{DocType}". buildEmail
    // looked them up by the bare "Mandate", missed every one, and the welcome
    // email has been Skipped-Missing-Attachment since 2026-08-18.

    @IsTest static void welcome_finds_files_stored_under_friendly_title() {
        PC1_Application__c app = makeApp('welcome@example.com', null);
        String stored = app.Name + '_' + app.First_Name__c + '_' + app.Last_Name__c + '_Mandate';
        insert new ContentVersion(
            Title = stored, PathOnClient = stored + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'), FirstPublishLocationId = app.Id);
        PC1_Message_Template__c tpl = new PC1_Message_Template__c(
            Channel__c = 'Email', Trigger_Event__c = 'Intake_Created', Active__c = true,
            Subject_Template__c = 'Welcome {{FirstName}}', Body_Template__c = 'Hi',
            Attach_App_File_Titles__c = 'Mandate');
        insert tpl;

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Sent', logs[0].Status__c,
            'the Mandate file exists under its friendly title and must be found: ' + logs[0].Error_Message__c);
    }

    // ─── audit 2026-11-11 ───────────────────────────────────────────

    private static void addFile(PC1_Application__c app, String docType) {
        String stored = app.Name + '_' + app.First_Name__c + '_' + app.Last_Name__c + '_' + docType;
        insert new ContentVersion(
            Title = stored, PathOnClient = stored + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'), FirstPublishLocationId = app.Id);
    }

    /** The live MSG-0000 configuration: two generic PDFs AND three per-client ones. */
    private static void welcomeTemplateAsConfiguredLive() {
        insert new PC1_Message_Template__c(
            Channel__c = 'Email', Trigger_Event__c = 'Intake_Created', Active__c = true,
            Subject_Template__c = 'Welcome {{FirstName}}', Body_Template__c = 'Hi',
            Attachment_Static_Resource_Name__c = 'PC1_Welcome_Guide,PC1_Service_Agreement',
            Attach_App_File_Titles__c = 'Welcome Guide,Service Agreement,Mandate');
    }

    // PC-APEX-5: the personalised render failed (only the mandate PDF is on
    // the record). The whole welcome email used to be dropped while the SMS
    // "check your email" still went.
    @IsTest static void welcome_goes_with_generic_pdfs_when_the_personalised_render_failed() {
        PC1_Application__c app = makeApp('welcome@example.com', null);
        addFile(app, 'Mandate');
        welcomeTemplateAsConfiguredLive();

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(1, logs.size());
        System.assertEquals('Sent', logs[0].Status__c, 'not held for a cover page: ' + logs[0].Error_Message__c);
        System.assert(logs[0].Error_Message__c != null && logs[0].Error_Message__c.contains('fallback-static:PC1_Welcome_Guide')
            && logs[0].Error_Message__c.contains('fallback-static:PC1_Service_Agreement'),
            'the log says the generic copies went: ' + logs[0].Error_Message__c);
        System.assertEquals(3, PC1_MessageDispatcher.lastBuiltEmail.getFileAttachments().size(),
            'ONE copy of each document: Welcome Guide, Service Agreement, Mandate');
    }

    // ...and when every personalised PDF is there, the client got five
    // attachments: the Welcome Guide and the Service Agreement twice.
    @IsTest static void welcome_sends_one_copy_of_each_document() {
        PC1_Application__c app = makeApp('welcome@example.com', null);
        addFile(app, 'Welcome Guide');
        addFile(app, 'Service Agreement');
        addFile(app, 'Mandate');
        welcomeTemplateAsConfiguredLive();

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        PC1_Message_Send_Log__c log = [SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals('Sent', log.Status__c, 'send log error: ' + log.Error_Message__c);
        System.assertEquals(null, log.Error_Message__c, 'nothing missing, nothing substituted');
        System.assertEquals(3, PC1_MessageDispatcher.lastBuiltEmail.getFileAttachments().size(), 'three PDFs, not five');
    }

    // The mandate is personal and has no generic twin: without it the email waits.
    @IsTest static void welcome_still_waits_for_the_mandate_pdf() {
        PC1_Application__c app = makeApp('welcome@example.com', null);
        addFile(app, 'Welcome Guide');
        addFile(app, 'Service Agreement');
        welcomeTemplateAsConfiguredLive();

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        PC1_Message_Send_Log__c log = [SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals('Skipped-Missing-Attachment', log.Status__c);
        System.assert(log.Error_Message__c.contains('app:Mandate'), log.Error_Message__c);
    }

    // PC-APEX-6: after Mary flags a client as deceased, nothing automated may
    // reach the client (or the helper in CC), on any channel.
    @IsTest static void dispatch_suppressed_for_do_not_contact() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp('dnc@example.com', '+441234567890');
        update new PC1_Application__c(Id = app.Id, Do_Not_Contact__c = true, Helper_Email__c = 'helper@example.com');
        makeTemplate('Email', 'Intake_Created', 's', 'b');
        makeTemplate('SMS', 'Intake_Created', null, 'Hi {{FirstName}}');
        Test.setMock(HttpCalloutMock.class, new TwilioForbiddenMock());

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Intake_Created');
        Test.stopTest();

        Id appId = app.Id;
        List<PC1_Message_Send_Log__c> logs = [
            SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals(2, logs.size(), 'one row per suppressed send, so the val team can see why nothing went');
        String expected = PC1_MessageDispatcher.skipStatus(PC1_MessageDispatcher.STATUS_SKIP_DNC);
        for (PC1_Message_Send_Log__c l : logs) {
            System.assertEquals(expected, l.Status__c, 'never Sent');
            System.assertNotEquals('Sent', l.Status__c);
            System.assert(l.Error_Message__c.contains('Do_Not_Contact'), l.Error_Message__c);
        }
        System.assertEquals(null, PC1_MessageDispatcher.lastBuiltEmail, 'no email was even built');
        System.assertEquals('Failed', PC1_MessageDispatcher.skipStatus('No-Such-Status'),
            'a value the picklist does not have yet falls back to Failed instead of breaking the insert');
    }

    // PC-APEX-7: a reschedule cancels the old row but keeps its time. A call
    // moved EARLIER made the reminder quote the cancelled, later time.
    @IsTest static void call_time_is_the_next_pending_slot_not_a_cancelled_later_one() {
        PC1_Application__c app = makeApp('call@example.com', '+441234567890');
        // Whole seconds: the database drops milliseconds.
        Datetime later = Datetime.newInstanceGmt(Date.today().addDays(3), Time.newInstance(15, 0, 0, 0));
        Datetime sooner = Datetime.newInstanceGmt(Date.today().addDays(2), Time.newInstance(10, 0, 0, 0));
        PC1_Call_Schedule__c old = new PC1_Call_Schedule__c(Application__c = app.Id, Scheduled_At__c = later, Status__c = 'Pending');
        insert old;
        update new PC1_Call_Schedule__c(Id = old.Id, Status__c = 'Cancelled', Cancelled_At__c = Datetime.now());
        insert new PC1_Call_Schedule__c(Application__c = app.Id, Scheduled_At__c = sooner, Status__c = 'Pending');

        // History only (no Pending slot): the latest slot is still the fallback.
        PC1_Application__c past = makeApp('past@example.com', '+441234567891');
        PC1_Call_Schedule__c gone = new PC1_Call_Schedule__c(Application__c = past.Id, Scheduled_At__c = later, Status__c = 'Pending');
        insert gone;
        update new PC1_Call_Schedule__c(Id = gone.Id, Status__c = 'Cancelled', Cancelled_At__c = Datetime.now());

        Map<Id, Datetime> calls = PC1_MessageDispatcher.loadLatestCalls(new Set<Id>{ app.Id, past.Id });
        System.assertEquals(sooner, calls.get(app.Id), 'the call that will actually happen');
        System.assertEquals(later, calls.get(past.Id), 'fallback: latest slot of any status');
    }

    // PC-APEX-14: the From was whoever triggered the send.
    @IsTest static void email_is_sent_from_the_clients_org_wide_address_when_there_is_one() {
        PC1_Application__c app = makeApp('from@example.com', null);
        makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        System.assertNotEquals(null, PC1_MessageDispatcher.lastBuiltEmail, 'the email was built');
        System.assertEquals(PC1_MessageDispatcher.loadClientsOwea(), PC1_MessageDispatcher.lastOweaIdUsed,
            'the clients@ Org-Wide address when the org has one, else the old behaviour');
        Id appId = app.Id;
        System.assertEquals('Sent', [SELECT Status__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId].Status__c);
    }

    // PC-APEX-16: the sandbox gate looked at the client's address only.
    @IsTest static void helper_cc_is_dropped_when_the_sandbox_gate_refuses_it() {
        PC1_Application__c app = makeApp('client@example.com', null);
        update new PC1_Application__c(Id = app.Id, Helper_Email__c = 'real.helper@elsewhere.example');
        makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');
        PC1_SendGate.sandboxOverride = true;
        PC1_SendGate.resetCaches();

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        Id appId = app.Id;
        PC1_Message_Send_Log__c log = [SELECT Status__c, Error_Message__c FROM PC1_Message_Send_Log__c WHERE Application__c = :appId];
        System.assertEquals('Sent', log.Status__c, 'the allow-listed client still gets the email');
        System.assert(log.Error_Message__c != null && log.Error_Message__c.contains('Helper CC not sent'), log.Error_Message__c);
        List<String> cc = PC1_MessageDispatcher.lastBuiltEmail.getCcAddresses();
        System.assert(cc == null || cc.isEmpty(), 'the real helper address must not be copied from a sandbox');
    }

    @IsTest static void helper_cc_is_kept_when_allowed() {
        PC1_Application__c app = makeApp('client@example.com', null);
        update new PC1_Application__c(Id = app.Id, Helper_Email__c = 'helper@example.com');
        makeTemplate('Email', 'Application_Submitted_DWP', 's', 'b');
        PC1_SendGate.sandboxOverride = true;
        PC1_SendGate.resetCaches();

        Test.startTest();
        PC1_MessageDispatcher.dispatch(app.Id, 'Application_Submitted_DWP');
        Test.stopTest();

        List<String> cc = PC1_MessageDispatcher.lastBuiltEmail.getCcAddresses();
        System.assert(cc != null && cc.size() == 1 && cc[0] == 'helper@example.com', 'staff / allow-listed helper is copied as before');
    }
}