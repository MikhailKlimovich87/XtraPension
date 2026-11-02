/**
 * AA_FeeInstallmentScheduler — daily Schedulable that walks the
 * AA_Fee_Installment__c table and drives two things:
 *
 *   1. ADVANCE NOTICES (T-5) — every pending instalment whose
 *      Scheduled_Date__c is exactly NOTICE_DAYS (5 CALENDAR days) away and
 *      has not been noticed yet dispatches the `Bacs_Advance_Notice` template
 *      on the parent Application, then the row is stamped
 *      Bacs_Notice_Sent__c / _At__c. The notice states the row's date and
 *      amount ({{FeeNextInstallmentDate}} / {{FeeNextInstallmentAmount}}).
 *      The stamp means "handed to the dispatcher", NOT "delivered": dispatch()
 *      returns normally when no active Bacs_Advance_Notice template exists,
 *      so the sweep checks for one first and leaves the rows unstamped when
 *      there is none. AA_Message_Send_Log__c is the delivery evidence.
 *      Notice window changed 3 working days → 5 calendar days on 2026-08-25;
 *      5 calendar days re-confirmed by Fernando on 2026-09-09.
 *
 *   2. COLLECTION (create-ahead) — every noticed, still-uncreated pending row
 *      is POSTed to Heroku's /internal/gocardless/charge-fee with
 *      charge_stage='installment_<n>' AND charge_date=Scheduled_Date__c, the
 *      same day it was noticed. GoCardless then debits on the date the
 *      notice stated. The row keeps Payment_Status__c='pending' (= GoCardless
 *      pending_submission) with Payment_Id__c + Charged_At__c stamped; the
 *      webhook moves it to submitted / paid / failed.
 *
 * ── Why create-ahead (audit 2026-10-02 F101/F79) ──
 * The old sweep created the GoCardless payment ON Scheduled_Date__c without a
 * charge_date, so GoCardless debited on its own earliest date, days AFTER the
 * date the notice gave; instalment #1 charged "today" got no notice at all,
 * and a row first seen at T+1..T+4 (missed sweep, or a first-charge date set
 * 1-4 days out) got a short notice. Now:
 *   - a pending row that has not been noticed and is dated sooner than
 *     today + NOTICE_DAYS is MOVED to today + NOTICE_DAYS (never noticed short);
 *   - a noticed row whose date passed before its payment could be created
 *     (creation was retried every day from the notice to the date and never
 *     succeeded) is put ON HOLD (Payment_Status__c='failed') with a High Task,
 *     never moved and re-noticed. It used to be re-dated and re-noticed, which
 *     after a permanent refusal (blank DD_Mandate_Id__c, a charged-back
 *     payment...) emailed the client "we will collect" every 5-6 days forever
 *     and told nobody (wave-2 review of F101). The operator fixes the cause
 *     and clicks Retry on the Fee Charge card, which sends one fresh notice;
 *   - a refusal from Heroku that retrying cannot fix (any 4xx except
 *     charge_date_too_soon / mandate_not_charge_ready / 401) puts the row on
 *     hold the same way at once (see isTerminalRefusal);
 *   - moved rows keep at least a month between instalments, so a mandate gap
 *     never makes two overdue instalments land together (audit F102);
 *   - when GoCardless says the date is before the mandate's
 *     next_possible_charge_date, the row is moved past it and re-noticed.
 * Keeping the created row 'pending' also keeps it the "next pending
 * instalment" the dispatcher reads for the notice tokens, whichever async
 * job runs first.
 *
 * ── Hold rules (audit 2026-10-02 F102) ──
 * Nothing is noticed, moved or collected unless the parent Application has
 * DD_Mandate_Status__c='active', a DD_Mandate_Id__c, Do_Not_Contact__c=false
 * and a Stage in COLLECTABLE_STAGES (the dispatcher's Bacs advance notice
 * stage gate minus HALT_STAGES, so a row is never collected in a stage where
 * its notice would be suppressed). The id matters on its own: the mandate
 * webhook can set the status 'active' while the id is still blank (mandate
 * PDF pending, audit F103), and Heroku refuses every charge for such a record
 * with 409 no_mandate_on_application. A cancelled/expired mandate therefore stops the "we will
 * collect" emails; rows simply wait and are re-dated + re-noticed on the first
 * sweep after a new mandate is active.
 * Do Not Contact is a PAUSE with its own step (owner decision 2026-10-02,
 * see pauseDoNotContact): uncreated rows move to Payment_Status__c='paused'
 * and lose their notice stamp, ops get one handoff per pause, and clearing the
 * flag puts the rows back to 'pending' and resumes the plan with fresh notices.
 *
 * ── ASYNC CALLOUT ARCHITECTURE (fixed 2026-09-02, audit critical #1/#2/#15) ──
 * Synchronous Web-service callouts are BANNED in Schedulable context, so
 * execute() runs the notice step inline (AA_MessageDispatcher.dispatch() only
 * enqueues async work + writes log rows) and hands the collection step to
 * AA_FeeInstallmentChargeQueueable (Queueable, Database.AllowsCallouts).
 * chargeDue() works in chunks of CHUNK rows with callouts-FIRST-then-DML in a
 * single transaction (audit #15). One chunk per fire, no self-chaining; a
 * >CHUNK backlog drains at CHUNK rows per run (audit #14).
 *
 * Idempotency:
 *   - Node side: /internal/gocardless/charge-fee dedupes on (sf_app_id,
 *     charge_stage). A repeat run for the same installment returns the
 *     existing PM id + 200 OK.
 *   - Apex side: only rows still pending with Charged_At__c = null are sent.
 *
 * Failure handling: per-installment try/catch — one bad callout doesn't stop
 * the sweep. A transient failure (5xx, unreachable) leaves the row uncreated
 * so the next sweep retries it, until its date passes; a permanent refusal
 * puts it on hold at once. Either way a hold raises a High Task.
 *
 * Cron: `0 0 8 * * ?` = daily 08:00 UK time (the CronTrigger runs in the
 * scheduling user's Europe/Dublin time zone, NOT UTC; audit 2026-10-02 F114c).
 * Registered via scripts/schedule-fee-installments.cjs. See
 * docs/aa-workflow-manual.md §3.0.
 */
