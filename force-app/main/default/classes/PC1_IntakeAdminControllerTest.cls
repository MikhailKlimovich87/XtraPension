/**
 * Tests for PC1_IntakeAdminController (admin page "PC Intake Users").
 * Added 2026-10-02 — the class had no test (0%).
 */
@IsTest
private class PC1_IntakeAdminControllerTest {

    private class HerokuMock implements HttpCalloutMock {
        Integer status;
        HerokuMock(Integer status) { this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(status == 200 ? '{"ok":true}' : '{"ok":false,"error":"unauthorized"}');
            return r;
        }
    }

    private static void config(Boolean complete) {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c c = rows.isEmpty() ? new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId()) : new PC1_Config__c(Id = rows[0].Id);
        c.Heroku_Base_Url__c = complete ? 'https://example.herokuapp.com/' : null;
        c.Internal_Admin_Token__c = complete ? 'tok' : null;
        upsert c;
    }

    private static Intake_User__c makeUser(String name) {
        Intake_User__c u = new Intake_User__c(Username__c = name, Role__c = 'sales', Active__c = true, Password_Hash__c = '$2b$12$test',
            Failed_Login_Count__c = 3, Locked_At__c = Datetime.now());
        insert u;
        return u;
    }

    @IsTest static void list_users() {
        makeUser('anna');
        List<PC1_IntakeAdminController.UserRow> rows = PC1_IntakeAdminController.listUsers();
        System.assertEquals(1, rows.size());
        System.assertEquals('anna', rows[0].username);
        System.assertEquals(3, rows[0].failedLoginCount);
    }

    @IsTest static void create_and_reset_call_heroku() {
        config(true);
        Intake_User__c u = makeUser('bob');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200));
        Test.startTest();
        System.assert(PC1_IntakeAdminController.createUser(' Carla ', 'longenough', 'Admin').contains('ok'));
        System.assert(PC1_IntakeAdminController.resetPassword(u.Id, 'longenough').contains('ok'));
        Test.stopTest();
    }

    @IsTest static void create_validation() {
        makeUser('dup');
        String[] cases = new String[]{ '', 'x', 'x', 'x', 'dup' };
        String[] pws = new String[]{ 'longenough', '', 'short', 'longenough', 'longenough' };
        String[] roles = new String[]{ 'sales', 'sales', 'sales', 'boss', 'sales' };
        for (Integer i = 0; i < cases.size(); i++) {
            Boolean threw = false;
            try { PC1_IntakeAdminController.createUser(cases[i], pws[i], roles[i]); } catch (AuraHandledException e) { threw = true; }
            System.assert(threw, 'case ' + i + ' must be rejected');
        }
    }

    @IsTest static void reset_validation_and_heroku_errors() {
        Intake_User__c u = makeUser('eve');
        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_IntakeAdminController.resetPassword(null, 'longenough'); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_IntakeAdminController.resetPassword(u.Id, 'short'); } catch (AuraHandledException e) { t2 = true; }
        try { PC1_IntakeAdminController.resetPassword(u.Id, 'longenough'); } catch (AuraHandledException e) { t3 = true; } // no config
        config(true);
        Test.setMock(HttpCalloutMock.class, new HerokuMock(401));
        try { PC1_IntakeAdminController.resetPassword(u.Id, 'longenough'); } catch (AuraHandledException e) { t4 = true; }
        System.assert(t1 && t2 && t3 && t4);
    }

    @IsTest static void deactivate_revokes_then_saves_and_reactivate_clears_lock() {
        config(true);
        Intake_User__c u = makeUser('fay');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200));
        Test.startTest();
        PC1_IntakeAdminController.setActive(u.Id, false);
        Test.stopTest();
        System.assertEquals(false, [SELECT Active__c FROM Intake_User__c WHERE Id = :u.Id].Active__c);

        PC1_IntakeAdminController.setActive(u.Id, true);   // no callout on activate
        Intake_User__c after = [SELECT Active__c, Failed_Login_Count__c, Locked_At__c FROM Intake_User__c WHERE Id = :u.Id];
        System.assertEquals(true, after.Active__c);
        System.assertEquals(0, after.Failed_Login_Count__c);
        System.assertEquals(null, after.Locked_At__c);
    }

    @IsTest static void revoke_failure_keeps_user_active_and_present() {
        Intake_User__c u = makeUser('gus');
        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_IntakeAdminController.setActive(u.Id, false); } catch (AuraHandledException e) { t1 = true; }  // no config
        config(true);
        Test.setMock(HttpCalloutMock.class, new HerokuMock(500));
        try { PC1_IntakeAdminController.deleteUser(u.Id); } catch (AuraHandledException e) { t2 = true; }
        try { PC1_IntakeAdminController.setActive(null, true); } catch (AuraHandledException e) { t3 = true; }
        try { PC1_IntakeAdminController.setActive(u.Id, null); } catch (AuraHandledException e) { t4 = true; }
        System.assert(t1 && t2 && t3 && t4);
        System.assertEquals(true, [SELECT Active__c FROM Intake_User__c WHERE Id = :u.Id].Active__c, 'no split-brain');
    }

    @IsTest static void delete_revokes_then_deletes() {
        config(true);
        Intake_User__c u = makeUser('hal');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200));
        Test.startTest();
        PC1_IntakeAdminController.deleteUser(u.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Intake_User__c WHERE Id = :u.Id]);
        Boolean threw = false;
        try { PC1_IntakeAdminController.deleteUser(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }
}