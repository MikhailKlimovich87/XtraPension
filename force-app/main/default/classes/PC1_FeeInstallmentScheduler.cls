/**
 * PC1_FeeInstallmentScheduler — Schedulable that walks the PC1_Fee_Installment__c
 * table daily and fires two things:
 *
 *   1. DUE INSTALLMENTS — every PC1_Fee_Installment__c where
 *      Scheduled_Date__c <= TODAY() AND Payment_Status__c = 'pending' is
 *      POSTed to Heroku's /internal/gocardless/charge-fee with
 *      charge_stage='installment_<n>' for per-installment idempotency.
 *      On success, the row's Payment_Id__c / Payment_Status__c / Charged_At__c
 *      fields are stamped, and Fee_Plan_Next_Charge_Date__c on the parent
 *      PC1_Application__c is advanced to the NEXT pending installment (or
 *      cleared to null when this was the final installment).
 *
 *   2. ADVANCE-NOTICE EMAILS — every PC1_Fee_Installment__c where
 *      Scheduled_Date__c is exactly 5 CALENDAR days from today AND
 *      Payment_Status__c = 'pending' triggers a dispatch of the
 *      `Bacs_Advance_Notice` template (MSG-0008) on the parent Application.
 *      The dispatcher's own 24h dedup guard prevents duplicate sends if the
 *      scheduler ever runs twice on the same UK day.
 *
 *      Notice window changed 3 working days → 5 calendar days on 2026-08-25
 *      (Fernando). Calendar days give a more predictable buffer for the
 *      client (a Friday charge still notices on Sunday, not the previous
 *      Tuesday) and remove the working-day drift that made the reminder
 *      land unpredictably around bank holidays.
 *
 * Cron: `0 0 8 * * ?` (daily 08:00 UTC — no DST gate needed; Bacs treats
 * anything submitted before ~14:00 UTC as same-day, so 08:00 gives us
 * plenty of runway. Registered via `scripts/schedule-fee-installments.cjs`
 * on deploy.)
 *
 * Idempotency:
 *   - Node side: /internal/gocardless/charge-fee dedupes on (sf_app_id,
 *     charge_stage). A repeat run for the same installment returns the
 *     existing PM id + 200 OK.
 *   - Apex side: we only touch rows still in Payment_Status__c='pending'.
 *     Once submitted, a row is skipped on the next sweep even if the callout
 *     redundantly returned an existing id.
 *
 * Failure handling:
 *   - Per-installment try/catch — one bad callout doesn't stop the sweep.
 *   - Failed installments stay in Payment_Status__c='pending' so the next
 *     day's sweep retries automatically. If GC returns a 4xx that isn't
 *     retryable, the webhook handler (payments.failed) will flip the row
 *     to 'failed' when the GC event lands.
 *
 * Added 2026-08-18 with the payment plan feature (up to 3 monthly installments).
 * See docs/pc1-workflow-manual.md §3.0.
 */
