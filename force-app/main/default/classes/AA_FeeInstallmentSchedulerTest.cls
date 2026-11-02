/**
 * AA_FeeInstallmentSchedulerTest — covers the scheduler's two responsibilities:
 *
 *   1. Dispatches the Bacs_Advance_Notice template exactly 5 CALENDAR days
 *      before each pending installment's Scheduled_Date__c, exactly once
 *      (per-row Bacs_Notice_Sent__c stamp), and NEVER short: a row that would
 *      be noticed with less than 5 days is moved to today+5 first (audit
 *      2026-10-02 F101/F79/F102).
 *   2. Creates the GoCardless payment for each NOTICED row via
 *      /internal/gocardless/charge-fee with charge_date = Scheduled_Date__c
 *      (create-ahead), and only while the mandate is active (F102).
 *
 * Callouts are stubbed with an HttpCalloutMock so we can drive the endpoint
 * without hitting Heroku. The dispatcher is bypassed via the class-level
 * testBypass flag so we can assert the (appId, installmentNumber) pairs
 * without stubbing AA_MessageDispatcher. The sweep still requires an active
 * Bacs_Advance_Notice template before it stamps anything, so notice tests
 * seed one via seedBacsTemplate().
 */
@isTest
private class AA_FeeInstallmentSchedulerTest {

    private class ChargeMock implements HttpCalloutMock {
        public Integer status = 200;
        public String body = '{"ok":true,"payment_id":"PM_INSTALL","status":"pending_submission"}';
        public List<String> requests = new List<String>();
        public HttpResponse respond(HttpRequest req) {
            requests.add(req.getBody());
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    private static void upsertConfig() {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        AA_Config__c cfg;
        if (rows.isEmpty()) {
            cfg = new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        } else {
            cfg = new AA_Config__c(Id = rows[0].Id);
        }
        cfg.Internal_Admin_Token__c = 'TEST-TOKEN';
        cfg.Auto_Create_DD_Mandate__c = false;    // don't fire the auto-mandate trigger
        upsert cfg;
    }

    private static AA_Application__c makeApp(Integer installments) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c              = 'FI',
            Last_Name__c               = 'Test' + System.now().getTime(),
            Email__c                   = 'fi@example.com',
            DOB__c                     = Date.newInstance(1955, 1, 1),
            Address_Line1__c           = '1 Test St',
            City__c                    = 'London',
            Postcode__c                = 'SW1A 1AA',
            DD_Mandate_Id__c           = 'MD-ACTIVE',
            DD_Mandate_Status__c       = 'active',
            Award_Amount__c            = 800,
            Fee_Plan_Installments__c   = installments,
            Stage__c                   = 'Awarded',
            CurrencyIsoCode            = 'GBP'
        );
        insert a;
        return a;
    }

    /**
     * The notice sweep refuses to stamp rows when no active Bacs_Advance_Notice
     * template exists (the dispatcher would exit silently at templates.isEmpty()),
     * so tests that expect a notice must seed one. Content is irrelevant — the
     * dispatcher is bypassed; subject + body only satisfy the object's own
     * validation rules (Email_Requires_Subject, Simple_Requires_Content_Text).
     */
    private static void seedBacsTemplate() {
        insert new AA_Message_Template__c(
            Channel__c          = 'Email',
            Trigger_Event__c    = 'Bacs_Advance_Notice',
            Active__c           = true,
            Subject_Template__c = 'Bacs advance notice (test)',
            Body_Template__c    = 'test body'
        );
    }

    private static List<AA_Fee_Installment__c> makeInstallments(Id appId, Integer plan, Date firstDate) {
        List<AA_Fee_Installment__c> rows = new List<AA_Fee_Installment__c>();
        Decimal fee = 160;   // 20% of 800
        Decimal per = (fee / plan).setScale(2, System.RoundingMode.HALF_UP);
        Decimal remainder = fee - (per * (plan - 1));
        for (Integer i = 1; i <= plan; i++) {
            rows.add(new AA_Fee_Installment__c(
                Application__c        = appId,
                Installment_Number__c = i,
                Scheduled_Date__c     = firstDate.addMonths(i - 1),
                Amount__c             = (i == plan) ? remainder : per,
                Payment_Status__c     = 'pending'
            ));
        }
        insert rows;
        return rows;
    }

    private static AA_Fee_Installment__c row(Id appId, Integer n, Date d, String status, Boolean noticed) {
        return new AA_Fee_Installment__c(
            Application__c = appId, Installment_Number__c = n,
            Scheduled_Date__c = d, Amount__c = 53.33,
            Payment_Status__c = status, Bacs_Notice_Sent__c = noticed);
    }

    // -----------------------------------------------------------------
    // Notice at exactly T-5, then the payment is created the same run with
    // charge_date = the noticed date; the row stays 'pending' until the
    // payments.submitted webhook.
    // -----------------------------------------------------------------
    @isTest static void run_noticesAtTMinus5_thenCreatesPaymentWithChargeDate() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(3);
        Date today = Date.today();
        makeInstallments(a.Id, 3, today.addDays(5));

        ChargeMock mock = new ChargeMock();
        Test.setMock(HttpCalloutMock.class, mock);
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();

