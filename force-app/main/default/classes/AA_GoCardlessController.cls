/**
 * AA_GoCardlessController — @AuraEnabled facade the aaDirectDebit LWCs
 * call to drive the Direct Debit lifecycle for a AA_Application__c:
 *
 *   1. createMandateForApplication  — POST /internal/gocardless/create-mandate
 *      after the sales agent has verified bank + read the DD terms.
 *   1b. recreateMandateForApplication — the same, from the card's confirmed
 *      "Create a new Direct Debit" (client agreed again); the only path that
 *      may replace a dead mandate that never reached DD_Mandate_Id__c.
 *   2. recordAward                  — sales agent captures the DWP award amount
 *      and advances Stage__c to 'Awarded' (fee formula recalcs on save).
 *   3. chargeFee                    — schedules the fee once the mandate is
 *      active + award recorded (20% of award). Since 2026-08-18 the fee can be
 *      split into up to 3 monthly installments via Fee_Plan_Installments__c —
 *      this method inserts the AA_Fee_Installment__c rows, sends the 5-day
 *      advance notice for instalment #1 when it is due today, and queues the
 *      GoCardless payment (charge_date = the noticed date). Nothing is ever
 *      collected sooner than NOTICE_DAYS from now (audit 2026-10-02 F101).
 *   3b. retryInstallment / getFeeInstallments — re-collect a failed or
 *      cancelled instalment with a fresh notice, and list the plan for the
 *      Fee Charge card (audit 2026-10-02 F110).
 *   4. getDDStatus                  — cacheable read of every DD/fee field so
 *      the LWC can render the panel without a wire per field.
 *
 * The Heroku endpoints are idempotent on `sf_app_id`, so re-invoking any of
 * the two callouts with the same record returns the existing mandate/payment
 * and this Apex short-circuits before calling out when the local record
 * already carries an id.
 *
 * Callout endpoint + Bearer token come from AA_Config__c.Internal_Admin_Token__c
 * (same pattern as AA_BankLookup — keeps secrets out of Named Credentials
 * that Fernando's sandbox admin permset can't manage). Callouts are gated
 * by remote site setting AA_Heroku_Autofill (already deployed).
 *
 * Failure handling: any HTTP or endpoint-side error is written to
 *   - DD_Mandate_Failure_Reason__c (persisted on the record so ops sees it)
 *   - a AA_Stage_Log__c row with Actor__c='system' + Note__c=reason
 * then re-thrown as AuraHandledException so the LWC shows the toast.
 */
