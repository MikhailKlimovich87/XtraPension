/**
 * PC1_FeeInstallmentSchedulerTest — the daily fee sweep.
 *
 * Rewritten on 2026-11-11 with the create-ahead sweep (audit PC-APEX-3 / -4 /
 * -12). What a regression here looks like in production:
 *   - a client charged on a different day from the one in the advance notice,
 *     or with no notice at all;
 *   - a refused, disputed or Needs Human case, or a client reported deceased,
 *     still being charged;
 *   - two overdue installments collected on the same day after a mandate gap;
 *   - a sweep that fails and tells nobody.
 *
 * Callouts are stubbed with an HttpCalloutMock that records the request. The
 * dispatcher is bypassed with testBypass so the (appId) pairs can be asserted
 * without sending email; "the notice was delivered" is a 'Sent'
 * PC1_Message_Send_Log__c row, which these tests insert themselves.
 */
@isTest
private class PC1_FeeInstallmentSchedulerTest {

    // Captured by the mock. Static so the test body can read them.
    private static Integer calls = 0;
    private static String lastBody;

    private class ChargeMock implements HttpCalloutMock {
        public Integer status = 200;
        public String body = '{"ok":true,"payment_id":"PM_INSTALL","status":"pending_submission"}';
        public HttpResponse respond(HttpRequest req) {
            calls++;
            lastBody = req.getBody();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    private static void upsertConfig() {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c cfg;
        if (rows.isEmpty()) {
            cfg = new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        } else {
            cfg = new PC1_Config__c(Id = rows[0].Id);
        }
        cfg.Internal_Admin_Token__c = 'TEST-TOKEN';
        cfg.Auto_Create_DD_Mandate__c = false;    // don't fire the auto-mandate trigger
        upsert cfg;
    }

    private static Integer seq = 0;
    private static PC1_Application__c makeApp(Integer installments) {
        seq++;
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c              = 'FI',
            Last_Name__c               = 'Test' + System.now().getTime(),
            Email__c                   = 'fi@example.com',
            DOB__c                     = Date.newInstance(1955, 1, 1),
            Address_Line1__c           = '1 Test St',
            City__c                    = 'London',
            Postcode__c                = 'SW1A 1AA',
            DD_Mandate_Id__c           = 'MD-ACTIVE' + (seq == 1 ? '' : String.valueOf(seq)),   // unique field
            DD_Mandate_Status__c       = 'active',
            Award_Amount__c            = 800,
            Fee_Plan_Installments__c   = installments,
            Stage__c                   = 'Awarded',
            CurrencyIsoCode            = 'GBP'
        );
        insert a;
        return a;
    }

