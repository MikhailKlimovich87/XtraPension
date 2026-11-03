/**
 * PC1_GoCardlessController — @AuraEnabled facade the pc1DirectDebit LWCs
 * call to drive the Direct Debit lifecycle for a PC1_Application__c:
 *
 *   1. createMandateForApplication  — POST /internal/gocardless/create-mandate
 *      after the sales agent has verified bank + read the DD terms.
 *   2. recordAward                  — sales agent captures the DWP award amount
 *      and advances Stage__c to 'Awarded' (fee formula recalcs on save).
 *   3. chargeFee                    — POST /internal/gocardless/charge-fee
 *      once the mandate is active + award recorded (20% of award, in pence).
 *      Since 2026-08-18 the fee can be split into up to 3 monthly installments
 *      via Fee_Plan_Installments__c — this method inserts PC1_Fee_Installment__c
 *      rows for the plan and immediately fires installment #1 (installments
 *      #2..N are scheduled + fired by PC1_FeeInstallmentScheduler).
 *   4. getDDStatus                  — cacheable read of every DD/fee field so
 *      the LWC can render the panel without a wire per field.
 *
 * The Heroku endpoints are idempotent on `sf_app_id`, so re-invoking any of
 * the two callouts with the same record returns the existing mandate/payment
 * and this Apex short-circuits before calling out when the local record
 * already carries an id.
 *
 * Callout endpoint + Bearer token come from PC1_Config__c.Internal_Admin_Token__c
 * (same pattern as PC1_BankLookup — keeps secrets out of Named Credentials
 * that Fernando's sandbox admin permset can't manage). Callouts are gated
 * by remote site setting PC1_Heroku_Autofill (already deployed).
 *
 * Failure handling: any HTTP or endpoint-side error is written to
 *   - DD_Mandate_Failure_Reason__c (persisted on the record so ops sees it)
 *   - a PC1_Stage_Log__c row with Actor__c='system' + Note__c=reason
 * then re-thrown as AuraHandledException so the LWC shows the toast.
 */