public with sharing class PC1_FeeInstallmentScheduler implements Schedulable {

    // ---------- endpoint config (mirrors PC1_GoCardlessController) ----------
    @TestVisible private static final String BASE_URL = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com';
    private static final String PATH_CHARGE_FEE = '/internal/gocardless/charge-fee';
    private static final Integer TIMEOUT_MS = 20000;

    // Template dispatched 3 working days before the scheduled charge.
    @TestVisible private static final String BACS_ADVANCE_TEMPLATE = 'Bacs_Advance_Notice';
    // Template dispatched on each non-final installment payment confirmation.
    // Owned by the webhook handler (payments.confirmed) — declared here for
    // reference so docs stay accurate.
    @TestVisible private static final String INSTALLMENT_RECEIPT_TEMPLATE = 'Fee_Receipt_Installment';

    // ---------- Schedulable entrypoint --------------------------------------
    // Audit R6 C2 fix: Schedulable context CANNOT make HTTP callouts.
    // run() does Http.send() for /internal/gocardless/charge-fee — before
    // this wrapper the CalloutException fired every scheduled day was
    // swallowed by the per-row try/catch, so installments never actually
    // charged in prod. @future(callout=true) hops to a new transaction
    // that CAN do callouts. Tests still call run(today) directly with
    // Test.setMock so this doesn't affect coverage.
    public void execute(SchedulableContext ctx) {
        runAsync(Date.today());
    }

    @future(callout=true)
    public static void runAsync(Date today) {
        run(today);
    }

    /**
     * Extracted for the test harness so we can pass a specific `today` value.
     * Returns a summary line (also written to debug log) for observability.
     */
    @TestVisible
    public static String run(Date today) {
        Integer fired = 0;
        Integer errored = 0;
        Integer notices = 0;

        // ---------- 1. Fire due installments -----------------------------
        // LIMIT 100 matches Apex synchronous callout cap. Backlogs > 100
        // roll over to the next daily sweep — safer than blowing the
        // callout limit mid-loop and losing later rows to LimitException
        // silently swallowed by the per-row try/catch.
        List<PC1_Fee_Installment__c> due = [
            SELECT Id, Application__c, Installment_Number__c, Amount__c,
                   Scheduled_Date__c, Payment_Status__c
              FROM PC1_Fee_Installment__c
             WHERE Scheduled_Date__c <= :today
               AND Payment_Status__c = 'pending'
             ORDER BY Application__c, Installment_Number__c
             LIMIT 100
        ];
        // Group by parent so we can update Fee_Plan_Next_Charge_Date__c once
        // per Application in a single DML.
        Map<Id, List<PC1_Fee_Installment__c>> byApp = new Map<Id, List<PC1_Fee_Installment__c>>();
        for (PC1_Fee_Installment__c row : due) {
            if (!byApp.containsKey(row.Application__c)) {
                byApp.put(row.Application__c, new List<PC1_Fee_Installment__c>());
            }
            byApp.get(row.Application__c).add(row);
        }
        // Two-phase to avoid 'uncommitted work pending' CalloutException on
        // the 2nd+ installment of the sweep (audit C5). Old code did
        // callout→DML per row inside the loop; Apex forbids callout after DML
        // in the same transaction, so only the first row succeeded and the
        // rest were silently swallowed by the per-row try/catch.
        //
        // Phase A — all HTTP callouts, collect results, NO DML.
        List<InstallmentFireResult> results = new List<InstallmentFireResult>();
        for (Id appId : byApp.keySet()) {
            for (PC1_Fee_Installment__c row : byApp.get(appId)) {
                InstallmentFireResult r = new InstallmentFireResult();
                r.rowId = row.Id;
                r.appId = appId;
                try {
                    Map<String, Object> resp = calloutForInstallment(appId, row);
                    if (!isTruthy(resp.get('ok'))) {
                        r.success = false;
                        r.error = String.isNotBlank(str(resp.get('error')))
                            ? str(resp.get('error')) : 'Unknown error';
                    } else {
                        r.success = true;
                        r.paymentId = str(resp.get('payment_id'));
                    }
                } catch (Exception e) {
                    r.success = false;
                    r.error = e.getMessage();
                }
                results.add(r);
            }
        }
        // Phase B — all DMLs at once.
        Datetime nowTs = Datetime.now();
        List<PC1_Fee_Installment__c> updates = new List<PC1_Fee_Installment__c>();
        Set<Id> touchedApps = new Set<Id>();
        for (InstallmentFireResult r : results) {
            touchedApps.add(r.appId);
            if (r.success) {
                updates.add(new PC1_Fee_Installment__c(
                    Id                = r.rowId,
                    Payment_Id__c     = r.paymentId,
                    Payment_Status__c = 'submitted',
                    Charged_At__c     = nowTs
                ));
                fired++;
            } else {
                errored++;
                System.debug(LoggingLevel.ERROR,
                    'PC1_FeeInstallmentScheduler: fire failed for ' +
                    r.rowId + ' — ' + r.error);
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
        // Bulkified — was per-app SOQL+DML (100 apps = SOQL limit blowup).
        // Single aggregate SOQL + single bulk update covers any batch size.
        if (!touchedApps.isEmpty()) {
            advanceParentNextChargeDatesBulk(touchedApps);
        }

        // ---------- 2. Advance-notice emails (T-5 calendar days) ---------
        // Changed 3 working → 5 calendar days on 2026-08-25 (Fernando).
        // Audit R10-HIGH-1 fix: R9-MED#18's T+3..T+7 range meant each
        // installment sat in the window for 5 consecutive daily runs.
        // Dispatcher's 24h dedup only suppresses when the prior Sent row
        // is >= now-24h; daily cron drift of even ~1 min meant the prior
        // send fell just outside the window and MSG-0008 re-fired.
        // Clients received the same money-collection notice 2-5 times.
        //
        // R14-HIGH-2 fix — reconciliation window bug. Prior code compared
        // Sent log's Sent_At__c >= now-48h AGAINST the stamp's
        // Bacs_Notice_Sent_At__c <= now-48h — both windows measured from
        // now, so a HEALTHY send stamped+logged 48h+ ago satisfied both
        // conditions (log aged out of lookback while stamp aged into
        // staleness) → unstamp → re-send → duplicate money-collection
        // notice on the normal path (R10-HIGH-1 client-facing bug back).
        // Fix: compare log against the stamp, per-row. Also branch on
        // near-Scheduled_Date to avoid unstamp-and-forget of failed-send
        // rows too close to charge (dispatch immediately or Handoff).
        // Apps whose notice failed and are too close to the charge to wait —
        // re-sent below in the SAME dispatch as the regular notices.
        Set<Id> urgentBacsApps = new Set<Id>();
        try {
            Datetime staleCutoff = Datetime.now().addHours(-48);
            Date urgentCutoff = today.addDays(3); // rows below this need immediate re-send, not unstamp
            Set<Id> bacsTplIds = new Set<Id>();
            for (PC1_Message_Template__c t : [
                SELECT Id FROM PC1_Message_Template__c
                 WHERE Active__c = true AND Trigger_Event__c = 'Bacs_Advance_Notice'
            ]) {
                bacsTplIds.add(t.Id);
            }
            // Stamped installments still due AND stamp is old enough that
            // a legit send would have logged by now.
            List<PC1_Fee_Installment__c> stamped = [
                SELECT Id, Application__c, Bacs_Notice_Sent_At__c, Scheduled_Date__c
                  FROM PC1_Fee_Installment__c
                 WHERE Bacs_Notice_Sent__c = true
                   AND Bacs_Notice_Sent_At__c <= :staleCutoff
                   AND Payment_Status__c = 'pending'
                   AND Scheduled_Date__c >= :today
                 LIMIT 500
            ];
            if (!stamped.isEmpty() && !bacsTplIds.isEmpty()) {
                Set<Id> apps = new Set<Id>();
                for (PC1_Fee_Installment__c i : stamped) apps.add(i.Application__c);
                // Per-app: most recent Sent log's Sent_At__c. Compared to
                // the row's own stamp — not to `now` — so healthy sends
                // (log AT stamp time) pass regardless of age.
                Map<Id, Datetime> lastSentByApp = new Map<Id, Datetime>();
                for (PC1_Message_Send_Log__c l : [
                    SELECT Application__c, Sent_At__c FROM PC1_Message_Send_Log__c
                     WHERE Template__c IN :bacsTplIds
                       AND Application__c IN :apps
                       AND Status__c = 'Sent'
                       AND Sent_At__c != null
                     ORDER BY Sent_At__c DESC
                ]) {
                    if (!lastSentByApp.containsKey(l.Application__c)) {
                        lastSentByApp.put(l.Application__c, l.Sent_At__c);
                    }
                }
                List<PC1_Fee_Installment__c> unstampUpdates = new List<PC1_Fee_Installment__c>();
                Set<Id> urgentReDispatch = new Set<Id>();
                for (PC1_Fee_Installment__c i : stamped) {
                    Datetime lastSent = lastSentByApp.get(i.Application__c);
                    // Healthy: log timestamp >= stamp timestamp. Any log
                    // AT OR AFTER the stamp proves the send landed.
                    Boolean healthy = lastSent != null && lastSent >= i.Bacs_Notice_Sent_At__c;
                    if (healthy) continue;
                    // Not healthy — enqueue-succeeded but send failed.
                    if (i.Scheduled_Date__c < urgentCutoff) {
                        // Too close to charge to unstamp-and-wait-for-next-cron
                        // (would exit the T+3..T+7 window). Immediate re-dispatch
                        // this cron under the same app-set.
                        urgentReDispatch.add(i.Application__c);
                    } else {
                        unstampUpdates.add(new PC1_Fee_Installment__c(
                            Id = i.Id,
                            Bacs_Notice_Sent__c = false,
                            Bacs_Notice_Sent_At__c = null
                        ));
                    }
                }
                if (!unstampUpdates.isEmpty()) {
                    Database.SaveResult[] rs = Database.update(unstampUpdates, false);
                    Integer unstamped = 0;
                    for (Database.SaveResult r : rs) if (r.isSuccess()) unstamped++;
                    if (unstamped > 0) {
                        System.debug(LoggingLevel.WARN,
                            'PC1_FeeInstallmentScheduler: reconciliation UNSTAMPED ' +
                            unstamped + ' Bacs_Notice_Sent rows (stamp AT OR AFTER ' +
                            'most recent Sent log — enqueue succeeded, send did NOT).');
                    }
                }
                urgentBacsApps.addAll(urgentReDispatch);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_FeeInstallmentScheduler: Bacs reconciliation sweep failed — ' + e.getMessage());
        }

        // R11-arch: per-installment Bacs_Notice_Sent__c stamp replaces
        // the R9/R10/R11 time-windowed dedup chain (exact T+5 →
        // T+3..T+7 → T+5..T+6 + 47h pre-filter). Now: query a WIDE
        // T+3..T+7 window filtered by Bacs_Notice_Sent__c=false. Any
        // installment we haven't stamped yet is a candidate. Absorbs
        // up to 4 consecutive missed cron runs, guarantees exactly-once
        // regardless of log insert timing, and no arithmetic race
        // remains. Stamped in-transaction after dispatch below.
        Date noticeWindowStart = today.addDays(3);
        Date noticeWindowEnd   = today.addDays(7);
        List<PC1_Fee_Installment__c> soon = [
            SELECT Id, Application__c, Installment_Number__c
              FROM PC1_Fee_Installment__c
             WHERE Scheduled_Date__c >= :noticeWindowStart
               AND Scheduled_Date__c <= :noticeWindowEnd
               AND Payment_Status__c = 'pending'
               AND Bacs_Notice_Sent__c = false
             ORDER BY Scheduled_Date__c, Id
             LIMIT 2000
        ];
        // Bulkified: was one enqueueJob per row → cap 50 async blows silently
        // at row 51. Dispatcher's bulk signature enqueues ONE job for the whole
        // Set<Id> and dedupes by (Template, Application) internally.
        Set<Id> noticeApps = new Set<Id>();
        List<Id> installmentIdsToStamp = new List<Id>();
        for (PC1_Fee_Installment__c row : soon) {
            if (row.Application__c != null) {
                noticeApps.add(row.Application__c);
                installmentIdsToStamp.add(row.Id);
            }
        }
        // R11-arch: 47h PC1_Message_Send_Log__c pre-filter (R11-HIGH-3)
        // is REMOVED — replaced by the per-row Bacs_Notice_Sent__c query
        // filter above. That's authoritative dedup: unstamped rows in
        // window = not yet noticed. No log-timing race, no window
        // arithmetic. Dispatcher's own 24h template dedup remains as
        // last-line belt-and-braces against a stamp-write failure.
        // ONE dispatch for regular + urgent notices. This sweep runs in
        // @future, where only one Queueable may be enqueued; three separate
        // dispatches (urgent, regular, receipts) threw an uncatchable
        // LimitException that rolled back the whole run — after GoCardless
        // payments had been created (audit 2026-10-02).
        Set<Id> bacsApps = new Set<Id>(noticeApps);
        bacsApps.addAll(urgentBacsApps);
        if (!bacsApps.isEmpty()) {
            Boolean dispatchOk = false;
            if (hasQueueCapacity()) {
                try {
                    dispatchBacsAdvanceNoticeBulk(bacsApps);
                    notices += bacsApps.size();
                    dispatchOk = true;
                } catch (Exception e) {
                    errored++;
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: Bacs notice bulk failed for ' +
                        bacsApps.size() + ' apps — ' + e.getMessage());
                }
            }
            if (!dispatchOk && !urgentBacsApps.isEmpty()) {
                // A client due to be charged within 3 days with no confirmed
                // notice: open a Handoff so a human sends it or delays the charge.
                raiseBacsHandoffs(urgentBacsApps);
            }
            // Stamp Bacs_Notice_Sent__c ONLY if dispatch succeeded. On
            // dispatch failure, next cron cycle re-picks unstamped rows +
            // retries. Bulk update with partial-success so one bad row
            // (FLS drift etc.) doesn't erase the whole batch's dedup.
            if (dispatchOk && !installmentIdsToStamp.isEmpty()) {
                List<PC1_Fee_Installment__c> stampUpdates = new List<PC1_Fee_Installment__c>();
                Datetime nowStamp = Datetime.now();
                for (Id iid : installmentIdsToStamp) {
                    stampUpdates.add(new PC1_Fee_Installment__c(
                        Id = iid,
                        Bacs_Notice_Sent__c = true,
                        Bacs_Notice_Sent_At__c = nowStamp
                    ));
                }
                try {
                    Database.SaveResult[] stampResults = Database.update(stampUpdates, false);
                    Integer stampFailed = 0;
                    for (Integer i = 0; i < stampResults.size(); i++) {
                        if (!stampResults[i].isSuccess()) {
                            stampFailed++;
                            String errs = '';
                            for (Database.Error err : stampResults[i].getErrors()) {
                                errs += err.getStatusCode() + ':' + err.getMessage() + '; ';
                            }
                            System.debug(LoggingLevel.ERROR,
                                'PC1_FeeInstallmentScheduler: Bacs_Notice_Sent stamp FAILED for ' +
                                stampUpdates[i].Id + ' — ' + errs +
                                ' (next cron will re-send: acceptable double-send, dispatcher 24h dedup catches most)');
                        }
                    }
                    if (stampFailed > 0) {
                        System.debug(LoggingLevel.WARN,
                            'PC1_FeeInstallmentScheduler: ' + stampFailed + ' of ' +
                            stampUpdates.size() + ' Bacs_Notice_Sent stamps failed');
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR,
                        'PC1_FeeInstallmentScheduler: Bacs_Notice_Sent bulk-stamp threw — ' +
                        e.getMessage() + ' (dispatcher 24h dedup will absorb any doubles)');
                }
            }
        }

        // R11-MED-5 reconciliation sweep — detect apps where every
        // installment is paid but Stage != Closed - Paid. Two concurrent
        // GC POSTs for installments #N-1 and #N can both see the other
        // as 'submitted' → both isFinal=false → both 200 → Stage never
        // flips + Fee_Receipt never sends. This sweep catches the drift
        // and fires the missing side effects idempotently.
        Integer reconciled = 0;
        try {
            // Apps that have paid installments but haven't been closed.
            // Constrain to recently-modified so we don't scan historical
            // Closed-Refunded / Closed-Cancelled apps forever. SOQL
            // doesn't support conditional aggregates so we do 2 queries:
            //  (a) distinct app ids with any recent installment activity
            //  (b) distinct app ids with a non-paid installment
            // apps in (a) but NOT in (b) have all installments paid.
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
            if (!allPaidApps.isEmpty()) {
                // Filter to Stage != Closed - Paid AND not in a terminal
                // failure state (chargeback/refunded) which shouldn't be
                // flipped back.
                // R12-MED — exclude 'Needs Human'. An app with a dispute/
                // complaint/safeguarding Handoff whose installments all paid
                // must NOT auto-close (would fire receipt at a disputing
                // client + vanish from Needs Human queue).
                List<PC1_Application__c> needsClose = [
                    SELECT Id, Stage__c FROM PC1_Application__c
                     WHERE Id IN :allPaidApps
                       AND Stage__c NOT IN ('Closed - Paid', 'Closed - Refunded', 'DD Chargeback', 'Closed - Cancelled', 'Needs Human')
                ];
                if (!needsClose.isEmpty()) {
                    List<PC1_Application__c> toUpdate = new List<PC1_Application__c>();
                    for (PC1_Application__c a : needsClose) {
                        toUpdate.add(new PC1_Application__c(
                            Id = a.Id,
                            Stage__c = 'Closed - Paid',
                            Fee_Payment_Status__c = 'confirmed'
                        ));
                    }
                    try {
                        Database.SaveResult[] saveResults = Database.update(toUpdate, false);
                        Set<Id> ok = new Set<Id>();
                        Integer failedCount = 0;
                        for (Integer i = 0; i < saveResults.size(); i++) {
                            if (saveResults[i].isSuccess()) {
                                ok.add(toUpdate[i].Id);
                            } else {
                                failedCount++;
                                String errs = '';
                                for (Database.Error err : saveResults[i].getErrors()) {
                                    errs += err.getStatusCode() + ':' + err.getMessage() + '; ';
                                }
                                // R12-MED — was previously silent on failure.
                                System.debug(LoggingLevel.ERROR,
                                    'PC1_FeeInstallmentScheduler: reconciliation row ' +
                                    toUpdate[i].Id + ' close-flip FAILED — ' + errs);
                            }
                        }
                        reconciled = ok.size();
                        if (!ok.isEmpty()) {
                            System.debug(LoggingLevel.WARN,
                                'PC1_FeeInstallmentScheduler: reconciled ' + ok.size() +
                                ' concurrent-final apps (failed=' + failedCount + '). Firing Fee_Receipt.');
                            PC1_MessageDispatcher.dispatch(ok, 'Fee_Receipt');
                        }
                    } catch (Exception e) {
                        System.debug(LoggingLevel.ERROR,
                            'PC1_FeeInstallmentScheduler: reconciliation DML failed — ' + e.getMessage());
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_FeeInstallmentScheduler: reconciliation sweep failed — ' + e.getMessage());
        }

        String summary = 'PC1_FeeInstallmentScheduler: fired=' + fired +
            ' notices=' + notices + ' reconciled=' + reconciled + ' errored=' + errored +
            ' (due=' + due.size() + ', notice-candidates=' + soon.size() + ')';
        System.debug(LoggingLevel.INFO, summary);
        return summary;
    }

    /** True while this transaction may still enqueue a Queueable. */
    @TestVisible private static Integer queueSlotsUsedOverride = null;
    private static Boolean hasQueueCapacity() {
        Integer used = queueSlotsUsedOverride != null ? queueSlotsUsedOverride : Limits.getQueueableJobs();
        return used < Limits.getLimitQueueableJobs();
    }

    private static void raiseBacsHandoffs(Set<Id> appIds) {
        List<PC1_Handoff__c> handoffs = new List<PC1_Handoff__c>();
        for (Id appId : appIds) {
            handoffs.add(new PC1_Handoff__c(
                CurrencyIsoCode = 'GBP',
                Application__c = appId,
                Escalation_Type__c = 'other',
                Reason__c = ('BACS advance-notice re-dispatch FAILED — client due to be charged within 3 days without notice. Manual send required.').left(255),
                Next_Step_Suggestion__c = ('Send MSG-0008 manually or delay the fee installment charge until notice is confirmed delivered.').left(255),
                Resolved__c = false
            ));
        }
        try { Database.insert(handoffs, false); }
        catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_FeeInstallmentScheduler: Handoff DML for BACS failures also failed — ' + e.getMessage());
        }
    }

    /** Result carrier for two-phase installment fire (audit C5). */
    @TestVisible
    private class InstallmentFireResult {
        public Id rowId;
        public Id appId;
        public Boolean success = false;
        public String paymentId;
        public String error;
    }

    // ---------- callout-only helper (no DML) — Phase A of two-phase fire.
    @TestVisible
    private static Map<String, Object> calloutForInstallment(Id appId, PC1_Fee_Installment__c row) {
        Integer n = (Integer) row.Installment_Number__c;
        String stage = 'installment_' + n;
        Long amountPence = (row.Amount__c * 100).longValue();
        Map<String, Object> body = new Map<String, Object>{
            'sf_app_id'    => String.valueOf(appId),
            'amount_pence' => amountPence,
            'currency'     => 'GBP',
            'charge_stage' => stage,
            'description'  => 'XtraPension PC1 success fee — installment ' + n
        };
        return doCallout(PATH_CHARGE_FEE, body);
    }

    // Legacy shim — kept as @TestVisible for existing test coverage. Now
    // delegates to the two-phase helpers so behaviour matches prod. Never
    // call this inside a loop; the sweep uses the two-phase path directly.
    @TestVisible
    private static void fireInstallment(Id appId, PC1_Fee_Installment__c row) {
        Map<String, Object> resp = calloutForInstallment(appId, row);
        if (!isTruthy(resp.get('ok'))) {
            String err = String.isNotBlank(str(resp.get('error')))
                ? str(resp.get('error')) : 'Unknown error';
            throw new PC1FeeInstallmentException('installment ' + row.Installment_Number__c + ' callout failed: ' + err);
        }
        update new PC1_Fee_Installment__c(
            Id                = row.Id,
            Payment_Id__c     = str(resp.get('payment_id')),
            Payment_Status__c = 'submitted',
            Charged_At__c     = Datetime.now()
        );
    }

    /**
     * After firing due installments for an Application, recompute the next
     * pending installment's Scheduled_Date__c and stamp it on the parent
     * (or clear to null when none remain).
     */
    @TestVisible
    private static void advanceParentNextChargeDate(Id appId, Date today) {
        // Kept for tests + external callers. Prefer the bulk variant in
        // sweeps.
        advanceParentNextChargeDatesBulk(new Set<Id>{ appId });
    }

    /**
     * Bulk variant: single aggregate SOQL + single bulk update. Governor-safe
     * regardless of how many apps were touched by the sweep (was blowing up
     * at 100 distinct apps under the old per-app SOQL+DML pattern).
     */
    @TestVisible
    private static void advanceParentNextChargeDatesBulk(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return;
        // Earliest pending scheduled date per Application.
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
        if (!updates.isEmpty()) update updates;
    }

    /**
     * Delegates to PC1_MessageDispatcher for the Bacs Advance Notice template.
     * Wrapped so tests can bypass without needing the dispatcher stubbed.
     */
    @TestVisible
    private static Boolean testBypass = false;
    @TestVisible
    private static List<String> testDispatched = new List<String>();

    @TestVisible
    private static void dispatchBacsAdvanceNotice(Id appId, Integer installmentNumber) {
        if (testBypass) {
            testDispatched.add(appId + ':' + installmentNumber);
            return;
        }
        // Dispatcher owns the 24h dedup guard on (Template, Application) so
        // a re-run of the sweep on the same day won't duplicate the email.
        PC1_MessageDispatcher.dispatch(appId, BACS_ADVANCE_TEMPLATE);
    }

    /** Bulk variant — one enqueue for the whole set (audit round-3 H2). */
    @TestVisible
    private static void dispatchBacsAdvanceNoticeBulk(Set<Id> appIds) {
        if (testBypass) {
            for (Id a : appIds) testDispatched.add(a + ':bulk');
            return;
        }
        PC1_MessageDispatcher.dispatch(appIds, BACS_ADVANCE_TEMPLATE);
    }

    // Working-day arithmetic removed 2026-08-25 — notice window is now 5
    // calendar days (see the ADVANCE-NOTICE EMAILS block above), computed
    // inline with Date.addDays(5). The old addWorkingDays helper was the
    // only caller; its unit tests were folded into PC1_FeeInstallmentSchedulerTest
    // as calendar-day checks.

    // ---------- callout plumbing (mirrors PC1_GoCardlessController) ---
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
            return new Map<String, Object>{
                'ok'    => false,
                'error' => 'Non-JSON response (HTTP ' + status + '): ' + safe(rawBody)
            };
        }
        if (status < 200 || status >= 300) {
            String err = String.isNotBlank(str(parsed.get('error')))
                ? str(parsed.get('error')) : 'HTTP ' + status;
            return new Map<String, Object>{ 'ok' => false, 'error' => err };
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

    public class PC1FeeInstallmentException extends Exception {}
}