        // Production runs the two steps in separate transactions (Schedulable
        // + Queueable); the notice stamp is DML, so it goes before startTest
        // and the callout after it.
        Integer[] nres = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);
        Test.startTest();
        AA_FeeInstallmentScheduler.ChargeResult cr = AA_FeeInstallmentScheduler.chargeDue(today);
        Test.stopTest();

        System.assertEquals(1, nres[0], 'one notice');
        System.assertEquals(1, cr.fired, 'payment created the same day as the notice');
        System.assertEquals(1, mock.requests.size());
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0]);
        System.assertEquals(String.valueOf(today.addDays(5)), sent.get('charge_date'),
            'GoCardless must debit on the date the notice stated');
        System.assertEquals('installment_1', sent.get('charge_stage'));
        System.assert(!String.valueOf(sent.get('description')).contains(String.fromCharArray(new List<Integer>{ 8212 })), 'no em dash in payer-facing text');

        AA_Fee_Installment__c[] rows = [
            SELECT Installment_Number__c, Payment_Status__c, Payment_Id__c, Charged_At__c, Bacs_Notice_Sent__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id ORDER BY Installment_Number__c
        ];
        System.assertEquals('PM_INSTALL', rows[0].Payment_Id__c);
        System.assertEquals('pending', rows[0].Payment_Status__c);
        System.assertNotEquals(null, rows[0].Charged_At__c);
        System.assertEquals(true, rows[0].Bacs_Notice_Sent__c);
        System.assertEquals(false, rows[1].Bacs_Notice_Sent__c, '#2 is a month out');
        System.assertEquals(null, rows[1].Payment_Id__c);

        // Exactly once: a second run the same day neither re-notices nor re-creates.
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Integer[] nres2 = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);
        AA_FeeInstallmentScheduler.ChargeResult cr2 = AA_FeeInstallmentScheduler.chargeDue(today);
        System.assertEquals(0, nres2[0]);
        System.assertEquals(0, cr2.due);
        System.assertEquals(1, mock.requests.size(), 'no second GoCardless call');
    }

    // audit 2026-10-02 F101: the old sweep charged a row due TODAY with no
    // notice and let GoCardless pick a later date. A row dated today that was
    // never noticed is now moved to today+5 and noticed, not charged.
    @isTest static void run_unnoticedRowDueToday_isMovedAndNoticed_notCharged() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today, 'pending', false);

        ChargeMock mock = new ChargeMock();
        mock.body = '{"ok":true,"payment_id":"PM_X","status":"pending_submission"}';
        Test.setMock(HttpCalloutMock.class, mock);
        AA_FeeInstallmentScheduler.testBypass = true;
        Integer[] res = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);

        AA_Fee_Installment__c r = [SELECT Scheduled_Date__c, Bacs_Notice_Sent__c, Payment_Id__c
                                     FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals(1, res[0]);
        System.assertEquals(today.addDays(5), r.Scheduled_Date__c, 'never noticed short: moved to today+5');
        System.assertEquals(true, r.Bacs_Notice_Sent__c);
        System.assertEquals(null, r.Payment_Id__c);
        AA_Application__c app = [SELECT Fee_Plan_Next_Charge_Date__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(today.addDays(5), app.Fee_Plan_Next_Charge_Date__c);
    }

    // audit 2026-10-02 F102: after a mandate gap, two overdue instalments must
    // not be collected together: the moved rows keep a month between them.
    @isTest static void run_overdueRows_keepAMonthApart() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(3);
        Date today = Date.today();
        insert new List<AA_Fee_Installment__c>{
            row(a.Id, 1, today.addDays(-40), 'pending', false),
            row(a.Id, 2, today.addDays(-10), 'pending', false),
            row(a.Id, 3, today.addDays(20), 'pending', false)
        };
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.sendAdvanceNotices(today);

        Map<Integer, AA_Fee_Installment__c> byN = new Map<Integer, AA_Fee_Installment__c>();
        for (AA_Fee_Installment__c r : [SELECT Installment_Number__c, Scheduled_Date__c, Bacs_Notice_Sent__c
                                           FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]) {
            byN.put(r.Installment_Number__c.intValue(), r);
        }
        System.assertEquals(today.addDays(5), byN.get(1).Scheduled_Date__c);
        System.assertEquals(true, byN.get(1).Bacs_Notice_Sent__c);
        System.assertEquals(today.addDays(5).addMonths(1), byN.get(2).Scheduled_Date__c);
        System.assertEquals(false, byN.get(2).Bacs_Notice_Sent__c);
        System.assertEquals(today.addDays(5).addMonths(2), byN.get(3).Scheduled_Date__c);
    }

    // audit 2026-10-02 F102: a cancelled mandate stops both the "we will
    // collect" notice and the collection.
    @isTest static void run_inactiveMandate_noNoticeNoCharge() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        a.DD_Mandate_Status__c = 'cancelled';
        update a;
        Date today = Date.today();
        insert new List<AA_Fee_Installment__c>{
            row(a.Id, 1, today.addDays(5), 'pending', false)
        };
        ChargeMock mock = new ChargeMock();
        Test.setMock(HttpCalloutMock.class, mock);
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.startTest();
        String summary = AA_FeeInstallmentScheduler.run(today);
        Test.stopTest();
        System.assert(summary.contains('notices=0') && summary.contains('fired=0'), summary);
        System.assertEquals(0, mock.requests.size());
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size());
    }

    @isTest static void run_doNotContact_noNoticeNoCharge() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        a.Do_Not_Contact__c = true;
        update a;
        insert row(a.Id, 1, Date.today().addDays(5), 'pending', false);
        AA_FeeInstallmentScheduler.testBypass = true;
        Integer[] res = AA_FeeInstallmentScheduler.sendAdvanceNotices(Date.today());
        System.assertEquals(0, res[0]);
    }

    // -----------------------------------------------------------------
    // Owner decision (Fernando 2026-10-02): Do Not Contact PAUSES the fee.
    // No notice, no charge; uncreated rows lose their notice stamp; ONE
    // handoff per pause, listing what is already at GoCardless.
    // -----------------------------------------------------------------
    private static List<AA_Handoff__c> pauseHandoffs(Id appId) {
        return [SELECT Id, Reason__c, Escalation_Type__c, Resolved__c, Last_Field_Id__c, Next_Step_Suggestion__c
                  FROM AA_Handoff__c
                 WHERE Application__c = :appId AND Reason__c = :AA_FeeInstallmentScheduler.DNC_PAUSE_REASON
                 ORDER BY CreatedDate, Id];
    }

    @isTest static void dncPause_noNoticeNoCharge_clearsNotice_raisesOneHandoff() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(3);
        Date today = Date.today();
        AA_Fee_Installment__c noticed = row(a.Id, 1, today.addDays(3), 'pending', true);
        AA_Fee_Installment__c atGc    = row(a.Id, 2, today.addDays(2), 'pending', true);
        atGc.Charged_At__c = Datetime.now().addDays(-3);
        atGc.Payment_Id__c = 'PM_ALREADY_AT_GC';
        AA_Fee_Installment__c later   = row(a.Id, 3, today.addDays(4), 'pending', false);
        insert new List<AA_Fee_Installment__c>{ noticed, atGc, later };
        a.Do_Not_Contact__c = true;
        update a;

        ChargeMock mock = new ChargeMock();
        Test.setMock(HttpCalloutMock.class, mock);
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.startTest();
        String summary = AA_FeeInstallmentScheduler.run(today);
        AA_FeeInstallmentScheduler.run(today);          // the next daily run
        Test.stopTest();

        System.assertEquals(0, mock.requests.size(), 'nothing may be charged: ' + summary);
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size(), 'no notice may be sent');
        Map<Id, AA_Fee_Installment__c> after = new Map<Id, AA_Fee_Installment__c>([
            SELECT Id, Payment_Status__c, Bacs_Notice_Sent__c, Bacs_Notice_Sent_At__c, Scheduled_Date__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]);
        // Wave 4: an uncreated row is held as 'paused' (not failed, not left
        // looking like an instalment about to be collected); a row already at
        // GoCardless stays 'pending' because it WILL be collected unless ops
        // cancels it.
        System.assertEquals(AA_FeeInstallmentScheduler.STATUS_PAUSED, after.get(noticed.Id).Payment_Status__c,
            'an uncreated row is paused');
        System.assertEquals('paused', after.get(later.Id).Payment_Status__c,
            'lowercase API name of the picklist value');
        System.assertEquals('pending', after.get(atGc.Id).Payment_Status__c,
            'a row already at GoCardless is not called paused');
        AA_Application__c app = [SELECT Fee_Plan_Next_Charge_Date__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(today.addDays(2), app.Fee_Plan_Next_Charge_Date__c,
            'only the payment already at GoCardless is a next charge while paused');
        System.assertEquals(false, after.get(noticed.Id).Bacs_Notice_Sent__c,
            'an uncreated row must be noticed again before any collection after the pause');
        System.assertEquals(today.addDays(3), after.get(noticed.Id).Scheduled_Date__c, 'not re-dated while paused');
        System.assertEquals(true, after.get(atGc.Id).Bacs_Notice_Sent__c, 'a row already at GoCardless is left as it is');

        List<AA_Handoff__c> hs = pauseHandoffs(a.Id);
        System.assertEquals(1, hs.size(), 'one handoff per pause, not one per daily run');
        System.assertEquals('other', hs[0].Escalation_Type__c);
        System.assertEquals(false, hs[0].Resolved__c);
        System.assertEquals(AA_FeeInstallmentScheduler.DNC_PAUSE_ACTIVE, hs[0].Last_Field_Id__c);
        System.assert(hs[0].Next_Step_Suggestion__c.contains('PM_ALREADY_AT_GC'),
            'ops must be told which payment to cancel at GoCardless: ' + hs[0].Next_Step_Suggestion__c);
        System.assert(!hs[0].Next_Step_Suggestion__c.contains('—'), 'no em dashes');
    }

    // Ops resolving the handoff while the client is still Do Not Contact
    // acknowledges the pause: no second handoff the next day.
    @isTest static void dncPause_resolvedByOpsWhileStillPaused_notRaisedAgain() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        insert row(a.Id, 1, Date.today().addDays(10), 'pending', false);
        a.Do_Not_Contact__c = true;
        update a;
        AA_FeeInstallmentScheduler.pauseDoNotContact(Date.today());
        List<AA_Handoff__c> hs = pauseHandoffs(a.Id);
        System.assertEquals(1, hs.size());
        AA_HandoffService.markResolved(hs[0].Id);

        Test.startTest();
        AA_FeeInstallmentScheduler.PauseResult pr = AA_FeeInstallmentScheduler.pauseDoNotContact(Date.today());
        Test.stopTest();
        System.assertEquals(0, pr.handoffs);
        System.assertEquals(1, pauseHandoffs(a.Id).size());
    }

    // Clearing the flag resumes normally: the handoff is closed with a note,
    // a row whose date passed during the pause is re-dated and noticed afresh
    // (NOT held as a failed creation), and a later pause raises a new handoff.
    @isTest static void dncCleared_resumesWithFreshNotice_thenNewPauseNewHandoff() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        AA_Fee_Installment__c r = row(a.Id, 1, today.addDays(-1), 'pending', true);   // noticed before the pause
        insert r;
        a.Do_Not_Contact__c = true;
        update a;
        AA_FeeInstallmentScheduler.pauseDoNotContact(today);
        System.assertEquals('paused', [SELECT Payment_Status__c FROM AA_Fee_Installment__c WHERE Id = :r.Id].Payment_Status__c);

        a.Do_Not_Contact__c = false;
        update a;
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.startTest();
        AA_FeeInstallmentScheduler.PauseResult pr = AA_FeeInstallmentScheduler.pauseDoNotContact(today);
        Integer[] nres = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);
        Test.stopTest();

        System.assertEquals(1, pr.resumed);
        System.assertEquals(1, pr.restored, 'the paused row is put back to pending');
        List<AA_Handoff__c> hs = pauseHandoffs(a.Id);
        System.assertEquals(1, hs.size());
        System.assertEquals(true, hs[0].Resolved__c);
        System.assertEquals(AA_FeeInstallmentScheduler.DNC_PAUSE_ENDED, hs[0].Last_Field_Id__c);
        System.assert(hs[0].Next_Step_Suggestion__c.startsWith(AA_FeeInstallmentScheduler.DNC_RESUMED_MARK));

        AA_Fee_Installment__c after = [SELECT Payment_Status__c, Scheduled_Date__c, Bacs_Notice_Sent__c
                                         FROM AA_Fee_Installment__c WHERE Id = :r.Id];
        System.assertEquals('pending', after.Payment_Status__c, 'resumed, not held as failed');
        System.assertEquals(today.addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS), after.Scheduled_Date__c);
        System.assertEquals(true, after.Bacs_Notice_Sent__c);
        System.assertEquals(1, nres[0], 'a fresh notice goes out on resume');

        // A second pause is a new episode: a new handoff.
        a.Do_Not_Contact__c = true;
        update a;
        AA_FeeInstallmentScheduler.pauseDoNotContact(today);
        hs = pauseHandoffs(a.Id);
        System.assertEquals(2, hs.size());
        System.assertEquals(AA_FeeInstallmentScheduler.DNC_PAUSE_ACTIVE, hs[1].Last_Field_Id__c);
        AA_Fee_Installment__c again = [SELECT Payment_Status__c, Bacs_Notice_Sent__c FROM AA_Fee_Installment__c WHERE Id = :r.Id];
        System.assertEquals('paused', again.Payment_Status__c, 'the second pause holds the row again');
        System.assertEquals(false, again.Bacs_Notice_Sent__c, 'and voids the notice sent during the gap');
    }

    // Wave 4: a paused row is invisible to both sweeps while the flag is set,
    // and only 'paused' rows are restored: a failed or cancelled row on the
    // same plan keeps its status when the flag is cleared.
    @isTest static void dncCleared_restoresOnlyPausedRows() {
        upsertConfig();
        AA_Application__c a = makeApp(3);
        Date today = Date.today();
        AA_Fee_Installment__c failed = row(a.Id, 1, today.addDays(-20), 'failed', true);
        AA_Fee_Installment__c held   = row(a.Id, 2, today.addDays(10), 'pending', false);
        AA_Fee_Installment__c gone   = row(a.Id, 3, today.addDays(40), 'cancelled', false);
        insert new List<AA_Fee_Installment__c>{ failed, held, gone };
        a.Do_Not_Contact__c = true;
        update a;
        AA_FeeInstallmentScheduler.PauseResult p1 = AA_FeeInstallmentScheduler.pauseDoNotContact(today);
        System.assertEquals(1, p1.unnoticed);

        a.Do_Not_Contact__c = false;
        update a;
        Test.startTest();
        AA_FeeInstallmentScheduler.PauseResult p2 = AA_FeeInstallmentScheduler.pauseDoNotContact(today);
        Test.stopTest();
        System.assertEquals(1, p2.restored);
        Map<Id, AA_Fee_Installment__c> after = new Map<Id, AA_Fee_Installment__c>(
            [SELECT Id, Payment_Status__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]);
        System.assertEquals('failed', after.get(failed.Id).Payment_Status__c);
        System.assertEquals('pending', after.get(held.Id).Payment_Status__c);
        System.assertEquals('cancelled', after.get(gone.Id).Payment_Status__c);
        System.assertEquals(today.addDays(10),
            [SELECT Fee_Plan_Next_Charge_Date__c FROM AA_Application__c WHERE Id = :a.Id].Fee_Plan_Next_Charge_Date__c,
            'the restored row is the next charge again');
    }

    // The production entrypoint runs the pause before the notice step.
    @isTest static void execute_pausesDoNotContactBeforeNotices() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        AA_Fee_Installment__c r = row(a.Id, 1, Date.today().addDays(4), 'pending', true);
        insert r;
        a.Do_Not_Contact__c = true;
        update a;
        AA_FeeInstallmentScheduler.testBypass = true;
        ChargeMock mock = new ChargeMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new AA_FeeInstallmentScheduler().execute(null);
        Test.stopTest();
        System.assertEquals(0, mock.requests.size());
        AA_Fee_Installment__c after = [SELECT Bacs_Notice_Sent__c, Payment_Status__c FROM AA_Fee_Installment__c WHERE Id = :r.Id];
        System.assertEquals(false, after.Bacs_Notice_Sent__c);
        System.assertEquals('paused', after.Payment_Status__c);
        System.assertEquals(1, pauseHandoffs(a.Id).size());
    }

    // A row sitting 6+ days out is left alone by the notice step.
    @isTest static void run_rowBeyondHorizon_untouched() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        insert row(a.Id, 1, Date.today().addDays(6), 'pending', false);
        AA_FeeInstallmentScheduler.testBypass = true;
        Integer[] res = AA_FeeInstallmentScheduler.sendAdvanceNotices(Date.today());
        AA_Fee_Installment__c r = [SELECT Scheduled_Date__c, Bacs_Notice_Sent__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals(0, res[0]);
        System.assertEquals(Date.today().addDays(6), r.Scheduled_Date__c);
        System.assertEquals(false, r.Bacs_Notice_Sent__c);
    }

    // -----------------------------------------------------------------
    // No active Bacs_Advance_Notice template: the dispatcher would return
    // normally and exit at templates.isEmpty(), so stamping here would mark
    // the row "Bacs Notice Sent" with no email behind it. The sweep must leave
    // the row unstamped (and therefore uncollectable) and report an error. An
    // inactive (retired) template must not count either.
    // -----------------------------------------------------------------
    @isTest static void run_noActiveBacsTemplate_leavesRowUnstamped() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', false);
        insert new AA_Message_Template__c(
            Channel__c = 'Email', Trigger_Event__c = 'Bacs_Advance_Notice',
            Active__c = false, Subject_Template__c = 'retired', Body_Template__c = 'retired'
        );

        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.startTest();
        Integer[] res = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);
        Test.stopTest();

        System.assertEquals(0, res[0], 'nothing may be counted as dispatched');
        System.assertEquals(1, res[1], 'a missing template must surface as an error');
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size());
        AA_Fee_Installment__c r = [
            SELECT Bacs_Notice_Sent__c, Bacs_Notice_Sent_At__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id
        ];
        System.assertEquals(false, r.Bacs_Notice_Sent__c);
        System.assertEquals(null, r.Bacs_Notice_Sent_At__c);
    }

    // -----------------------------------------------------------------
    // Failure paths of the create-ahead step
    // -----------------------------------------------------------------
    @isTest static void chargeDue_calloutFail_leavesRowUncreated() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', true);

        ChargeMock fail = new ChargeMock();
        fail.status = 502;
        fail.body = '{"ok":false,"error":"gocardless_call_failed"}';
        Test.setMock(HttpCalloutMock.class, fail);

        Test.startTest();
        AA_FeeInstallmentScheduler.ChargeResult cr = AA_FeeInstallmentScheduler.chargeDue(today);
        Test.stopTest();

        System.assertEquals(1, cr.errored);
        AA_Fee_Installment__c r = [SELECT Payment_Status__c, Charged_At__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals('pending', r.Payment_Status__c);
        System.assertEquals(null, r.Charged_At__c, 'stays uncreated so tomorrow retries');
    }

    // GoCardless refuses a charge_date before the mandate's next possible
    // date: the row is moved past it and its notice cleared, so the client is
    // told the real date before anything is taken.
    @isTest static void chargeDue_chargeDateTooSoon_movesRowAndClearsNotice() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', true);
        Date npcd = today.addDays(9);

        ChargeMock tooSoon = new ChargeMock();
        tooSoon.status = 409;
        tooSoon.body = '{"ok":false,"error":"charge_date_too_soon","next_possible_charge_date":"' + String.valueOf(npcd) + '"}';
        Test.setMock(HttpCalloutMock.class, tooSoon);

        Test.startTest();
        AA_FeeInstallmentScheduler.ChargeResult cr = AA_FeeInstallmentScheduler.chargeDue(today);
        Test.stopTest();

        System.assertEquals(1, cr.redated);
        AA_Fee_Installment__c r = [SELECT Scheduled_Date__c, Bacs_Notice_Sent__c, Charged_At__c
                                     FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals(npcd, r.Scheduled_Date__c);
        System.assertEquals(false, r.Bacs_Notice_Sent__c, 'a fresh notice must go out for the new date');
        System.assertEquals(null, r.Charged_At__c);
    }

    // -----------------------------------------------------------------
    // wave-2 W1: a permanent refusal must not loop. It used to be only
    // System.debug'd; the row stayed noticed + uncreated, and once its date
    // passed the notice step re-dated it and emailed the client again, every
    // 5-6 days, forever, with no Task.
    // -----------------------------------------------------------------
    @isTest static void chargeDue_terminalRefusal_holdsRowAndRaisesTask() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', true);

        ChargeMock refused = new ChargeMock();
        refused.status = 409;
        refused.body = '{"ok":false,"error":"no_mandate_on_application"}';
        Test.setMock(HttpCalloutMock.class, refused);

        Test.startTest();
        AA_FeeInstallmentScheduler.ChargeResult cr = AA_FeeInstallmentScheduler.chargeDue(today);
        Test.stopTest();

        System.assertEquals(1, cr.held, 'a terminal refusal holds the row');
        AA_Fee_Installment__c r = [SELECT Payment_Status__c, Charged_At__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals('failed', r.Payment_Status__c, 'on hold: out of both sweeps, Retry shows on the card');
        List<Task> tasks = [SELECT Subject, Priority FROM Task WHERE WhatId = :a.Id];
        System.assertEquals(1, tasks.size(), 'ops must be told');
        System.assertEquals('High', tasks[0].Priority);

        // Days later (the date has passed): no re-date, no second notice.
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        seedBacsTemplate();
        Integer[] nres = AA_FeeInstallmentScheduler.sendAdvanceNotices(today.addDays(6));
        System.assertEquals(0, nres[0]);
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size(), 'the client is not re-noticed');
    }

    // A transient failure (5xx) is retried by the next sweep, not held.
    @isTest static void isTerminalRefusal_classifies() {
        System.assertEquals(true,  AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 409, 'error' => 'payment_not_retryable' }));
        System.assertEquals(true,  AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 400, 'error' => 'bad_charge_stage' }));
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 409, 'error' => 'charge_date_too_soon' }));
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 409, 'error' => 'mandate_not_charge_ready' }));
        // Heroku's copy of the stage / Do Not Contact gates (integrator 2026-10-02).
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 409, 'error' => 'stage_not_collectable' }));
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 409, 'error' => 'do_not_contact' }));
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 401, 'error' => 'unauthorized' }));
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 502, 'error' => 'gocardless_call_failed' }));
        System.assertEquals(false, AA_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'error' => 'Endpoint unreachable: x' }));
    }

    // A noticed row whose date passed without its payment being created is
    // held with a Task, never moved and re-noticed (the old loop).
    @isTest static void run_noticedRowPassedUncreated_isHeldNotReNoticed() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(-1), 'pending', true);

        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Integer[] res = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);

        AA_Fee_Installment__c r = [SELECT Scheduled_Date__c, Payment_Status__c, Bacs_Notice_Sent__c
                                     FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals(0, res[0], 'no second notice');
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size());
        System.assertEquals('failed', r.Payment_Status__c);
        System.assertEquals(today.addDays(-1), r.Scheduled_Date__c, 'not re-dated');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :a.Id AND Priority = 'High']);
        System.assertEquals(null, [SELECT Fee_Plan_Next_Charge_Date__c FROM AA_Application__c WHERE Id = :a.Id].Fee_Plan_Next_Charge_Date__c,
            'nothing left scheduled');
    }

    // Status 'active' with a blank mandate id (mandate document pending,
    // audit F103): Heroku refuses every charge, so nothing is noticed.
    @isTest static void run_activeStatusButNoMandateId_noNoticeNoCharge() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        a.DD_Mandate_Id__c = null;
        update a;
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', false);
        insert row(a.Id, 2, today.addDays(4), 'pending', true);
        ChargeMock mock = new ChargeMock();
        Test.setMock(HttpCalloutMock.class, mock);
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.startTest();
        String summary = AA_FeeInstallmentScheduler.run(today);
        Test.stopTest();
        System.assert(summary.contains('notices=0') && summary.contains('fired=0'), summary);
        System.assertEquals(0, mock.requests.size());
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size());
    }

    // wave-2 W3 (deploy order): an older Heroku build ignores charge_date and
    // GoCardless picks an EARLIER date than the notice gave. The payment is
    // stamped (it exists) but an urgent Task goes out.
    @isTest static void chargeDue_gcDateEarlierThanNoticed_raisesUrgentTask() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', true);
        ChargeMock mock = new ChargeMock();
        mock.body = '{"ok":true,"payment_id":"PM_EARLY","status":"pending_submission","charge_date":"' +
            String.valueOf(today.addDays(3)) + '"}';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        AA_FeeInstallmentScheduler.chargeDue(today);
        Test.stopTest();
        AA_Fee_Installment__c r = [SELECT Payment_Id__c, Scheduled_Date__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals('PM_EARLY', r.Payment_Id__c);
        System.assertEquals(today.addDays(3), r.Scheduled_Date__c, 'the ledger shows the real debit date');
        List<Task> t = [SELECT Subject FROM Task WHERE WhatId = :a.Id];
        System.assertEquals(1, t.size());
        System.assert(t[0].Subject.contains('EARLY'), t[0].Subject);
    }

    // A failed row put back by retryInstallment carries its old payment id:
    // the sweep asks Node to re-collect THAT payment, not create a duplicate.
    @isTest static void chargeDue_retriedRow_sendsRetryPaymentId() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        AA_Fee_Installment__c r0 = row(a.Id, 1, today.addDays(5), 'pending', true);
        r0.Payment_Id__c = 'PM_OLD_FAILED';
        insert r0;
        ChargeMock mock = new ChargeMock();
        mock.body = '{"ok":true,"payment_id":"PM_OLD_FAILED","status":"pending_submission"}';
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        AA_FeeInstallmentScheduler.chargeDue(today);
        Test.stopTest();
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0]);
        System.assertEquals('PM_OLD_FAILED', sent.get('retry_payment_id'));
    }

    // -----------------------------------------------------------------
    // Async path (audit #1/#2): the charge Queueable does the callout in an
    // AllowsCallouts context; it flushes at Test.stopTest().
    // -----------------------------------------------------------------
    @isTest static void queueable_createsNoticedInstallment() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', true);

        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        System.enqueueJob(new AA_FeeInstallmentChargeQueueable(today));
        Test.stopTest();

        AA_Fee_Installment__c r = [
            SELECT Payment_Status__c, Payment_Id__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id
        ];
        System.assertEquals('pending', r.Payment_Status__c);
        System.assertEquals('PM_INSTALL', r.Payment_Id__c);
    }

    // -----------------------------------------------------------------
    // Schedulable entrypoint: execute() sends notices inline and enqueues the
    // charge Queueable, which creates the noticed row's payment at
    // Test.stopTest(). This is the real production path.
    // -----------------------------------------------------------------
    @isTest static void execute_sendsNoticesAndEnqueuesCharge() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        insert row(a.Id, 1, today.addDays(5), 'pending', false);

        AA_FeeInstallmentScheduler.testBypass = true;
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        new AA_FeeInstallmentScheduler().execute(null);
        Test.stopTest();   // flushes the enqueued charge Queueable

        AA_Fee_Installment__c r = [
            SELECT Payment_Id__c, Bacs_Notice_Sent__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id
        ];
        System.assertEquals(true, r.Bacs_Notice_Sent__c);
        System.assertEquals('PM_INSTALL', r.Payment_Id__c,
            'execute() must enqueue the charge Queueable that creates the noticed instalment');
    }
    // -----------------------------------------------------------------
    // Integrator 2026-10-02 (wave-4 critical): the sweep used to notice and
    // collect in every stage outside HALT_STAGES while the dispatcher sends
    // the Bacs advance notice only in its FeeCollection stages. In the gap
    // ('Mandatory Reconsideration Requested', 'Needs Human', ...) the notice
    // was suppressed, the row was still stamped as noticed, and the client
    // was charged with no 5-day notice. COLLECTABLE_STAGES is now derived
    // from the dispatcher's gate.
    // -----------------------------------------------------------------

    // Fails if the two lists ever diverge: a collectable stage where the
    // notice would be suppressed is a charge without notice.
    @isTest static void collectableStages_neverWiderThanTheNoticeGate() {
        Set<String> picklist = new Set<String>();
        for (Schema.PicklistEntry e : Schema.SObjectType.AA_Application__c.fields.Stage__c.getPicklistValues()) {
            picklist.add(e.getValue());
            if (AA_FeeInstallmentScheduler.isCollectableStage(e.getValue())) {
                System.assert(AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', e.getValue()),
                    'the sweep would collect at "' + e.getValue() + '" where the Bacs advance notice is suppressed');
            }
        }
        Set<String> collectable = AA_FeeInstallmentScheduler.collectableStages();
        System.assert(!collectable.isEmpty() && collectable.contains('Awarded'),
            'fee collection must run after an award: ' + collectable);
        for (String s : collectable) {
            System.assert(picklist.contains(s), '"' + s + '" is not a Stage__c value');
            System.assert(AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', s), s);
        }
        for (String s : AA_FeeInstallmentScheduler.HALT_STAGES) {
            System.assert(!AA_FeeInstallmentScheduler.isCollectableStage(s), 'halted stage is collectable: ' + s);
        }
        System.assert(!AA_FeeInstallmentScheduler.isCollectableStage(null));
        System.assert(!AA_FeeInstallmentScheduler.isCollectableStage('Mandatory Reconsideration Requested'));
        // A copy: changing it must not widen the gate.
        collectable.add('Mandatory Reconsideration Requested');
        System.assert(!AA_FeeInstallmentScheduler.isCollectableStage('Mandatory Reconsideration Requested'));
    }

    // The behaviour itself: at a stage where the notice is gated, an
    // un-noticed row is not noticed and a row noticed earlier (while the
    // case was still Awarded) is not charged.
    @isTest static void run_stageWhereNoticeIsGated_noNoticeNoCharge() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(2);
        Date today = Date.today();
        AA_Fee_Installment__c noticedEarlier = row(a.Id, 1, today.addDays(3), 'pending', true);
        AA_Fee_Installment__c dueNotice      = row(a.Id, 2, today.addDays(5), 'pending', false);
        insert new List<AA_Fee_Installment__c>{ noticedEarlier, dueNotice };
        update new AA_Application__c(Id = a.Id, Stage__c = 'Mandatory Reconsideration Requested');
        System.assert(!AA_MessageDispatcher.stageAllows('Bacs_Advance_Notice', 'Mandatory Reconsideration Requested'),
            'precondition: the dispatcher suppresses the notice at this stage');

        ChargeMock mock = new ChargeMock();
        Test.setMock(HttpCalloutMock.class, mock);
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.startTest();
        String summary = AA_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        System.assertEquals(0, mock.requests.size(), 'nothing may be collected where the notice cannot go: ' + summary);
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size(), 'no notice handed to the dispatcher');
        Map<Id, AA_Fee_Installment__c> after = new Map<Id, AA_Fee_Installment__c>([
            SELECT Id, Payment_Status__c, Charged_At__c, Bacs_Notice_Sent__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]);
        System.assertEquals(false, after.get(dueNotice.Id).Bacs_Notice_Sent__c, 'not stamped as noticed');
        System.assertEquals(null, after.get(noticedEarlier.Id).Charged_At__c, 'not created at GoCardless');
        System.assertEquals('pending', after.get(noticedEarlier.Id).Payment_Status__c);
        System.assertEquals(false, after.get(noticedEarlier.Id).Bacs_Notice_Sent__c,
            'the earlier notice is void: if the case returns to a collectable stage the row is noticed afresh first');
    }

    // ...and when the case comes back, the row is re-dated and noticed again
    // before anything is collected.
    @isTest static void gatedStage_thenBackToAwarded_freshNoticeBeforeCollection() {
        upsertConfig();
        seedBacsTemplate();
        AA_Application__c a = makeApp(1);
        Date today = Date.today();
        AA_Fee_Installment__c r = row(a.Id, 1, today.addDays(3), 'pending', true);
        insert r;
        update new AA_Application__c(Id = a.Id, Stage__c = 'Needs Human');
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        AA_FeeInstallmentScheduler.sendAdvanceNotices(today);
        System.assertEquals(false, [SELECT Bacs_Notice_Sent__c FROM AA_Fee_Installment__c WHERE Id = :r.Id].Bacs_Notice_Sent__c);

        update new AA_Application__c(Id = a.Id, Stage__c = 'Awarded');
        Test.startTest();
        Integer[] nres = AA_FeeInstallmentScheduler.sendAdvanceNotices(today);
        Test.stopTest();
        AA_Fee_Installment__c after = [SELECT Scheduled_Date__c, Bacs_Notice_Sent__c FROM AA_Fee_Installment__c WHERE Id = :r.Id];
        System.assertEquals(1, nres[0], 'a fresh notice');
        System.assertEquals(true, after.Bacs_Notice_Sent__c);
        System.assertEquals(today.addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS), after.Scheduled_Date__c,
            'moved so the fresh notice gives the full 5 days');
    }

    // The manual entry point refuses a plan the sweep would never collect.
    @isTest static void chargeFee_atGatedStage_refusedWithoutRows() {
        upsertConfig();
        AA_Application__c a = makeApp(1);
        update new AA_Application__c(Id = a.Id, Stage__c = 'Mandatory Reconsideration Requested');
        Boolean threw = false;
        try { AA_GoCardlessController.chargeFee(a.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'no plan may be scheduled where the notice cannot be sent');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]);
    }

    // Integrator 2026-10-02: a pause handoff whose insert failed is raised
    // again on the next run (the rows are already 'paused' by then and used
    // to drop out of the 'pending' query), without re-pausing anything and
    // without a second handoff once one exists.
    @isTest static void dncPause_missingHandoff_isRaisedOnTheNextRun_once() {
        upsertConfig();
        AA_Application__c a = makeApp(2);
        insert new List<AA_Fee_Installment__c>{
            row(a.Id, 1, Date.today().addDays(10), 'pending', false),
            row(a.Id, 2, Date.today().addDays(40), 'pending', false)
        };
        a.Do_Not_Contact__c = true;
        update a;
        AA_FeeInstallmentScheduler.PauseResult p1 = AA_FeeInstallmentScheduler.pauseDoNotContact(Date.today());
        System.assertEquals(2, p1.unnoticed);
        // Stand-in for a failed handoff insert (notify trigger threw, lock...).
        delete pauseHandoffs(a.Id);
        System.assertEquals(0, pauseHandoffs(a.Id).size());

        Test.startTest();
        AA_FeeInstallmentScheduler.PauseResult p2 = AA_FeeInstallmentScheduler.pauseDoNotContact(Date.today());
        AA_FeeInstallmentScheduler.PauseResult p3 = AA_FeeInstallmentScheduler.pauseDoNotContact(Date.today());
        Test.stopTest();

        System.assertEquals(1, p2.handoffs, 'the missing handoff is raised on the next run');
        System.assertEquals(0, p2.unnoticed, 'paused rows are not paused again');
        System.assertEquals(0, p3.handoffs, 'and only once');
        System.assertEquals(1, pauseHandoffs(a.Id).size());
        System.assertEquals(2, [SELECT COUNT() FROM AA_Fee_Installment__c
                                 WHERE Application__c = :a.Id AND Payment_Status__c = 'paused']);
    }
}