public with sharing class AA_GoCardlessController {

    // Endpoint constants — same shape AA_BankLookup uses; makes it trivial
    // to swap for a Named Credential later without touching the Aura contract.
    @TestVisible private static final String BASE_URL = 'https://aa-autofill-14d501200453.herokuapp.com';
    private static final String PATH_CREATE_MANDATE = '/internal/gocardless/create-mandate';
    private static final String PATH_CHARGE_FEE     = '/internal/gocardless/charge-fee';
    // audit #13: create-mandate on the Node side runs the mandate-PDF upload +
    // welcome-pack render inline before responding; its retry backoff alone sums to
    // ~25s. A 20s Apex timeout made a slow-but-SUCCESSFUL create surface to the rep
    // as a false 'Endpoint unreachable'. 60s covers the worst case (Apex hard max is
    // 120s).
    private static final Integer TIMEOUT_MS         = 60000;

    // Sanity ceiling for recordAward — DWP arrears cap sits well under this.
    // Anything higher is almost certainly a typo (pence vs pounds mix-up).
    private static final Decimal AWARD_MAX = 100000;

    // audit 2026-10-02 F111: Award_Amount__c is the ANNUAL award = weekly rate
    // x 52, so a real value sits in one of two narrow bands (2026/27: lower
    // £76.70 x 52 = £3,988.40, higher £114.60 x 52 = £5,959.20). A weekly
    // (114.60) or 4-weekly/monthly figure typed from the DWP letter passed every
    // old check and under-charged the fee five- to fifty-fold. Outside this
    // band the save needs an explicit confirmation from the operator. MIN sits
    // below 52 x the lower rate even at older rates; MAX leaves ~25% headroom
    // over the higher rate for future April upratings. Update when the rates
    // move past it.
    @TestVisible private static final Decimal AWARD_BAND_MIN = 3500;
    @TestVisible private static final Decimal AWARD_BAND_MAX = 7200;

    // Statuses considered "verified" for the purposes of mandate creation.
    // Kept as a Set so we can broaden later without touching guard code.
    // Extended 2026-08-18 for the Data8 CoP-shaped return values so the
    // full happy path (Data8 up → 'Bank Confirmed') unlocks the DD agreement.
    // Must stay in sync with AA_MandateEligibility.VERIFIED_STATUSES.
    private static final Set<String> BANK_VERIFIED_STATUSES = new Set<String>{
        'Modulus Passed', 'Bank Confirmed', 'Name Verified', 'Name Close Match'
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
        'DWP_Lump_Sum_Received__c, Stage__c, Do_Not_Contact__c';

    // Fee model constants — changed 2026-08-18 from 25% → 20% (Fernando).
    // Fee_Amount__c formula field on the object mirrors this; keep in sync.
    @TestVisible private static final Decimal FEE_RATE = 0.20;
    // Payment plan bounds — restricted by validation rule on
    // Fee_Plan_Installments__c. Anything outside this range gets clamped
    // (< 1 → 1 single charge; > MAX → MAX). AA is capped at THREE
    // instalments (Fernando, 2026-09-09): PC1's 3 → 6 widening was cloned in
    // but never adopted for AA, and the Heroku charge-fee endpoint only
    // accepts charge_stage installment_1..3 — a plan of 4+ would build rows
    // the scheduler can never charge (400 bad_charge_stage on every sweep).
    // Keep in sync with Fee_Plan_Installments_In_Range (AA_Application__c),
    // Installment_Number_In_Range (AA_Fee_Installment__c) and ALLOWED_STAGES
    // in src/webhooks/gocardless-internal.js.
    private static final Integer PLAN_MIN = 1;
    private static final Integer PLAN_MAX = 3;
    // Agent-chosen first-charge date is capped at +90 days from today.
    // Big enough for "next payday" scheduling; small enough that a mistyped
    // year (2027 typo when meaning 2026) fails loudly rather than silently
    // sitting in the scheduler queue for months.
    private static final Integer FIRST_CHARGE_MAX_DAYS_AHEAD = 90;

    // Wave-3 W3-2: shown when a new mandate would replace a dead one without
    // the client's fresh agreement on record.
    @TestVisible private static final String DEAD_NEEDS_AGREEMENT_MSG =
        'The client\'s previous Direct Debit was cancelled or failed, so a new one needs their fresh agreement. ' +
        'Read them the Direct Debit terms again and use "Create a new Direct Debit" on the Direct Debit card. ' +
        'If the card does not offer it, refresh the page or ask the tech team.';

    private static final String MANDATE_DOC_PENDING_MSG =
        'The Direct Debit document has not reached the record yet, so no fee can be collected. ' +
        'Click "Retry mandate document" on the Direct Debit card first.';

    // GoCardless mandate statuses no payment can be taken on. A create /
    // re-create that comes back with one of these returned an OLD mandate
    // (replayed idempotency key), not a new one (wave-2 W2/W4).
    @TestVisible private static final Set<String> DEAD_MANDATE_STATUSES = new Set<String>{
        'failed', 'cancelled', 'expired', 'consumed', 'blocked', 'suspended_by_payer'
    };

    // -----------------------------------------------------------------
    // 1. createMandateForApplication
    // -----------------------------------------------------------------
    @AuraEnabled
    public static Map<String, Object> createMandateForApplication(Id recordId) {
        return createMandate(recordId, false);
    }

    /**
     * "Create a new Direct Debit" on the Direct Debit card. The card only calls
     * this after the rep confirmed (LightningConfirm) that the client agreed,
     * on this call, to a new Direct Debit (wave-3 W3-2). Same flow as
     * createMandateForApplication, plus that consent, which is what allows a
     * new mandate over a dead one that never reached DD_Mandate_Id__c.
     */
    @AuraEnabled
    public static Map<String, Object> recreateMandateForApplication(Id recordId) {
        return createMandate(recordId, true);
    }

    private static Map<String, Object> createMandate(Id recordId, Boolean clientReconfirmed) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        AA_Application__c app = loadApp(recordId);

        // Idempotent short-circuit — if we already have a LIVE mandate, return
        // it without a callout. A dead mandate (failed/cancelled/expired) must
        // NOT short-circuit: the rep is expected to correct the bank digits and
        // click Create Direct Debit again, and the Node lib fingerprints the
        // idempotency key on those digits so corrected details mint a fresh
        // mandate (audit #19). With UNCHANGED digits (a payer who cancelled and
        // then agreed again, an expired mandate) the old mandate id is sent as
        // replaces_mandate_id so the keys still differ (wave-2 W2).
        Boolean wasRecreate = false;
        if (String.isNotBlank(app.DD_Mandate_Id__c)) {
            String mstat = app.DD_Mandate_Status__c == null
                ? '' : app.DD_Mandate_Status__c.toLowerCase();
            Boolean deadMandate = mstat == 'failed' || mstat == 'cancelled' || mstat == 'expired';
            if (!deadMandate) {
                return new Map<String, Object>{
                    'ok'         => true,
                    'mandate_id' => app.DD_Mandate_Id__c,
                    'status'     => app.DD_Mandate_Status__c,
                    'existed'    => true
                };
            }
            // else fall through to recreate with (possibly corrected) bank details.
            wasRecreate = true;
        }
        // Wave-3 W3-2: a dead status with NO mandate id = the payer cancelled
        // (or the bank failed) the mandate while its PDF was still pending, so
        // the dead id never reached the record. Nothing tells GoCardless which
        // mandate is being replaced, and the plain "Create Direct Debit" button
        // and the auto-create Queueable carry no fresh client agreement. Only
        // the card's confirmed "Create a new Direct Debit" may go on.
        Boolean deadWithoutId = String.isBlank(app.DD_Mandate_Id__c)
            && DEAD_MANDATE_STATUSES.contains(app.DD_Mandate_Status__c == null ? '' : app.DD_Mandate_Status__c.toLowerCase());
        if (deadWithoutId && clientReconfirmed != true) {
            throw new AuraHandledException(DEAD_NEEDS_AGREEMENT_MSG);
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
        // wave-2 W2/W4: with UNCHANGED bank details the Node lib rebuilt the
        // same idempotency keys, and GoCardless handed back the old cancelled /
        // expired mandate instead of a new one. Naming the mandate being
        // replaced salts the keys so a genuinely new mandate is created.
        if (wasRecreate) body.put('replaces_mandate_id', app.DD_Mandate_Id__c);
        // Heroku refuses to mint a new mandate over a dead one without either
        // the replaced id or this flag (wave-3 W3-2).
        if (clientReconfirmed == true) body.put('client_reconfirmed', true);

        Map<String, Object> resp = doCallout(PATH_CREATE_MANDATE, body);
        if (isTruthy(resp.get('ok'))
                && DEAD_MANDATE_STATUSES.contains(str(resp.get('status')).toLowerCase())) {
            // Never write a dead status back as if a Direct Debit had been set
            // up, and never let the card show a success toast for it.
            String dead = 'GoCardless returned a Direct Debit that is already ' + str(resp.get('status')) +
                ' (' + str(resp.get('mandate_id')) + ') instead of a new one. Nothing was changed. Ask the tech team to check it.';
            recordFailure(app.Id, 'Mandate create failed: ' + dead);
            throw new AuraHandledException('Mandate create failed: ' + dead);
        }
        if (isTruthy(resp.get('ok'))) {
            // Fernando's rule (2026-08-18): welcome-email trigger fires on
            // DD_Mandate_Id__c null→non-null transition. Only stamp
            // DD_Mandate_Id__c when the mandate PDF is confirmed live in SF
            // (Node's mandate_pdf.ok). Otherwise the trigger fires without
            // AA_Mandate ContentVersion + dispatcher blocks the send + no
            // email lands. Node's watchdog cron will call this method again
            // on next tick — idempotent, retries the PDF fetch, and only
            // then does DD_Mandate_Id__c actually get stamped, so welcome
            // fires with the full 3-PDF payload.
            Map<String, Object> pdf = (Map<String, Object>) resp.get('mandate_pdf');
            Boolean pdfOk = pdf != null && isTruthy(pdf.get('ok'));
            AA_Application__c patch = new AA_Application__c(
                Id = app.Id,
                DD_Mandate_Status__c        = str(resp.get('status')),
                DD_Mandate_Created_At__c    = Datetime.now(),
                DD_Mandate_Failure_Reason__c = null
            );
            if (pdfOk) {
                patch.DD_Mandate_Id__c = str(resp.get('mandate_id'));
            } else if (wasRecreate) {
                // audit #6: don't leave the OLD dead mandate id sitting with a fresh
                // 'pending_submission' status — that non-dead status blocks both the
                // watchdog PDF-retry and a rep's Create-DD re-attempt. Clear it; the
                // watchdog re-runs this method, refetches the PDF, and stamps the new
                // id (null→non-null) so the welcome-email trigger still fires cleanly.
                // That re-run no longer knows the replaced id (wasRecreate is false
                // with a blank id), so it replays the unsalted keys: the Node lib
                // detects the dead mandate those return and picks up the new live
                // one on the same bank account instead (wave-2 W2).
                patch.DD_Mandate_Id__c = null;
            }
            update patch;
            return new Map<String, Object>{
                'ok'          => true,
                'mandate_id'  => str(resp.get('mandate_id')),
                'status'      => patch.DD_Mandate_Status__c,
                'pdf_pending' => !pdfOk,
                'existed'     => false
            };
        }
        String err = String.isNotBlank(str(resp.get('error')))
            ? str(resp.get('error'))
            : 'Unknown error';
        if (str(resp.get('code')) == 'mandate_dead_needs_client_agreement') {
            // GoCardless holds only a dead mandate for this client and the
            // call carried no fresh agreement (wave-3 W3-2).
            recordFailure(app.Id, 'Mandate create refused: ' + DEAD_NEEDS_AGREEMENT_MSG);
            throw new AuraHandledException(DEAD_NEEDS_AGREEMENT_MSG);
        }
        recordFailure(app.Id, 'Mandate create failed: ' + err);
        throw new AuraHandledException('Mandate create failed: ' + err);
    }

    // -----------------------------------------------------------------
    // 2. recordAward
    // -----------------------------------------------------------------
    // Apex @AuraEnabled forbids overloading, so `installments`, `lumpSum` and
    // `firstChargeDate` are nullable parameters — legacy callers (pre-2026-08-18)
    // pass null and get defaults: installments=1 (single charge), lumpSum
    // untouched, firstChargeDate = earliest legal date (today + NOTICE_DAYS,
    // applied by chargeFee). The LWC aaAwardRecorder sends every argument.
    //
    // `lumpSum` (2026-08-18): the initial DWP back-payment. Persisted to
    // DWP_Lump_Sum_Received__c and used by the LWC to *recommend* a plan
    // (lump>=fee → single, lump<fee → 3 monthly), but the val team makes
    // the final call via the manual override toggle. The server does NOT
    // recompute `installments` from lumpSum — it trusts the LWC's chosen
    // plan value and just persists what it was told.
    //
    // `firstChargeDate` (2026-08-25): agent-chosen date for installment #1.
    // If null, chargeFee uses the earliest legal date (today + NOTICE_DAYS).
    // Range: today+NOTICE_DAYS..today+90 (see FIRST_CHARGE_MAX_DAYS_AHEAD).
    // The floor is the 5-calendar-day Bacs advance notice (audit 2026-10-02
    // F101): a date sooner than that could only be collected without the
    // notice the client was promised. Installments #2..N are computed as
    // firstChargeDate.addMonths(k-1) — SF Apex's Date.addMonths handles
    // month-end snap (Jan 31 → Feb 28, Mar 31 → Apr 30) automatically.
    //
    // `confirmUnusualAmount` (audit 2026-10-02 F111): required true when the
    // amount is outside the annual-award band [AWARD_BAND_MIN, AWARD_BAND_MAX].
    @AuraEnabled
    public static Map<String, Object> recordAward(Id recordId, Decimal amount, Integer installments, Decimal lumpSum, Date firstChargeDate, Boolean confirmUnusualAmount) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        if (amount == null || amount <= 0)
            throw new AuraHandledException('Award amount must be greater than zero');
        if (amount >= AWARD_MAX)
            throw new AuraHandledException('Award amount unrealistically large (>' + AWARD_MAX + ')');
        if ((amount < AWARD_BAND_MIN || amount > AWARD_BAND_MAX) && confirmUnusualAmount != true) {
            throw new AuraHandledException('UNUSUAL_AWARD: £' + amount.setScale(2) + ' does not look like an annual ' +
                'Attendance Allowance award. Enter the weekly rate x 52 (2026/27: £3,988.40 lower rate, £5,959.20 higher rate). ' +
                'If you typed the weekly amount, multiply it by 52. If this amount is right, tick ' +
                '"I have checked this amount against the DWP letter" and save again.');
        }
        if (lumpSum != null && lumpSum < 0)
            throw new AuraHandledException('DWP lump sum received cannot be negative');
        if (lumpSum != null && lumpSum >= AWARD_MAX)
            throw new AuraHandledException('DWP lump sum received unrealistically large (>' + AWARD_MAX + ')');
        if (firstChargeDate != null) {
            Date today = Date.today();
            Date earliest = today.addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS);
            if (firstChargeDate < earliest) {
                throw new AuraHandledException('First charge date must be at least ' +
                    AA_FeeInstallmentScheduler.NOTICE_DAYS + ' days from today (' + earliest.format() +
                    ' or later), so the client gets the 5-day Direct Debit advance notice first.');
            }
            if (firstChargeDate > today.addDays(FIRST_CHARGE_MAX_DAYS_AHEAD)) {
                throw new AuraHandledException('First charge date must be within ' + FIRST_CHARGE_MAX_DAYS_AHEAD + ' days from today');
            }
        }

        Integer plan = normalisePlan(installments);

        AA_Application__c app = loadApp(recordId);
        // audit #7/#47: once charging has started (a base-fee payment id exists, or
        // AA_Fee_Installment__c child rows were created), the child schedule is
        // immutable — changing Award_Amount__c / Fee_Plan_Installments__c here would
        // silently diverge the parent from the already-charged children. Allow a
        // no-op re-save (same amount + plan), block a real change with a clear error.
        Boolean chargingStarted = String.isNotBlank(app.Fee_Payment_Id__c)
            || [SELECT COUNT() FROM AA_Fee_Installment__c WHERE Application__c = :recordId] > 0;
        if (chargingStarted) {
            Boolean amountChanged = app.Award_Amount__c == null || app.Award_Amount__c != amount;
            Boolean planChanged   = plan != (Integer) app.Fee_Plan_Installments__c;
            if (amountChanged || planChanged) {
                throw new AuraHandledException('This award has already been charged (or has an installment schedule), so the amount and plan can no longer be changed here. Cancel/refund the existing plan first, then re-record.');
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
        AA_Application__c after = Database.query(
            'SELECT Award_Amount__c, Fee_Amount__c, Fee_Plan_Installments__c, ' +
            'Fee_Plan_Installment_Amount__c, Fee_First_Charge_Date__c, ' +
            'DWP_Lump_Sum_Received__c, Stage__c ' +
            'FROM AA_Application__c WHERE Id = :recordId LIMIT 1');
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
     * Clamp installments to the restricted range 1..PLAN_MAX (3 for AA).
     * Anything outside is treated as 1 (single charge) below PLAN_MIN, or
     * PLAN_MAX above — matches the Fee_Plan_Installments__c validation rule
     * on the object (Fee_Plan_Installments_In_Range).
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
    // First-click behaviour (Fernando's 2026-08-25 plan model; notice rules
    // from audit 2026-10-02 F101/F79):
    //   1. Snapshot the plan (Fee_Plan_Installments__c, defaults to 1) and
    //      the anchor date: Fee_First_Charge_Date__c, but never sooner than
    //      today + NOTICE_DAYS (a stored date that is now too close is moved
    //      forward and the move is written back, so the card shows it).
    //   2. Insert N AA_Fee_Installment__c rows (row #1 on the anchor date,
    //      row #k on anchor.addMonths(k-1) — SF Date arithmetic snaps
    //      month-end automatically so Jan 31 → Feb 28, Mar 31 → Apr 30).
    //      Final row absorbs the sub-penny rounding remainder so the sum of
    //      amounts equals Fee_Amount__c exactly.
    //   3. Run the advance-notice step for this Application at once: when
    //      the anchor is exactly NOTICE_DAYS out the client is emailed today,
    //      and the charge Queueable is enqueued to create the GoCardless
    //      payment with charge_date = that date. A later anchor is noticed
    //      and created by the daily AA_FeeInstallmentScheduler sweep.
    //   There is NO "fire now" any more: the old path charged instalment #1
    //   the moment the button was clicked, with no XtraPension notice and on
    //   a GoCardless-chosen date.
    //   4. The parent's Fee_Payment_Id__c / Stage 'Fee Charged' are written by
    //      the Node endpoint when instalment #1's payment is created.
    //
    // Re-clicking Charge Fee on an app that already has installments:
    //   - Returns the current schedule without side effects (idempotent).
    // -----------------------------------------------------------------
    @AuraEnabled
    public static Map<String, Object> chargeFee(Id recordId) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        AA_Application__c app = loadApp(recordId);

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
        // The webhook can mark the status 'active' while DD_Mandate_Id__c is
        // still blank (mandate PDF pending, audit F103). Heroku refuses every
        // charge for that record, so scheduling here would only email the
        // client a notice for a collection that cannot happen (wave-2 W1).
        if (String.isBlank(app.DD_Mandate_Id__c)) {
            throw new AuraHandledException(MANDATE_DOC_PENDING_MSG);
        }
        if (app.Award_Amount__c == null || app.Award_Amount__c <= 0) {
            throw new AuraHandledException('Award not recorded');
        }
        // A client marked Do Not Contact cannot be sent the advance notice, so
        // no collection may be scheduled (conservative default, see
        // AA_FeeInstallmentScheduler hold rules).
        if (app.Do_Not_Contact__c == true) {
            throw new AuraHandledException('This client is marked Do Not Contact, so the Direct Debit advance notice cannot be sent. ' +
                'No collection can be scheduled until that flag is cleared.');
        }
        // The sweep notices and collects only in AA_FeeInstallmentScheduler's
        // collectable stages (the Bacs advance notice stage gate minus the
        // halt stages). A plan built elsewhere would sit unnoticed, so refuse
        // it here with the reason instead (integrator 2026-10-02).
        if (!AA_FeeInstallmentScheduler.isCollectableStage(app.Stage__c)) {
            throw new AuraHandledException('No fee can be scheduled at stage "' + app.Stage__c + '". ' +
                'Fee collection only runs once the award is recorded (Awarded, Fee Charged or Change of Circumstances Review).');
        }

        // Idempotent: a plan that already exists is never rebuilt. Rebuilding
        // used to delete and re-insert the rows, wiping their notice stamps
        // (a second advance notice) and, with a payment already created at
        // GoCardless, orphaning it.
        List<AA_Fee_Installment__c> existing = [
            SELECT Installment_Number__c, Scheduled_Date__c, Amount__c
              FROM AA_Fee_Installment__c
             WHERE Application__c = :app.Id
             ORDER BY Installment_Number__c
        ];
        if (!existing.isEmpty()) {
            return new Map<String, Object>{
                'ok'                => true,
                'existed'           => true,
                'deferred'          => true,
                'first_charge_date' => existing[0].Scheduled_Date__c,
                'amount_pounds'     => existing[0].Amount__c,
                'installments'      => existing.size(),
                'installment_amount'=> existing[0].Amount__c,
                'next_charge_date'  => app.Fee_Plan_Next_Charge_Date__c
            };
        }

        // 20% of the award, rounded to pence. Reproduce the Fee_Amount__c
        // formula deliberately so the rows never depend on a formula re-read.
        // Rate changed 25% → 20% on 2026-08-18 (Fernando).
        Decimal feePounds = (app.Award_Amount__c * FEE_RATE).setScale(2, System.RoundingMode.HALF_UP);
        Integer plan = normalisePlan((Integer) app.Fee_Plan_Installments__c);
        Date earliest = Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS);
        Date anchor = app.Fee_First_Charge_Date__c;
        if (anchor == null || anchor < earliest) anchor = earliest;

        List<AA_Fee_Installment__c> installments = buildInstallmentRows(app.Id, feePounds, plan, anchor);
        AA_Fee_Installment__c first = installments[0];
        insert installments;
        AA_Application__c patch = new AA_Application__c(
            Id                           = app.Id,
            Fee_Plan_Next_Charge_Date__c = first.Scheduled_Date__c
            // Fee_Payment_Id__c / Stage 'Fee Charged' land when the Node
            // endpoint creates instalment #1's GoCardless payment.
        );
        if (app.Fee_First_Charge_Date__c != anchor) patch.Fee_First_Charge_Date__c = anchor;
        update patch;

        Boolean noticeSent = noticeAndQueueCharge(app.Id);
        return new Map<String, Object>{
            'ok'                => true,
            'deferred'          => true,
            'notice_sent'       => noticeSent,
            'first_charge_date' => first.Scheduled_Date__c,
            'amount_pounds'     => first.Amount__c,
            'installments'      => plan,
            'installment_amount'=> first.Amount__c,
            'next_charge_date'  => first.Scheduled_Date__c
        };
    }

    /**
     * Send the advance notice for this Application now when one is due today,
     * and if it went out, enqueue the charge Queueable so the GoCardless
     * payment (charge_date = the noticed date) is created now rather than at
     * tomorrow's sweep, which leaves GoCardless its full lead time. Returns
     * whether a notice was handed to the dispatcher.
     */
    private static Boolean noticeAndQueueCharge(Id appId) {
        Integer[] r = AA_FeeInstallmentScheduler.sendAdvanceNotices(Date.today(), new Set<Id>{ appId });
        Boolean sent = r != null && r[0] > 0;
        if (sent) System.enqueueJob(new AA_FeeInstallmentChargeQueueable(Date.today()));
        return sent;
    }

    // -----------------------------------------------------------------
    // 3b. retryInstallment — re-collect a failed / cancelled instalment
    //
    // audit 2026-10-02 F110: a failed instalment could not be re-collected in
    // the system at all (the card locked once #1 had a payment id, and the
    // per-stage idempotency key handed back the original failed payment). The
    // row goes back to 'pending', dated NOTICE_DAYS out with its notice
    // cleared; the notice step emails the client the new date now and the
    // charge step re-collects: GoCardless's retry action on the same payment
    // when it failed on the current mandate, else a new payment (Node
    // gcClient.retryPayment). The old Payment_Id__c is kept as the marker.
    // -----------------------------------------------------------------
    @AuraEnabled
    public static Map<String, Object> retryInstallment(Id installmentId) {
        if (installmentId == null) throw new AuraHandledException('installmentId is required');
        List<AA_Fee_Installment__c> rows = [
            SELECT Id, Application__c, Installment_Number__c, Payment_Status__c, Payment_Id__c
              FROM AA_Fee_Installment__c WHERE Id = :installmentId LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Instalment not found');
        AA_Fee_Installment__c row = rows[0];
        if (row.Payment_Status__c != 'failed' && row.Payment_Status__c != 'cancelled') {
            throw new AuraHandledException('Only a failed or cancelled instalment can be retried (this one is "' +
                row.Payment_Status__c + '").');
        }
        AA_Application__c app = loadApp(row.Application__c);
        if (app.Stage__c == 'DD Chargeback') {
            throw new AuraHandledException('The client disputed a payment (DD Chargeback). Do not re-collect through the Direct Debit.');
        }
        if (app.DD_Mandate_Status__c != 'active') {
            throw new AuraHandledException('The Direct Debit is not active. Set up a new Direct Debit with the client first, then retry.');
        }
        if (String.isBlank(app.DD_Mandate_Id__c)) {
            throw new AuraHandledException(MANDATE_DOC_PENDING_MSG);
        }
        if (app.Do_Not_Contact__c == true) {
            throw new AuraHandledException('This client is marked Do Not Contact, so the advance notice cannot be sent.');
        }
        // wave-2 W1: an operator can move the Stage off 'DD Chargeback' by
        // hand. Heroku would then refuse the charged-back payment
        // (payment_not_retryable), but only AFTER the client had been emailed
        // a fresh "we will collect" notice. A plan that was ever charged back
        // is never re-collected through the Direct Debit.
        if ([SELECT COUNT() FROM AA_Stage_Log__c
              WHERE Application__c = :app.Id AND To_Stage__c = 'DD Chargeback'] > 0) {
            throw new AuraHandledException('The client disputed a payment on this case (it was in DD Chargeback). ' +
                'Do not re-collect through the Direct Debit: agree with the client how the balance is settled.');
        }
        // The stage the case will be at after this retry ('Closed - Fee
        // Failed' is reopened as 'Fee Charged' below). Outside the sweep's
        // collectable stages the fresh notice would be suppressed and the row
        // never collected, so refuse up front (integrator 2026-10-02).
        String stageAfter = app.Stage__c == 'Closed - Fee Failed' ? 'Fee Charged' : app.Stage__c;
        if (!AA_FeeInstallmentScheduler.isCollectableStage(stageAfter)) {
            throw new AuraHandledException('No fee can be collected at stage "' + app.Stage__c + '". ' +
                'Move the case back to Awarded, Fee Charged or Change of Circumstances Review first, then retry.');
        }
        Date nd = Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS);
        update new AA_Fee_Installment__c(
            Id                     = row.Id,
            Payment_Status__c      = 'pending',
            Charged_At__c          = null,
            Scheduled_Date__c      = nd,
            Bacs_Notice_Sent__c    = false,
            Bacs_Notice_Sent_At__c = null
        );
        AA_Application__c patch = new AA_Application__c(Id = app.Id);
        if (app.Stage__c == 'Closed - Fee Failed') patch.Stage__c = 'Fee Charged';
        if (app.Fee_Plan_Next_Charge_Date__c == null || app.Fee_Plan_Next_Charge_Date__c > nd) {
            patch.Fee_Plan_Next_Charge_Date__c = nd;
        }
        update patch;
        Boolean noticeSent = noticeAndQueueCharge(app.Id);
        return new Map<String, Object>{
            'ok'          => true,
            'charge_date' => nd,
            'notice_sent' => noticeSent
        };
    }

    // -----------------------------------------------------------------
    // 3c. getFeeInstallments — the plan rows for the Fee Charge card.
    // -----------------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFeeInstallments(Id recordId) {
        if (recordId == null) throw new AuraHandledException('recordId is required');
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        // Owner decision 2026-10-02: Do Not Contact pauses fee collection. The
        // daily sweep moves uncreated rows to 'paused' (wave 4), but until it
        // runs a newly flagged client's rows are still 'pending' (and a row
        // already at GoCardless stays 'pending'), so the card is also told
        // the flag. A 'paused' row whose flag was cleared goes back to
        // 'pending' on the next daily run: shown as resuming, not paused.
        List<AA_Application__c> apps = [SELECT Do_Not_Contact__c FROM AA_Application__c WHERE Id = :recordId LIMIT 1];
        Boolean dnc = !apps.isEmpty() && apps[0].Do_Not_Contact__c == true;
        for (AA_Fee_Installment__c r : [
            SELECT Id, Installment_Number__c, Scheduled_Date__c, Amount__c,
                   Payment_Status__c, Payment_Id__c, Charged_At__c,
                   Bacs_Notice_Sent__c, Bacs_Notice_Sent_At__c
              FROM AA_Fee_Installment__c
             WHERE Application__c = :recordId
             ORDER BY Installment_Number__c
        ]) {
            String st = r.Payment_Status__c;
            // A pending row already created at GoCardless is NOT paused: it
            // WILL be collected unless ops cancels it there (the pause handoff
            // lists it). Flagged on its own so the card never calls it paused.
            Boolean atGc = st == 'pending' && r.Charged_At__c != null;
            out.add(new Map<String, Object>{
                'id'             => r.Id,
                'number'         => r.Installment_Number__c,
                'scheduled_date' => r.Scheduled_Date__c,
                'amount'         => r.Amount__c,
                'status'         => st,
                'created_at_gc'  => r.Charged_At__c != null,
                'notice_sent'    => r.Bacs_Notice_Sent__c == true,
                'notice_sent_at' => r.Bacs_Notice_Sent_At__c,
                'can_retry'      => st == 'failed' || st == 'cancelled',
                'paused_dnc'     => dnc && ((st == 'pending' && !atGc) || st == AA_FeeInstallmentScheduler.STATUS_PAUSED),
                'dnc_at_gc'      => dnc && atGc,
                'resuming'       => !dnc && st == AA_FeeInstallmentScheduler.STATUS_PAUSED
            });
        }
        return out;
    }

    /**
     * Build the list of AA_Fee_Installment__c rows for a plan.
     * Dates: row #1 = anchor, row #k = anchor.addMonths(k-1). SF Apex
     *        Date.addMonths handles the month-end snap automatically
     *        (Jan 31 + 1 month → Feb 28/29, Mar 31 + 1 → Apr 30).
     * Amounts: rows 1..N-1 = ROUND(fee/N, 2); final row absorbs remainder so
     *          the sum equals feePounds exactly (e.g. £800/3 → £266.67 x2 +
     *          £266.66 = £800.00).
     */
    @TestVisible
    private static List<AA_Fee_Installment__c> buildInstallmentRows(Id appId, Decimal feePounds, Integer plan, Date anchor) {
        List<AA_Fee_Installment__c> out = new List<AA_Fee_Installment__c>();
        Decimal per = (feePounds / plan).setScale(2, System.RoundingMode.HALF_UP);
        Decimal remainder = feePounds - (per * (plan - 1));  // final row
        for (Integer i = 1; i <= plan; i++) {
            Decimal amt = (i == plan) ? remainder : per;
            out.add(new AA_Fee_Installment__c(
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
        AA_Application__c app = loadApp(recordId);
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
    private static AA_Application__c loadApp(Id recordId) {
        List<AA_Application__c> apps = Database.query(
            'SELECT ' + APP_FIELDS + ' FROM AA_Application__c WHERE Id = :recordId LIMIT 1'
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
            return new Map<String, Object>{
                'ok'    => false,
                'error' => 'Non-JSON response (HTTP ' + status + '): ' + safe(rawBody)
            };
        }
        if (status < 200 || status >= 300) {
            String err = String.isNotBlank(str(parsed.get('error')))
                ? str(parsed.get('error'))
                : 'HTTP ' + status;
            // 'code' carries the GoCardless-lib reason under a generic error
            // (e.g. mandate_dead_needs_client_agreement under gocardless_call_failed).
            return new Map<String, Object>{ 'ok' => false, 'error' => err, 'code' => str(parsed.get('code')) };
        }
        return parsed;
    }

    /**
     * Persist a failure trail:
     *   - DD_Mandate_Failure_Reason__c (visible on the record page)
     *   - AA_Stage_Log__c with Actor__c='system' + Note__c=reason
     * Deliberately swallowing DML exceptions here so the primary failure
     * error surfaces to the LWC uncoloured. The Stage_Log write is best-effort.
     */
    private static void recordFailure(Id appId, String reason) {
        try {
            AA_Application__c patch = new AA_Application__c(
                Id = appId,
                DD_Mandate_Failure_Reason__c = safe(reason)
            );
            update patch;
        } catch (Exception ignored) { /* best-effort */ }
        try {
            insert new AA_Stage_Log__c(
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
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Internal_Admin_Token__c))
            ? cfg.Internal_Admin_Token__c.trim() : null;
    }
    private static String buildFullName(AA_Application__c a) {
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