    private static List<PC1_Fee_Installment__c> makeInstallments(Id appId, Integer plan, Date firstDate) {
        List<PC1_Fee_Installment__c> rows = new List<PC1_Fee_Installment__c>();
        Decimal fee = 160;   // 20% of 800
        Decimal per = (fee / plan).setScale(2, System.RoundingMode.HALF_UP);
        Decimal remainder = fee - (per * (plan - 1));
        for (Integer i = 1; i <= plan; i++) {
            rows.add(new PC1_Fee_Installment__c(
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

    private static PC1_Message_Template__c bacsTemplate() {
        PC1_Message_Template__c t = new PC1_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Bacs_Advance_Notice',
            Active__c = true, Subject_Template__c = 'Notice', Body_Template__c = 'Hi');
        insert t;
        return t;
    }

    /** The row was handed to the dispatcher a day ago. */
    private static void stampNoticed(Id rowId) {
        update new PC1_Fee_Installment__c(Id = rowId, Bacs_Notice_Sent__c = true,
            Bacs_Notice_Sent_At__c = Datetime.now().addDays(-1));
    }

    /** ...and the email really went out (after the stamp). */
    private static void logDelivered(Id appId, Id templateId) {
        insert new PC1_Message_Send_Log__c(Template__c = templateId, Application__c = appId, Channel__c = 'Email',
            Status__c = 'Sent', Sent_At__c = Datetime.now().addHours(-23));
    }

    private static PC1_Fee_Installment__c reload(Id rowId) {
        return [SELECT Installment_Number__c, Payment_Status__c, Payment_Id__c, Charged_At__c, Scheduled_Date__c,
                       Bacs_Notice_Sent__c, Bacs_Notice_Sent_At__c
                  FROM PC1_Fee_Installment__c WHERE Id = :rowId];
    }

    private static String runSweep(HttpCalloutMock mock) {
        PC1_FeeInstallmentScheduler.testBypass = true;   // no real dispatcher job
        PC1_FeeInstallmentScheduler.testDispatched.clear();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(Date.today());
        Test.stopTest();
        return summary;
    }

    // -----------------------------------------------------------------
    // Advance notices
    // -----------------------------------------------------------------
    @isTest static void run_noticesRowInsideHorizon_withoutCreatingThePayment() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(1);
        Date due = Date.today().addDays(7);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, due)[0];

        String summary = runSweep(new ChargeMock());

        System.assert(summary.contains('notices=1'), 'expected notices=1 in: ' + summary);
        System.assert(summary.contains('fired=0'), 'a row is never created on the run that notices it: ' + summary);
        System.assertEquals(0, calls, 'no GoCardless call before the notice is delivered');
        System.assertEquals(1, PC1_FeeInstallmentScheduler.testDispatched.size());
        System.assertEquals(a.Id + ':bulk', PC1_FeeInstallmentScheduler.testDispatched[0]);
        PC1_Fee_Installment__c after = reload(row.Id);
        System.assertEquals(true, after.Bacs_Notice_Sent__c);
        System.assertEquals('pending', after.Payment_Status__c);
        System.assertEquals(null, after.Payment_Id__c);
        System.assertEquals(due, after.Scheduled_Date__c, 'a date with enough notice is not moved');
    }

    @isTest static void run_rowTooCloseIsMovedToTheNoticePeriod() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(2))[0];

        String summary = runSweep(new ChargeMock());

        Date moved = Date.today().addDays(PC1_FeeInstallmentScheduler.NOTICE_DAYS);
        PC1_Fee_Installment__c after = reload(row.Id);
        System.assertEquals(moved, after.Scheduled_Date__c, 'never noticed with fewer than NOTICE_DAYS');
        System.assertEquals(true, after.Bacs_Notice_Sent__c);
        System.assert(summary.contains('notices=1'), summary);
        System.assertEquals(moved, [SELECT Fee_Plan_Next_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id].Fee_Plan_Next_Charge_Date__c,
            'the card shows the moved date');
    }

