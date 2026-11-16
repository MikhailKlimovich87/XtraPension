/**
 * PC1_FeeInstallmentScheduler — daily Schedulable that walks the
 * PC1_Fee_Installment__c table and drives three things:
 *
 *   1. COLLECTION (create-ahead) — every pending installment that was
 *      NOTICED on an earlier run, whose notice is proven delivered (a 'Sent'
 *      PC1_Message_Send_Log__c row at or after the stamp) and whose date is
 *      still ahead, is POSTed to Heroku's /internal/gocardless/charge-fee
 *      with charge_stage='installment_<n>' AND charge_date=Scheduled_Date__c.
 *      GoCardless then debits on the date the notice stated. On success the
 *      row is stamped Payment_Id__c / Charged_At__c and moves to 'submitted';
 *      the webhook moves it on to paid / failed.
 *
 *   2. ADVANCE NOTICES — every pending, not yet created installment whose
 *      Scheduled_Date__c is within NOTICE_HORIZON_DAYS (7) and has not been
 *      noticed dispatches the `Bacs_Advance_Notice` template (MSG-0008) on the
 *      parent Application, then the row is stamped Bacs_Notice_Sent__c /
 *      _At__c. The notice states the row's date and amount
 *      ({{NextChargeDate}} / {{NextChargeAmount}}). A row is never noticed
 *      with fewer than NOTICE_DAYS (5 calendar days, Fernando 2026-08-25): a
 *      row dated sooner than that is MOVED to today + NOTICE_DAYS first.
 *
 *   3. RECONCILIATION — applications whose installments are all paid but
 *      whose stage never reached Closed - Paid (see reconcilePaidPlans).
 *
 * ── Why create-ahead (audit 2026-11-11 PC-APEX-4, port of the AA sweep) ──
 * The old sweep created the GoCardless payment ON Scheduled_Date__c with no
 * charge_date, so GoCardless debited on its own earliest date, days AFTER the
 * date the notice gave (the class header used to say Bacs was "same-day";
 * it is not). Installment #1 charged at click time got no notice at all.
 * Now the payment is created the day after its notice, dated as noticed, and
 * PC1_GoCardlessController.chargeFee no longer fires anything itself.
 *
 * ── Hold rules (audit 2026-11-11 PC-APEX-3) ──
 * Nothing is noticed, moved or collected unless the parent Application has
 * DD_Mandate_Status__c='active', a DD_Mandate_Id__c, Do_Not_Contact__c=false
 * and a Stage in COLLECTABLE_STAGES. Before this, the only thing that stopped
 * installments 2..N was a GoCardless webhook having cancelled the rows:
 * a refused, disputed, refunded or Needs Human case, and a client reported
 * deceased, were all still charged on schedule.
 *   - Mandate not active (bank change parked it, or it died): rows wait
 *     un-noticed and are re-dated + noticed on the first sweep after a new
 *     mandate is active, a month apart, never two together.
 *   - Do Not Contact: collection is PAUSED (see pauseDoNotContact): the
 *     notice stamp of rows not yet at GoCardless is cleared, ops get one
 *     handoff per pause, and clearing the flag resumes the plan with fresh
 *     notices. PC keeps the rows 'pending' (AA has a 'paused' status; PC's
 *     webhook counts 'pending' rows as still owed, which is what keeps a
 *     paused plan from being closed as paid).
 *   - A noticed row whose payment could not be created before its date is
 *     put ON HOLD (Payment_Status__c='failed') with a handoff, never moved
 *     and re-noticed in a loop. Retry on the Fee card puts it back.
 *   - A refusal from Heroku that retrying cannot fix (any 4xx except the
 *     NON_TERMINAL_4XX_ERRORS and 401) puts the row on hold at once.
 *   - No delivered notice, no collection: a stamped row with no 'Sent' log
 *     is un-stamped, noticed again and a handoff tells ops why.
 *
 * Callouts are banned in Schedulable context, so execute() hops to
 * @future(callout=true). run() does every callout first (chargeDue phase A)
 * and only then any DML.
 *
 * Cron: `0 0 8 * * ?` = daily 08:00 in the scheduling user's time zone
 * (Europe/Dublin). Registered via scripts/schedule-fee-installments.cjs.
 *
 * Idempotency:
 *   - Node side: /internal/gocardless/charge-fee dedupes on (sf_app_id,
 *     charge_stage). A repeat for the same installment returns the existing
 *     payment.
 *   - Apex side: only rows still 'pending' with Charged_At__c = null are sent.
 *
 * Failure handling: one bad callout or one bad row never stops the sweep
 * (per-row try/catch, partial-success DML), and a run with any error emails
 * the admin address (audit 2026-11-11 PC-APEX-12: errors used to go to the
 * debug log only).
 *
 * Added 2026-08-18 with the payment plan feature. See
 * docs/pc1-workflow-manual.md §3.0.
 */
