/**
 * PC1_FeeInstallmentSchedulerTest — covers the scheduler's two responsibilities:
 *
 *   1. Fires DUE installments via /internal/gocardless/charge-fee and advances
 *      Fee_Plan_Next_Charge_Date__c on the parent Application.
 *   2. Dispatches the Bacs_Advance_Notice template 5 CALENDAR days before each
 *      pending installment's Scheduled_Date__c (changed from 3 working days
 *      on 2026-08-25).
 *
 * Callouts are stubbed with an HttpCalloutMock so we can drive the endpoint
 * without hitting Heroku. The dispatcher is bypassed via the class-level
 * testBypass flag so we can assert the (appId, installmentNumber) pairs
 * without stubbing PC1_MessageDispatcher.
 */
@isTest
private class PC1_FeeInstallmentSchedulerTest {

    private class ChargeMock implements HttpCalloutMock {
        public Integer status = 200;
        public String body = '{"ok":true,"payment_id":"PM_INSTALL","status":"pending_submission"}';
        public HttpResponse respond(HttpRequest req) {
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

    // -----------------------------------------------------------------
    // Due installment path — one row is due today, others are future
    // -----------------------------------------------------------------
    @isTest static void run_firesDueInstallment_andAdvancesNextChargeDate() {
        upsertConfig();
        PC1_Application__c a = makeApp(3);
        Date today = Date.today();
        List<PC1_Fee_Installment__c> rows = makeInstallments(a.Id, 3, today);

        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        PC1_FeeInstallmentScheduler.testBypass = true;   // don't fire Bacs notices to the real dispatcher

        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        System.assert(summary.contains('fired=1'), 'installment #1 (today) should fire, got: ' + summary);

        PC1_Fee_Installment__c[] refreshed = [
            SELECT Installment_Number__c, Payment_Status__c, Payment_Id__c, Charged_At__c
              FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id
             ORDER BY Installment_Number__c
        ];
        System.assertEquals('submitted', refreshed[0].Payment_Status__c);
        System.assertEquals('PM_INSTALL', refreshed[0].Payment_Id__c);
        System.assertNotEquals(null, refreshed[0].Charged_At__c);
        System.assertEquals('pending', refreshed[1].Payment_Status__c);
        System.assertEquals('pending', refreshed[2].Payment_Status__c);

        PC1_Application__c after = [SELECT Fee_Plan_Next_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(today.addMonths(1), after.Fee_Plan_Next_Charge_Date__c,
            'next charge date should be installment #2 (+1 month)');
    }

    @isTest static void run_finalInstallment_clearsNextChargeDate() {
        upsertConfig();
        PC1_Application__c a = makeApp(2);
        Date today = Date.today();
        // Insert: installment #1 already paid, installment #2 due today.
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1,
            Scheduled_Date__c = today.addMonths(-1), Amount__c = 80,
            Payment_Status__c = 'paid', Payment_Id__c = 'PM_1', Charged_At__c = Datetime.now().addDays(-30)
        );
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 2,
            Scheduled_Date__c = today, Amount__c = 80,
            Payment_Status__c = 'pending'
        );

        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        PC1_FeeInstallmentScheduler.testBypass = true;
        Test.startTest();
        PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        PC1_Application__c after = [SELECT Fee_Plan_Next_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.Fee_Plan_Next_Charge_Date__c,
            'no pending installments left → Fee_Plan_Next_Charge_Date__c cleared');
    }

    // -----------------------------------------------------------------
    // Advance-notice path — exactly 5 calendar days out
    // -----------------------------------------------------------------
    @isTest static void run_dispatchesAdvanceNotice_atMinus5CalendarDays() {
        upsertConfig();
        PC1_Application__c a = makeApp(1);
        Date today = Date.today();
        Date target = today.addDays(5);   // matches scheduler's addDays(5)
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1,
            Scheduled_Date__c = target, Amount__c = 160,
            Payment_Status__c = 'pending'
        );

        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_FeeInstallmentScheduler.testDispatched.clear();
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        System.assert(summary.contains('notices=1'), 'expected notices=1 in: ' + summary);
        System.assertEquals(1, PC1_FeeInstallmentScheduler.testDispatched.size());
        // Post-audit-r3 bulk refactor: stub emits '<appId>:bulk' from
        // dispatchBacsAdvanceNoticeBulk instead of '<appId>:1' per-row.
        System.assertEquals(a.Id + ':bulk', PC1_FeeInstallmentScheduler.testDispatched[0]);
    }