    @isTest static void run_rowBeyondHorizon_isLeftAlone() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(8))[0];

        String summary = runSweep(new ChargeMock());

        System.assert(summary.contains('notices=0'), summary);
        System.assertEquals(false, reload(row.Id).Bacs_Notice_Sent__c);
        System.assertEquals(0, PC1_FeeInstallmentScheduler.testDispatched.size());
    }

    @isTest static void run_noActiveTemplate_leavesRowsUnnoticed_andAlerts() {
        upsertConfig();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(7))[0];

        String summary = runSweep(new ChargeMock());

        System.assert(summary.contains('errored=1'), summary);
        System.assertEquals(false, reload(row.Id).Bacs_Notice_Sent__c, 'not stamped: a stamped row would be collected');
        System.assertNotEquals(null, PC1_FeeInstallmentScheduler.lastAlert, 'a run with errors emails the admin');
    }

    // -----------------------------------------------------------------
    // Collection: created ahead, dated as noticed
    // -----------------------------------------------------------------
    @isTest static void run_createsNoticedDeliveredRow_withTheNoticedChargeDate() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(3);
        Date due = Date.today().addDays(6);
        List<PC1_Fee_Installment__c> rows = makeInstallments(a.Id, 3, due);
        stampNoticed(rows[0].Id);
        logDelivered(a.Id, t.Id);

        ChargeMock mock = new ChargeMock();
        mock.body = '{"ok":true,"payment_id":"PM_INSTALL","status":"pending_submission","charge_date":"' + String.valueOf(due) + '"}';
        String summary = runSweep(mock);

        System.assert(summary.contains('fired=1'), summary);
        System.assertEquals(1, calls, 'one installment, one GoCardless call');
        System.assert(lastBody.contains('"charge_date":"' + String.valueOf(due) + '"'),
            'the payment must be dated as the notice said: ' + lastBody);
        System.assert(lastBody.contains('"charge_stage":"installment_1"'), lastBody);
        System.assert(lastBody.contains('"amount_pence":5333'), lastBody);

        PC1_Fee_Installment__c first = reload(rows[0].Id);
        System.assertEquals('submitted', first.Payment_Status__c);
        System.assertEquals('PM_INSTALL', first.Payment_Id__c);
        System.assertNotEquals(null, first.Charged_At__c);
        System.assertEquals(due, first.Scheduled_Date__c);
        System.assertEquals('pending', reload(rows[1].Id).Payment_Status__c);
        System.assertEquals('pending', reload(rows[2].Id).Payment_Status__c);
        System.assertEquals(due.addMonths(1), [SELECT Fee_Plan_Next_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id].Fee_Plan_Next_Charge_Date__c,
            'next charge date is installment #2');
    }

    @isTest static void run_finalInstallment_clearsNextChargeDate() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(2);
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1,
            Scheduled_Date__c = Date.today().addMonths(-1), Amount__c = 80,
            Payment_Status__c = 'paid', Payment_Id__c = 'PM_1', Charged_At__c = Datetime.now().addDays(-30)
        );
        PC1_Fee_Installment__c last = new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 2,
            Scheduled_Date__c = Date.today().addDays(6), Amount__c = 80,
            Payment_Status__c = 'pending'
        );
        insert last;
        stampNoticed(last.Id);
        logDelivered(a.Id, t.Id);

        runSweep(new ChargeMock());

        System.assertEquals('submitted', reload(last.Id).Payment_Status__c);
        System.assertEquals(null, [SELECT Fee_Plan_Next_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id].Fee_Plan_Next_Charge_Date__c,
            'no pending installments left: next charge date cleared');
    }

    @isTest static void run_weekendRoll_recordsTheRealDebitDate() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(6))[0];
        stampNoticed(row.Id);
        logDelivered(a.Id, t.Id);

        ChargeMock mock = new ChargeMock();
        Date rolled = Date.today().addDays(8);
        mock.body = '{"ok":true,"payment_id":"PM_ROLL","status":"pending_submission","charge_date":"' + String.valueOf(rolled) + '"}';
        runSweep(mock);

        System.assertEquals(rolled, reload(row.Id).Scheduled_Date__c);
        System.assertEquals(0, [SELECT COUNT() FROM PC1_Handoff__c WHERE Application__c = :a.Id], 'a later date is not an alarm');
    }

    @isTest static void run_earlierDateFromAnOldHerokuBuild_raisesUrgentHandoff() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(6))[0];
        stampNoticed(row.Id);
        logDelivered(a.Id, t.Id);

        ChargeMock mock = new ChargeMock();
        Date early = Date.today().addDays(2);
        mock.body = '{"ok":true,"payment_id":"PM_EARLY","status":"pending_submission","charge_date":"' + String.valueOf(early) + '"}';
        runSweep(mock);

        PC1_Fee_Installment__c after = reload(row.Id);
        System.assertEquals('submitted', after.Payment_Status__c, 'the payment exists, so the ledger must show it');
        System.assertEquals(early, after.Scheduled_Date__c);
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c WHERE Application__c = :a.Id AND Reason__c LIKE 'URGENT%'],
            'collected earlier than the client was told: a human must act');
    }

    @isTest static void run_noDeliveredNotice_noCollection() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(6))[0];
        stampNoticed(row.Id);   // handed to the dispatcher, but no 'Sent' log exists

        PC1_FeeInstallmentScheduler.testBypass = true;
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(Date.today());
        // The notice was sent again in that run; until its dispatch job has
        // had time to log, the next run waits instead of alarming twice.
        String second = PC1_FeeInstallmentScheduler.run(Date.today());
        Test.stopTest();

        System.assertEquals(0, calls, 'nothing is collected without a delivered notice');
        System.assert(summary.contains('undelivered=1'), summary);
        System.assert(summary.contains('notices=1'), 'the notice is tried again: ' + summary);
        System.assert(second.contains('undelivered=0'), second);
        PC1_Fee_Installment__c after = reload(row.Id);
        System.assertEquals('pending', after.Payment_Status__c);
        System.assertEquals(null, after.Payment_Id__c);
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c
                                 WHERE Application__c = :a.Id AND Reason__c = :PC1_FeeInstallmentScheduler.UNDELIVERED_REASON],
            'ops are told once why the fee is not being collected');
    }

    @isTest static void run_onlyOneInstallmentPerApplicationPerRun() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(2);
        // Two noticed rows on one application cannot happen through the sweep
        // (it keeps a month between them); a data load can produce it.
        PC1_Fee_Installment__c r1 = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1,
            Scheduled_Date__c = Date.today().addDays(6), Amount__c = 80, Payment_Status__c = 'pending');
        PC1_Fee_Installment__c r2 = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 2,
            Scheduled_Date__c = Date.today().addDays(40), Amount__c = 80, Payment_Status__c = 'pending');
        insert new List<PC1_Fee_Installment__c>{ r1, r2 };
        stampNoticed(r1.Id);
        stampNoticed(r2.Id);
        logDelivered(a.Id, t.Id);

        String summary = runSweep(new ChargeMock());

        System.assertEquals(1, calls, 'never two installments of one client on the same day');
        System.assert(summary.contains('fired=1'), summary);
        System.assertEquals('submitted', reload(r1.Id).Payment_Status__c);
        System.assertEquals('pending', reload(r2.Id).Payment_Status__c);
    }

    // -----------------------------------------------------------------
    // Hold rules: stage, Do Not Contact, mandate
    // -----------------------------------------------------------------
    @isTest static void run_holdRules_stageDoNotContactAndMandate() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        // A human is dealing with a dispute.
        PC1_Application__c needsHuman = makeApp(1);
        PC1_Fee_Installment__c rowHuman = makeInstallments(needsHuman.Id, 1, Date.today().addDays(6))[0];
        // Client reported deceased; installment 1 is already with GoCardless.
        PC1_Application__c dnc = makeApp(2);
        List<PC1_Fee_Installment__c> dncRows = makeInstallments(dnc.Id, 2, Date.today().addDays(6));
        update new PC1_Fee_Installment__c(Id = dncRows[0].Id, Payment_Status__c = 'submitted', Payment_Id__c = 'PM_DNC',
            Charged_At__c = Datetime.now().addDays(-40), Scheduled_Date__c = Date.today().addDays(-40));
        update new PC1_Fee_Installment__c(Id = dncRows[1].Id, Scheduled_Date__c = Date.today().addDays(6));
        // Bank details changed: the mandate is parked.
        PC1_Application__c parked = makeApp(1);
        PC1_Fee_Installment__c rowParked = makeInstallments(parked.Id, 1, Date.today().addDays(6))[0];
        // Not noticed yet, mandate parked: nothing may be sent either.
        PC1_Application__c parkedUnnoticed = makeApp(1);
        PC1_Fee_Installment__c rowParkedUnnoticed = makeInstallments(parkedUnnoticed.Id, 1, Date.today().addDays(6))[0];

        for (Id rowId : new List<Id>{ rowHuman.Id, dncRows[1].Id, rowParked.Id }) stampNoticed(rowId);
        for (Id appId : new List<Id>{ needsHuman.Id, dnc.Id, parked.Id }) logDelivered(appId, t.Id);
        update new List<PC1_Application__c>{
            new PC1_Application__c(Id = needsHuman.Id, Stage__c = 'Needs Human'),
            new PC1_Application__c(Id = dnc.Id, Do_Not_Contact__c = true),
            new PC1_Application__c(Id = parked.Id, DD_Mandate_Status__c = 'cancelled'),
            new PC1_Application__c(Id = parkedUnnoticed.Id, DD_Mandate_Status__c = 'cancelled')
        };

        PC1_FeeInstallmentScheduler.testBypass = true;
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(Date.today());

        System.assertEquals(0, calls, 'none of the three may be collected');
        System.assert(summary.contains('fired=0'), summary);
        System.assert(summary.contains('notices=0'), 'and none may be told "we will collect": ' + summary);
        System.assertEquals(0, PC1_FeeInstallmentScheduler.testDispatched.size());
        // The old notice no longer stands: each row is noticed afresh later.
        System.assertEquals(false, reload(rowHuman.Id).Bacs_Notice_Sent__c);
        System.assertEquals(false, reload(dncRows[1].Id).Bacs_Notice_Sent__c);
        System.assertEquals(false, reload(rowParked.Id).Bacs_Notice_Sent__c);
        System.assertEquals(false, reload(rowParkedUnnoticed.Id).Bacs_Notice_Sent__c);
        System.assertEquals('pending', reload(dncRows[1].Id).Payment_Status__c);

        List<PC1_Handoff__c> pause = [SELECT Reason__c, Next_Step_Suggestion__c, Last_Field_Id__c, Resolved__c
                                        FROM PC1_Handoff__c WHERE Application__c = :dnc.Id];
        System.assertEquals(1, pause.size(), 'one handoff per pause');
        System.assertEquals(PC1_FeeInstallmentScheduler.DNC_PAUSE_REASON, pause[0].Reason__c);
        System.assert(pause[0].Next_Step_Suggestion__c.contains('ACTION NEEDED'), 'the payment already at GoCardless is listed');
        System.assert(pause[0].Next_Step_Suggestion__c.contains('PM_DNC'), pause[0].Next_Step_Suggestion__c);

        // Second day: still paused, no second handoff.
        PC1_FeeInstallmentScheduler.run(Date.today());
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c WHERE Application__c = :dnc.Id]);

        // The flag is cleared: the plan resumes with a fresh notice.
        update new PC1_Application__c(Id = dnc.Id, Do_Not_Contact__c = false);
        PC1_FeeInstallmentScheduler.testDispatched.clear();
        String resumed = PC1_FeeInstallmentScheduler.run(Date.today());
        Test.stopTest();

        System.assert(resumed.contains('dncResumed=1'), resumed);
        PC1_Handoff__c closed = [SELECT Resolved__c, Last_Field_Id__c, Next_Step_Suggestion__c
                                   FROM PC1_Handoff__c WHERE Application__c = :dnc.Id];
        System.assertEquals(true, closed.Resolved__c);
        System.assertEquals(PC1_FeeInstallmentScheduler.DNC_PAUSE_ENDED, closed.Last_Field_Id__c);
        System.assert(closed.Next_Step_Suggestion__c.startsWith(PC1_FeeInstallmentScheduler.DNC_RESUMED_MARK));
        System.assert(new Set<String>(PC1_FeeInstallmentScheduler.testDispatched).contains(dnc.Id + ':bulk'),
            'a fresh notice goes out before anything is collected');
        System.assertEquals(true, reload(dncRows[1].Id).Bacs_Notice_Sent__c);
        System.assertEquals(0, calls);
    }

    @isTest static void run_afterMandateGap_oneInstallmentAtATime_aMonthApart() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(3);
        List<PC1_Fee_Installment__c> rows = makeInstallments(a.Id, 3, Date.today().addDays(-70));
        update new PC1_Fee_Installment__c(Id = rows[0].Id, Payment_Status__c = 'paid', Payment_Id__c = 'PM1',
            Charged_At__c = Datetime.now().addDays(-70));
        // #2 and #3 both fell due while the mandate was being replaced.
        update new PC1_Fee_Installment__c(Id = rows[1].Id, Scheduled_Date__c = Date.today().addDays(-40));
        update new PC1_Fee_Installment__c(Id = rows[2].Id, Scheduled_Date__c = Date.today().addDays(-10));

        String summary = runSweep(new ChargeMock());

        Date second = Date.today().addDays(PC1_FeeInstallmentScheduler.NOTICE_DAYS);
        System.assertEquals(0, calls, 'overdue rows are noticed first, never fired on sight');
        System.assert(summary.contains('notices=1'), summary);
        PC1_Fee_Installment__c r2 = reload(rows[1].Id);
        PC1_Fee_Installment__c r3 = reload(rows[2].Id);
        System.assertEquals(second, r2.Scheduled_Date__c);
        System.assertEquals(true, r2.Bacs_Notice_Sent__c);
        System.assertEquals(second.addMonths(1), r3.Scheduled_Date__c, 'a month between installments, never two together');
        System.assertEquals(false, r3.Bacs_Notice_Sent__c);
    }

    // -----------------------------------------------------------------
    // Refusals and failures
    // -----------------------------------------------------------------
    @isTest static void run_chargeDateTooSoon_movesTheRow_noticedByTheNextRun() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(6))[0];
        stampNoticed(row.Id);
        logDelivered(a.Id, t.Id);

        ChargeMock mock = new ChargeMock();
        mock.status = 409;
        // Inside the notice horizon on purpose: without skipNotice the same
        // run would notice it again.
        Date npcd = Date.today().addDays(7);
        mock.body = '{"ok":false,"error":"charge_date_too_soon","next_possible_charge_date":"' + String.valueOf(npcd) + '"}';
        String summary = runSweep(mock);

        System.assert(summary.contains('redated=1'), summary);
        PC1_Fee_Installment__c after = reload(row.Id);
        System.assertEquals(npcd, after.Scheduled_Date__c, 'moved past the mandate\'s next possible charge date');
        System.assertEquals(false, after.Bacs_Notice_Sent__c, 'the client must be told the new date first');
        System.assertEquals('pending', after.Payment_Status__c);
        System.assertEquals(0, PC1_FeeInstallmentScheduler.testDispatched.size(),
            'noticed tomorrow, so the dispatcher\'s 24h dedup cannot swallow the new notice');
    }

    @isTest static void run_terminalRefusal_putsTheRowOnHold() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(6))[0];
        stampNoticed(row.Id);
        logDelivered(a.Id, t.Id);

        ChargeMock mock = new ChargeMock();
        mock.status = 409;
        mock.body = '{"ok":false,"error":"no_mandate_on_application"}';
        String summary = runSweep(mock);

        System.assert(summary.contains('held=1'), summary);
        System.assertEquals('failed', reload(row.Id).Payment_Status__c, 'on hold: shows Retry on the Fee card');
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c
                                 WHERE Application__c = :a.Id AND Reason__c LIKE 'Fee installment 1 NOT collected%']);
        System.assertEquals(0, PC1_FeeInstallmentScheduler.testDispatched.size(), 'a held row is not noticed again');
    }

    @isTest static void run_transientFailure_leavesRowForTomorrow_andAlerts() {
        upsertConfig();
        PC1_Message_Template__c t = bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(6))[0];
        stampNoticed(row.Id);
        logDelivered(a.Id, t.Id);

        ChargeMock mock = new ChargeMock();
        mock.status = 502;
        mock.body = '{"ok":false,"error":"gocardless_call_failed"}';
        String summary = runSweep(mock);

        System.assert(summary.contains('errored=1'), 'expected errored=1: ' + summary);
        PC1_Fee_Installment__c after = reload(row.Id);
        System.assertEquals('pending', after.Payment_Status__c, 'a transient failure is retried by the next run');
        System.assertEquals(true, after.Bacs_Notice_Sent__c, 'and the notice still stands');
        System.assertNotEquals(null, PC1_FeeInstallmentScheduler.lastAlert, 'somebody is told (was: debug log only)');
    }

    @isTest static void terminalRefusal_classification() {
        System.assert(!PC1_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'ok' => false, 'error' => 'Endpoint unreachable' }),
            'no HTTP status = transient');
        System.assert(!PC1_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 401, 'error' => 'unauthorized' }),
            'a bad token is fixed in config, not per installment');
        System.assert(!PC1_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 502, 'error' => 'gocardless_call_failed' }));
        System.assert(!PC1_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 409, 'error' => 'mandate_not_charge_ready' }));
        System.assert(PC1_FeeInstallmentScheduler.isTerminalRefusal(new Map<String, Object>{ 'http_status' => 404, 'error' => 'application_not_found' }));
        System.assert(PC1_FeeInstallmentScheduler.isCollectableStage('Fee Charged'));
        System.assert(!PC1_FeeInstallmentScheduler.isCollectableStage('Closed - Refused'));
        System.assert(!PC1_FeeInstallmentScheduler.isCollectableStage(null));
    }

    @isTest static void run_noticedRowWhoseDatePassedUncreated_isHeldNotRenoticed() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today())[0];
        stampNoticed(row.Id);

        String summary = runSweep(new ChargeMock());

        System.assertEquals(0, calls, 'a payment dated today cannot be created any more');
        System.assertEquals('failed', reload(row.Id).Payment_Status__c);
        System.assert(summary.contains('notices=0'), 'no second "we will collect" email: ' + summary);
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c WHERE Application__c = :a.Id]);
    }

    // -----------------------------------------------------------------
    // One Queueable per run (the sweep runs in @future) + reconciliation
    // -----------------------------------------------------------------
    @isTest static void run_noQueueSlot_noticeRetriedNextRun_andReconciliationDeferred() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeApp(1);
        PC1_Fee_Installment__c row = makeInstallments(a.Id, 1, Date.today().addDays(7))[0];
        PC1_Application__c paid = makeApp(1);
        List<PC1_Fee_Installment__c> rows = makeInstallments(paid.Id, 1, Date.today().addDays(-10));
        update new PC1_Fee_Installment__c(Id = rows[0].Id, Payment_Status__c = 'paid', Payment_Id__c = 'PM1');

        PC1_FeeInstallmentScheduler.queueSlotsUsedOverride = 1000;   // no slot left
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        PC1_FeeInstallmentScheduler.run(Date.today());
        Test.stopTest();

        System.assertEquals(false, reload(row.Id).Bacs_Notice_Sent__c, 'not stamped without a dispatch: next run notices it');
        System.assertEquals('Awarded', [SELECT Stage__c FROM PC1_Application__c WHERE Id = :paid.Id].Stage__c,
            'not closed without its receipt — next run');
    }

    @isTest static void run_reconcilesAllPaidApp_andSendsReceipt() {
        upsertConfig();
        Date today = Date.today();
        PC1_Application__c paid = makeApp(2);
        List<PC1_Fee_Installment__c> rows = makeInstallments(paid.Id, 2, today.addDays(-40));
        update new List<PC1_Fee_Installment__c>{
            new PC1_Fee_Installment__c(Id = rows[0].Id, Payment_Status__c = 'paid', Payment_Id__c = 'PM1'),
            new PC1_Fee_Installment__c(Id = rows[1].Id, Payment_Status__c = 'paid', Payment_Id__c = 'PM2')
        };
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();
        System.assert(summary.contains('reconciled=1'), summary);
        PC1_Application__c after = [SELECT Stage__c, Fee_Payment_Status__c FROM PC1_Application__c WHERE Id = :paid.Id];
        System.assertEquals('Closed - Paid', after.Stage__c);
        System.assertEquals('confirmed', after.Fee_Payment_Status__c);
    }

    @isTest static void schedulable_entry_runs_async() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        new PC1_FeeInstallmentScheduler().execute(null);
        Test.stopTest();
    }
}