public with sharing class PC1_FeeInstallmentScheduler implements Schedulable {

    // ---------- endpoint config (mirrors PC1_GoCardlessController) ----------
    @TestVisible private static final String BASE_URL = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com';
    private static final String PATH_CHARGE_FEE = '/internal/gocardless/charge-fee';
    private static final Integer TIMEOUT_MS = 20000;

    // Max rows sent to GoCardless per run. Kept under the 100 callouts per
    // transaction limit; a backlog beyond one chunk drains on the next run.
    public static final Integer CHUNK = 90;

    // Template dispatched before each scheduled charge.
    @TestVisible private static final String BACS_ADVANCE_TEMPLATE = 'Bacs_Advance_Notice';
    // Template dispatched on each non-final installment payment confirmation.
    // Owned by the webhook handler (payments.confirmed) — declared here for
    // reference so docs stay accurate.
    @TestVisible private static final String INSTALLMENT_RECEIPT_TEMPLATE = 'Fee_Receipt_Installment';

    // The advance notice the client is promised, in CALENDAR days (Fernando
    // 2026-08-25). No row is ever noticed with less than this.
    public static final Integer NOTICE_DAYS = 5;
    // A row is noticed as soon as its date is this close, which is what the
    // old T+3..T+7 window did on a normal daily run. The payment is created
    // on the next run, so GoCardless gets about six days of lead time.
    @TestVisible private static final Integer NOTICE_HORIZON_DAYS = 7;

    // THE stages in which an installment may be noticed and collected: the
    // award is recorded and the case is neither closed, disputed nor with a
    // human (Needs Human). The reconciliation below already refused to close
    // those cases; the charge query had no stage filter at all.
    public static final Set<String> COLLECTABLE_STAGES = new Set<String>{ 'Awarded', 'Fee Charged' };

    // Closed or disputed cases: stopped already and owned by ops, so the Do
    // Not Contact pause does not raise a handoff for them.
    public static final Set<String> HALT_STAGES = new Set<String>{
        'DD Chargeback', 'Closed - Paid', 'Closed - Fee Failed', 'Closed - Refused', 'Closed - Refunded'
    };

    /** True when an installment of an app at this stage may be noticed and collected. */
    public static Boolean isCollectableStage(String stage) {
        return stage != null && COLLECTABLE_STAGES.contains(stage);
    }

    // Heroku charge-fee refusals that are NOT terminal although they are 4xx:
    // charge_date_too_soon is handled by moving the row; mandate_not_charge_ready
    // is a status race; stage_not_collectable / do_not_contact mean the record
    // changed between the query and the callout (the next sweep voids the
    // notice or pauses the plan). 401 is a token problem that affects every
    // row and is fixed in config, not per installment.
    private static final Set<String> NON_TERMINAL_4XX_ERRORS = new Set<String>{
        'charge_date_too_soon', 'mandate_not_charge_ready', 'stage_not_collectable', 'do_not_contact'
    };

    // ---------- Do Not Contact pause (port of AA, owner decision 2026-10-02) ----
    // Reason__c of the ops handoff raised once per paused application.
    @TestVisible private static final String DNC_PAUSE_REASON = 'Fee collection paused: client is Do Not Contact';
    // Written at the start of Next_Step_Suggestion__c when the sweep closes a
    // pause handoff because Do_Not_Contact__c was cleared.
    @TestVisible private static final String DNC_RESUMED_MARK = 'RESUMED AUTOMATICALLY:';
    // Machine state of a pause handoff, kept in Last_Field_Id__c (Text(50); a
    // fee pause has no form field). ACTIVE = this pause is current, whether or
    // not ops resolved the handoff, so no second handoff is raised; ENDED = Do
    // Not Contact was cleared, so a later pause raises a new one.
    @TestVisible private static final String DNC_PAUSE_ACTIVE = 'fee_dnc_pause';
    @TestVisible private static final String DNC_PAUSE_ENDED  = 'fee_dnc_pause_ended';

    // Reason__c of the handoff raised when a notice was stamped but no 'Sent'
    // log exists for it. One open handoff per application.
    @TestVisible private static final String UNDELIVERED_REASON = 'Fee advance notice NOT delivered: installment not collected';
    // A stamp younger than this may still have its dispatch job in flight.
    private static final Integer NOTICE_IN_FLIGHT_HOURS = 2;

    /** Result of one chargeDue() run. */
    public class ChargeResult {
        public Integer due = 0;
        public Integer fired = 0;
        public Integer errored = 0;
        public Integer redated = 0;
        // Rows put on hold (Payment_Status__c='failed' + handoff) because
        // Heroku refused them for a reason a retry cannot fix.
        public Integer held = 0;
        // Rows whose notice has no 'Sent' log: un-stamped, not collected.
        public Integer undelivered = 0;
        // Rows re-dated in this run: noticed by the NEXT run, so the fresh
        // notice is not swallowed by the dispatcher's 24h dedup.
        public Set<Id> skipNotice = new Set<Id>();
        public List<String> errors = new List<String>();
    }

    /** Result of one pauseDoNotContact() run. */
    public class PauseResult {
        public Integer handoffs = 0;      // pause handoffs opened
        public Integer unnoticed = 0;     // rows whose notice stamp was cleared
        public Integer resumed = 0;       // pause handoffs closed because the flag was cleared
    }

    // ---------- Schedulable entrypoint --------------------------------------
    // Audit R6 C2: Schedulable context CANNOT make HTTP callouts, so the
    // sweep hops to @future(callout=true). Tests call run(today) directly
    // with Test.setMock.
    public void execute(SchedulableContext ctx) {
        runAsync(Date.today());
    }

    @future(callout=true)
    public static void runAsync(Date today) {
        run(today);
    }

    /**
     * The whole sweep. Callouts first (chargeDue phase A), then DML only.
     * Returns a summary line (also written to the debug log).
     */
    @TestVisible
    public static String run(Date today) {
        List<String> errors = new List<String>();

        // ---------- 1. Create the payments noticed on an earlier run -------
        ChargeResult cr = chargeDue(today);
        Integer errored = cr.errored;
        errors.addAll(cr.errors);

        // ---------- 2. Do Not Contact pause / resume -----------------------
        PauseResult pr = new PauseResult();
        try {
            pr = pauseDoNotContact(today);
        } catch (Exception e) {
            errored++;
            errors.add('Do Not Contact pause step failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'PC1_FeeInstallmentScheduler: DNC pause failed — ' + e.getMessage());
        }

        // ---------- 3. Advance notices -------------------------------------
        Integer notices = 0;
        try {
            NoticeResult nr = sendAdvanceNoticesInternal(today, null, cr.skipNotice);
            notices = nr.notices;
            errored += nr.errored;
            errors.addAll(nr.errors);
        } catch (Exception e) {
            errored++;
            errors.add('Advance notice step failed: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'PC1_FeeInstallmentScheduler: notice step failed — ' + e.getMessage());
        }

        // ---------- 4. Reconciliation --------------------------------------
        Integer reconciled = 0;
        try {
            reconciled = reconcilePaidPlans();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_FeeInstallmentScheduler: reconciliation sweep failed — ' + e.getMessage());
        }

        String summary = 'PC1_FeeInstallmentScheduler: fired=' + cr.fired +
            ' notices=' + notices + ' reconciled=' + reconciled + ' errored=' + errored +
            ' (due=' + cr.due + ' redated=' + cr.redated + ' held=' + cr.held +
            ' undelivered=' + cr.undelivered + ' dncPaused=' + pr.handoffs + ' dncResumed=' + pr.resumed + ')';
        System.debug(LoggingLevel.INFO, summary);
        if (errored > 0) alertAdmin(summary, errors);
        return summary;
    }

    // ---------- collection: callouts FIRST, then partial-success DML --------
    /**
     * Create the GoCardless payment for the NOTICED installments, with
     * charge_date = the noticed Scheduled_Date__c. At most one installment per
     * application per run. Phase A is callouts only; Phase B is DML only.
     */
    @TestVisible
    private static ChargeResult chargeDue(Date today) {
        ChargeResult res = new ChargeResult();
        List<PC1_Fee_Installment__c> due = [
            SELECT Id, Application__c, Installment_Number__c, Amount__c,
                   Scheduled_Date__c, Payment_Status__c, Bacs_Notice_Sent__c, Bacs_Notice_Sent_At__c,
                   Application__r.Fee_Plan_Installments__c
              FROM PC1_Fee_Installment__c
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
        if (due.isEmpty()) return res;

        Set<Id> dueApps = new Set<Id>();
        for (PC1_Fee_Installment__c row : due) dueApps.add(row.Application__c);
        Map<Id, Datetime> lastSentByApp = lastBacsNoticeSent(dueApps);
        Datetime inFlightCutoff = Datetime.now().addHours(-NOTICE_IN_FLIGHT_HOURS);

        // ---- Phase A: callouts only, collect updates (NO DML yet) ----
        List<PC1_Fee_Installment__c> toUpdate = new List<PC1_Fee_Installment__c>();
        List<PC1_Handoff__c> handoffs = new List<PC1_Handoff__c>();
        Set<Id> undeliveredApps = new Set<Id>();
        Set<Id> touchedApps = new Set<Id>();
        Set<Id> seenApps = new Set<Id>();
        for (PC1_Fee_Installment__c row : due) {
            // One installment per application per run (audit PC-APEX-3: after
            // a mandate gap every overdue row used to fire on the same day).
            if (seenApps.contains(row.Application__c)) continue;
            seenApps.add(row.Application__c);

            // No delivered notice, no collection.
            Datetime lastSent = lastSentByApp.get(row.Application__c);
            Boolean delivered = lastSent != null && row.Bacs_Notice_Sent_At__c != null
                && lastSent >= row.Bacs_Notice_Sent_At__c;
            if (!delivered) {
                if (row.Bacs_Notice_Sent_At__c != null && row.Bacs_Notice_Sent_At__c > inFlightCutoff) continue;
                toUpdate.add(new PC1_Fee_Installment__c(
                    Id = row.Id, Bacs_Notice_Sent__c = false, Bacs_Notice_Sent_At__c = null));
                undeliveredApps.add(row.Application__c);
                touchedApps.add(row.Application__c);
                res.undelivered++;
                continue;
            }

            touchedApps.add(row.Application__c);
            try {
                Map<String, Object> resp = calloutForInstallment(row.Application__c, row);
                String paymentId = str(resp.get('payment_id'));
                if (isTruthy(resp.get('ok')) && String.isNotBlank(paymentId)) {
                    PC1_Fee_Installment__c up = new PC1_Fee_Installment__c(
                        Id                = row.Id,
                        Payment_Id__c     = paymentId,
                        Payment_Status__c = 'submitted',
                        Charged_At__c     = Datetime.now()
                    );
                    // GoCardless rolls a weekend / bank-holiday charge_date to
                    // the next working day; record the real debit date.
                    Date gcDate = parseDate(resp.get('charge_date'));
                    if (gcDate != null && gcDate > row.Scheduled_Date__c) up.Scheduled_Date__c = gcDate;
                    if (gcDate != null && gcDate < row.Scheduled_Date__c) {
                        // Deploy-order guard: a Heroku build older than the
                        // create-ahead change drops charge_date, so GoCardless
                        // debits on its own earliest date, BEFORE the date the
                        // client was told. The payment already exists, so the
                        // row is still stamped, but a human has to act.
                        up.Scheduled_Date__c = gcDate;
                        handoffs.add(alertHandoff(row.Application__c,
                            'URGENT: fee installment ' + row.Installment_Number__c.intValue() + ' will be collected EARLY',
                            'GoCardless payment ' + paymentId + ' for installment ' + row.Installment_Number__c.intValue() +
                            ' (£' + row.Amount__c + ') is dated ' + gcDate.format() + ', but the client was told ' +
                            row.Scheduled_Date__c.format() + ' in the advance notice. Heroku is most likely running a build ' +
                            'older than the Salesforce fee code (it ignores charge_date).\n\n' +
                            'Before ' + gcDate.format() + ': cancel this payment in the GoCardless dashboard and tell the tech team.'));
                    }
                    toUpdate.add(up);
                    res.fired++;
                } else if (str(resp.get('error')) == 'charge_date_too_soon') {
                    // The noticed date is before the mandate's next possible
                    // charge date. Move the row past it and clear the notice,
                    // so the client is told the real date before anything is
                    // taken. Noticed by tomorrow's run (see skipNotice).
                    Date npcd = parseDate(resp.get('next_possible_charge_date'));
                    Date floor = today.addDays(NOTICE_DAYS + 1);
                    Date nd = (npcd != null && npcd > floor) ? npcd : floor;
                    toUpdate.add(new PC1_Fee_Installment__c(
                        Id                     = row.Id,
                        Scheduled_Date__c      = nd,
                        Bacs_Notice_Sent__c    = false,
                        Bacs_Notice_Sent_At__c = null
                    ));
                    res.skipNotice.add(row.Id);
                    res.redated++;
                } else if (isTerminalRefusal(resp)) {
                    holdRow(row, 'Heroku refused to create the payment: ' + str(resp.get('error')) +
                        (String.isNotBlank(str(resp.get('detail'))) ? ' (' + safe(str(resp.get('detail'))) + ')' : ''),
                        toUpdate, handoffs);
                    res.held++;
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: row ' + row.Id + ' put on hold, terminal refusal ' + str(resp.get('error')));
                } else {
                    res.errored++;
                    String err = String.isNotBlank(str(resp.get('error'))) ? str(resp.get('error')) : 'no payment id in the answer';
                    res.errors.add('Installment ' + row.Id + ' not created at GoCardless: ' + safe(err));
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: fire failed for ' + row.Id + ' — ' + err);
                }
            } catch (Exception e) {
                res.errored++;
                res.errors.add('Installment ' + row.Id + ' not created at GoCardless: ' + safe(e.getMessage()));
                System.debug(LoggingLevel.ERROR,
                    'PC1_FeeInstallmentScheduler: fire failed for ' + row.Id + ' — ' + e.getMessage());
            }
        }

        // ---- Phase B: DML only (no callouts past this point) ----
        // The GoCardless payments above ALREADY exist. A plain `update` is
        // all-or-nothing, so one bad row (lock, validation rule) used to roll
        // back every payment-id stamp of the run and everything after it
        // (audit 2026-11-11 PC-APEX-12). Partial success keeps each stamp.
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] srs = Database.update(toUpdate, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (!srs[i].isSuccess()) {
                    res.errored++;
                    res.errors.add('Installment ' + toUpdate[i].Id + ' could not be stamped (its payment may already exist at GoCardless): '
                        + safe(String.valueOf(srs[i].getErrors())));
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: stamp failed for ' + toUpdate[i].Id + ' — ' + srs[i].getErrors());
                }
            }
        }
        insertHandoffs(handoffs);
        raiseUndeliveredHandoffs(undeliveredApps);
        try {
            advanceParentNextChargeDatesBulk(touchedApps);
        } catch (Exception e) {
            res.errored++;
            res.errors.add('Next charge date refresh failed: ' + safe(e.getMessage()));
        }
        return res;
    }

    /** Latest delivered ('Sent') Bacs advance notice email per application. */
    private static Map<Id, Datetime> lastBacsNoticeSent(Set<Id> appIds) {
        Map<Id, Datetime> out = new Map<Id, Datetime>();
        if (appIds == null || appIds.isEmpty()) return out;
        for (PC1_Message_Send_Log__c l : [
            SELECT Application__c, Sent_At__c
              FROM PC1_Message_Send_Log__c
             WHERE Application__c IN :appIds
               AND Template__r.Trigger_Event__c = :BACS_ADVANCE_TEMPLATE
               AND Channel__c = 'Email'
               AND Status__c = 'Sent'
               AND Sent_At__c != null
             ORDER BY Sent_At__c DESC
             LIMIT 2000
        ]) {
            if (!out.containsKey(l.Application__c)) out.put(l.Application__c, l.Sent_At__c);
        }
        return out;
    }

    /**
     * A refusal from /internal/gocardless/charge-fee that the next day's sweep
     * cannot fix: no_mandate_on_application, bad_charge_stage,
     * application_not_found, a GoCardless validation error... = any 4xx except
     * 401 and the non-terminal ones. 5xx, timeouts and non-JSON answers stay
     * transient.
     */
    @TestVisible
    private static Boolean isTerminalRefusal(Map<String, Object> resp) {
        Integer st = resp.get('http_status') == null ? null : Integer.valueOf(resp.get('http_status'));
        if (st == null || st < 400 || st >= 500 || st == 401) return false;
        return !NON_TERMINAL_4XX_ERRORS.contains(str(resp.get('error')));
    }

    /**
     * Put a pending, not yet created row on hold: 'failed' takes it out of
     * both sweeps (they only read 'pending') and shows the Retry button on
     * the Fee card. Retry puts it back to 'pending' and the sweep sends one
     * fresh notice before collecting.
     */
    private static void holdRow(PC1_Fee_Installment__c row, String why,
                                List<PC1_Fee_Installment__c> ups, List<PC1_Handoff__c> handoffs) {
        ups.add(new PC1_Fee_Installment__c(Id = row.Id, Payment_Status__c = 'failed'));
        String n = String.valueOf(row.Installment_Number__c.intValue());
        String dateTold = row.Scheduled_Date__c == null ? 'the date in the notice' : row.Scheduled_Date__c.format();
        handoffs.add(alertHandoff(row.Application__c,
            'Fee installment ' + n + ' NOT collected: call the client',
            'Installment ' + n + ' (£' + row.Amount__c + ') could not be set up at GoCardless, so nothing will be taken on ' +
            dateTold + '. ' + (row.Bacs_Notice_Sent__c == true
                ? 'The client WAS emailed an advance notice for that date: let them know nothing will be taken. '
                : '') +
            'The installment is on hold (status "failed") and will not be retried or re-noticed automatically.\n\n' +
            'Reason: ' + why + '\n\n' +
            'Next steps:\n' +
            ' 1. Fix the cause (for example the Direct Debit is dead: set up a new one with the client).\n' +
            ' 2. Click "Retry" on this installment in the Fee card. A fresh advance notice goes out and it is collected on the new date.\n' +
            ' 3. If the client disputed a payment, do NOT retry: decide with them how the balance is settled.'));
    }

    private static PC1_Handoff__c alertHandoff(Id appId, String reason, String nextStep) {
        return new PC1_Handoff__c(
            CurrencyIsoCode         = 'GBP',
            Application__c          = appId,
            Escalation_Type__c      = 'other',
            Reason__c               = reason.left(255),
            Next_Step_Suggestion__c = nextStep.left(2000),
            Resolved__c             = false
        );
    }

    /** Best-effort: a handoff failure must not roll back the ledger stamps. */
    private static Integer insertHandoffs(List<PC1_Handoff__c> handoffs) {
        Integer ok = 0;
        if (handoffs == null || handoffs.isEmpty()) return ok;
        try {
            Database.SaveResult[] srs = Database.insert(handoffs, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (srs[i].isSuccess()) { ok++; continue; }
                System.debug(LoggingLevel.ERROR,
                    'PC1_FeeInstallmentScheduler: handoff insert failed for ' + handoffs[i].Application__c + ' — ' + srs[i].getErrors());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_FeeInstallmentScheduler: handoff DML failed — ' + e.getMessage());
        }
        return ok;
    }

    /** One open handoff per application whose notice never went out. */
    private static void raiseUndeliveredHandoffs(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return;
        Set<Id> already = new Set<Id>();
        for (PC1_Handoff__c h : [
            SELECT Application__c FROM PC1_Handoff__c
             WHERE Application__c IN :appIds AND Reason__c = :UNDELIVERED_REASON AND Resolved__c = false
        ]) {
            already.add(h.Application__c);
        }
        List<PC1_Handoff__c> handoffs = new List<PC1_Handoff__c>();
        for (Id appId : appIds) {
            if (already.contains(appId)) continue;
            handoffs.add(alertHandoff(appId, UNDELIVERED_REASON,
                'The Direct Debit advance notice (MSG-0008) for the next fee installment was handed to the dispatcher but no ' +
                '"Sent" row exists for it in the message send log (skipped or failed: no email address, sandbox gate, a ' +
                'missing value in the template...). Nothing is collected without a delivered notice, so the installment was ' +
                'NOT set up at GoCardless.\n\n' +
                'Open the PC Message Send Log rows of this application to see why, fix the cause, and the daily sweep sends ' +
                'the notice again and collects on the new date. Resolve this handoff once a notice shows "Sent".'));
        }
        insertHandoffs(handoffs);
    }

    // ---------- callout-only helper (no DML) — Phase A --------------------
    /**
     * Returns the parsed endpoint response, ok or not ('ok' + 'error' keys, on
     * a refusal also http_status and next_possible_charge_date).
     */
    @TestVisible
    private static Map<String, Object> calloutForInstallment(Id appId, PC1_Fee_Installment__c row) {
        Integer n = row.Installment_Number__c.intValue();
        String stage = 'installment_' + n;
        // Integer pence, rounded the same way the row amount was built.
        Long amountPence = (row.Amount__c * 100).setScale(0, System.RoundingMode.HALF_UP).longValue();
        Integer plan = (row.Application__r != null && row.Application__r.Fee_Plan_Installments__c != null)
            ? row.Application__r.Fee_Plan_Installments__c.intValue() : null;
        Map<String, Object> body = new Map<String, Object>{
            'sf_app_id'    => String.valueOf(appId),
            'amount_pence' => amountPence,
            'currency'     => 'GBP',
            'charge_stage' => stage,
            // The date the advance notice gave the client (audit PC-APEX-4).
            'charge_date'  => String.valueOf(row.Scheduled_Date__c),
            // GoCardless shows this to the payer.
            'description'  => (plan != null && plan > 1)
                ? 'XtraPension fee, payment ' + n + ' of ' + plan
                : 'XtraPension fee'
        };
        return doCallout(PATH_CHARGE_FEE, body);
    }

    /**
     * Refresh Fee_Plan_Next_Charge_Date__c on every touched Application: the
     * earliest still-pending installment date, or null when none remain.
     * Single aggregate SOQL + single partial-success update.
     */
    @TestVisible
    private static void advanceParentNextChargeDatesBulk(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return;
        AggregateResult[] rows = [
            SELECT Application__c app, MIN(Scheduled_Date__c) minDate
              FROM PC1_Fee_Installment__c
             WHERE Application__c IN :appIds
               AND Payment_Status__c = 'pending'
             GROUP BY Application__c
        ];
        Map<Id, Date> nextByApp = new Map<Id, Date>();
        for (AggregateResult r : rows) {
            nextByApp.put((Id) r.get('app'), (Date) r.get('minDate'));
        }
        List<PC1_Application__c> updates = new List<PC1_Application__c>();
        for (Id appId : appIds) {
            updates.add(new PC1_Application__c(
                Id = appId,
                Fee_Plan_Next_Charge_Date__c = nextByApp.get(appId) // null if no pending remain
            ));
        }
        if (updates.isEmpty()) return;
        // One application that cannot be saved (validation rule, row lock)
        // must not undo the others (audit 2026-11-11 PC-APEX-12).
        Database.SaveResult[] srs = Database.update(updates, false);
        for (Integer i = 0; i < srs.size(); i++) {
            if (!srs[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR,
                    'PC1_FeeInstallmentScheduler: next charge date not saved for ' + updates[i].Id + ' — ' + srs[i].getErrors());
            }
        }
    }

    // ---------- Do Not Contact: pause + resume ------------------------------
    /**
     * Do Not Contact (often a reported death) PAUSES fee collection. The
     * notice and charge queries already skip such an application; this step
     * makes the pause visible to ops and safe to undo:
     *   - an installment not yet created at GoCardless loses its notice stamp,
     *     so on resume it is re-dated if needed and noticed afresh: nothing is
     *     collected on a notice sent before the pause;
     *   - an installment already created at GoCardless WILL be collected
     *     unless ops cancels it; the sweep does not cancel it;
     *   - ONE PC1_Handoff__c per pause tells ops the fee is paused and lists
     *     any installment already at GoCardless;
     *   - when Do_Not_Contact__c is cleared, the pause handoff is closed with
     *     a note and the sweeps pick the rows up again as normal.
     * No callouts.
     */
    @TestVisible
    private static PauseResult pauseDoNotContact(Date today) {
        PauseResult res = new PauseResult();

        // 1. Resume: close the pause handoff of every application whose flag
        //    was cleared.
        List<PC1_Handoff__c> ended = new List<PC1_Handoff__c>();
        for (PC1_Handoff__c h : [
            SELECT Id, Reviewed_At__c, Next_Step_Suggestion__c
              FROM PC1_Handoff__c
             WHERE Last_Field_Id__c = :DNC_PAUSE_ACTIVE
               AND Application__r.Do_Not_Contact__c = false
             LIMIT 1000
        ]) {
            ended.add(new PC1_Handoff__c(
                Id                      = h.Id,
                Last_Field_Id__c        = DNC_PAUSE_ENDED,
                Resolved__c             = true,
                Reviewed_At__c          = h.Reviewed_At__c != null ? h.Reviewed_At__c : Datetime.now(),
                Next_Step_Suggestion__c = (DNC_RESUMED_MARK + ' Do Not Contact was cleared, so fee collection resumed on ' +
                    today.format() + '. Installments not yet set up at GoCardless get a fresh advance notice before they are collected.\n\n' +
                    (h.Next_Step_Suggestion__c == null ? '' : h.Next_Step_Suggestion__c)).left(2000)
            ));
        }

        // 2. Pause: pending rows of Do Not Contact applications.
        Map<Id, List<PC1_Fee_Installment__c>> byApp = new Map<Id, List<PC1_Fee_Installment__c>>();
        List<PC1_Fee_Installment__c> unnotice = new List<PC1_Fee_Installment__c>();
        for (PC1_Fee_Installment__c r : [
            SELECT Id, Application__c, Installment_Number__c, Amount__c, Scheduled_Date__c,
                   Charged_At__c, Payment_Id__c, Bacs_Notice_Sent__c, Payment_Status__c
              FROM PC1_Fee_Installment__c
             WHERE Payment_Status__c IN ('pending', 'submitted')
               AND Application__r.Do_Not_Contact__c = true
               AND Application__r.Stage__c NOT IN :HALT_STAGES
             ORDER BY Application__c, Installment_Number__c
             LIMIT 2000
        ]) {
            if (!byApp.containsKey(r.Application__c)) byApp.put(r.Application__c, new List<PC1_Fee_Installment__c>());
            byApp.get(r.Application__c).add(r);
            if (r.Payment_Status__c == 'pending' && r.Charged_At__c == null && r.Bacs_Notice_Sent__c == true) {
                unnotice.add(new PC1_Fee_Installment__c(
                    Id = r.Id, Bacs_Notice_Sent__c = false, Bacs_Notice_Sent_At__c = null));
            }
        }

        // 3. One handoff per pause: skip an application whose current pause
        //    already has one (open, or resolved by ops while still paused).
        List<PC1_Handoff__c> raised = new List<PC1_Handoff__c>();
        if (!byApp.isEmpty()) {
            Set<Id> already = new Set<Id>();
            for (PC1_Handoff__c h : [
                SELECT Application__c FROM PC1_Handoff__c
                 WHERE Application__c IN :byApp.keySet()
                   AND Last_Field_Id__c = :DNC_PAUSE_ACTIVE
            ]) {
                already.add(h.Application__c);
            }
            for (Id appId : byApp.keySet()) {
                if (already.contains(appId)) continue;
                PC1_Handoff__c h = alertHandoff(appId, DNC_PAUSE_REASON, pauseNote(byApp.get(appId)));
                h.Last_Field_Id__c = DNC_PAUSE_ACTIVE;
                raised.add(h);
            }
        }

        // Partial success throughout: one locked row must not undo the rest.
        if (!ended.isEmpty()) res.resumed = countOk(Database.update(ended, false), 'resume handoff');
        if (!unnotice.isEmpty()) res.unnoticed = countOk(Database.update(unnotice, false), 'notice void');
        if (!raised.isEmpty()) res.handoffs = insertHandoffs(raised);
        return res;
    }

    /** Ops-facing body of a pause handoff (Next_Step_Suggestion__c). */
    private static String pauseNote(List<PC1_Fee_Installment__c> rows) {
        List<String> atGc = new List<String>();
        for (PC1_Fee_Installment__c r : rows) {
            if (r.Payment_Status__c != 'submitted' && r.Charged_At__c == null) continue;
            atGc.add(' - installment ' + r.Installment_Number__c.intValue() + ', £' + r.Amount__c + ', due ' +
                (r.Scheduled_Date__c == null ? '(no date)' : r.Scheduled_Date__c.format()) +
                (String.isBlank(r.Payment_Id__c) ? '' : ' (GoCardless payment ' + r.Payment_Id__c + ')'));
        }
        String s = 'This client is marked Do Not Contact, so no fee installment will be noticed or collected. '
            + 'Nothing needs doing to keep it paused.\n\n';
        if (!atGc.isEmpty()) {
            s += 'ACTION NEEDED: these installments were already set up at GoCardless before the flag was set and WILL be '
                + 'collected unless you cancel them in the GoCardless dashboard before their date:\n'
                + String.join(atGc, '\n') + '\n\n';
        }
        s += 'If Do Not Contact was set by mistake, clear it: collection resumes on the next daily run and the client '
            + 'gets a fresh advance notice before each payment. If the client has died, check with your manager '
            + 'before taking any further step on the fee.';
        return s;
    }

    private static Integer countOk(Database.SaveResult[] srs, String what) {
        Integer ok = 0;
        for (Database.SaveResult sr : srs) {
            if (sr.isSuccess()) { ok++; continue; }
            System.debug(LoggingLevel.ERROR,
                'PC1_FeeInstallmentScheduler: ' + what + ' failed: ' + sr.getErrors());
        }
        return ok;
    }

    // ---------- advance notices ---------------------------------------------
    /** Result carrier of the notice step. */
    private class NoticeResult {
        Integer notices = 0;
        Integer errored = 0;
        List<String> errors = new List<String>();
    }

    /**
     * Returns {sent, errored} where sent = Applications dispatched. `onlyApps`
     * (nullable) restricts the run to those Applications:
     * PC1_GoCardlessController uses it to send the first notice the moment a
     * plan is scheduled or a held installment is retried. No callouts; ONE
     * PC1_MessageDispatcher job for the whole batch.
     */
    public static Integer[] sendAdvanceNotices(Date today, Set<Id> onlyApps) {
        NoticeResult nr = sendAdvanceNoticesInternal(today, onlyApps, null);
        return new Integer[]{ nr.notices, nr.errored };
    }

    private static NoticeResult sendAdvanceNoticesInternal(Date today, Set<Id> onlyApps, Set<Id> skipRows) {
        NoticeResult out = new NoticeResult();
        Date noticeDate = today.addDays(NOTICE_DAYS);
        Date horizon = today.addDays(NOTICE_HORIZON_DAYS);
        if (skipRows == null) skipRows = new Set<Id>();

        // 0. Void the notice of every noticed, not yet created row whose
        //    application can no longer be collected (stage moved, mandate
        //    parked or dead). The charge query skips such rows, but the stamp
        //    would survive: once the case is collectable again the row would
        //    be collected on a notice that named another date or mandate.
        //    Clearing it makes the walk below re-date and re-notice it first.
        List<PC1_Fee_Installment__c> voided = new List<PC1_Fee_Installment__c>();
        for (PC1_Fee_Installment__c r : [
            SELECT Id, Application__c
              FROM PC1_Fee_Installment__c
             WHERE Payment_Status__c = 'pending'
               AND Charged_At__c = null
               AND Bacs_Notice_Sent__c = true
               AND (Application__r.Stage__c NOT IN :COLLECTABLE_STAGES
                    OR Application__r.DD_Mandate_Status__c != 'active'
                    OR Application__r.DD_Mandate_Id__c = null)
             LIMIT 2000
        ]) {
            if (onlyApps != null && !onlyApps.contains(r.Application__c)) continue;
            voided.add(new PC1_Fee_Installment__c(Id = r.Id, Bacs_Notice_Sent__c = false, Bacs_Notice_Sent_At__c = null));
        }
        if (!voided.isEmpty()) {
            Database.SaveResult[] vrs = Database.update(voided, false);
            for (Integer i = 0; i < vrs.size(); i++) {
                if (!vrs[i].isSuccess()) {
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: notice void failed for ' + voided[i].Id + ' — ' + vrs[i].getErrors());
                }
            }
        }

        // 1. Applications with a row that needs a notice, a new date or a
        //    hold: an un-noticed, not yet created pending row dated within
        //    the horizon, or a noticed one whose date has passed before it
        //    was created. Only applications that may be collected.
        Set<Id> appIds = new Set<Id>();
        for (PC1_Fee_Installment__c r : [
            SELECT Application__c
              FROM PC1_Fee_Installment__c
             WHERE Payment_Status__c = 'pending'
               AND Charged_At__c = null
               AND Scheduled_Date__c <= :horizon
               AND (Bacs_Notice_Sent__c = false OR Scheduled_Date__c <= :today)
               AND Application__r.DD_Mandate_Status__c = 'active'
               AND Application__r.DD_Mandate_Id__c != null
               AND Application__r.Do_Not_Contact__c = false
               AND Application__r.Stage__c IN :COLLECTABLE_STAGES
             LIMIT 2000
        ]) {
            if (onlyApps != null && !onlyApps.contains(r.Application__c)) continue;
            appIds.add(r.Application__c);
        }
        if (appIds.isEmpty()) return out;

        // 2. Walk each Application's rows in installment order: move rows
        //    that would otherwise be noticed short, keeping a month between
        //    installments, and pick the rows whose notice goes out today.
        Map<Id, PC1_Fee_Installment__c> changes = new Map<Id, PC1_Fee_Installment__c>();
        List<PC1_Fee_Installment__c> toNotice = new List<PC1_Fee_Installment__c>();
        List<PC1_Fee_Installment__c> holds = new List<PC1_Fee_Installment__c>();
        List<PC1_Handoff__c> handoffs = new List<PC1_Handoff__c>();
        Set<Id> redatedApps = new Set<Id>();
        Id curApp = null;
        Date spacingFloor = null;
        for (PC1_Fee_Installment__c row : [
            SELECT Id, Application__c, Installment_Number__c, Scheduled_Date__c, Amount__c,
                   Payment_Status__c, Charged_At__c, Bacs_Notice_Sent__c
              FROM PC1_Fee_Installment__c
             WHERE Application__c IN :appIds
             ORDER BY Application__c, Installment_Number__c
        ]) {
            if (row.Application__c != curApp) { curApp = row.Application__c; spacingFloor = null; }
            Boolean movable = row.Payment_Status__c == 'pending' && row.Charged_At__c == null;
            if (movable && row.Bacs_Notice_Sent__c == true && row.Scheduled_Date__c != null
                    && row.Scheduled_Date__c <= today) {
                // The client was told this date and the payment could not be
                // created on any run since. Re-dating and re-noticing here
                // would loop for ever on a permanent refusal: hold it.
                holdRow(row, 'the payment could not be created at GoCardless on any day between the advance notice and ' +
                    row.Scheduled_Date__c.format(), holds, handoffs);
                redatedApps.add(row.Application__c);
                continue;                              // a held row does not hold the plan back
            }
            if (!movable) {
                // Created / submitted / paid rows keep their date; the next
                // installment stays a month after them.
                if (row.Scheduled_Date__c != null
                        && (row.Payment_Status__c == 'pending' || row.Payment_Status__c == 'submitted'
                            || row.Payment_Status__c == 'paid')) {
                    spacingFloor = maxDate(spacingFloor, row.Scheduled_Date__c.addMonths(1));
                }
                continue;
            }
            Date d = row.Scheduled_Date__c;
            Boolean noticed = row.Bacs_Notice_Sent__c == true;
            // A noticed row may sit inside the notice period (its payment is
            // created on the next run). An un-noticed row may not: it would
            // be noticed short.
            Date floor = maxDate(spacingFloor, noticed ? today.addDays(1) : noticeDate);
            if (d == null || d < floor) {
                Date nd = maxDate(noticeDate, spacingFloor);
                changes.put(row.Id, new PC1_Fee_Installment__c(
                    Id                     = row.Id,
                    Scheduled_Date__c      = nd,
                    Bacs_Notice_Sent__c    = false,
                    Bacs_Notice_Sent_At__c = null
                ));
                redatedApps.add(row.Application__c);
                d = nd;
                noticed = false;
            }
            if (!noticed && d <= horizon && !skipRows.contains(row.Id)) toNotice.add(row);
            spacingFloor = d.addMonths(1);
        }

        Set<Id> noticeApps = new Set<Id>();
        for (PC1_Fee_Installment__c row : toNotice) noticeApps.add(row.Application__c);

        if (!noticeApps.isEmpty()) {
            // dispatch() cannot tell us whether anything will go out: with no
            // active template its execute() returns at once and the rows would
            // still be stamped. Rows stay unstamped until a template is active.
            Integer activeTemplates = [
                SELECT COUNT()
                  FROM PC1_Message_Template__c
                 WHERE Active__c = true
                   AND Trigger_Event__c = :BACS_ADVANCE_TEMPLATE
                   AND Channel__c = 'Email'
            ];
            Boolean dispatched = false;
            if (activeTemplates == 0) {
                out.errored++;
                out.errors.add('No active ' + BACS_ADVANCE_TEMPLATE + ' email template: ' + toNotice.size() +
                    ' installment(s) due a notice were left un-noticed and will not be collected.');
                System.debug(LoggingLevel.ERROR,
                    'PC1_FeeInstallmentScheduler: no active ' + BACS_ADVANCE_TEMPLATE + ' template');
            } else if (!hasQueueCapacity()) {
                // The sweep runs in @future, where one Queueable may be
                // enqueued. Rows stay unstamped and are noticed by the next run.
                out.errored++;
                out.errors.add('No Queueable slot left for the advance notices of ' + noticeApps.size() + ' application(s); retried on the next run.');
            } else {
                try {
                    dispatchBacsAdvanceNoticeBulk(noticeApps);
                    dispatched = true;
                    out.notices = noticeApps.size();
                } catch (Exception e) {
                    out.errored++;
                    out.errors.add('Advance notice dispatch failed for ' + noticeApps.size() + ' application(s): ' + safe(e.getMessage()));
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: Bacs notice dispatch failed for ' +
                        noticeApps.size() + ' apps — ' + e.getMessage());
                }
            }
            if (dispatched) {
                Datetime nowStamp = Datetime.now();
                for (PC1_Fee_Installment__c row : toNotice) {
                    PC1_Fee_Installment__c up = changes.containsKey(row.Id)
                        ? changes.get(row.Id) : new PC1_Fee_Installment__c(Id = row.Id);
                    up.Bacs_Notice_Sent__c    = true;
                    up.Bacs_Notice_Sent_At__c = nowStamp;
                    changes.put(row.Id, up);
                }
            }
        }

        // Re-dates are persisted even when no notice could go out, so a row is
        // never left dated sooner than a notice could cover. Partial success:
        // one bad row cannot roll back the batch's stamps.
        for (PC1_Fee_Installment__c h : holds) changes.put(h.Id, h);
        if (!changes.isEmpty()) {
            List<PC1_Fee_Installment__c> changeList = changes.values();
            Database.SaveResult[] srs = Database.update(changeList, false);
            for (Integer i = 0; i < srs.size(); i++) {
                if (!srs[i].isSuccess()) {
                    out.errored++;
                    out.errors.add('Notice stamp / re-date failed for installment ' + changeList[i].Id + ': '
                        + safe(String.valueOf(srs[i].getErrors())));
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: notice/re-date stamp failed — ' + srs[i].getErrors());
                }
            }
        }
        insertHandoffs(handoffs);
        if (!redatedApps.isEmpty()) advanceParentNextChargeDatesBulk(redatedApps);
        return out;
    }

    // ---------- reconciliation ----------------------------------------------
    /**
     * R11-MED-5 — applications where every installment is paid but Stage is
     * not Closed - Paid. Two concurrent GoCardless webhooks for installments
     * #N-1 and #N can both see the other as 'submitted', so neither closes
     * the case and the Fee_Receipt never goes. Returns how many were closed.
     */
    private static Integer reconcilePaidPlans() {
        Integer reconciled = 0;
        // SOQL has no conditional aggregates, so two queries:
        //  (a) app ids with any recent installment activity
        //  (b) of those, app ids with a non-paid installment
        Datetime rec_cutoff = Datetime.now().addDays(-14);
        Set<Id> anyRecent = new Set<Id>();
        for (AggregateResult r : [
            SELECT Application__c app FROM PC1_Fee_Installment__c
             WHERE LastModifiedDate >= :rec_cutoff
             GROUP BY Application__c
        ]) {
            anyRecent.add((Id) r.get('app'));
        }
        Set<Id> hasUnpaid = new Set<Id>();
        if (!anyRecent.isEmpty()) {
            for (AggregateResult r : [
                SELECT Application__c app FROM PC1_Fee_Installment__c
                 WHERE Application__c IN :anyRecent
                   AND Payment_Status__c != 'paid'
                 GROUP BY Application__c
            ]) {
                hasUnpaid.add((Id) r.get('app'));
            }
        }
        Set<Id> allPaidApps = new Set<Id>(anyRecent);
        allPaidApps.removeAll(hasUnpaid);
        // Closing without queueing the receipt would lose it for good
        // (closed apps are not picked up again), so wait for a run with
        // a free Queueable slot.
        if (!allPaidApps.isEmpty() && !hasQueueCapacity()) {
            System.debug(LoggingLevel.WARN,
                'PC1_FeeInstallmentScheduler: reconciliation of ' + allPaidApps.size() +
                ' apps deferred to the next run (no Queueable slot left for the receipt).');
            allPaidApps.clear();
        }
        if (allPaidApps.isEmpty()) return reconciled;

        // Not Closed - Paid already, and not in a terminal failure state or
        // with a human (R12-MED: a disputing client must not get a receipt).
        List<PC1_Application__c> needsClose = [
            SELECT Id, Stage__c FROM PC1_Application__c
             WHERE Id IN :allPaidApps
               AND Stage__c NOT IN ('Closed - Paid', 'Closed - Refunded', 'DD Chargeback', 'Closed - Cancelled', 'Needs Human')
        ];
        if (needsClose.isEmpty()) return reconciled;
        List<PC1_Application__c> toUpdate = new List<PC1_Application__c>();
        for (PC1_Application__c a : needsClose) {
            toUpdate.add(new PC1_Application__c(
                Id = a.Id,
                Stage__c = 'Closed - Paid',
                Fee_Payment_Status__c = 'confirmed'
            ));
        }
        Database.SaveResult[] saveResults = Database.update(toUpdate, false);
        Set<Id> ok = new Set<Id>();
        Integer failedCount = 0;
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                ok.add(toUpdate[i].Id);
            } else {
                failedCount++;
                System.debug(LoggingLevel.ERROR,
                    'PC1_FeeInstallmentScheduler: reconciliation row ' +
                    toUpdate[i].Id + ' close-flip FAILED — ' + saveResults[i].getErrors());
            }
        }
        reconciled = ok.size();
        if (!ok.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'PC1_FeeInstallmentScheduler: reconciled ' + ok.size() +
                ' concurrent-final apps (failed=' + failedCount + '). Firing Fee_Receipt.');
            PC1_MessageDispatcher.dispatch(ok, 'Fee_Receipt');
        }
        return reconciled;
    }

    /** True while this transaction may still enqueue a Queueable. */
    @TestVisible private static Integer queueSlotsUsedOverride = null;
    private static Boolean hasQueueCapacity() {
        Integer used = queueSlotsUsedOverride != null ? queueSlotsUsedOverride : Limits.getQueueableJobs();
        return used < Limits.getLimitQueueableJobs();
    }

    // ---------- dispatch (bypassable in tests) -----------------------------
    @TestVisible
    private static Boolean testBypass = false;
    @TestVisible
    private static List<String> testDispatched = new List<String>();

    /** One dispatch for the whole set — the dispatcher enqueues a single job. */
    @TestVisible
    private static void dispatchBacsAdvanceNoticeBulk(Set<Id> appIds) {
        if (testBypass) {
            for (Id a : appIds) testDispatched.add(a + ':bulk');
            return;
        }
        // The dispatcher dedupes by (Template, Application) within 24h. The
        // sweep keeps a month between one app's installments, so one email
        // per app per sweep is the intended behaviour.
        PC1_MessageDispatcher.dispatch(appIds, BACS_ADVANCE_TEMPLATE);
    }

    // ---------- admin alert (audit 2026-11-11 PC-APEX-12) -------------------
    /** Summary of the alert last attempted (tests). */
    @TestVisible private static String lastAlert;

    private static void alertAdmin(String summary, List<String> errors) {
        lastAlert = summary;
        String to = null;
        try {
            PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
            if (cfg != null) {
                Object v = cfg.get('Admin_Alert_Email__c');
                if (v != null && String.isNotBlank(String.valueOf(v))) to = String.valueOf(v).trim();
            }
        } catch (Exception ignored) { /* field may not exist in every org */ }
        try {
            if (String.isBlank(to)) to = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
        } catch (Exception ignored) { /* no recipient */ }
        if (String.isBlank(to)) {
            System.debug(LoggingLevel.ERROR, 'PC1_FeeInstallmentScheduler: no alert recipient; errors NOT alerted: ' + summary);
            return;
        }
        List<String> lines = new List<String>();
        for (Integer i = 0; i < errors.size() && i < 25; i++) lines.add(' - ' + errors[i]);
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ to });
        msg.setSubject('PC1 fee sweep had errors: some installments were not noticed or collected');
        msg.setPlainTextBody(
            'The daily PC1 fee sweep (PC1_FeeInstallmentScheduler) finished with errors on '
            + Datetime.now().formatGmt('yyyy-MM-dd HH:mm') + ' UTC.\n\n'
            + summary + '\n\n'
            + String.join(lines, '\n') + '\n\n'
            + 'Rows that could not be created stay pending and are retried on the next daily run until their date; '
            + 'after that they are put on hold with a handoff. Check the Heroku app (pc1-autofill) is up and that '
            + 'PC1_Config__c.Internal_Admin_Token__c matches INTERNAL_ADMIN_TOKEN on Heroku.'
        );
        msg.setSaveAsActivity(false);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PC1_FeeInstallmentScheduler: alert sendEmail threw: ' + e.getMessage());
        }
    }

    // ---------- callout plumbing (mirrors PC1_GoCardlessController) ---
    /**
     * POSTs and returns the parsed JSON body. On a non-2xx response the body's
     * own keys are kept (error code, next_possible_charge_date…) with ok=false
     * and http_status, so the caller can act on a business refusal instead of
     * a bare HTTP code.
     */
    private static Map<String, Object> doCallout(String path, Map<String, Object> body) {
        String token = getInternalToken();
        if (String.isBlank(token)) {
            return new Map<String, Object>{ 'ok' => false, 'error' => 'PC1_Config__c.Internal_Admin_Token__c not set' };
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
            out.put('http_status', status);
            if (String.isBlank(str(parsed.get('error')))) out.put('error', 'HTTP ' + status);
            return out;
        }
        return parsed;
    }

    // ---------- tiny helpers -----------------------------------------
    @TestVisible
    private static String getInternalToken() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
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

    public class PC1FeeInstallmentException extends Exception {}
}