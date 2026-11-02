/**
 * AA_WelcomePackWatchdogTest — audit 2026-10-02 F73: a welcome email held for
 * a missing per-application PDF must go out (with its held SMS) once the file
 * lands.
 *
 * A regression here looks like: a held welcome that is never re-sent, a
 * re-send that repeats a part the client already got, a re-send attempted
 * every hour while the file is still missing, or the watchdog calling out to
 * Heroku again (wave 3: the mandate-PDF retry has ONE caller, the Heroku
 * scheduler tick; a callout here also broke fireOnce() with "uncommitted
 * work pending" whenever there was a held event to re-send).
 */
@IsTest
private class AA_WelcomePackWatchdogTest {

    private static final String BASE  = 'https://aa-watchdog.test.invalid';
    private static final String TOKEN = 'watchdog-secret-token';

    private static Integer herokuCalls = 0;
    private static Integer twilioCalls = 0;

    // Routes by endpoint: Twilio (the held SMS) vs anything else, which counts
    // as a Heroku call and must not happen any more.
    private class RoutingMock implements HttpCalloutMock {
        private Integer herokuStatus;
        RoutingMock(Integer herokuStatus) { this.herokuStatus = herokuStatus; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('api.twilio.com')) {
                twilioCalls++;
                r.setStatusCode(201);
                r.setBody('{"sid":"SMwatchdog0000000000000000000001","status":"queued",'
                        + '"to":"+441234567890","from":"+447476900311","body":"hi"}');
                return r;
            }
            herokuCalls++;
            r.setStatusCode(herokuStatus);
            r.setBody('{"ok":true,"candidates_scanned":0,"results":[]}');
            return r;
        }
    }

    private static void seedConfig(String baseUrl, String token) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Heroku_Base_Url__c       = baseUrl;
        cfg.Heroku_Internal_Token__c = token;
        cfg.Admin_Alert_Email__c     = 'ops@example.test';
        upsert cfg;
        insert new XtraPension_Data__c(
            SetupOwnerId      = UserInfo.getOrganizationId(),
            Twilio_Account__c = 'ACtestaccount',
            Twilio_Token__c   = 'testtoken');
    }

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Alice', Last_Name__c = 'Test', Stage__c = 'New',
            Email__c = 'recipient@example.com', Phone__c = '+441234567890');
        insert a;
        return [SELECT Id, Name, First_Name__c, Last_Name__c FROM AA_Application__c WHERE Id = :a.Id];
    }

    private static AA_Message_Template__c makeTemplate(String channel, String body, String appFiles) {
        AA_Message_Template__c t = new AA_Message_Template__c(
            Channel__c = channel, Trigger_Event__c = 'Intake_Created', Active__c = true,
            Subject_Template__c = channel == 'Email' ? 'Welcome' : null,
            Body_Template__c = body, Attach_App_File_Titles__c = appFiles);
        insert t;
        return t;
    }

    private static AA_Message_Send_Log__c logRow(Id tplId, Id appId, String channel, String status, Datetime at) {
        return new AA_Message_Send_Log__c(
            Template__c = tplId, Application__c = appId, Channel__c = channel,
            Status__c = status, Sent_At__c = at);
    }

    private static void addMandateFile(AA_Application__c app) {
        String title = app.Name + '_Alice_Test_Mandate';
        insert new ContentVersion(Title = title, PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 mandate'), FirstPublishLocationId = app.Id);
    }

    private static Integer count(Id appId, String channel, String status) {
        return [SELECT COUNT() FROM AA_Message_Send_Log__c
                 WHERE Application__c = :appId AND Channel__c = :channel AND Status__c = :status];
    }

    // ── 1. held emails ──────────────────────────────────────────────

    // The F73 fix: the held welcome email AND its held SMS go out once the
    // mandate PDF is on the application.
    @IsTest static void held_welcome_and_its_sms_go_out_once_the_file_lands() {
        seedConfig(BASE, TOKEN);
        AA_Application__c app = makeApp();
        AA_Message_Template__c email = makeTemplate('Email', 'Hi {{FirstName}}', 'Mandate');
        AA_Message_Template__c sms   = makeTemplate('SMS', 'Check your email shortly', null);
        Datetime heldAt = Datetime.now().addHours(-2);
        insert new List<AA_Message_Send_Log__c>{
            logRow(email.Id, app.Id, 'Email', 'Skipped-Missing-Attachment', heldAt),
            logRow(sms.Id,   app.Id, 'SMS',   'Skipped-Missing-Attachment', heldAt) };
        addMandateFile(app);
        Test.setMock(HttpCalloutMock.class, new RoutingMock(200));

        Test.startTest();
        Map<String, Set<Id>> resent = AA_WelcomePackWatchdog.resendHeld();
        Test.stopTest();

        System.assert(resent.containsKey('Intake_Created') && resent.get('Intake_Created').contains(app.Id),
            'the held Intake_Created must be re-dispatched: ' + resent);
        System.assertEquals(1, count(app.Id, 'Email', 'Sent'), 'the welcome email must now be Sent');
        System.assertEquals(1, count(app.Id, 'SMS', 'Sent'), 'the held SMS goes out with it');
        System.assertEquals(1, twilioCalls, 'exactly one SMS');
    }

    // While the file is still missing nothing happens: no new log rows and no
    // repeat ops alert every hour.
    @IsTest static void nothing_happens_while_the_file_is_still_missing() {
        seedConfig(BASE, TOKEN);
        AA_Application__c app = makeApp();
        AA_Message_Template__c email = makeTemplate('Email', 'Hi', 'Mandate');
        insert logRow(email.Id, app.Id, 'Email', 'Skipped-Missing-Attachment', Datetime.now().addHours(-1));

        Test.startTest();
        Map<String, Set<Id>> resent = AA_WelcomePackWatchdog.resendHeld();
        Test.stopTest();

        System.assert(resent.isEmpty(), 'nothing may be re-sent without the file: ' + resent);
        System.assertEquals(1, [SELECT COUNT() FROM AA_Message_Send_Log__c WHERE Application__c = :app.Id],
            'no extra log rows while waiting');
    }

    // An email of that event already Sent (earlier re-send, manual send)
    // closes the case.
    @IsTest static void an_already_sent_welcome_is_not_resent() {
        seedConfig(BASE, TOKEN);
        AA_Application__c app = makeApp();
        AA_Message_Template__c email = makeTemplate('Email', 'Hi', 'Mandate');
        insert new List<AA_Message_Send_Log__c>{
            logRow(email.Id, app.Id, 'Email', 'Skipped-Missing-Attachment', Datetime.now().addDays(-2)),
            logRow(email.Id, app.Id, 'Email', 'Sent', Datetime.now().addDays(-1)) };
        addMandateFile(app);

        Test.startTest();
        Map<String, Set<Id>> resent = AA_WelcomePackWatchdog.resendHeld();
        Test.stopTest();

        System.assert(resent.isEmpty(), 'a Sent welcome must close the case: ' + resent);
    }

    // Held longer ago than the lookback: given up (ops was alerted at the time).
    @IsTest static void holds_older_than_the_lookback_are_ignored() {
        seedConfig(BASE, TOKEN);
        AA_Application__c app = makeApp();
        AA_Message_Template__c email = makeTemplate('Email', 'Hi', 'Mandate');
        insert logRow(email.Id, app.Id, 'Email', 'Skipped-Missing-Attachment',
            Datetime.now().addDays(-AA_WelcomePackWatchdog.LOOKBACK_DAYS - 1));
        addMandateFile(app);

        Test.startTest();
        System.assert(AA_WelcomePackWatchdog.resendHeld().isEmpty(), 'an old hold must be ignored');
        Test.stopTest();
    }

    // dispatchHeldResend never repeats a part the client already got, even
    // when that send is older than the normal 24 h dedup window.
    @IsTest static void held_resend_does_not_repeat_an_sms_sent_days_ago() {
        seedConfig(BASE, TOKEN);
        AA_Application__c app = makeApp();
        AA_Message_Template__c email = makeTemplate('Email', 'Hi', 'Mandate');
        AA_Message_Template__c sms   = makeTemplate('SMS', 'Check your email shortly', null);
        insert new List<AA_Message_Send_Log__c>{
            logRow(email.Id, app.Id, 'Email', 'Skipped-Missing-Attachment', Datetime.now().addDays(-3)),
            logRow(sms.Id,   app.Id, 'SMS',   'Sent', Datetime.now().addDays(-3)) };
        addMandateFile(app);
        Test.setMock(HttpCalloutMock.class, new RoutingMock(200));

        Test.startTest();
        AA_MessageDispatcher.dispatchHeldResend(new Set<Id>{ app.Id }, 'Intake_Created');
        Test.stopTest();

        System.assertEquals(1, count(app.Id, 'Email', 'Sent'), 'the held email goes out');
        System.assertEquals(0, twilioCalls, 'the SMS the client got 3 days ago must not be repeated');
        System.assertEquals(1, count(app.Id, 'SMS', 'Skipped-Deduped'), 'the skipped repeat is logged');
    }

    // Readiness: a generic static stand-in counts as present; DNC is excluded.
    @IsTest static void readiness_accepts_static_stand_ins_and_skips_do_not_contact() {
        AA_Application__c ok  = makeApp();
        AA_Application__c dnc = makeApp();
        update new AA_Application__c(Id = dnc.Id, Do_Not_Contact__c = true);
        makeTemplate('Email', 'Hi', 'Welcome Guide');

        Set<Id> ready = AA_MessageDispatcher.appsWithAttachmentsReady(new Set<Id>{ ok.Id, dnc.Id }, 'Intake_Created');
        System.assert(ready.contains(ok.Id), 'AA_Welcome_Guide stands in for a missing per-app Welcome Guide');
        System.assert(!ready.contains(dnc.Id), 'a Do Not Contact app is never re-sent to');
    }

    // ── 2. no Heroku callout, fireOnce with work to do ──────────────

    // Wave-2 review finding: fireOnce() re-sent a held event (enqueueJob) and
    // then made a synchronous Heroku callout in the same transaction, which
    // threw "You have uncommitted work pending" exactly when it had work to
    // do. The Heroku half is gone (wave 3), so this must now succeed.
    @IsTest static void fireOnce_resends_a_held_event_without_calling_heroku() {
        seedConfig(BASE, TOKEN);
        AA_Application__c app = makeApp();
        AA_Message_Template__c email = makeTemplate('Email', 'Hi {{FirstName}}', 'Mandate');
        insert logRow(email.Id, app.Id, 'Email', 'Skipped-Missing-Attachment', Datetime.now().addHours(-2));
        addMandateFile(app);
        Test.setMock(HttpCalloutMock.class, new RoutingMock(200));

        Test.startTest();
        String out = AA_WelcomePackWatchdog.fireOnce()[0];
        Test.stopTest();

        System.assert(out.startsWith('resent 1'), out);
        System.assertEquals(0, herokuCalls, 'the mandate-PDF retry belongs to the Heroku scheduler tick, not here');
        System.assertEquals(1, count(app.Id, 'Email', 'Sent'), 'the held welcome goes out');
    }

    @IsTest static void execute_makes_no_heroku_callout() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new RoutingMock(200));

        Test.startTest();
        new AA_WelcomePackWatchdog().execute(null);
        Test.stopTest();

        System.assertEquals(0, herokuCalls, 'one caller for the mandate-PDF retry: src/webhooks/scheduler.js');
    }

    // The documented System.schedule call is valid (CronTrigger accepted).
    @IsTest static void the_documented_cron_expression_schedules() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new RoutingMock(200)); // the job runs at stopTest
        Test.startTest();
        Id jobId = System.schedule('AA Welcome Pack Watchdog TEST', '0 20 * * * ?', new AA_WelcomePackWatchdog());
        Test.stopTest();
        System.assertEquals('0 20 * * * ?', [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId].CronExpression);
    }
}