/**
 * AA_FormMonitorSchedulerTest — the daily walk trigger: posts to Heroku with
 * the internal token, skips quietly when the token is missing, and survives a
 * failed callout.
 */
@isTest
private class AA_FormMonitorSchedulerTest {

    private class RunMock implements HttpCalloutMock {
        Boolean fail;
        RunMock(Boolean fail) { this.fail = fail; }
        public HttpResponse respond(HttpRequest req) {
            if (fail) throw new CalloutException('down');
            System.assert(req.getEndpoint().endsWith('/internal/form-monitor/run'));
            System.assertEquals('POST', req.getMethod());
            System.assertEquals('TOKEN-1', req.getHeader('X-Heroku-Token'));
            HttpResponse r = new HttpResponse();
            r.setStatusCode(202);
            r.setBody('{"ok":true}');
            return r;
        }
    }

    private static void seedToken(String token) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Heroku_Internal_Token__c = token;
        upsert cfg;
    }

    @isTest static void execute_postsToHerokuWithToken() {
        seedToken('TOKEN-1');
        Test.setMock(HttpCalloutMock.class, new RunMock(false));
        Test.startTest();
        System.schedule('AA Form Monitor test', '0 30 3 * * ?', new AA_FormMonitorScheduler());
        AA_FormMonitorScheduler.firePostAsync();
        Test.stopTest();
        System.assertEquals('TOKEN-1', AA_FormMonitorScheduler.getHerokuToken());
    }

    @isTest static void firePostAsync_survivesCalloutFailure() {
        seedToken('TOKEN-1');
        Test.setMock(HttpCalloutMock.class, new RunMock(true));
        Test.startTest();
        AA_FormMonitorScheduler.firePostAsync();
        Test.stopTest();
        System.assertEquals('TOKEN-1', AA_FormMonitorScheduler.getHerokuToken());
    }

    @isTest static void firePostAsync_skipsWithoutToken() {
        seedToken(null);
        Test.startTest();
        AA_FormMonitorScheduler.firePostAsync();
        Test.stopTest();
        System.assertEquals(null, AA_FormMonitorScheduler.getHerokuToken());
    }
}