    // -----------------------------------------------------------------
    // R11-arch — new T+3..T+7 window backed by per-installment
    // Bacs_Notice_Sent__c stamp. Brackets: T+2 (below) and T+8 (above)
    // should NOT fire; T+3/T+5/T+7 all inside. Also verifies idempotency
    // (2nd run finds the stamps and skips).
    // -----------------------------------------------------------------
    @isTest static void run_windowAndBacsNoticeStamp() {
        upsertConfig();
        PC1_Application__c a = makeApp(3);
        Date today = Date.today();
        // Out-of-window brackets
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1,
            Scheduled_Date__c = today.addDays(2), Amount__c = 80,
            Payment_Status__c = 'pending'
        );
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 5,
            Scheduled_Date__c = today.addDays(8), Amount__c = 80,
            Payment_Status__c = 'pending'
        );
        // In-window
        PC1_Fee_Installment__c inWin1 = new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 2,
            Scheduled_Date__c = today.addDays(3), Amount__c = 80,
            Payment_Status__c = 'pending'
        );
        PC1_Fee_Installment__c inWin2 = new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 3,
            Scheduled_Date__c = today.addDays(5), Amount__c = 80,
            Payment_Status__c = 'pending'
        );
        PC1_Fee_Installment__c inWin3 = new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 4,
            Scheduled_Date__c = today.addDays(7), Amount__c = 80,
            Payment_Status__c = 'pending'
        );
        insert new List<PC1_Fee_Installment__c>{ inWin1, inWin2, inWin3 };

        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_FeeInstallmentScheduler.testDispatched.clear();
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        // One MSG-0008 dispatch (3 installments on the SAME app → 1 app-set entry).
        System.assert(summary.contains('notices=1'), 'expected notices=1: ' + summary);
        System.assertEquals(1, PC1_FeeInstallmentScheduler.testDispatched.size());
        // All 3 in-window installments got Bacs_Notice_Sent__c stamped.
        Integer stamped = [
            SELECT COUNT() FROM PC1_Fee_Installment__c
             WHERE Application__c = :a.Id AND Bacs_Notice_Sent__c = true
        ];
        System.assertEquals(3, stamped, 'expected 3 stamped installments');
        // Out-of-window brackets NOT stamped.
        Integer unstamped = [
            SELECT COUNT() FROM PC1_Fee_Installment__c
             WHERE Application__c = :a.Id AND Bacs_Notice_Sent__c = false
        ];
        System.assertEquals(2, unstamped, 'expected 2 out-of-window unstamped');

        // Idempotency: second run in the same day finds no unstamped rows.
        PC1_FeeInstallmentScheduler.testDispatched.clear();
        String summary2 = PC1_FeeInstallmentScheduler.run(today);
        System.assert(summary2.contains('notices=0'),
            'idempotency: 2nd run should skip (Bacs_Notice_Sent__c=true): ' + summary2);
        System.assertEquals(0, PC1_FeeInstallmentScheduler.testDispatched.size());
    }

    // -----------------------------------------------------------------
    // Failure path — callout returns ok=false → row stays pending for retry
    // -----------------------------------------------------------------
    @isTest static void run_calloutFail_leavesRowPending() {
        upsertConfig();
        PC1_Application__c a = makeApp(1);
        Date today = Date.today();
        insert new PC1_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1,
            Scheduled_Date__c = today, Amount__c = 160,
            Payment_Status__c = 'pending'
        );

        ChargeMock fail = new ChargeMock();
        fail.body = '{"ok":false,"error":"insufficient_permissions"}';
        Test.setMock(HttpCalloutMock.class, fail);
        PC1_FeeInstallmentScheduler.testBypass = true;

        Test.startTest();
        String summary = PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        System.assert(summary.contains('errored=1'), 'expected errored=1: ' + summary);
        PC1_Fee_Installment__c row = [SELECT Payment_Status__c FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals('pending', row.Payment_Status__c,
            'failed callout must leave the row pending for tomorrow\'s retry');
    }

    // -----------------------------------------------------------------
    // 2026-10-02 — one Queueable per run (the sweep runs in @future)
    // -----------------------------------------------------------------
    private static void bacsTemplate() {
        insert new PC1_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Bacs_Advance_Notice',
            Active__c = true, Subject_Template__c = 'Notice', Body_Template__c = 'Hi');
    }

    @isTest static void run_urgentAndRegularNotices_shareOneDispatch() {
        upsertConfig();
        bacsTemplate();
        Date today = Date.today();
        PC1_Application__c urgent = makeApp(3);
        PC1_Fee_Installment__c u = makeInstallments(urgent.Id, 3, today.addDays(2))[0];
        // Stamped 3 days ago but no Sent log → the notice never went out.
        update new PC1_Fee_Installment__c(Id = u.Id, Bacs_Notice_Sent__c = true, Bacs_Notice_Sent_At__c = Datetime.now().addHours(-72));
        PC1_Application__c regular = makeApp(3);
        makeInstallments(regular.Id, 3, today.addDays(5));

        PC1_FeeInstallmentScheduler.testBypass = true;
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        Set<String> dispatched = new Set<String>(PC1_FeeInstallmentScheduler.testDispatched);
        System.assert(dispatched.contains(urgent.Id + ':bulk'), 'urgent re-send included');
        System.assert(dispatched.contains(regular.Id + ':bulk'), 'regular notice included');
        System.assertEquals(2, PC1_FeeInstallmentScheduler.testDispatched.size(), 'one dispatch for both');
    }

    @isTest static void run_noQueueSlot_handoffForUrgent_andReconciliationDeferred() {
        upsertConfig();
        bacsTemplate();
        Date today = Date.today();
        PC1_Application__c urgent = makeApp(3);
        PC1_Fee_Installment__c u = makeInstallments(urgent.Id, 3, today.addDays(2))[0];
        update new PC1_Fee_Installment__c(Id = u.Id, Bacs_Notice_Sent__c = true, Bacs_Notice_Sent_At__c = Datetime.now().addHours(-72));
        PC1_Application__c paid = makeApp(1);
        List<PC1_Fee_Installment__c> rows = makeInstallments(paid.Id, 1, today.addDays(-10));
        update new PC1_Fee_Installment__c(Id = rows[0].Id, Payment_Status__c = 'paid', Payment_Id__c = 'PM1');

        PC1_FeeInstallmentScheduler.queueSlotsUsedOverride = 1000;   // no slot left
        Test.setMock(HttpCalloutMock.class, new ChargeMock());
        Test.startTest();
        PC1_FeeInstallmentScheduler.run(today);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c WHERE Application__c = :urgent.Id],
            'charge within 3 days without a notice → a human must act');
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

    @isTest static void single_notice_helper() {
        PC1_Application__c a = makeApp(1);
        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_FeeInstallmentScheduler.dispatchBacsAdvanceNotice(a.Id, 1);
        System.assertEquals(1, PC1_FeeInstallmentScheduler.testDispatched.size());
    }
}