public with sharing class PC1_GoCardlessController {

    // Endpoint constants — same shape PC1_BankLookup uses; makes it trivial
    // to swap for a Named Credential later without touching the Aura contract.
    @TestVisible private static final String BASE_URL = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com';
    private static final String PATH_CREATE_MANDATE = '/internal/gocardless/create-mandate';
    private static final String PATH_CHARGE_FEE     = '/internal/gocardless/charge-fee';
    private static final String PATH_RETRY_PAYMENT  = '/internal/gocardless/retry-payment';
    // 90 s (was 20 s): create-mandate runs customer + bank + mandate at
    // GoCardless, then fetches the mandate PDF with retries (up to ~35 s)
    // and renders the welcome pack. At 20 s the rep saw "failed" while the
    // mandate was in fact being created (audit 2026-10-02). Apex allows
    // 120 s per callout.
    private static final Integer TIMEOUT_MS         = 90000;

    // Sanity ceiling for recordAward — DWP arrears cap sits well under this.
    // Anything higher is almost certainly a typo (pence vs pounds mix-up).
    private static final Decimal AWARD_MAX = 100000;

    // Statuses considered "verified" for the purposes of mandate creation.
    // Kept as a Set so we can broaden later without touching guard code.
    // Extended 2026-08-18 for the Data8 CoP-shaped return values so the
    // full happy path (Data8 up → 'Bank Confirmed') unlocks the DD agreement.
    // Must stay in sync with PC1_MandateEligibility.VERIFIED_STATUSES.
    private static final Set<String> BANK_VERIFIED_STATUSES = new Set<String>{
        'Modulus Passed', 'Bank Confirmed', 'Name Verified', 'Name Close Match'
    };

    // Mandate statuses after which a NEW mandate may be created for the app
    // (failed at the bank, cancelled — including parked after a bank change
    // — or expired). Must match FAILED_STATUSES in pc1DDStatusCard.
    @TestVisible private static final Set<String> REPLACEABLE_MANDATE_STATUSES = new Set<String>{
        'failed', 'cancelled', 'expired', 'consumed', 'blocked'
    };

    // Fields we always project when loading the record — keep in ONE spot so
    // the four public methods can't drift on selected columns.
    private static final String APP_FIELDS =
        'Id, First_Name__c, Last_Name__c, Email__c, ' +
        'Address_Line1__c, Address_Line2__c, City__c, Postcode__c, County__c, ' +
        'Bank_Account_Holder__c, Bank_Account_Number__c, Bank_Sort_Code__c, ' +
        'Bank_Verification_Status__c, DD_Terms_Read_By_Sales__c, ' +
        'DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c, ' +
        'DD_Mandate_Activated_At__c, DD_Mandate_Failure_Reason__c, ' +
        'Award_Amount__c, Fee_Amount__c, Fee_Payment_Id__c, ' +
        'Fee_Payment_Status__c, Fee_Charged_At__c, ' +
        'Fee_Plan_Installments__c, Fee_Plan_Installment_Amount__c, ' +
        'Fee_Plan_Next_Charge_Date__c, Fee_First_Charge_Date__c, ' +
        'DWP_Lump_Sum_Received__c, Stage__c';

    // Fee model constants — changed 2026-08-18 from 25% → 20% (Fernando).
    // Fee_Amount__c formula field on the object mirrors this; keep in sync.
    @TestVisible private static final Decimal FEE_RATE = 0.20;
    // Payment plan bounds — restricted by validation rule on
    // Fee_Plan_Installments__c. Anything outside this range gets clamped
    // (< 1 → 1 single charge; > MAX → MAX). Range widened 3 → 6 on
    // 2026-08-25 (Fernando) so val team can spread larger fees over a
    // longer horizon when the client's back-payment doesn't cover it.
    private static final Integer PLAN_MIN = 1;
    private static final Integer PLAN_MAX = 6;
    // Agent-chosen first-charge date is capped at +90 days from today.
    // Big enough for "next payday" scheduling; small enough that a mistyped
    // year (2027 typo when meaning 2026) fails loudly rather than silently
    // sitting in the scheduler queue for months.
    private static final Integer FIRST_CHARGE_MAX_DAYS_AHEAD = 90;

    // -----------------------------------------------------------------
    // Installments list + retry of a failed one (audit 2026-10-02: there
    // was no screen for installments and no way to collect a failed one —
    // the Task said "consider a retry" but nothing could perform it).
    // -----------------------------------------------------------------
    @AuraEnabled
    public static List<PC1_Fee_Installment__c> getInstallments(Id recordId) {
        if (recordId == null) return new List<PC1_Fee_Installment__c>();
        return [
            SELECT Id, Installment_Number__c, Amount__c, Scheduled_Date__c, Payment_Status__c,
                   Payment_Id__c, Charged_At__c, Bacs_Notice_Sent__c
              FROM PC1_Fee_Installment__c
             WHERE Application__c = :recordId
             ORDER BY Installment_Number__c ASC
        ];
    }

    /**
     * Ask GoCardless to re-present a FAILED installment. Same payment (no
     * second charge); GoCardless picks the next possible charge date and the
     * usual webhooks (submitted → confirmed / failed) update the row.
     */
    @AuraEnabled
    public static Map<String, Object> retryInstallment(Id installmentId) {
        if (installmentId == null) throw new AuraHandledException('installmentId is required');
        List<PC1_Fee_Installment__c> rows = [
            SELECT Id, Application__c, Application__r.Stage__c, Installment_Number__c, Payment_Id__c, Payment_Status__c
              FROM PC1_Fee_Installment__c WHERE Id = :installmentId LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Installment not found');
        PC1_Fee_Installment__c row = rows[0];
        if (row.Payment_Status__c != 'failed') {
            throw new AuraHandledException('Only a failed installment can be retried (this one is ' + row.Payment_Status__c + ').');
        }
        if (String.isBlank(row.Payment_Id__c)) {
            throw new AuraHandledException('This installment has no GoCardless payment to retry.');
        }
        Map<String, Object> resp = doCallout(PATH_RETRY_PAYMENT, new Map<String, Object>{
            'sf_app_id'  => String.valueOf(row.Application__c),
            'payment_id' => row.Payment_Id__c
        });
        if (!isTruthy(resp.get('ok'))) {
            String err = String.isNotBlank(str(resp.get('detail'))) ? str(resp.get('detail')) : str(resp.get('error'));
            throw new AuraHandledException('Retry refused by GoCardless: ' + (String.isBlank(err) ? 'unknown error' : err));
        }
        update new PC1_Fee_Installment__c(Id = row.Id, Payment_Status__c = 'submitted', Charged_At__c = Datetime.now());
        insert new PC1_Stage_Log__c(
            Application__c = row.Application__c, From_Stage__c = row.Application__r.Stage__c, To_Stage__c = row.Application__r.Stage__c,
            Actor__c = 'human', Changed_At__c = Datetime.now(), Changed_By__c = UserInfo.getUserId(),
            Note__c = ('Installment ' + row.Installment_Number__c + ' retried at GoCardless (payment ' + row.Payment_Id__c
                + ', charge date ' + str(resp.get('charge_date')) + ').').left(255));
        return new Map<String, Object>{
            'ok' => true, 'payment_id' => row.Payment_Id__c,
            'status' => str(resp.get('status')), 'charge_date' => str(resp.get('charge_date'))
        };
    }

    // -----------------------------------------------------------------
    // 1. createMandateForApplication
    // -----------------------------------------------------------------
    @AuraEnabled
    public static Map<String, Object> createMandateForApplication(Id recordId) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        PC1_Application__c app = loadApp(recordId);

        // Idempotent short-circuit — if we already have a usable mandate,
        // return it without a callout. A dead one (failed / cancelled /
        // expired) is replaced instead: until 2026-10-02 this returned the
        // dead mandate forever, so the "set up again" path did not exist.
        String replaces = null;
        if (String.isNotBlank(app.DD_Mandate_Id__c)
                && REPLACEABLE_MANDATE_STATUSES.contains(app.DD_Mandate_Status__c)) {
            replaces = app.DD_Mandate_Id__c;
        } else if (String.isNotBlank(app.DD_Mandate_Id__c)) {
            return new Map<String, Object>{
                'ok'         => true,
                'mandate_id' => app.DD_Mandate_Id__c,
                'status'     => app.DD_Mandate_Status__c,
                'existed'    => true
            };
        }

        // Pre-checks — order matches the UI flow so the message a rep sees
        // matches the step they still need to complete.
        if (!BANK_VERIFIED_STATUSES.contains(String.valueOf(app.Bank_Verification_Status__c))) {
            throw new AuraHandledException('Bank not verified');
        }
        if (app.DD_Terms_Read_By_Sales__c != true) {
            throw new AuraHandledException('DD terms not read');
        }
        if (String.isBlank(app.Bank_Account_Number__c) || String.isBlank(app.Bank_Sort_Code__c)) {
            throw new AuraHandledException('Bank account details missing');
        }
        String holder = String.isNotBlank(app.Bank_Account_Holder__c)
            ? app.Bank_Account_Holder__c
            : buildFullName(app);
        if (String.isBlank(holder)) throw new AuraHandledException('Account holder name missing');

        // Build the customer + bank_account payload the sibling Node endpoint
        // documented. Country is hardcoded 'GB' — the DD scheme is UK-only.
        Map<String, Object> customer = new Map<String, Object>{
            'given_name'    => nz(app.First_Name__c),
            'family_name'   => nz(app.Last_Name__c),
            'email'         => nz(app.Email__c),
            'address_line1' => nz(app.Address_Line1__c),
            'city'          => nz(app.City__c),
            'postal_code'   => nz(app.Postcode__c),
            'country_code'  => 'GB'
        };
        if (String.isNotBlank(app.Address_Line2__c)) customer.put('address_line2', app.Address_Line2__c);

        Map<String, Object> bank = new Map<String, Object>{
            'account_holder_name' => holder.trim(),
            'account_number'      => sanitiseAccount(app.Bank_Account_Number__c),
            'sort_code'           => sanitiseSort(app.Bank_Sort_Code__c)
        };
        Map<String, Object> body = new Map<String, Object>{
            'sf_app_id'    => String.valueOf(app.Id),
            'customer'     => customer,
            'bank_account' => bank
        };
        if (replaces != null) body.put('replaces_mandate_id', replaces);

        Map<String, Object> resp = doCallout(PATH_CREATE_MANDATE, body);
        if (isTruthy(resp.get('ok'))) {
            // Fernando's rule (2026-08-18): welcome-email trigger fires on
            // DD_Mandate_Id__c null→non-null transition. Only stamp
            // DD_Mandate_Id__c when the mandate PDF is confirmed live in SF
            // (Node's mandate_pdf.ok). Otherwise the trigger fires without
            // PC1_Mandate ContentVersion + dispatcher blocks the send + no
            // email lands. Node's watchdog cron will call this method again
            // on next tick — idempotent, retries the PDF fetch, and only
            // then does DD_Mandate_Id__c actually get stamped, so welcome
            // fires with the full 3-PDF payload.
            Map<String, Object> pdf = (Map<String, Object>) resp.get('mandate_pdf');
            Boolean pdfOk = pdf != null && isTruthy(pdf.get('ok'));
            PC1_Application__c patch = new PC1_Application__c(
                Id = app.Id,
                DD_Mandate_Status__c        = str(resp.get('status')),
                DD_Mandate_Created_At__c    = Datetime.now(),
                DD_Mandate_Failure_Reason__c = null
            );
            // A replacement always stamps the new id: the welcome email only
            // fires on the first mandate (null → id) and the PDF watchdog
            // only picks up apps with no mandate id, so holding it back
            // would leave the app pointing at the dead mandate.
            if (pdfOk || replaces != null) {
                patch.DD_Mandate_Id__c = str(resp.get('mandate_id'));
            }
            if (replaces != null) patch.DD_Mandate_Activated_At__c = null;
            update patch;
            if (replaces != null) {
                Map<String, Object> rep = resp.get('replaced') instanceof Map<String, Object>
                    ? (Map<String, Object>) resp.get('replaced') : null;
                Boolean oldCancelled = rep != null && isTruthy(rep.get('cancelled'));
                String oldNote = rep == null ? ''
                    : (oldCancelled ? ' Old mandate cancelled at GoCardless.'
                       : (rep.get('error') != null ? ' Old mandate NOT cancelled (' + str(rep.get('error')) + ') — cancel it in GoCardless.'
                          : ' Old mandate was already inactive.'));
                insert new PC1_Stage_Log__c(
                    Application__c = app.Id, From_Stage__c = app.Stage__c, To_Stage__c = app.Stage__c,
                    Actor__c = 'system', Changed_At__c = Datetime.now(), Changed_By__c = UserInfo.getUserId(),
                    Note__c = ('Direct Debit replaced: ' + replaces + ' → ' + str(resp.get('mandate_id')) + '.' + oldNote).left(255));
            }
            return new Map<String, Object>{
                'ok'          => true,
                'mandate_id'  => str(resp.get('mandate_id')),
                'status'      => patch.DD_Mandate_Status__c,
                'pdf_pending' => !pdfOk && replaces == null,
                'existed'     => false,
                'replaced'    => replaces
            };
        }
        String err = String.isNotBlank(str(resp.get('error')))
            ? str(resp.get('error'))
            : 'Unknown error';
        recordFailure(app.Id, 'Mandate create failed: ' + err);
        throw new AuraHandledException('Mandate create failed: ' + err);
    }

    // -----------------------------------------------------------------
    // 2. recordAward
    // -----------------------------------------------------------------
    // Apex @AuraEnabled forbids overloading, so `installments`, `lumpSum` and
    // `firstChargeDate` are nullable parameters — legacy callers (pre-2026-08-18)
    // pass null and get defaults: installments=1 (single charge), lumpSum
    // untouched, firstChargeDate=today (fired on next Charge Fee click). The
    // LWC pc1AwardRecorder always sends all four explicitly.
    //
    // `lumpSum` (2026-08-18): the initial DWP back-payment. Persisted to
    // DWP_Lump_Sum_Received__c and used by the LWC to *recommend* a plan
    // (lump>=fee → single, lump<fee → 3 monthly), but the val team makes
    // the final call via the manual override toggle. The server does NOT
    // recompute `installments` from lumpSum — it trusts the LWC's chosen
    // plan value and just persists what it was told.
    //
    // `firstChargeDate` (2026-08-25): agent-chosen date for installment #1.
    // If null, defaults to today at chargeFee time (matches legacy behaviour
    // where #1 fires immediately). Range: today..today+90 (see
    // FIRST_CHARGE_MAX_DAYS_AHEAD). Installments #2..N are computed as
    // firstChargeDate.addMonths(k-1) — SF Apex's Date.addMonths handles
    // month-end snap (Jan 31 → Feb 28, Mar 31 → Apr 30) automatically.
    @AuraEnabled
    public static Map<String, Object> recordAward(Id recordId, Decimal amount, Integer installments, Decimal lumpSum, Date firstChargeDate) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        if (amount == null || amount <= 0)
            throw new AuraHandledException('Award amount must be greater than zero');
        if (amount >= AWARD_MAX)
            throw new AuraHandledException('Award amount unrealistically large (>' + AWARD_MAX + ')');
        if (lumpSum != null && lumpSum < 0)
            throw new AuraHandledException('DWP lump sum received cannot be negative');
        if (lumpSum != null && lumpSum >= AWARD_MAX)
            throw new AuraHandledException('DWP lump sum received unrealistically large (>' + AWARD_MAX + ')');
        if (firstChargeDate != null) {
            Date today = Date.today();
            if (firstChargeDate < today) {
                throw new AuraHandledException('First charge date cannot be in the past');
            }
            if (firstChargeDate > today.addDays(FIRST_CHARGE_MAX_DAYS_AHEAD)) {
                throw new AuraHandledException('First charge date must be within ' + FIRST_CHARGE_MAX_DAYS_AHEAD + ' days from today');
            }
        }

        Integer plan = normalisePlan(installments);

        PC1_Application__c app = loadApp(recordId);

        // Once collection has started, the award, plan and first date are
        // frozen. The installment rows carry their own amounts, so changing
        // the award afterwards updated the card (new fee) while the scheduler
        // kept collecting the old amounts: a £10,000 → £8,000 correction after
        // installment 1 overcharged the client £400 (audit 2026-10-02 C7).
        // Re-saving the same values and updating the lump sum stay allowed.
        Boolean feeStarted = String.isNotBlank(app.Fee_Payment_Id__c)
            || [SELECT COUNT() FROM PC1_Fee_Installment__c WHERE Application__c = :recordId] > 0;
        if (feeStarted) {
            Decimal currentPlan = app.Fee_Plan_Installments__c == null ? 1 : app.Fee_Plan_Installments__c;
            Boolean changesMoney = app.Award_Amount__c != amount
                || currentPlan != plan
                || (firstChargeDate != null && firstChargeDate != app.Fee_First_Charge_Date__c);
            if (changesMoney) {
                throw new AuraHandledException(
                    'The fee for this award is already being collected by Direct Debit, so the award amount, '
                    + 'plan and first charge date can no longer be changed here. Cancel the remaining payments '
                    + 'in GoCardless and their installment records first, then record the corrected award.');
            }
        }

        app.Award_Amount__c = amount;
        app.Fee_Plan_Installments__c = plan;
        // Only overwrite lump sum when caller sent a value; null preserves any
        // previously recorded amount so re-saves of the same award don't wipe
        // the lump-sum context the val team already captured.
        if (lumpSum != null) {
            app.DWP_Lump_Sum_Received__c = lumpSum;
        }
        // Same principle for first-charge date: null preserves existing value
        // (val team re-saves the award without touching the date). An explicit
        // value overwrites — including reverting to today by picking today.
        if (firstChargeDate != null) {
            app.Fee_First_Charge_Date__c = firstChargeDate;
        }
        // Only advance if we're not already at/past this milestone — keep the
        // stage-log tidy on re-saves of the same amount.
        if (app.Stage__c != 'Awarded' && app.Stage__c != 'Fee Charged' && app.Stage__c != 'Closed - Paid') {
            app.Stage__c = 'Awarded';
        }
        update app;

        // Re-select for the recalculated formula (Fee_Amount__c +
        // Fee_Plan_Installment_Amount__c) — formulas aren't materialised on
        // the in-memory record after the update.
        PC1_Application__c after = Database.query(
            'SELECT Award_Amount__c, Fee_Amount__c, Fee_Plan_Installments__c, ' +
            'Fee_Plan_Installment_Amount__c, Fee_First_Charge_Date__c, ' +
            'DWP_Lump_Sum_Received__c, Stage__c ' +
            'FROM PC1_Application__c WHERE Id = :recordId LIMIT 1');
        return new Map<String, Object>{
            'ok'                        => true,
            'award_amount'              => after.Award_Amount__c,
            'fee_amount'                => after.Fee_Amount__c,
            'installments'              => after.Fee_Plan_Installments__c,
            'installment_amount'        => after.Fee_Plan_Installment_Amount__c,
            'first_charge_date'         => after.Fee_First_Charge_Date__c,
            'lump_sum_received'         => after.DWP_Lump_Sum_Received__c,
            'stage'                     => after.Stage__c
        };
    }

    /**
     * Clamp installments to the restricted range 1..PLAN_MAX (widened 3→6 on
     * 2026-08-25). Anything outside is treated as 1 (single charge) below
     * PLAN_MIN, or PLAN_MAX above — matches the Fee_Plan_Installments__c
     * validation rule on the object (Fee_Plan_Installments_In_Range).
     */
    @TestVisible
    private static Integer normalisePlan(Integer n) {
        if (n == null) return 1;
        if (n < PLAN_MIN) return 1;
        if (n > PLAN_MAX) return PLAN_MAX;
        return n;
    }

    // -----------------------------------------------------------------
    // 3. chargeFee
    //
    // First-click behaviour (Fernando's 2026-08-25 plan model):
    //   1. Snapshot the plan (Fee_Plan_Installments__c, defaults to 1) and
    //      the anchor date (Fee_First_Charge_Date__c, defaults to today).
    //   2. Insert N PC1_Fee_Installment__c rows (row #1 on the anchor date,
    //      row #k on anchor.addMonths(k-1) — SF Date arithmetic snaps
    //      month-end automatically so Jan 31 → Feb 28, Mar 31 → Apr 30).
    //      Final row absorbs the sub-penny rounding remainder so the sum of
    //      amounts equals Fee_Amount__c exactly.
    //   3. If the anchor date is TODAY (or earlier), fire installment #1
    //      immediately via /internal/gocardless/charge-fee with
    //      charge_stage='installment_1'. Otherwise leave #1 pending — the
    //      daily PC1_FeeInstallmentScheduler will pick it up on its
    //      Scheduled_Date__c.
    //   4. Mirror the fired installment's GC payment id / status onto the
    //      parent PC1_Application__c so the pre-existing single-charge fields
    //      keep working (backward compat + admin reports). When #1 is
    //      deferred, the mirror stays null until the scheduler fires.
    //   5. Stamp Fee_Plan_Next_Charge_Date__c with installment #2's date
    //      when #1 fires immediately; with installment #1's date when it
    //      is deferred; null for plan=1 fired-immediately.
    //
    // Subsequent installments are fired by PC1_FeeInstallmentScheduler; that
    // scheduler calls this same Node endpoint with charge_stage='installment_N'
    // for its own per-installment idempotency.
    //
    // Re-clicking Charge Fee on an app that already has installments:
    //   - Returns the current status without side effects (idempotent).
    //   - Val team can use the installment table (surfaced via the LWC) to
    //     see remaining charges + due dates.
    // -----------------------------------------------------------------
    @AuraEnabled
    public static Map<String, Object> chargeFee(Id recordId) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        PC1_Application__c app = loadApp(recordId);

        if (String.isNotBlank(app.Fee_Payment_Id__c)) {
            return new Map<String, Object>{
                'ok'         => true,
                'payment_id' => app.Fee_Payment_Id__c,
                'status'     => app.Fee_Payment_Status__c,
                'charge_date' => app.Fee_Charged_At__c,
                'existed'    => true
            };
        }
        if (app.DD_Mandate_Status__c != 'active') {
            throw new AuraHandledException('Mandate not active yet');
        }
        if (app.Award_Amount__c == null || app.Award_Amount__c <= 0) {
            throw new AuraHandledException('Award not recorded');
        }

        // 20% of the award, rounded to pence. Reproduce the Fee_Amount__c
        // formula deliberately so we don't have to round-trip the record
        // after recordAward for the callout. Rate changed 25% → 20% on
        // 2026-08-18 (Fernando).
        Decimal feePounds = (app.Award_Amount__c * FEE_RATE).setScale(2, System.RoundingMode.HALF_UP);
        Integer plan = normalisePlan((Integer) app.Fee_Plan_Installments__c);
        Date anchor = app.Fee_First_Charge_Date__c != null ? app.Fee_First_Charge_Date__c : Date.today();

        // Audit R9-CRIT#1 fix: DML-before-callout meant the fireNow path
        // (anchor <= today, the default) threw 'uncommitted work pending'
        // 100% of the time at Http.send — doCallout swallowed it into
        // ok=false, chargeFee threw AuraHandledException, and the entire
        // transaction (installments included) rolled back. Val team's
        // "Charge Fee (today)" was broken permanently; only the deferred
        // path (future anchor) actually shipped a GC payment.
        //
        // Refactored to: build in memory → in the fireNow branch, do
        // callout FIRST, then delete-stale + insert + Fee_Payment_Id__c
        // stamp in a single DML block on success. Deferred branch keeps
        // the old ordering because it has no callout.
        List<PC1_Fee_Installment__c> installments = buildInstallmentRows(app.Id, feePounds, plan, anchor);
        PC1_Fee_Installment__c first = installments[0];
        Boolean fireNow = anchor <= Date.today();

        if (!fireNow) {
            // Defer — scheduler will fire on Scheduled_Date__c. Safe to do
            // DML-only here: no callout in this branch.
            List<PC1_Fee_Installment__c> stale = [
                SELECT Id FROM PC1_Fee_Installment__c
                WHERE Application__c = :app.Id AND Payment_Id__c = null
            ];
            if (!stale.isEmpty()) delete stale;
            insert installments;
            PC1_Application__c patch = new PC1_Application__c(
                Id                          = app.Id,
                Fee_Plan_Next_Charge_Date__c = first.Scheduled_Date__c
            );
            update patch;
            return new Map<String, Object>{
                'ok'                => true,
                'deferred'          => true,
                'first_charge_date' => first.Scheduled_Date__c,
                'amount_pounds'     => first.Amount__c,
                'installments'      => plan,
                'installment_amount'=> first.Amount__c,
                'next_charge_date'  => first.Scheduled_Date__c
            };
        }

        // Fire installment #1 immediately. CALLOUT BEFORE DML.
        String firstStage = 'installment_1';
        Long firstAmountPence = (first.Amount__c * 100).longValue();
        Map<String, Object> body = new Map<String, Object>{
            'sf_app_id'    => String.valueOf(app.Id),
            'amount_pence' => firstAmountPence,
            'currency'     => 'GBP',
            'charge_stage' => firstStage,
            'description'  => 'XtraPension PC1 success fee — installment 1 of ' + plan +
                              ' (20% of £' + app.Award_Amount__c + ')'
        };
        Map<String, Object> resp = doCallout(PATH_CHARGE_FEE, body);
        if (isTruthy(resp.get('ok'))) {
            Date chargeDate = parseDate(resp.get('charge_date'));
            String gcPaymentId = str(resp.get('payment_id'));
            String gcStatus    = str(resp.get('status'));

            // DML block — only reached on callout success, so no uncommitted-
            // work exception can be triggered upstream.
            List<PC1_Fee_Installment__c> stale = [
                SELECT Id FROM PC1_Fee_Installment__c
                WHERE Application__c = :app.Id AND Payment_Id__c = null
            ];
            if (!stale.isEmpty()) delete stale;

            first.Payment_Id__c     = gcPaymentId;
            first.Payment_Status__c = 'submitted';
            first.Charged_At__c     = Datetime.now();
            insert installments;

            // Mirror installment #1 GC details onto the parent for backward
            // compat with the pre-plan single-charge flow.
            Date nextChargeDate = plan > 1 ? installments[1].Scheduled_Date__c : null;
            PC1_Application__c patch = new PC1_Application__c(
                Id                          = app.Id,
                Fee_Payment_Id__c           = gcPaymentId,
                Fee_Payment_Status__c       = gcStatus,
                Fee_Charged_At__c           = Datetime.now(),
                Fee_Plan_Next_Charge_Date__c = nextChargeDate
            );
            if (app.Stage__c == 'Awarded' || app.Stage__c == null) {
                patch.Stage__c = 'Fee Charged';
            }
            update patch;
            return new Map<String, Object>{
                'ok'                => true,
                'payment_id'        => patch.Fee_Payment_Id__c,
                'status'            => patch.Fee_Payment_Status__c,
                'charge_date'       => chargeDate,
                'first_charge_date' => first.Scheduled_Date__c,
                'amount_pounds'     => first.Amount__c,
                'installments'      => plan,
                'installment_amount'=> first.Amount__c,
                'next_charge_date'  => nextChargeDate
            };
        }
        // Callout failed pre-DML — no orphans to clean up. Log + throw.
        String err = String.isNotBlank(str(resp.get('error'))) ? str(resp.get('error')) : 'Unknown error';
        recordFailure(app.Id, 'Fee charge failed: ' + err);
        throw new AuraHandledException('Fee charge failed: ' + err);
    }

    /**
     * Build the list of PC1_Fee_Installment__c rows for a plan.
     * Dates: row #1 = anchor, row #k = anchor.addMonths(k-1). SF Apex
     *        Date.addMonths handles the month-end snap automatically
     *        (Jan 31 + 1 month → Feb 28/29, Mar 31 + 1 → Apr 30).
     * Amounts: rows 1..N-1 = ROUND(fee/N, 2); final row absorbs remainder so
     *          the sum equals feePounds exactly (e.g. £800/3 → £266.67 x2 +
     *          £266.66 = £800.00).
     */
    @TestVisible
    private static List<PC1_Fee_Installment__c> buildInstallmentRows(Id appId, Decimal feePounds, Integer plan, Date anchor) {
        List<PC1_Fee_Installment__c> out = new List<PC1_Fee_Installment__c>();
        Decimal per = (feePounds / plan).setScale(2, System.RoundingMode.HALF_UP);
        Decimal remainder = feePounds - (per * (plan - 1));  // final row
        for (Integer i = 1; i <= plan; i++) {
            Decimal amt = (i == plan) ? remainder : per;
            out.add(new PC1_Fee_Installment__c(
                Application__c      = appId,
                Installment_Number__c = i,
                Scheduled_Date__c   = anchor.addMonths(i - 1),
                Amount__c           = amt,
                Payment_Status__c   = 'pending'
            ));
        }
        return out;
    }

    // -----------------------------------------------------------------
    // 4. getDDStatus
    // -----------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDDStatus(Id recordId) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        PC1_Application__c app = loadApp(recordId);
        return new Map<String, Object>{
            'id'                        => app.Id,
            'bank_verification_status'  => app.Bank_Verification_Status__c,
            'bank_verified'             => BANK_VERIFIED_STATUSES.contains(String.valueOf(app.Bank_Verification_Status__c)),
            'dd_terms_read'             => app.DD_Terms_Read_By_Sales__c == true,
            'mandate_id'                => app.DD_Mandate_Id__c,
            'mandate_status'            => app.DD_Mandate_Status__c,
            'mandate_created_at'        => app.DD_Mandate_Created_At__c,
            'mandate_activated_at'      => app.DD_Mandate_Activated_At__c,
            'mandate_failure_reason'    => app.DD_Mandate_Failure_Reason__c,
            'award_amount'              => app.Award_Amount__c,
            'fee_amount'                => app.Fee_Amount__c,
            'fee_plan_installments'     => app.Fee_Plan_Installments__c,
            'fee_plan_installment_amount' => app.Fee_Plan_Installment_Amount__c,
            'fee_plan_next_charge_date' => app.Fee_Plan_Next_Charge_Date__c,
            'fee_first_charge_date'     => app.Fee_First_Charge_Date__c,
            'fee_payment_id'            => app.Fee_Payment_Id__c,
            'fee_payment_status'        => app.Fee_Payment_Status__c,
            'fee_charged_at'            => app.Fee_Charged_At__c,
            'stage'                     => app.Stage__c
        };
    }

    // -----------------------------------------------------------------
    // Internals
    // -----------------------------------------------------------------
    private static PC1_Application__c loadApp(Id recordId) {
        List<PC1_Application__c> apps = Database.query(
            'SELECT ' + APP_FIELDS + ' FROM PC1_Application__c WHERE Id = :recordId LIMIT 1'
        );
        if (apps.isEmpty()) throw new AuraHandledException('Application not found');
        return apps[0];
    }

    /**
     * Callout with Bearer auth. Isolated so the four public methods share
     * exact same auth + parse behaviour. Returns the parsed JSON as
     * Map<String,Object> even on HTTP failures, populating an 'error' key
     * so callers only branch on truthiness of 'ok'.
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
            return new Map<String, Object>{
                'ok'    => false,
                'error' => 'Non-JSON response (HTTP ' + status + '): ' + safe(rawBody)
            };
        }
        if (status < 200 || status >= 300) {
            String err = String.isNotBlank(str(parsed.get('error')))
                ? str(parsed.get('error'))
                : 'HTTP ' + status;
            return new Map<String, Object>{ 'ok' => false, 'error' => err };
        }
        return parsed;
    }

    /**
     * Persist a failure trail:
     *   - DD_Mandate_Failure_Reason__c (visible on the record page)
     *   - PC1_Stage_Log__c with Actor__c='system' + Note__c=reason
     * Deliberately swallowing DML exceptions here so the primary failure
     * error surfaces to the LWC uncoloured. The Stage_Log write is best-effort.
     */
    private static void recordFailure(Id appId, String reason) {
        try {
            PC1_Application__c patch = new PC1_Application__c(
                Id = appId,
                DD_Mandate_Failure_Reason__c = safe(reason)
            );
            update patch;
        } catch (Exception ignored) { /* best-effort */ }
        try {
            insert new PC1_Stage_Log__c(
                Application__c = appId,
                Actor__c       = 'system',
                Changed_At__c  = Datetime.now(),
                Changed_By__c  = UserInfo.getUserId(),
                Note__c        = safe(reason)
            );
        } catch (Exception ignored) { /* best-effort */ }
    }

    // -----------------------------------------------------------------
    // Config + tiny helpers
    // -----------------------------------------------------------------
    @TestVisible
    private static String getInternalToken() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Internal_Admin_Token__c))
            ? cfg.Internal_Admin_Token__c.trim() : null;
    }
    private static String buildFullName(PC1_Application__c a) {
        String f = a.First_Name__c == null ? '' : a.First_Name__c.trim();
        String l = a.Last_Name__c  == null ? '' : a.Last_Name__c.trim();
        String full = (f + ' ' + l).trim();
        return full.length() == 0 ? null : full;
    }
    private static String sanitiseSort(String s) {
        return s == null ? '' : s.replaceAll('[- ]', '');
    }
    private static String sanitiseAccount(String s) {
        return s == null ? '' : s.trim();
    }
    private static Boolean isTruthy(Object o) {
        return o == true || 'true'.equalsIgnoreCase(String.valueOf(o));
    }
    private static String str(Object o) {
        return o == null ? '' : String.valueOf(o);
    }
    private static String nz(String s) { return s == null ? '' : s; }
    private static String safe(String s) {
        if (s == null) return '';
        return s.length() > 255 ? s.substring(0, 255) : s;
    }
    private static Date parseDate(Object v) {
        if (v == null) return null;
        try {
            String s = String.valueOf(v);
            if (s.length() >= 10) return Date.valueOf(s.substring(0, 10));
        } catch (Exception e) { /* fall through */ }
        return null;
    }
}