public with sharing class AA_FeeInstallmentScheduler implements Schedulable {

    // ---------- endpoint config (mirrors AA_GoCardlessController) ----------
    @TestVisible private static final String BASE_URL = 'https://aa-autofill-14d501200453.herokuapp.com';
    private static final String PATH_CHARGE_FEE = '/internal/gocardless/charge-fee';
    private static final Integer TIMEOUT_MS = 20000;

    // Max due rows charged per transaction. Kept under the 100 callouts/txn
    // governor limit; the Queueable chains itself for anything beyond one chunk.
    @TestVisible public static final Integer CHUNK = 90;

    // Template dispatched 5 calendar days before the scheduled charge.
    @TestVisible private static final String BACS_ADVANCE_TEMPLATE = 'Bacs_Advance_Notice';
    // Advance-notice lead time in CALENDAR days (Fernando 2026-08-25, re-confirmed
    // 2026-09-09). Public: AA_GoCardlessController uses it for the earliest
    // first-charge date it accepts.
    public static final Integer NOTICE_DAYS = 5;
    // Template dispatched on each non-final installment payment confirmation.
    // Owned by the webhook handler (payments.confirmed) — declared for docs.
    @TestVisible private static final String INSTALLMENT_RECEIPT_TEMPLATE = 'Fee_Receipt_Installment';

    // Application stages on which no instalment is noticed or collected
    // (audit 2026-10-02 F102): a disputed debit, or a case already closed.
    public static final Set<String> HALT_STAGES = new Set<String>{
        'DD Chargeback', 'Closed - Paid', 'Closed - Fee Failed', 'Closed - Refused'
    };

    // THE stages in which an instalment may be noticed and collected
    // (integrator 2026-10-02, wave-4 critical). It is DERIVED from the
    // dispatcher's stage gate for the Bacs advance notice, never copied: the
    // sweep stamps Bacs_Notice_Sent__c as soon as dispatch() returns, and the
    // dispatcher re-checks the stage at send time and suppresses the notice
    // outside its FeeCollection list. When this sweep kept only its own
    // HALT_STAGES, an app in e.g. 'Mandatory Reconsideration Requested' or
    // 'Needs Human' got its notice suppressed, the row was still stamped, and
    // the client was charged with no 5-day advance notice. Deriving the set
    // means the two lists cannot disagree: a stage where the notice cannot go
    // is a stage where nothing is noticed or collected. HALT_STAGES is taken
    // out on top (a closed or disputed case is never collected by the sweep).
    // AA_FeeInstallmentSchedulerTest.collectableStages_neverWiderThanTheNoticeGate
    // fails if anyone re-introduces a separate list.
    private static final Set<String> COLLECTABLE_STAGES = buildCollectableStages();
    private static Set<String> buildCollectableStages() {
        Set<String> s = AA_MessageDispatcher.allowedStagesFor(BACS_ADVANCE_TEMPLATE);
        // null = the notice event lost its stage gate. Fail closed (collect
        // nothing) rather than guess: the test above goes red at once.
        if (s == null) return new Set<String>();
        s.removeAll(HALT_STAGES);
        return s;
    }

    /** A copy of COLLECTABLE_STAGES (for tests and diagnostics; changing it changes nothing). */
    public static Set<String> collectableStages() {
        return new Set<String>(COLLECTABLE_STAGES);
    }

    /** True when an instalment of an app at this stage may be noticed and collected. */
    public static Boolean isCollectableStage(String stage) {
        return stage != null && COLLECTABLE_STAGES.contains(stage);
    }

    /** Result of one chargeDue() chunk. */
    public class ChargeResult {
        public Integer due = 0;
        public Integer fired = 0;
        public Integer errored = 0;
        public Integer redated = 0;
        // Rows put on hold (Payment_Status__c='failed' + High Task) because
        // Heroku refused them for a reason a retry cannot fix.
        public Integer held = 0;
    }

    // Heroku charge-fee refusals that are NOT terminal although they are 4xx:
    // charge_date_too_soon is handled by moving the row; mandate_not_charge_ready
    // is a status race (the sweep's own filter drops the row once Salesforce
    // catches up); 401 is a token problem that affects every row and is fixed
    // in config, not per instalment (the rows are held when their date passes).
    // stage_not_collectable / do_not_contact are Heroku's own copy of this
    // sweep's stage and Do Not Contact gates (integrator 2026-10-02): seen only
    // when the record changed between the query and the callout. The row stays
    // uncreated; the next sweep voids its notice (or the DNC pause takes it).
    private static final Set<String> NON_TERMINAL_4XX_ERRORS = new Set<String>{
        'charge_date_too_soon', 'mandate_not_charge_ready', 'stage_not_collectable', 'do_not_contact'
    };

    // ---------- Do Not Contact pause (owner decision, Fernando 2026-10-02) ----
    // Reason__c of the ops handoff raised once per paused application. It is
    // also how the sweep finds its own handoffs again (dedupe + auto-resume),
    // so do not reword it without migrating open rows.
    @TestVisible public static final String DNC_PAUSE_REASON = 'Fee collection paused: client is Do Not Contact';
    // Written at the start of Next_Step_Suggestion__c when the sweep closes a
    // pause handoff because Do_Not_Contact__c was cleared (for the human
    // reading the handoff; the sweep's own state is in Last_Field_Id__c).
    @TestVisible public static final String DNC_RESUMED_MARK = 'RESUMED AUTOMATICALLY:';
    // Machine state of a pause handoff, kept in Last_Field_Id__c (Text(50),
    // filterable, not shown on the handoff card; a fee pause has no form
    // field). ACTIVE = this pause is current, whether or not ops resolved the
    // handoff, so no second handoff is raised; ENDED = Do Not Contact was
    // cleared, so a later pause raises a new one.
    @TestVisible public static final String DNC_PAUSE_ACTIVE = 'fee_dnc_pause';
    @TestVisible public static final String DNC_PAUSE_ENDED  = 'fee_dnc_pause_ended';
    // Payment_Status__c of an instalment held by the Do Not Contact pause
    // (wave 4: the value was added to the restricted picklist so reports and
    // list views can tell a held instalment from one about to be collected).
    // Lowercase API name, like 'pending'. Only an uncreated 'pending' row is
    // ever paused, so resuming always restores 'pending'.
    public static final String STATUS_PAUSED = 'paused';

    /** Result of one pauseDoNotContact() run. */
    public class PauseResult {
        public Integer handoffs = 0;      // pause handoffs opened
        public Integer unnoticed = 0;     // uncreated rows moved to 'paused' (notice stamp cleared)
        public Integer resumed = 0;       // pause handoffs closed because the flag was cleared
        public Integer restored = 0;      // 'paused' rows put back to 'pending' because the flag was cleared
    }

    // ---------- Schedulable entrypoint --------------------------------------
    public void execute(SchedulableContext ctx) {
        Date today = Date.today();
        // Do Not Contact pause first, so a client flagged since the last sweep
        // is never noticed or charged today. No callouts; guarded so a failure
        // here never blocks the rest of the sweep (the notice and charge
        // queries exclude Do Not Contact applications on their own anyway).
        try {
            pauseDoNotContact(today);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'AA_FeeInstallmentScheduler DNC pause failed: ' + e.getMessage());
        }
        // Advance notices: dispatch() enqueues its own async job + writes log
        // rows but performs NO callout here, so it is safe in Schedulable
        // context. Guarded so a notice failure never blocks the charge hand-off.
        try {
            sendAdvanceNotices(today);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'AA_FeeInstallmentScheduler notices failed: ' + e.getMessage());
        }
        // Charges MUST be async — synchronous callouts are illegal here.
        System.enqueueJob(new AA_FeeInstallmentChargeQueueable(today));
    }

    /**
     * Full synchronous sweep (notices + charges). Retained for the test
     * harness and manual anonymous-Apex runs. Because it performs HTTP
     * callouts it is only safe from a test context or an
     * AllowsCallouts async context — NOT from a bare Schedulable/trigger.
     */
    @TestVisible
    public static String run(Date today) {
        PauseResult pr = pauseDoNotContact(today);
        Integer[] nres = sendAdvanceNotices(today);
        ChargeResult cr = chargeDue(today);
        String summary = 'AA_FeeInstallmentScheduler: notices=' + nres[0] +
            ' fired=' + cr.fired + ' errored=' + (cr.errored + nres[1]) +
            ' (due=' + cr.due + ' redated=' + cr.redated + ' held=' + cr.held +
            ' dncPaused=' + pr.handoffs + ' dncResumed=' + pr.resumed +
            ' dncRowsPaused=' + pr.unnoticed + ' dncRowsRestored=' + pr.restored + ')';
        System.debug(LoggingLevel.INFO, summary);
        return summary;
    }

    // ---------- charges: callouts-FIRST, then a single bulk DML -------------
    /**
     * Create the GoCardless payment for one chunk (<= CHUNK) of NOTICED
     * instalments, with charge_date = the noticed Scheduled_Date__c. All
     * callouts run first (Phase A) collecting the row updates in memory; a
     * single bulk DML then commits them (Phase B) — so there is never a
     * callout after DML in the same transaction. Safe only from
     * AllowsCallouts/test context.
     */
    @TestVisible
    public static ChargeResult chargeDue(Date today) {
        ChargeResult res = new ChargeResult();
        // Stage re-checked here, not only at notice time: it can move between
        // the notice and this Queueable (see COLLECTABLE_STAGES).
        List<AA_Fee_Installment__c> due = [
            SELECT Id, Application__c, Installment_Number__c, Amount__c,
                   Scheduled_Date__c, Payment_Status__c, Payment_Id__c, Bacs_Notice_Sent__c,
                   Application__r.Fee_Plan_Installments__c
              FROM AA_Fee_Installment__c
             WHERE Payment_Status__c = 'pending'
               AND Charged_At__c = null
               AND Bacs_Notice_Sent__c = true
               AND Scheduled_Date__c > :today
               AND Application__r.DD_Mandate_Status__c = 'active'
               AND Application__r.DD_Mandate_Id__c != null
               AND Application__r.Do_Not_Contact__c = false
               AND Application__r.Stage__c IN :COLLECTABLE_STAGES
             ORDER BY Application__c, Installment_Number__c
             LIMIT :CHUNK
        ];
        res.due = due.size();

        // ---- Phase A: callouts only, collect updates (NO DML yet) ----
        List<AA_Fee_Installment__c> toUpdate = new List<AA_Fee_Installment__c>();
        List<Task> tasks = new List<Task>();
        Set<Id> touchedApps = new Set<Id>();
        for (AA_Fee_Installment__c row : due) {
            touchedApps.add(row.Application__c);
            try {
                Map<String, Object> resp = fireInstallmentCallout(row.Application__c, row);
                if (isTruthy(resp.get('ok'))) {
                    AA_Fee_Installment__c up = new AA_Fee_Installment__c(
                        Id                = row.Id,
                        Payment_Id__c     = str(resp.get('payment_id')),
                        // Stays 'pending' (= GoCardless pending_submission) until
                        // the payments.submitted webhook; Charged_At__c marks it
                        // as created so it is never sent twice.
                        Payment_Status__c = 'pending',
                        Charged_At__c     = Datetime.now()
                    );
                    // GoCardless rolls a weekend / bank-holiday charge_date to
                    // the next working day; record the real debit date.
                    Date gcDate = parseDate(resp.get('charge_date'));
                    if (gcDate != null && gcDate > row.Scheduled_Date__c) up.Scheduled_Date__c = gcDate;
                    if (gcDate != null && gcDate < row.Scheduled_Date__c) {
                        // Deploy-order guard (wave-2 review W3): a Heroku build
                        // older than the create-ahead change drops charge_date,
                        // so GoCardless debits on its own earliest date, BEFORE
                        // the date the client was told. The payment already
                        // exists, so the row is still stamped (the ledger must
                        // show it), but a human has to act before the debit.
                        up.Scheduled_Date__c = gcDate;
                        tasks.add(alertTask(row.Application__c,
                            'URGENT: fee instalment ' + row.Installment_Number__c + ' will be collected EARLY',
                            'GoCardless payment ' + str(resp.get('payment_id')) + ' for instalment ' + row.Installment_Number__c +
                            ' (£' + row.Amount__c + ') is dated ' + gcDate.format() + ', but the client was told ' +
                            row.Scheduled_Date__c.format() + ' in the advance notice. Heroku is most likely running a build ' +
                            'older than the Salesforce fee code (it ignores charge_date).\n\n' +
                            'Before ' + gcDate.format() + ': cancel this payment in the GoCardless dashboard, then use Retry on the ' +
                            'Fee Charge card once Heroku is updated (a fresh notice goes to the client). Tell the tech team.'));
                    }
                    toUpdate.add(up);
                    res.fired++;
                } else if (str(resp.get('error')) == 'charge_date_too_soon') {
                    // The noticed date is before the mandate's next possible
                    // charge date. Move the row past it and clear the notice, so
                    // the client is told the real date before anything is taken.
                    Date npcd = parseDate(resp.get('next_possible_charge_date'));
                    Date floor = today.addDays(NOTICE_DAYS + 1);
                    Date nd = (npcd != null && npcd > floor) ? npcd : floor;
                    toUpdate.add(new AA_Fee_Installment__c(
                        Id                     = row.Id,
                        Scheduled_Date__c      = nd,
                        Bacs_Notice_Sent__c    = false,
                        Bacs_Notice_Sent_At__c = null
                    ));
                    res.redated++;
                } else if (isTerminalRefusal(resp)) {
                    // Retrying tomorrow would get the same answer, and once the
                    // date passed the client would be noticed again for nothing.
                    // Hold the row and tell a human now.
                    holdRow(row, 'Heroku refused to create the payment: ' + str(resp.get('error')) +
                        (String.isNotBlank(str(resp.get('detail'))) ? ' (' + safe(str(resp.get('detail'))) + ')' : ''),
                        toUpdate, tasks);
                    res.held++;
                    System.debug(LoggingLevel.ERROR,
                        'AA_FeeInstallmentScheduler: row ' + row.Id + ' put on hold, terminal refusal ' + str(resp.get('error')));
                } else {
                    res.errored++;
                    System.debug(LoggingLevel.ERROR,
                        'AA_FeeInstallmentScheduler: fire failed for ' + row.Id +
                        ' — ' + str(resp.get('error')));
                }
            } catch (Exception e) {
                res.errored++;
                System.debug(LoggingLevel.ERROR,
                    'AA_FeeInstallmentScheduler: fire failed for ' + row.Id +
                    ' — ' + e.getMessage());
            }
        }

        // ---- Phase B: DML only (no callouts past this point) ----
        // audit #11: the GC charge callouts in Phase A ALREADY fired. A plain
        // `update toUpdate` is all-or-nothing, so one bad row (lock/validation) would
        // roll back EVERY payment-id stamp in the chunk — those rows stay 'pending'
        // and refire next sweep (relying on the per-stage GC idem key to dodge a real
        // double-charge, but leaving the ledger wrong meanwhile). Use partial-success
        // so each successfully-charged row keeps its stamp; log the stragglers.
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] srs = Database.update(toUpdate, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (!srs[i].isSuccess()) {
                    res.errored++;
                    System.debug(LoggingLevel.ERROR,
                        'AA_FeeInstallmentScheduler: stamp failed for ' + toUpdate[i].Id +
                        ' (payment may already exist at GC) — ' + srs[i].getErrors());
                }
            }
        }
        insertTasks(tasks);
        advanceParentNextChargeDates(touchedApps);
        return res;
    }

    /**
     * A refusal from /internal/gocardless/charge-fee that the next day's sweep
     * cannot fix: no_mandate_on_application, payment_not_retryable,
     * retry_payment_mismatch, bad_charge_stage, application_not_found, a
     * GoCardless validation error... = any 4xx except the non-terminal ones.
     * 5xx, timeouts and non-JSON answers stay transient.
     */
    @TestVisible
    private static Boolean isTerminalRefusal(Map<String, Object> resp) {
        Integer st = resp.get('http_status') == null ? null : Integer.valueOf(resp.get('http_status'));
        if (st == null || st < 400 || st >= 500 || st == 401) return false;
        return !NON_TERMINAL_4XX_ERRORS.contains(str(resp.get('error')));
    }

    /**
     * Put a pending, uncreated row on hold: 'failed' takes it out of both
     * sweeps (they only read 'pending'), keeps the webhook from closing the
     * case as fully paid (audit F99), and shows the Retry button on the Fee
     * Charge card. Retry sends one fresh 5-day notice and collects again.
     */
    private static void holdRow(AA_Fee_Installment__c row, String why,
                                List<AA_Fee_Installment__c> ups, List<Task> tasks) {
        ups.add(new AA_Fee_Installment__c(Id = row.Id, Payment_Status__c = 'failed'));
        String n = String.valueOf(row.Installment_Number__c);
        String dateTold = row.Scheduled_Date__c == null ? 'the date in the notice' : row.Scheduled_Date__c.format();
        tasks.add(alertTask(row.Application__c,
            'Fee instalment ' + n + ' NOT collected: call the client',
            'Instalment ' + n + ' (£' + row.Amount__c + ') could not be set up at GoCardless, so nothing will be taken on ' +
            dateTold + '. ' + (row.Bacs_Notice_Sent__c == true
                ? 'The client WAS emailed an advance notice for that date: let them know nothing will be taken. '
                : '') +
            'The instalment is on hold (status "failed") and will not be retried or re-noticed automatically.\n\n' +
            'Reason: ' + why + '\n\n' +
            'Next steps:\n' +
            ' 1. Fix the cause (for example the Direct Debit card shows "mandate document pending": click "Retry mandate document"; ' +
            'or the Direct Debit is dead: set up a new one with the client).\n' +
            ' 2. Click "Retry" on this instalment in the Fee Charge card. It sends one fresh 5-day notice and collects on that date.\n' +
            ' 3. If the client disputed a payment, do NOT retry: decide with them how the balance is settled.'));
    }

    private static Task alertTask(Id appId, String subject, String body) {
        return new Task(
            WhatId       = appId,
            Subject      = subject.length() > 255 ? subject.substring(0, 255) : subject,
            Description  = body,
            Status       = 'Open',
            Priority     = 'High',
            ActivityDate = Date.today()
        );
    }

    /** Best-effort: a Task failure must not roll back the ledger stamps. */
    private static void insertTasks(List<Task> tasks) {
        if (tasks == null || tasks.isEmpty()) return;
        Database.SaveResult[] srs = Database.insert(tasks, false);
        for (Integer i = 0; i < srs.size(); i++) {
            if (!srs[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR,
                    'AA_FeeInstallmentScheduler: alert Task insert failed for ' + tasks[i].WhatId + ' — ' + srs[i].getErrors());
            }
        }
    }

    // ---------- fire one installment (callout only, returns response) -------
    /**
     * Returns the parsed endpoint response, ok or not ('ok' + 'error' keys, and
     * on a 409 also next_possible_charge_date). Never performs DML.
     */
    @TestVisible
    private static Map<String, Object> fireInstallmentCallout(Id appId, AA_Fee_Installment__c row) {
        Integer n = (Integer) row.Installment_Number__c;
        String stage = 'installment_' + n;
        // Integer pence, rounded the same way the row amount was built.
        Long amountPence = (row.Amount__c * 100).setScale(0, System.RoundingMode.HALF_UP).longValue();
        Integer plan = (row.Application__r != null && row.Application__r.Fee_Plan_Installments__c != null)
            ? (Integer) row.Application__r.Fee_Plan_Installments__c : null;

        Map<String, Object> body = new Map<String, Object>{
            'sf_app_id'    => String.valueOf(appId),
            'amount_pence' => amountPence,
            'currency'     => 'GBP',
            'charge_stage' => stage,
            // The date the advance notice gave the client (audit 2026-10-02 F101).
            'charge_date'  => String.valueOf(row.Scheduled_Date__c),
            // GoCardless shows this to the payer: no em dash (audit 2026-10-02 F112).
            'description'  => (plan != null && plan > 1)
                ? 'XtraPension fee, payment ' + n + ' of ' + plan
                : 'XtraPension fee'
        };
        // A pending row that already carries a payment id was put back by
        // AA_GoCardlessController.retryInstallment: re-collect that payment
        // instead of creating a duplicate (audit 2026-10-02 F110).
        if (String.isNotBlank(row.Payment_Id__c)) body.put('retry_payment_id', row.Payment_Id__c);
        return doCallout(PATH_CHARGE_FEE, body);
    }

    /**
     * Bulk-refresh Fee_Plan_Next_Charge_Date__c on every touched Application:
     * the earliest still-pending installment date, or null when none remain.
     * A 'paused' row (Do Not Contact) is not a next charge: it is counted
     * again once the pause step puts it back to 'pending'.
     * One aggregate query + one DML (no callouts) — safe in Phase B.
     */
    @TestVisible
    private static void advanceParentNextChargeDates(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return;
        Map<Id, Date> nextByApp = new Map<Id, Date>();
        for (AggregateResult ar : [
            SELECT Application__c app, MIN(Scheduled_Date__c) nd
              FROM AA_Fee_Installment__c
             WHERE Application__c IN :appIds
               AND Payment_Status__c = 'pending'
             GROUP BY Application__c
        ]) {
            nextByApp.put((Id) ar.get('app'), (Date) ar.get('nd'));
        }
        List<AA_Application__c> ups = new List<AA_Application__c>();
        for (Id appId : appIds) {
            ups.add(new AA_Application__c(
                Id = appId,
                Fee_Plan_Next_Charge_Date__c = nextByApp.get(appId) // null clears it
            ));
        }
        update ups;
    }

    // ---------- Do Not Contact: pause + resume ------------------------------
    /**
     * Owner decision (Fernando, 2026-10-02): Do Not Contact (often a reported
     * death) PAUSES fee collection. The notice and charge sweeps already skip a
     * Do Not Contact application, so nothing is noticed or created for it. This
     * step makes the pause visible to ops and safe to undo:
     *   - an instalment not yet created at GoCardless moves to
     *     Payment_Status__c = 'paused' and loses its notice stamp. On resume
     *     it goes back to 'pending' and the notice sweep re-dates it if needed
     *     and sends a fresh 5-day notice: nothing is collected on a notice
     *     sent before the pause, and a date that passed during the pause is
     *     not mistaken for a failed payment creation (that path puts the row
     *     on hold as 'failed');
     *   - an instalment already created at GoCardless keeps 'pending': it WILL
     *     be collected unless ops cancels it, so calling it paused would be
     *     wrong. The sweep does not cancel it (orchestrator default, wave 4:
     *     it is created only 5 days before its date, and cancelling a payment
     *     is not undone by clearing the flag);
     *   - ONE AA_Handoff__c per pause tells ops the fee is paused and lists any
     *     instalment that was already created at GoCardless before the flag was
     *     set. This sweep cannot recall those; ops cancels them in the
     *     GoCardless dashboard before their date. A handoff that could not be
     *     inserted is raised again on the next daily run (the app's 'paused'
     *     rows keep it a candidate until an ACTIVE handoff exists);
     *   - when Do_Not_Contact__c is cleared, the 'paused' rows go back to
     *     'pending' (the only status a row is ever paused from), the pause
     *     handoff is closed with a note and the sweeps pick the rows up again
     *     as normal.
     * The Fee Charge card shows 'paused' rows as "Paused: Do Not Contact".
     * No callouts: safe in Schedulable context.
     */
    @TestVisible
    public static PauseResult pauseDoNotContact(Date today) {
        PauseResult res = new PauseResult();
        Set<Id> touchedApps = new Set<Id>();

        // 1. Resume: close the pause handoff of every application whose flag
        //    was cleared, and put its 'paused' rows back to 'pending' (their
        //    notice stamp was cleared when they were paused, so the notice
        //    sweep re-notices them before anything is collected).
        List<AA_Fee_Installment__c> restore = new List<AA_Fee_Installment__c>();
        for (AA_Fee_Installment__c r : [
            SELECT Id, Application__c
              FROM AA_Fee_Installment__c
             WHERE Payment_Status__c = :STATUS_PAUSED
               AND Application__r.Do_Not_Contact__c = false
             LIMIT 2000
        ]) {
            restore.add(new AA_Fee_Installment__c(Id = r.Id, Payment_Status__c = 'pending'));
            touchedApps.add(r.Application__c);
        }
        List<AA_Handoff__c> ended = new List<AA_Handoff__c>();
        for (AA_Handoff__c h : [
            SELECT Id, Resolved__c, Reviewed_At__c, Next_Step_Suggestion__c
              FROM AA_Handoff__c
             WHERE Last_Field_Id__c = :DNC_PAUSE_ACTIVE
               AND Application__r.Do_Not_Contact__c = false
             LIMIT 1000
        ]) {
            ended.add(new AA_Handoff__c(
                Id                      = h.Id,
                Last_Field_Id__c        = DNC_PAUSE_ENDED,
                Resolved__c             = true,
                Reviewed_At__c          = h.Reviewed_At__c != null ? h.Reviewed_At__c : Datetime.now(),
                Next_Step_Suggestion__c = (DNC_RESUMED_MARK + ' Do Not Contact was cleared, so fee collection resumed on ' +
                    today.format() + '. Instalments not yet set up at GoCardless get a fresh 5-day advance notice before they are collected.\n\n' +
                    (h.Next_Step_Suggestion__c == null ? '' : h.Next_Step_Suggestion__c)).left(2000)
            ));
        }

        // 2. Pause: pending AND already-paused rows of Do Not Contact
        //    applications. Closed or disputed cases (HALT_STAGES) are stopped
        //    already and owned by ops.
        //    'paused' rows are read again on purpose (integrator 2026-10-02):
        //    they are never re-paused (only an uncreated 'pending' row goes
        //    into `unnotice`), but they keep the application a handoff
        //    candidate. The row update and the handoff insert are separate
        //    partial-success DMLs, so a handoff insert that failed (the
        //    notify trigger's FeedItem or email throwing, a lock) used to be
        //    lost for good once the rows were 'paused' and no longer matched
        //    a 'pending' query: ops were never told. Now the next daily run
        //    finds no ACTIVE handoff for the app and raises it, and the ACTIVE
        //    dedupe in step 3 keeps it to one handoff per pause episode.
        Set<String> pauseScope = new Set<String>{ 'pending', STATUS_PAUSED };
        Map<Id, List<AA_Fee_Installment__c>> byApp = new Map<Id, List<AA_Fee_Installment__c>>();
        List<AA_Fee_Installment__c> unnotice = new List<AA_Fee_Installment__c>();
        for (AA_Fee_Installment__c r : [
            SELECT Id, Application__c, Installment_Number__c, Amount__c, Scheduled_Date__c,
                   Charged_At__c, Payment_Id__c, Bacs_Notice_Sent__c, Payment_Status__c
              FROM AA_Fee_Installment__c
             WHERE Payment_Status__c IN :pauseScope
               AND Application__r.Do_Not_Contact__c = true
               AND Application__r.Stage__c NOT IN :HALT_STAGES
             ORDER BY Application__c, Installment_Number__c
             LIMIT 2000
        ]) {
            if (!byApp.containsKey(r.Application__c)) byApp.put(r.Application__c, new List<AA_Fee_Installment__c>());
            byApp.get(r.Application__c).add(r);
            if (r.Payment_Status__c == 'pending' && r.Charged_At__c == null) {
                unnotice.add(new AA_Fee_Installment__c(
                    Id = r.Id, Payment_Status__c = STATUS_PAUSED,
                    Bacs_Notice_Sent__c = false, Bacs_Notice_Sent_At__c = null));
                touchedApps.add(r.Application__c);
            }
        }

        // 3. One handoff per pause: skip an application whose current pause
        //    already has one (open, or resolved by ops while still paused).
        List<AA_Handoff__c> raised = new List<AA_Handoff__c>();
        if (!byApp.isEmpty()) {
            Set<Id> already = new Set<Id>();
            for (AA_Handoff__c h : [
                SELECT Application__c FROM AA_Handoff__c
                 WHERE Application__c IN :byApp.keySet()
                   AND Last_Field_Id__c = :DNC_PAUSE_ACTIVE
            ]) {
                already.add(h.Application__c);
            }
            for (Id appId : byApp.keySet()) {
                if (already.contains(appId)) continue;
                raised.add(new AA_Handoff__c(
                    Application__c          = appId,
                    Escalation_Type__c      = 'other',
                    Reason__c               = DNC_PAUSE_REASON,
                    Last_Field_Id__c        = DNC_PAUSE_ACTIVE,
                    Next_Step_Suggestion__c = pauseNote(byApp.get(appId)).left(2000)
                ));
            }
        }

        // Partial success throughout: one locked row must not undo the rest.
        // The handoff insert also emails ops (AA_HandoffNotifyTrigger).
        if (!restore.isEmpty()) res.restored = countOk(Database.update(restore, false), 'row restore');
        if (!ended.isEmpty()) res.resumed = countOk(Database.update(ended, false), 'resume handoff');
        if (!unnotice.isEmpty()) res.unnoticed = countOk(Database.update(unnotice, false), 'row pause');
        if (!raised.isEmpty()) res.handoffs = countOk(Database.insert(raised, false), 'pause handoff');
        // A paused row is not a next charge, a restored one is again. Guarded:
        // the row writes above are already committed and must stand.
        try {
            advanceParentNextChargeDates(touchedApps);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'AA_FeeInstallmentScheduler: DNC next-charge-date refresh failed: ' + e.getMessage());
        }
        return res;
    }

    /** Ops-facing body of a pause handoff (Next_Step_Suggestion__c). */
    private static String pauseNote(List<AA_Fee_Installment__c> rows) {
        List<String> atGc = new List<String>();
        for (AA_Fee_Installment__c r : rows) {
            if (r.Charged_At__c == null) continue;
            atGc.add(' - instalment ' + r.Installment_Number__c + ', £' + r.Amount__c + ', due ' +
                (r.Scheduled_Date__c == null ? '(no date)' : r.Scheduled_Date__c.format()) +
                (String.isBlank(r.Payment_Id__c) ? '' : ' (GoCardless payment ' + r.Payment_Id__c + ')'));
        }
        String s = 'This client is marked Do Not Contact, so no fee instalment will be noticed or collected. '
            + 'Nothing needs doing to keep it paused. Instalments not yet set up at GoCardless now show the status "paused".\n\n';
        if (!atGc.isEmpty()) {
            s += 'ACTION NEEDED: these instalments were already set up at GoCardless before the flag was set and WILL be '
                + 'collected unless you cancel them in the GoCardless dashboard before their date:\n'
                + String.join(atGc, '\n') + '\n\n';
        }
        s += 'If Do Not Contact was set by mistake, clear it: collection resumes on the next daily run and the client '
            + 'gets a fresh 5-day advance notice before each payment. If the client has died, check with your manager '
            + 'before taking any further step on the fee.';
        return s;
    }

    private static Integer countOk(Database.SaveResult[] srs, String what) {
        Integer ok = 0;
        for (Database.SaveResult sr : srs) {
            if (sr.isSuccess()) { ok++; continue; }
            System.debug(LoggingLevel.ERROR,
                'AA_FeeInstallmentScheduler: DNC ' + what + ' failed: ' + sr.getErrors());
        }
        return ok;
    }

    // ---------- advance-notice emails (T-5 calendar days) ------------------
    /** Daily sweep over every eligible Application. */
    @TestVisible
    public static Integer[] sendAdvanceNotices(Date today) {
        return sendAdvanceNotices(today, null);
    }

    /**
     * Returns {sent, errored} where sent = Applications dispatched; errored=1
     * when rows are due a notice but no active template exists (rows are left
     * unstamped so they retry). `onlyApps` (nullable) restricts the run to
     * those Applications — AA_GoCardlessController uses it to send the first
     * notice the moment a plan is scheduled or an instalment is retried.
     * Enqueues async dispatch only — no callouts. ONE AA_MessageDispatcher job
     * for the whole batch (the 50-async cap from Schedulable context).
     */
    public static Integer[] sendAdvanceNotices(Date today, Set<Id> onlyApps) {
        Date noticeDate = today.addDays(NOTICE_DAYS);

        // 0. Void the notice of every noticed, still-uncreated row whose
        //    application has left COLLECTABLE_STAGES (integrator 2026-10-02).
        //    The charge query skips such rows, but the stamp would survive:
        //    if the case came back to a collectable stage before the date,
        //    the row would be collected on a notice that may have been
        //    suppressed by the dispatcher's stage gate (the stage can move
        //    between this sweep and the dispatcher's async send). Clearing it
        //    makes the step below re-date and re-notice the row first, the
        //    same way the Do Not Contact pause does. No callouts.
        List<AA_Fee_Installment__c> voided = new List<AA_Fee_Installment__c>();
        for (AA_Fee_Installment__c r : [
            SELECT Id, Application__c
              FROM AA_Fee_Installment__c
             WHERE Payment_Status__c = 'pending'
               AND Charged_At__c = null
               AND Bacs_Notice_Sent__c = true
               AND Application__r.Stage__c NOT IN :COLLECTABLE_STAGES
             LIMIT 2000
        ]) {
            if (onlyApps != null && !onlyApps.contains(r.Application__c)) continue;
            voided.add(new AA_Fee_Installment__c(Id = r.Id, Bacs_Notice_Sent__c = false, Bacs_Notice_Sent_At__c = null));
        }
        if (!voided.isEmpty()) {
            Database.SaveResult[] vrs = Database.update(voided, false);
            for (Integer i = 0; i < vrs.size(); i++) {
                if (!vrs[i].isSuccess()) {
                    System.debug(LoggingLevel.ERROR,
                        'AA_FeeInstallmentScheduler: gated-stage notice void failed for ' + voided[i].Id + ' — ' + vrs[i].getErrors());
                }
            }
        }

        // 1. Applications with a row that needs a notice, a new date or a hold:
        //    an un-noticed, uncreated pending row dated within the notice
        //    horizon, or a noticed one whose date has passed before it was
        //    created (held below, never re-noticed). Only apps at a stage
        //    where the dispatcher will actually send the notice
        //    (COLLECTABLE_STAGES).
        Set<Id> appIds = new Set<Id>();
        for (AA_Fee_Installment__c r : [
            SELECT Application__c
              FROM AA_Fee_Installment__c
             WHERE Payment_Status__c = 'pending'
               AND Charged_At__c = null
               AND Scheduled_Date__c <= :noticeDate
               AND (Bacs_Notice_Sent__c = false OR Scheduled_Date__c <= :today)
               AND Application__r.DD_Mandate_Status__c = 'active'
               AND Application__r.DD_Mandate_Id__c != null
               AND Application__r.Do_Not_Contact__c = false
               AND Application__r.Stage__c IN :COLLECTABLE_STAGES
             LIMIT 2000
        ]) {
            if (r.Application__c == null) continue;
            if (onlyApps != null && !onlyApps.contains(r.Application__c)) continue;
            appIds.add(r.Application__c);
        }
        if (appIds.isEmpty()) return new Integer[]{ 0, 0 };

        // 2. Walk each Application's rows in instalment order: move rows that
        //    would otherwise be noticed short (or were noticed for a date that
        //    has passed), keeping a month between instalments, and pick the
        //    rows whose notice goes out today.
        Map<Id, AA_Fee_Installment__c> changes = new Map<Id, AA_Fee_Installment__c>();
        List<AA_Fee_Installment__c> toNotice = new List<AA_Fee_Installment__c>();
        List<AA_Fee_Installment__c> holds = new List<AA_Fee_Installment__c>();
        List<Task> tasks = new List<Task>();
        Set<Id> redatedApps = new Set<Id>();
        Id curApp = null;
        Date spacingFloor = null;
        for (AA_Fee_Installment__c row : [
            SELECT Id, Application__c, Installment_Number__c, Scheduled_Date__c, Amount__c,
                   Payment_Status__c, Charged_At__c, Bacs_Notice_Sent__c
              FROM AA_Fee_Installment__c
             WHERE Application__c IN :appIds
             ORDER BY Application__c, Installment_Number__c
        ]) {
            if (row.Application__c != curApp) { curApp = row.Application__c; spacingFloor = null; }
            Boolean movable = row.Payment_Status__c == 'pending' && row.Charged_At__c == null;
            if (movable && row.Bacs_Notice_Sent__c == true && row.Scheduled_Date__c != null
                    && row.Scheduled_Date__c <= today) {
                // The client was told this date, and the charge step tried to
                // create the payment every day since the notice without success.
                // Re-dating + re-noticing here looped forever on a permanent
                // refusal (wave-2 review of F101): hold it and tell a human.
                holdRow(row, 'the payment could not be created at GoCardless on any day between the advance notice and ' +
                    row.Scheduled_Date__c.format() + ' (see the Apex debug log of AA_FeeInstallmentChargeQueueable for the error)',
                    holds, tasks);
                redatedApps.add(row.Application__c);   // refresh Fee_Plan_Next_Charge_Date__c
                continue;                              // a held row does not hold the plan back
            }
            if (!movable) {
                // Created / submitted / paid rows hold their date; the next
                // instalment must stay a month after them. Failed or cancelled
                // rows do not hold the plan back. A 'paused' row only meets
                // this loop if Do Not Contact was cleared after today's pause
                // step ran; it is still owed, so it keeps the month gap too.
                if (row.Scheduled_Date__c != null
                        && row.Payment_Status__c != 'failed' && row.Payment_Status__c != 'cancelled') {
                    spacingFloor = maxDate(spacingFloor, row.Scheduled_Date__c.addMonths(1));
                }
                continue;
            }
            Date d = row.Scheduled_Date__c;
            Boolean noticed = row.Bacs_Notice_Sent__c == true;
            // A noticed row may sit inside the 5-day horizon (its payment is
            // created the same day; a GoCardless outage can delay that by a
            // day or two). An un-noticed row may not: it would be noticed short.
            Date floor = maxDate(spacingFloor, noticed ? today.addDays(1) : noticeDate);
            if (d == null || d < floor) {
                Date nd = maxDate(noticeDate, spacingFloor);
                changes.put(row.Id, new AA_Fee_Installment__c(
                    Id                     = row.Id,
                    Scheduled_Date__c      = nd,
                    Bacs_Notice_Sent__c    = false,
                    Bacs_Notice_Sent_At__c = null
                ));
                redatedApps.add(row.Application__c);
                d = nd;
                noticed = false;
            }
            if (!noticed && d <= noticeDate) toNotice.add(row);
            spacingFloor = d.addMonths(1);
        }

        Integer notices = 0;
        Integer errored = 0;
        Set<Id> noticeApps = new Set<Id>();
        for (AA_Fee_Installment__c row : toNotice) noticeApps.add(row.Application__c);

        if (!noticeApps.isEmpty()) {
            // dispatch() cannot tell us whether anything will go out: with no active
            // Bacs_Advance_Notice template its execute() returns at templates.isEmpty()
            // and the rows would still be stamped "sent". Same predicate as the
            // dispatcher's template query. Rows stay unstamped (and so uncollectable)
            // until a template is (re)activated.
            Integer activeTemplates = [
                SELECT COUNT()
                  FROM AA_Message_Template__c
                 WHERE Active__c = true
                   AND Trigger_Event__c = :BACS_ADVANCE_TEMPLATE
            ];
            Boolean dispatched = false;
            if (activeTemplates == 0) {
                System.debug(LoggingLevel.ERROR,
                    'AA_FeeInstallmentScheduler: no active ' + BACS_ADVANCE_TEMPLATE +
                    ' template — ' + toNotice.size() + ' installment(s) due a notice left unstamped for retry');
                errored = 1;
            } else {
                try {
                    dispatchBacsAdvanceNotice(noticeApps);
                    dispatched = true;
                    notices = noticeApps.size();
                } catch (Exception e) {
                    // Leave the rows unstamped: the next sweep re-picks them.
                    System.debug(LoggingLevel.ERROR,
                        'AA_FeeInstallmentScheduler: Bacs notice dispatch failed for ' +
                        noticeApps.size() + ' apps — ' + e.getMessage());
                    errored = 1;
                }
            }
            if (dispatched) {
                Datetime nowStamp = Datetime.now();
                for (AA_Fee_Installment__c row : toNotice) {
                    AA_Fee_Installment__c up = changes.containsKey(row.Id)
                        ? changes.get(row.Id) : new AA_Fee_Installment__c(Id = row.Id);
                    up.Bacs_Notice_Sent__c    = true;
                    up.Bacs_Notice_Sent_At__c = nowStamp;
                    changes.put(row.Id, up);
                }
            }
        }

        // Re-dates are persisted even when no notice could go out, so a row is
        // never left dated sooner than a notice could cover. Partial success:
        // one bad row (lock, FLS drift) cannot roll back the batch's stamps and
        // re-send every notice tomorrow; the dispatcher's 24h dedup absorbs
        // a single re-send.
        for (AA_Fee_Installment__c h : holds) changes.put(h.Id, h);
        if (!changes.isEmpty()) {
            Database.SaveResult[] srs = Database.update(changes.values(), false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (!srs[i].isSuccess()) {
                    errored++;
                    System.debug(LoggingLevel.ERROR,
                        'AA_FeeInstallmentScheduler: notice/re-date stamp failed — ' + srs[i].getErrors());
                }
            }
        }
        insertTasks(tasks);
        if (!redatedApps.isEmpty()) advanceParentNextChargeDates(redatedApps);
        return new Integer[]{ notices, errored };
    }

    @TestVisible private static Boolean testBypass = false;
    @TestVisible private static List<String> testDispatched = new List<String>();

    /** One dispatch for the whole set — the dispatcher enqueues a single job. */
    @TestVisible
    private static void dispatchBacsAdvanceNotice(Set<Id> appIds) {
        if (testBypass) {
            for (Id appId : appIds) testDispatched.add(String.valueOf(appId));
            return;
        }
        // Dispatcher dedupes by (Template, Application) within 24h. The sweep
        // keeps a month between one app's instalments, so one email per app per
        // sweep is the intended behaviour.
        AA_MessageDispatcher.dispatch(appIds, BACS_ADVANCE_TEMPLATE);
    }

    // ---------- callout plumbing (mirrors AA_GoCardlessController) ---
    /**
     * POSTs and returns the parsed JSON body. On a non-2xx response the body's
     * own keys are kept (error code, next_possible_charge_date…) with ok=false,
     * so the caller can act on a business refusal instead of a bare HTTP code.
     */
    private static Map<String, Object> doCallout(String path, Map<String, Object> body) {
        String token = getInternalToken();
        if (String.isBlank(token)) {
            return new Map<String, Object>{ 'ok' => false, 'error' => 'AA_Config__c.Internal_Admin_Token__c not set' };
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(body));

        HttpResponse resp;
        try {
            resp = new Http().send(req);
        } catch (Exception e) {
            return new Map<String, Object>{ 'ok' => false, 'error' => 'Endpoint unreachable: ' + e.getMessage() };
        }
        Integer status = resp.getStatusCode();
        String rawBody = resp.getBody();
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(rawBody);
        } catch (Exception e) {
            // Non-JSON (a Heroku router error page, a proxy) is never treated
            // as a business refusal: no http_status, so it stays transient.
            return new Map<String, Object>{
                'ok'    => false,
                'error' => 'Non-JSON response (HTTP ' + status + '): ' + safe(rawBody)
            };
        }
        if (status < 200 || status >= 300) {
            Map<String, Object> out = new Map<String, Object>(parsed);
            out.put('ok', false);
            // chargeDue tells a permanent refusal (4xx) from a transient one.
            out.put('http_status', status);
            if (String.isBlank(str(parsed.get('error')))) out.put('error', 'HTTP ' + status);
            return out;
        }
        return parsed;
    }

    // ---------- tiny helpers -----------------------------------------
    @TestVisible
    private static String getInternalToken() {
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Internal_Admin_Token__c))
            ? cfg.Internal_Admin_Token__c.trim() : null;
    }
    private static Boolean isTruthy(Object o) {
        return o == true || 'true'.equalsIgnoreCase(String.valueOf(o));
    }
    private static String str(Object o) { return o == null ? '' : String.valueOf(o); }
    private static String safe(String s) {
        if (s == null) return '';
        return s.length() > 255 ? s.substring(0, 255) : s;
    }
    private static Date maxDate(Date a, Date b) {
        if (a == null) return b;
        if (b == null) return a;
        return a > b ? a : b;
    }
    private static Date parseDate(Object v) {
        if (v == null) return null;
        try {
            String s = String.valueOf(v);
            if (s.length() >= 10) return Date.valueOf(s.substring(0, 10));
        } catch (Exception e) { /* fall through */ }
        return null;
    }

    public class AAFeeInstallmentException extends Exception {}
}