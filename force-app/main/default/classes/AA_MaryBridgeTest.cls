/**
 * AA_MaryBridgeTest — the Call Now bridge (AA_MaryBridge.callNow).
 *
 * audit 2026-10-02 F50/F86: Call Now had no stage guard, so a click on an
 * Awarded / Needs Human record rolled the stage back to 'Call In Progress'
 * (the Heroku handler overwrites it), and a second click while a call was
 * live dialled the client twice. The refusals below make no callout at all:
 * a test method without a mock throws on any callout, so reaching the
 * expected AuraHandledException proves Heroku was never contacted.
 * Also lifts the class off 0% coverage (F157).
 */
@isTest
private class AA_MaryBridgeTest {

    private class HerokuMock implements HttpCalloutMock {
        Integer code;
        String body;
        HttpRequest seen;
        HerokuMock(Integer code, String body) { this.code = code; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            seen = req;
            HttpResponse r = new HttpResponse();
            r.setStatusCode(code);
            r.setBody(body);
            return r;
        }
    }

    private static void seedConfig(String base, String token) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Heroku_Base_Url__c = base;
        cfg.Heroku_Internal_Token__c = token;
        upsert cfg;
    }

    private static AA_Application__c makeApp(String stage, Boolean dnc) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Call', Last_Name__c = 'Now' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c = '+441234567890', Stage__c = stage, Do_Not_Contact__c = dnc,
            DWP_Reference__c = 'JT 12 34 56 A'
        );
        insert a;
        return a;
    }

    private static String refusal(Id appId) {
        try {
            AA_MaryBridge.callNow(appId);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest static void dials_from_a_collecting_stage() {
        seedConfig('https://aa.example.com/', 'tok-123');
        AA_Application__c a = makeApp('Partial Data', false);
        HerokuMock mock = new HerokuMock(202, '{"status":"dialing"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String body = AA_MaryBridge.callNow(a.Id);
        Test.stopTest();

        System.assertEquals('{"status":"dialing"}', body, 'the Heroku body is returned to the LWC');
        System.assertEquals('https://aa.example.com/internal/mary/call-now/' + a.Id, mock.seen.getEndpoint(),
            'trailing slash on the base URL is not doubled');
        System.assertEquals('POST', mock.seen.getMethod());
        System.assertEquals('tok-123', mock.seen.getHeader('X-Heroku-Token'), 'the shared secret is sent');
    }

    @isTest static void every_collecting_stage_is_callable() {
        for (String s : AA_MaryBridge.CALLABLE_STAGES) {
            System.assert(new Set<String>{ 'New', 'Awaiting First Call', 'Partial Data', 'Data Complete' }.contains(s),
                'unexpected callable stage ' + s);
        }
        System.assert(!AA_MaryBridge.CALLABLE_STAGES.contains('Call In Progress'), 'a live call must not be re-dialled');
        System.assert(!AA_MaryBridge.CALLABLE_STAGES.contains('Needs Human'), 'Needs Human must not be dialled from Call Now');
    }

    @isTest static void refuses_while_a_call_is_live() {
        seedConfig('https://aa.example.com', 'tok');
        AA_Application__c a = makeApp('Call In Progress', false);
        String msg = refusal(a.Id);
        System.assertNotEquals(null, msg, 'a second Call Now during a live call must be refused (no double dial)');
        System.assert(msg.contains('already on a call'), msg);
        System.assertEquals('Call In Progress', [SELECT Stage__c FROM AA_Application__c WHERE Id = :a.Id].Stage__c);
    }

    @isTest static void refuses_post_collection_stages_without_touching_the_stage() {
        seedConfig('https://aa.example.com', 'tok');
        for (String stage : new List<String>{ 'Awarded', 'Needs Human', 'Submitted', 'Fee Charged' }) {
            AA_Application__c a = makeApp(stage, false);
            String msg = refusal(a.Id);
            System.assertNotEquals(null, msg, stage + ' must not be dialled by Call Now');
            System.assert(msg.contains(stage), 'the message names the current stage: ' + msg);
            System.assertEquals(stage, [SELECT Stage__c FROM AA_Application__c WHERE Id = :a.Id].Stage__c,
                'a refused Call Now leaves the stage alone');
        }
    }

    @isTest static void refuses_do_not_contact() {
        seedConfig('https://aa.example.com', 'tok');
        AA_Application__c a = makeApp('Awaiting First Call', true);
        String msg = refusal(a.Id);
        System.assertNotEquals(null, msg, 'Do Not Contact must block Call Now');
        System.assert(msg.contains('Do Not Contact'), msg);
    }

    @isTest static void surfaces_heroku_errors_and_missing_config() {
        AA_Application__c a = makeApp('Awaiting First Call', false);

        System.assertNotEquals(null, refusal(null), 'a null application id is rejected');
        seedConfig(null, null);
        String noCfg = refusal(a.Id);
        System.assert(noCfg != null && noCfg.contains('Heroku_Base_Url__c'), 'missing config is reported: ' + noCfg);

        seedConfig('https://aa.example.com', 'tok');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(500, 'boom'));
        Test.startTest();
        String httpErr = refusal(a.Id);
        Test.stopTest();
        System.assert(httpErr != null && httpErr.contains('HTTP 500'), 'a Heroku error is surfaced: ' + httpErr);
    }
}