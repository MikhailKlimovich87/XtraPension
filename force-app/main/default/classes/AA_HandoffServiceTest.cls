/**
 * Tests for AA_HandoffService and the two escalation notify triggers
 * (audit 2026-10-02 F75/F80: the class sat at 0/21 covered, and an
 * escalation only produced a Chatter post nobody follows).
 *
 * The ops email is asserted through AA_HandoffService.lastOpsEmail, which is
 * set before Messaging.sendEmail runs, so the assertions hold whatever the
 * org's email deliverability setting is.
 */
@IsTest
private class AA_HandoffServiceTest {

    private static final String OPS = 'ops-alerts@example.test';

    private static void seedAlertEmail(String addr) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Admin_Alert_Email__c = addr;
        upsert cfg;
    }

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Hanna', Last_Name__c = 'Off', Stage__c = 'Partial Data', Phone__c = '+447700900555');
        insert a;
        return [SELECT Id, Name FROM AA_Application__c WHERE Id = :a.Id];
    }

    private static AA_Handoff__c handoff(Id appId, String etype) {
        return new AA_Handoff__c(Application__c = appId, Escalation_Type__c = etype,
            Reason__c = 'Caller said she is not safe at home', Next_Step_Suggestion__c = 'Call back today', Resolved__c = false);
    }

    // ─── escalation → ops email (F75) ───────────────────────────────

    @IsTest static void a_safeguarding_handoff_emails_ops_as_urgent() {
        seedAlertEmail(OPS);
        AA_Application__c app = makeApp();

        Test.startTest();
        insert handoff(app.Id, 'safeguarding');
        Test.stopTest();

        Messaging.SingleEmailMessage m = AA_HandoffService.lastOpsEmail;
        System.assertNotEquals(null, m, 'a new handoff must email the ops mailbox, not only post to Chatter');
        System.assertEquals(new List<String>{ OPS }, m.getToAddresses());
        System.assert(m.getSubject().startsWith('URGENT '), 'safeguarding is urgent: ' + m.getSubject());
        System.assert(m.getSubject().contains(app.Name), m.getSubject());
        System.assert(m.getPlainTextBody().contains('not safe at home'), m.getPlainTextBody());
        System.assert(m.getPlainTextBody().contains('/' + app.Id), 'the email must link to the record: ' + m.getPlainTextBody());
        System.assertEquals(1, [SELECT COUNT() FROM FeedItem WHERE ParentId = :app.Id AND Type = 'TextPost'], 'the Chatter post stays');
    }

    @IsTest static void a_routine_handoff_is_not_marked_urgent() {
        seedAlertEmail(OPS);
        AA_Application__c app = makeApp();
        insert handoff(app.Id, 'technical');
        System.assert(!AA_HandoffService.lastOpsEmail.getSubject().startsWith('URGENT'), AA_HandoffService.lastOpsEmail.getSubject());
    }

    @IsTest static void needs_human_without_a_fresh_handoff_emails_ops() {
        seedAlertEmail(OPS);
        AA_Application__c app = makeApp();
        AA_HandoffService.lastOpsEmail = null;

        Test.startTest();
        update new AA_Application__c(Id = app.Id, Stage__c = 'Needs Human');
        Test.stopTest();

        System.assertNotEquals(null, AA_HandoffService.lastOpsEmail, 'an operator move to Needs Human must reach ops');
        System.assert(AA_HandoffService.lastOpsEmail.getPlainTextBody().contains(app.Name));
    }

    @IsTest static void no_alert_address_means_no_email_and_no_error() {
        seedAlertEmail(null);
        AA_Application__c app = makeApp();
        insert handoff(app.Id, 'distress'); // must not throw
        System.assertEquals(null, AA_HandoffService.lastOpsEmail);
        System.assertEquals(false, AA_HandoffService.emailOps('s', 'b'));
    }

    // ─── LWC bridge ─────────────────────────────────────────────────

    @IsTest static void latest_open_handoff_and_mark_resolved() {
        AA_Application__c app = makeApp();
        System.assertEquals(null, AA_HandoffService.getLatestOpenHandoff(app.Id));
        AA_Handoff__c h = handoff(app.Id, 'confused');
        insert h;

        AA_Handoff__c open = AA_HandoffService.getLatestOpenHandoff(app.Id);
        System.assertEquals(h.Id, open.Id);

        AA_HandoffService.markResolved(h.Id);
        AA_Handoff__c done = [SELECT Resolved__c, Reviewed_At__c, Reviewed_By__c FROM AA_Handoff__c WHERE Id = :h.Id];
        System.assertEquals(true, done.Resolved__c);
        System.assertNotEquals(null, done.Reviewed_At__c);
        System.assertEquals(UserInfo.getUserId(), done.Reviewed_By__c);
        System.assertEquals(null, AA_HandoffService.getLatestOpenHandoff(app.Id), 'resolved handoffs are not "open"');
    }

    @IsTest static void fill_run_panel_data_without_runs() {
        AA_Application__c app = makeApp();
        System.assertEquals(null, AA_HandoffService.getLatestFillRun(app.Id));
        AA_HandoffService.FillRunPanelData d = AA_HandoffService.getFillRunPanelData(app.Id);
        System.assertEquals('Partial Data', d.stage);
        System.assertEquals(null, d.fillRun);
    }
}