/**
 * Tests for PC1_HerokuBridge. Uses HttpCalloutMock to avoid hitting Heroku.
 */
@IsTest
private class PC1_HerokuBridgeTest {

    private class MockOk implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(202);
            r.setHeader('Content-Type', 'application/json');
            r.setBody('{"status":"queued","run_id":"a1ZTEST0000000001","application_id":"a1VTEST0000000001"}');
            return r;
        }
    }

    private class MockUnauthorized implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(401);
            r.setBody('{"error":"unauthorized"}');
            return r;
        }
    }

    private static void seedConfig(String token) {
        PC1_Config__c cfg = new PC1_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Heroku_Base_Url__c = 'https://pc1-autofill-example.herokuapp.com',
            Heroku_Internal_Token__c = token
        );
        insert cfg;
    }

    @IsTest static void success_returns_run_id() {
        seedConfig('t0ken');
        // Real Application so we have a valid Id, at a stage a fill may start from.
        PC1_Application__c app = new PC1_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'Reviewed'
        );
        insert app;

        Test.setMock(HttpCalloutMock.class, new MockOk());
        Test.startTest();
        List<PC1_HerokuBridge.StartResult> res = PC1_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].success);
        System.assertEquals(202, res[0].statusCode);
        System.assertEquals('a1ZTEST0000000001', res[0].runId);
    }

    @IsTest static void missing_config_returns_error() {
        // No PC1_Config__c row — should fail loud.
        PC1_Application__c app = new PC1_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'New'
        );
        insert app;

        Test.startTest();
        List<PC1_HerokuBridge.StartResult> res = PC1_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(false, res[0].success);
        System.assert(res[0].errorMessage.contains('PC1_Config'), res[0].errorMessage);
    }

    @IsTest static void non_202_returns_error_message() {
        seedConfig('t0ken');
        PC1_Application__c app = new PC1_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'Reviewed'
        );
        insert app;

        Test.setMock(HttpCalloutMock.class, new MockUnauthorized());
        Test.startTest();
        List<PC1_HerokuBridge.StartResult> res = PC1_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(false, res[0].success);
        System.assertEquals(401, res[0].statusCode);
        System.assert(res[0].errorMessage.contains('401'), res[0].errorMessage);
    }

    // ── startFillFromUi (record-page "Fill on DWP" button) — 2026-10-02 ──
    private class MockBody implements HttpCalloutMock {
        Integer status; String body;
        MockBody(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    private static PC1_Application__c uiApp() {
        PC1_Application__c app = new PC1_Application__c(First_Name__c = 'U', Last_Name__c = 'I', Stage__c = 'Reviewed');
        insert app;
        return app;
    }

    @IsTest static void ui_requires_declaration_unless_forced() {
        seedConfig('t0ken');
        PC1_Application__c app = uiApp();
        Boolean threw = false;
        try { PC1_HerokuBridge.startFillFromUi(app.Id, true, false); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'unsigned declaration blocks the fill');
        Test.setMock(HttpCalloutMock.class, new MockOk());
        Test.startTest();
        System.assertEquals('a1ZTEST0000000001', PC1_HerokuBridge.startFillFromUi(app.Id, true, true));
        Test.stopTest();
    }

    // Audit 2026-11-11 PC-SFUI-9: the stage gate lived in the browser only.
    private class MustNotCallMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assert(false, 'no fill may be requested for an application that is not ready');
            return null;
        }
    }

    @IsTest static void stage_gate_is_enforced_on_the_server_and_force_does_not_bypass_it() {
        seedConfig('t0ken');
        PC1_Application__c app = new PC1_Application__c(First_Name__c = 'N', Last_Name__c = 'R', Stage__c = 'Partial Data');
        insert app;
        Test.setMock(HttpCalloutMock.class, new MustNotCallMock());

        List<PC1_HerokuBridge.StartResult> res = PC1_HerokuBridge.startFill(new List<Id>{ app.Id });
        System.assertEquals(false, res[0].success, 'the invocable refuses too, not only the button');
        System.assert(res[0].errorMessage.contains('Partial Data'), res[0].errorMessage);

        Boolean t1 = false, t2 = false;
        try { PC1_HerokuBridge.startFillFromUi(app.Id, true, false); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_HerokuBridge.startFillFromUi(app.Id, true, true); } catch (AuraHandledException e) { t2 = true; }
        System.assert(t1, 'refused at Partial Data');
        System.assert(t2, 'Force is for the declaration and mandate gates, never for the stage');
    }

    @IsTest static void ui_maps_the_code_node_really_sends_for_a_run_in_flight() {
        seedConfig('t0ken');
        PC1_Application__c app = uiApp();
        Test.setMock(HttpCalloutMock.class, new MockBody(409, '{"error":"fill_in_progress","hint":"A fill run is already in progress for this application."}'));
        String msg = null;
        Test.startTest();
        try { PC1_HerokuBridge.startFillFromUi(app.Id, true, true); } catch (AuraHandledException e) { msg = e.getMessage(); }
        Test.stopTest();
        System.assertNotEquals(null, msg, 'a refusal must reach the agent');
    }

    // Audit 2026-11-11 PC-ENGINE-9: testMode was dropped here, so the worker
    // could not tell a test run from a real one.
    private static String lastBody;
    private class CaptureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            lastBody = req.getBody();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(202);
            r.setBody('{"status":"queued","run_id":"a1ZTEST0000000001"}');
            return r;
        }
    }

    @IsTest static void test_mode_reaches_heroku_and_only_an_explicit_false_is_a_real_run() {
        seedConfig('t0ken');
        PC1_Application__c app = uiApp();
        Test.setMock(HttpCalloutMock.class, new CaptureMock());
        Test.startTest();
        PC1_HerokuBridge.startFill(new List<Id>{ app.Id });
        System.assert(lastBody.contains('"testMode":true') && lastBody.contains('"force":false'),
            'the invocable starts a test run: ' + lastBody);
        PC1_HerokuBridge.startFill(new List<Id>{ app.Id }, true, null);
        System.assert(lastBody.contains('"testMode":true') && lastBody.contains('"force":true'),
            'no answer is a test run: ' + lastBody);
        PC1_HerokuBridge.startFillFromUi(app.Id, false, true);
        System.assert(lastBody.contains('"testMode":false'), 'only an explicit false is passed on as a real run: ' + lastBody);
        Test.stopTest();
    }

    @IsTest static void ui_maps_worker_errors_to_sentences() {
        seedConfig('t0ken');
        PC1_Application__c app = uiApp();
        List<String> bodies = new List<String>{
            '{"error":"dd_mandate_not_active","dd_mandate_status":"pending_submission"}',
            '{"error":"already_submitted","dwp_reference":"REF"}',
            '{"error":"application_not_found"}',
            '{"error":"fill_already_running"}',
            '{"error":"unauthorized"}',
            '{"error":"something_else","hint":"x"}',
            'not json'
        };
        Test.startTest();
        for (String b : bodies) {
            Test.setMock(HttpCalloutMock.class, new MockBody(409, b));
            Boolean threw = false;
            try { PC1_HerokuBridge.startFillFromUi(app.Id, true, true); } catch (AuraHandledException e) { threw = true; }
            System.assert(threw, b);
        }
        Test.stopTest();
        Boolean t1 = false, t2 = false;
        try { PC1_HerokuBridge.startFillFromUi(null, true, true); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_HerokuBridge.startFillFromUi(UserInfo.getUserId(), true, true); } catch (Exception e) { t2 = true; }
        System.assert(t1 && t2);
    }
}