/**
 * AA_IntakeAdminControllerTest — covers the aaIntakeUsers backend (was 0%
 * covered, audit 2026-10-02 F157) and pins the F131 fixes:
 *   - listUsers is admin-gated like the mutating methods
 *   - setActive(false) and deleteUser call /internal/intake/revoke BEFORE the
 *     DML, and still succeed when that callout fails
 * and the wave-3 one-login-per-sales-agent link (owner decision 2026-10-02):
 *   - only active Sales_Agent__c picklist values can be linked
 *   - one agent per ACTIVE login (link, create and reactivate all enforce it)
 *   - a bad agent is refused BEFORE the set-password callout
 */
@isTest
private class AA_IntakeAdminControllerTest {

    /** Records every callout; answers 200 unless told to fail. */
    private class HerokuMock implements HttpCalloutMock {
        public List<HttpRequest> calls = new List<HttpRequest>();
        public Integer status = 200;
        public HttpResponse respond(HttpRequest req) {
            calls.add(req);
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody('{"ok":true}');
            return r;
        }
    }

    private static void config() {
        insert new AA_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Heroku_Base_Url__c = 'https://aa-autofill.example.test/',
            Internal_Admin_Token__c = 'test-admin-token'
        );
    }

    private static AA_Intake_User__c makeUser(String username, Boolean active) {
        AA_Intake_User__c u = new AA_Intake_User__c(
            Username__c = username, Password_Hash__c = '$2b$10$x', Role__c = 'sales',
            Active__c = active, Failed_Login_Count__c = 3
        );
        insert u;
        return u;
    }

    @isTest static void listUsers_returnsRows() {
        makeUser('alice', true);
        makeUser('bob', false);
        List<AA_IntakeAdminController.UserRow> rows = AA_IntakeAdminController.listUsers();
        System.assertEquals(2, rows.size());
        System.assertEquals('alice', rows[0].username, 'active users sort first');
        System.assertEquals(3, rows[0].failedLoginCount);
    }

    @isTest static void listUsers_refusesNonAdmin() {
        List<Profile> p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (p.isEmpty()) return; // org without the standard profile: nothing to assert
        User u = new User(
            Alias = 'aaiut', Email = 'aa.intake.test@example.test', EmailEncodingKey = 'UTF-8',
            LastName = 'IntakeTest', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_GB',
            ProfileId = p[0].Id, TimeZoneSidKey = 'Europe/London',
            UserName = 'aa.intake.test.' + Crypto.getRandomInteger() + '@example.test'
        );
        insert u;
        Boolean refused = false;
        System.runAs(u) {
            try { AA_IntakeAdminController.listUsers(); }
            catch (AuraHandledException e) { refused = true; }
        }
        System.assert(refused, 'F131: listUsers must require intake-admin');
    }

    @isTest static void createUser_callsSetPassword() {
        config();
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        String body = AA_IntakeAdminController.createUser('  NewAgent ', 'longenough', 'sales', null);
        Test.stopTest();
        System.assertEquals('{"ok":true}', body);
        System.assertEquals(1, m.calls.size());
        System.assertEquals('https://aa-autofill.example.test/internal/intake/set-password', m.calls[0].getEndpoint());
        System.assertEquals('test-admin-token', m.calls[0].getHeader('x-internal-token'));
        System.assert(m.calls[0].getBody().contains('"username":"newagent"'), 'username is trimmed + lower-cased');
    }

    @isTest static void createUser_validation() {
        Integer refused = 0;
        try { AA_IntakeAdminController.createUser('', 'longenough', 'sales', null); } catch (AuraHandledException e) { refused++; }
        try { AA_IntakeAdminController.createUser('x', 'short', 'sales', null); } catch (AuraHandledException e) { refused++; }
        try { AA_IntakeAdminController.createUser('x', 'longenough', 'boss', null); } catch (AuraHandledException e) { refused++; }
        makeUser('dupe', true);
        try { AA_IntakeAdminController.createUser('dupe', 'longenough', 'sales', null); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(4, refused);
    }

    @isTest static void resetPassword_requiresConfig() {
        AA_Intake_User__c u = makeUser('carol', true);
        Boolean refused = false;
        try { AA_IntakeAdminController.resetPassword(u.Id, 'longenough'); }
        catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'missing AA_Config__c must fail loudly');
    }

    @isTest static void resetPassword_callsHeroku() {
        config();
        AA_Intake_User__c u = makeUser('dave', true);
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        AA_IntakeAdminController.resetPassword(u.Id, 'longenough');
        Test.stopTest();
        System.assertEquals(1, m.calls.size());
        System.assert(m.calls[0].getEndpoint().endsWith('/internal/intake/set-password'));
    }

    @isTest static void deactivate_revokesSessionsThenUpdates() {
        config();
        AA_Intake_User__c u = makeUser('erin', true);
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        AA_IntakeAdminController.setActive(u.Id, false);
        Test.stopTest();
        System.assertEquals(1, m.calls.size(), 'F131: deactivate must revoke live sessions');
        System.assert(m.calls[0].getEndpoint().endsWith('/internal/intake/revoke'));
        System.assert(m.calls[0].getBody().contains('"username":"erin"'));
        System.assertEquals(false, [SELECT Active__c FROM AA_Intake_User__c WHERE Id = :u.Id].Active__c);
    }

    @isTest static void deactivate_stillSavesWhenRevokeFails() {
        config();
        AA_Intake_User__c u = makeUser('frank', true);
        HerokuMock m = new HerokuMock();
        m.status = 503;
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        AA_IntakeAdminController.setActive(u.Id, false);
        Test.stopTest();
        System.assertEquals(false, [SELECT Active__c FROM AA_Intake_User__c WHERE Id = :u.Id].Active__c,
            'a Heroku outage must not block a deactivation');
    }

    @isTest static void reactivate_clearsLockWithoutCallout() {
        AA_Intake_User__c u = makeUser('gina', false);
        update new AA_Intake_User__c(Id = u.Id, Locked_At__c = System.now());
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        AA_IntakeAdminController.setActive(u.Id, true);
        AA_Intake_User__c after = [SELECT Active__c, Failed_Login_Count__c, Locked_At__c FROM AA_Intake_User__c WHERE Id = :u.Id];
        System.assertEquals(true, after.Active__c);
        System.assertEquals(0, after.Failed_Login_Count__c);
        System.assertEquals(null, after.Locked_At__c);
        System.assertEquals(0, m.calls.size(), 'reactivation needs no revoke');
    }

    @isTest static void delete_revokesSessionsThenDeletes() {
        config();
        AA_Intake_User__c u = makeUser('hank', true);
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        AA_IntakeAdminController.deleteUser(u.Id);
        Test.stopTest();
        System.assertEquals(1, m.calls.size(), 'F131: delete must revoke live sessions');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Intake_User__c WHERE Id = :u.Id]);
    }

    @isTest static void callRevoke_withoutConfigIsANoop() {
        System.assertEquals(false, AA_IntakeAdminController.callRevoke('nobody'));
        System.assertEquals(false, AA_IntakeAdminController.callRevoke(''));
    }

    // ── wave 3: one login per sales agent ───────────────────────────

    /** First active Sales_Agent__c value on the Application (restricted picklist). */
    private static String anyAgent(Integer i) {
        List<String> agents = AA_IntakeAdminController.listSalesAgents();
        System.assert(agents.size() > i, 'AA_Application__c.Sales_Agent__c needs at least ' + (i + 1) + ' active values');
        return agents[i];
    }

    @isTest static void listSalesAgents_mirrorsApplicationPicklist() {
        List<String> agents = AA_IntakeAdminController.listSalesAgents();
        System.assert(!agents.isEmpty());
        Set<String> picklist = new Set<String>();
        for (Schema.PicklistEntry pe : AA_Application__c.Sales_Agent__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) picklist.add(pe.getValue());
        }
        System.assertEquals(picklist, new Set<String>(agents));
    }

    @isTest static void setSalesAgent_linksUnlinksAndNormalisesCase() {
        AA_Intake_User__c u = makeUser('megan.login', true);
        String agent = anyAgent(0);
        AA_IntakeAdminController.setSalesAgent(u.Id, '  ' + agent.toLowerCase() + ' ');
        System.assertEquals(agent, [SELECT Sales_Agent__c FROM AA_Intake_User__c WHERE Id = :u.Id].Sales_Agent__c,
            'stored as the exact picklist value so the Application insert accepts it');
        System.assertEquals(agent, AA_IntakeAdminController.listUsers()[0].salesAgent);
        AA_IntakeAdminController.setSalesAgent(u.Id, '');
        System.assertEquals(null, [SELECT Sales_Agent__c FROM AA_Intake_User__c WHERE Id = :u.Id].Sales_Agent__c);
    }

    @isTest static void setSalesAgent_rejectsUnknownName() {
        AA_Intake_User__c u = makeUser('someone', true);
        Boolean refused = false;
        try { AA_IntakeAdminController.setSalesAgent(u.Id, 'Not A Real Agent'); }
        catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'only Sales_Agent__c picklist values may be linked');
        System.assertEquals(null, [SELECT Sales_Agent__c FROM AA_Intake_User__c WHERE Id = :u.Id].Sales_Agent__c);
    }

    @isTest static void oneActiveLoginPerAgent() {
        String agent = anyAgent(0);
        AA_Intake_User__c a = makeUser('agent.old', true);
        AA_Intake_User__c b = makeUser('agent.new', true);
        AA_IntakeAdminController.setSalesAgent(a.Id, agent);

        Boolean refused = false;
        try { AA_IntakeAdminController.setSalesAgent(b.Id, agent); }
        catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a second ACTIVE login for the same agent must be refused');

        // Retire the old login (direct update: no revoke callout in this test),
        // then the replacement can take the agent.
        update new AA_Intake_User__c(Id = a.Id, Active__c = false);
        AA_IntakeAdminController.setSalesAgent(b.Id, agent);
        System.assertEquals(agent, [SELECT Sales_Agent__c FROM AA_Intake_User__c WHERE Id = :b.Id].Sales_Agent__c);

        // Reactivating the old login would give the agent two active logins.
        refused = false;
        try { AA_IntakeAdminController.setActive(a.Id, true); }
        catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'reactivation must respect one login per agent');
        System.assertEquals(false, [SELECT Active__c FROM AA_Intake_User__c WHERE Id = :a.Id].Active__c);
    }

    @isTest static void createUser_badAgentRefusedBeforeCallout() {
        config();
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        Boolean refused = false;
        Test.startTest();
        try { AA_IntakeAdminController.createUser('newrep', 'longenough', 'sales', 'Not A Real Agent'); }
        catch (AuraHandledException e) { refused = true; }
        Test.stopTest();
        System.assert(refused);
        System.assertEquals(0, m.calls.size(), 'no half-made login on Heroku for a bad agent');
    }

    @isTest static void createUser_takenAgentRefusedBeforeCallout() {
        config();
        String agent = anyAgent(0);
        AA_Intake_User__c a = makeUser('agent.taken', true);
        AA_IntakeAdminController.setSalesAgent(a.Id, agent);
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        Boolean refused = false;
        Test.startTest();
        try { AA_IntakeAdminController.createUser('agent.second', 'longenough', 'sales', agent); }
        catch (AuraHandledException e) { refused = true; }
        Test.stopTest();
        System.assert(refused);
        System.assertEquals(0, m.calls.size());
    }

    @isTest static void createUser_withAgentCallsHerokuOnce() {
        // The row is created by Heroku in production; in a test the mock does
        // not insert it, so the link step must be a quiet no-op, not an error.
        config();
        HerokuMock m = new HerokuMock();
        Test.setMock(HttpCalloutMock.class, m);
        String agent = anyAgent(0);
        Test.startTest();
        AA_IntakeAdminController.createUser('fresh.rep', 'longenough', 'sales', agent);
        Test.stopTest();
        System.assertEquals(1, m.calls.size());
        System.assert(!m.calls[0].getBody().contains(agent), 'the agent is linked in Salesforce, not sent to Heroku');
    }

    @isTest static void setSalesAgent_refusesNonAdmin() {
        AA_Intake_User__c target = makeUser('target', true);
        List<Profile> p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        if (p.isEmpty()) return;
        User u = new User(
            Alias = 'aaiua', Email = 'aa.intake.agent@example.test', EmailEncodingKey = 'UTF-8',
            LastName = 'IntakeAgentTest', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_GB',
            ProfileId = p[0].Id, TimeZoneSidKey = 'Europe/London',
            UserName = 'aa.intake.agent.' + Crypto.getRandomInteger() + '@example.test'
        );
        insert u;
        Boolean refused = false;
        System.runAs(u) {
            try { AA_IntakeAdminController.setSalesAgent(target.Id, null); }
            catch (AuraHandledException e) { refused = true; }
        }
        System.assert(refused, 'linking a login to an agent is intake-admin only');
    }

    @isTest static void missingIdsAreRefused() {
        Integer refused = 0;
        try { AA_IntakeAdminController.setActive(null, true); } catch (AuraHandledException e) { refused++; }
        try { AA_IntakeAdminController.deleteUser(null); } catch (AuraHandledException e) { refused++; }
        try { AA_IntakeAdminController.resetPassword(null, 'longenough'); } catch (AuraHandledException e) { refused++; }
        try { AA_IntakeAdminController.setSalesAgent(null, null); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(4, refused);
    }
}