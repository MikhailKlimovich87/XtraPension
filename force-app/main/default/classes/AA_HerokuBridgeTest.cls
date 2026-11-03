/**
 * Tests for AA_HerokuBridge. Uses HttpCalloutMock to avoid hitting Heroku.
 */
@IsTest
private class AA_HerokuBridgeTest {

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

    private class MockMandateInactive implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(409);
            r.setBody('{"error":"dd_mandate_not_active","dd_mandate_status":"pending_submission","hint":"raw hint"}');
            return r;
        }
    }

    /** Application at a fill-ready stage, declaration signed or not. */
    private static AA_Application__c readyApp(String stage, Boolean declSigned) {
        AA_Application__c app = new AA_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'New'
        );
        insert app;
        // Set after insert: the default-answer seeding on insert recomputes
        // Declaration_Complete__c from the (empty) declaration rows.
        update new AA_Application__c(Id = app.Id, Stage__c = stage, Declaration_Complete__c = declSigned);
        return app;
    }

    private static void seedConfig(String token) {
        AA_Config__c cfg = new AA_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Heroku_Base_Url__c = 'https://aa-autofill-14d501200453.herokuapp.com',
            Heroku_Internal_Token__c = token
        );
        insert cfg;
    }

    @IsTest static void success_returns_run_id() {
        seedConfig('t0ken');
        // Real Application so we have a valid Id.
        AA_Application__c app = new AA_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'New'
        );
        insert app;

        Test.setMock(HttpCalloutMock.class, new MockOk());
        Test.startTest();
        List<AA_HerokuBridge.StartResult> res = AA_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].success);
        System.assertEquals(202, res[0].statusCode);
        System.assertEquals('a1ZTEST0000000001', res[0].runId);
    }

    @IsTest static void missing_config_returns_error() {
        // No AA_Config__c row — should fail loud.
        AA_Application__c app = new AA_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'New'
        );
        insert app;

        Test.startTest();
        List<AA_HerokuBridge.StartResult> res = AA_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(false, res[0].success);
        System.assert(res[0].errorMessage.contains('AA_Config'), res[0].errorMessage);
    }

    @IsTest static void non_202_returns_error_message() {
        seedConfig('t0ken');
        AA_Application__c app = new AA_Application__c(
            First_Name__c = 'A', Last_Name__c = 'B', Stage__c = 'New'
        );
        insert app;

        Test.setMock(HttpCalloutMock.class, new MockUnauthorized());
        Test.startTest();
        List<AA_HerokuBridge.StartResult> res = AA_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();

        System.assertEquals(false, res[0].success);
        System.assertEquals(401, res[0].statusCode);
        // friendly text, not the raw JSON body (audit 2026-10-02 F149)
        System.assert(res[0].errorMessage.contains('rejected'), res[0].errorMessage);
        System.assert(!res[0].errorMessage.contains('{'), res[0].errorMessage);
    }

    // ── startFillFromUi gates (audit 2026-10-02 F157/F142/F149) ────────────

    @IsTest static void ui_unsigned_declaration_is_refused_without_callout() {
        seedConfig('t0ken');
        AA_Application__c app = readyApp('Reviewed', false);
        // No mock set: a callout here would throw "Methods defined as TestMethod
        // do not support Web service callouts", so passing proves none was made.
        Test.startTest();
        String msg;
        try {
            AA_HerokuBridge.startFillFromUi(app.Id, true);
        } catch (AuraHandledException e) {
            msg = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, msg, 'an unsigned declaration must block the fill');
    }

    @IsTest static void ui_signed_declaration_starts_fill() {
        seedConfig('t0ken');
        AA_Application__c app = readyApp('Reviewed', true);
        System.assertEquals(true, [SELECT Declaration_Complete__c FROM AA_Application__c WHERE Id = :app.Id].Declaration_Complete__c);
        Test.setMock(HttpCalloutMock.class, new MockOk());
        Test.startTest();
        String runId = AA_HerokuBridge.startFillFromUi(app.Id, true);
        Test.stopTest();
        System.assertEquals('a1ZTEST0000000001', runId);
    }

    @IsTest static void ui_stage_outside_fill_stages_is_refused() {
        seedConfig('t0ken');
        AA_Application__c app = readyApp('Awaiting DWP Decision', true);
        Test.startTest();
        String msg;
        try {
            AA_HerokuBridge.startFillFromUi(app.Id, true);
        } catch (AuraHandledException e) {
            msg = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, msg, 'Fill on DWP must not start from Awaiting DWP Decision');
    }

    @IsTest static void http_409_is_turned_into_plain_english() {
        seedConfig('t0ken');
        AA_Application__c app = readyApp('Reviewed', true);
        Test.setMock(HttpCalloutMock.class, new MockMandateInactive());
        Test.startTest();
        List<AA_HerokuBridge.StartResult> res = AA_HerokuBridge.startFill(new List<Id>{ app.Id });
        Test.stopTest();
        System.assertEquals(false, res[0].success);
        System.assertEquals(409, res[0].statusCode);
        System.assert(res[0].errorMessage.contains('Direct Debit'), res[0].errorMessage);
        System.assert(res[0].errorMessage.contains('pending_submission'), res[0].errorMessage);
        System.assert(!res[0].errorMessage.contains('{'), res[0].errorMessage);
    }

    @IsTest static void friendly_error_covers_every_heroku_code() {
        System.assert(AA_HerokuBridge.friendlyError(409, '{"error":"already_submitted"}').contains('DWP reference'));
        System.assert(AA_HerokuBridge.friendlyError(409, '{"error":"fill_in_progress"}').contains('already running'));
        System.assert(AA_HerokuBridge.friendlyError(409, '{"error":"declaration_incomplete"}').contains('Declaration'));
        // wave 2 (W3): an open hand-off shows the server's plain instructions
        System.assertEquals('Set Stage back to Reviewed.',
            AA_HerokuBridge.friendlyError(409, '{"error":"review_session_open","hint":"Set Stage back to Reviewed."}'));
        System.assert(AA_HerokuBridge.friendlyError(409, '{"error":"review_session_open"}').contains('still be open'));
        System.assertEquals('Fill on DWP is not available at stage "New".',
            AA_HerokuBridge.friendlyError(409, '{"error":"stage_not_fillable","hint":"Fill on DWP is not available at stage \\"New\\"."}'));
        System.assert(AA_HerokuBridge.friendlyError(404, '{"error":"application_not_found"}').contains('could not find'));
        System.assert(AA_HerokuBridge.friendlyError(500, '{"error":"spawn_failed","hint":"x"}').contains('spawn_failed'));
        System.assert(AA_HerokuBridge.friendlyError(502, 'Bad gateway').contains('HTTP 502'));
    }
}