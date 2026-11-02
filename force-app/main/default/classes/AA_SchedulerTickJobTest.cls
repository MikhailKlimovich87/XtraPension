/**
 * AA_SchedulerTickJobTest — the 5-minute tick that makes every scheduled Mary
 * call dial. Schedulable Apex cannot call out, so execute() hands off to a
 * @future(callout=true); fireOnce() is the synchronous console / Flow path.
 *
 * A regression here looks like: the tick posting to the wrong path, dropping
 * the X-Heroku-Token header (Heroku answers 401 and nobody is dialled),
 * calling out with no config, or a Heroku outage escaping the @future as an
 * unhandled exception. Every test asserts the request the mock actually saw.
 */
@isTest
private class AA_SchedulerTickJobTest {

    private static final String BASE  = 'https://aa-tick.test.invalid';
    private static final String TOKEN = 'tick-secret-token';

    // Captured by the mocks. Static so the @future run at Test.stopTest() and
    // the test body share them.
    private static Integer calls = 0;
    private static String  lastMethod;
    private static String  lastEndpoint;
    private static String  lastToken;
    private static String  lastBody;

    private class CapturingMock implements HttpCalloutMock {
        private Integer status;
        private String  body;
        CapturingMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            calls++;
            lastMethod   = req.getMethod();
            lastEndpoint = req.getEndpoint();
            lastToken    = req.getHeader('X-Heroku-Token');
            lastBody     = req.getBody();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setHeader('Content-Type', 'application/json');
            r.setBody(body);
            return r;
        }
    }

    // Heroku down: Http.send() throws instead of answering.
    private class OutageMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            calls++;
            throw new CalloutException('simulated Heroku outage');
        }
    }

    // Query-then-upsert so the fixture is deterministic whether or not the
    // org-default row is visible to the test (AA_FeeInstallmentSchedulerTest idiom).
    private static void seedConfig(String baseUrl, String token) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Heroku_Base_Url__c       = baseUrl;
        cfg.Heroku_Internal_Token__c = token;
        upsert cfg;
    }

    // ── fireOnce (console / Flow path) ──────────────────────────────

    // POST {} to <base>/internal/scheduler-tick with the internal token, and
    // report Heroku's answer verbatim.
    @isTest static void fireOnce_posts_to_scheduler_tick_with_token() {
        seedConfig(BASE + '/', TOKEN); // trailing slash must not produce '//internal'
        Test.setMock(HttpCalloutMock.class, new CapturingMock(200, '{"status":"ok","dialed":1}'));

        Test.startTest();
        List<String> out = AA_SchedulerTickJob.fireOnce();
        Test.stopTest();

        System.assertEquals(1, calls, 'fireOnce must make exactly one callout');
        System.assertEquals('POST', lastMethod, 'the tick is a POST');
        System.assertEquals(BASE + '/internal/scheduler-tick', lastEndpoint,
            'endpoint must be <base without trailing slash>/internal/scheduler-tick');
        System.assertEquals(TOKEN, lastToken, 'X-Heroku-Token header must carry Heroku_Internal_Token__c');
        System.assertEquals('{}', lastBody, 'body is an empty JSON object');
        System.assertEquals(1, out.size(), 'the invocable returns one result per invocation');
        System.assertEquals('HTTP 200 — {"status":"ok","dialed":1}', out[0],
            'result must echo the status code and the Heroku body');
    }

    // A non-2xx must be reported, not masked, and a long body abbreviated to
    // 200 chars so the console result stays readable.
    @isTest static void fireOnce_reports_non_2xx_and_abbreviates_body() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new CapturingMock(503, 'x'.repeat(500)));

        Test.startTest();
        String out = AA_SchedulerTickJob.fireOnce()[0];
        Test.stopTest();

        System.assert(out.startsWith('HTTP 503 — '), 'a non-2xx status must be surfaced: ' + out);
        System.assertEquals('HTTP 503 — '.length() + 200, out.length(), 'the body must be abbreviated to 200 chars');
        System.assert(out.endsWith('...'), 'an abbreviated body ends with an ellipsis');
    }

    // No internal token → skip loudly and never touch the network.
    @isTest static void fireOnce_without_token_skips_and_makes_no_callout() {
        seedConfig(BASE, '');
        Test.setMock(HttpCalloutMock.class, new OutageMock()); // any callout would throw

        Test.startTest();
        String out = AA_SchedulerTickJob.fireOnce()[0];
        Test.stopTest();

        System.assertEquals(0, calls, 'no callout may be attempted without a token');
        System.assert(out.startsWith('skipped: AA_Config__c missing'), 'the result must explain the skip: ' + out);
    }

    // ── Schedulable path ────────────────────────────────────────────

    // execute() cannot call out itself, so it must hand off to the @future,
    // which runs at Test.stopTest() and performs the real POST.
    @isTest static void execute_hands_off_to_future_which_calls_out() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new CapturingMock(200, '{"status":"ok"}'));

        Test.startTest();
        new AA_SchedulerTickJob().execute(null);
        System.assertEquals(0, calls, 'execute() itself must not call out (Schedulable cannot)');
        Test.stopTest(); // runs the @future

        System.assertEquals(1, calls, 'the @future must perform the tick callout');
        System.assertEquals(BASE + '/internal/scheduler-tick', lastEndpoint, 'the async path must hit the same endpoint as fireOnce');
        System.assertEquals(TOKEN, lastToken, 'the async path must send the same token as fireOnce');
    }

    // A Heroku outage inside the @future is logged, never rethrown — an
    // unhandled exception there would mark the cron run failed while dials
    // silently stop.
    @isTest static void future_swallows_heroku_outage() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new OutageMock());

        Boolean escaped = false;
        Test.startTest();
        try {
            new AA_SchedulerTickJob().execute(null);
            Test.stopTest();
        } catch (Exception e) {
            escaped = true;
        }
        System.assertEquals(1, calls, 'the tick must still be attempted during an outage');
        System.assert(!escaped, 'a callout failure must be swallowed by the @future, not rethrown');
    }

    // ── Failure alerting (audit F91) ────────────────────────────────

    // A non-2xx from Heroku (401 after a token rotation, 5xx) used to be
    // discarded by the @future. It must now raise the ops alert.
    @isTest static void async_non_2xx_raises_alert() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new CapturingMock(401, '{"error":"unauthorized"}'));
        AA_SchedulerTickJob.forceAlertSlot = true;

        Test.startTest();
        new AA_SchedulerTickJob().execute(null);
        Test.stopTest();

        System.assertEquals(1, calls, 'the tick was attempted');
        System.assertNotEquals(null, AA_SchedulerTickJob.lastAlertReason, 'a 401 must raise the alert');
        System.assert(AA_SchedulerTickJob.lastAlertReason.contains('HTTP 401'),
            'the alert names the status: ' + AA_SchedulerTickJob.lastAlertReason);
    }

    // An outage (callout exception) alerts too, and is still swallowed.
    @isTest static void async_outage_raises_alert() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new OutageMock());
        AA_SchedulerTickJob.forceAlertSlot = true;

        Test.startTest();
        new AA_SchedulerTickJob().execute(null);
        Test.stopTest();

        System.assertNotEquals(null, AA_SchedulerTickJob.lastAlertReason, 'an outage must raise the alert');
        System.assert(AA_SchedulerTickJob.lastAlertReason.startsWith('Callout failed'), AA_SchedulerTickJob.lastAlertReason);
    }

    // Missing config means no tick is ever sent: that is an outage too.
    @isTest static void async_missing_config_raises_alert_without_callout() {
        seedConfig(BASE, '');
        Test.setMock(HttpCalloutMock.class, new OutageMock()); // any callout would throw
        AA_SchedulerTickJob.forceAlertSlot = true;

        Test.startTest();
        new AA_SchedulerTickJob().execute(null);
        Test.stopTest();

        System.assertEquals(0, calls, 'no callout without a token');
        System.assertNotEquals(null, AA_SchedulerTickJob.lastAlertReason, 'missing config must alert');
        System.assert(AA_SchedulerTickJob.lastAlertReason.contains('AA_Config__c'), AA_SchedulerTickJob.lastAlertReason);
    }

    // A healthy 200 never alerts.
    @isTest static void async_ok_does_not_alert() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new CapturingMock(200, '{"status":"ok"}'));
        AA_SchedulerTickJob.forceAlertSlot = true;

        Test.startTest();
        new AA_SchedulerTickJob().execute(null);
        Test.stopTest();

        System.assertEquals(null, AA_SchedulerTickJob.lastFailure, 'a 200 is not a failure');
        System.assertEquals(null, AA_SchedulerTickJob.lastAlertReason, 'a 200 must not alert');
    }

    // Outside the alert slot the failure is recorded but no email is sent,
    // so a persistent outage costs one email per hour, not twelve.
    @isTest static void async_failure_outside_slot_is_recorded_not_alerted() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new CapturingMock(503, 'down'));
        AA_SchedulerTickJob.forceAlertSlot = false;

        Test.startTest();
        new AA_SchedulerTickJob().execute(null);
        Test.stopTest();

        System.assertNotEquals(null, AA_SchedulerTickJob.lastFailure, 'the failure is recorded');
        System.assertEquals(null, AA_SchedulerTickJob.lastAlertReason, 'no alert outside the hourly slot');
    }

    @isTest static void alert_slot_is_first_five_minutes_of_the_hour() {
        System.assert(AA_SchedulerTickJob.isAlertSlot(Datetime.newInstanceGmt(2026, 10, 2, 9, 0, 30)));
        System.assert(AA_SchedulerTickJob.isAlertSlot(Datetime.newInstanceGmt(2026, 10, 2, 9, 4, 59)));
        System.assert(!AA_SchedulerTickJob.isAlertSlot(Datetime.newInstanceGmt(2026, 10, 2, 9, 5, 0)));
        System.assert(!AA_SchedulerTickJob.isAlertSlot(Datetime.newInstanceGmt(2026, 10, 2, 9, 55, 0)));
    }

    // System.schedule wiring: the cron entry is created and the scheduled run
    // (executed at Test.stopTest()) must NOT call out inline — Salesforce
    // forbids callouts from scheduled Apex, so an inline POST here would fail
    // in production every 5 minutes. The @future it hands off to is not
    // executed by the test runner from inside a scheduled job (only work
    // queued before Test.stopTest() runs), so the hand-off's real callout is
    // proven by execute_hands_off_to_future_which_calls_out above.
    @isTest static void schedule_creates_cron_and_never_calls_out_inline() {
        seedConfig(BASE, TOKEN);
        Test.setMock(HttpCalloutMock.class, new CapturingMock(200, '{"status":"ok"}'));
        Datetime at = Datetime.now().addMinutes(2);
        String cron = at.second() + ' ' + at.minute() + ' ' + at.hour() + ' ' + at.day() + ' ' + at.month() + ' ? ' + at.year();

        Test.startTest();
        Id jobId = System.schedule('AA_SchedulerTickJobTest ' + at.getTime(), cron, new AA_SchedulerTickJob());
        Test.stopTest();

        CronTrigger ct = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(cron, ct.CronExpression, 'the cron expression must be stored as given');
        System.assertEquals(0, calls,
            'a Schedulable must never call out inline (forbidden in scheduled Apex) — the tick belongs to the @future');
    }
}