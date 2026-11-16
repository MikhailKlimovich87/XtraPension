/**
 * PC1_GoCardlessController — @AuraEnabled facade the pc1DirectDebit LWCs
 * call to drive the Direct Debit lifecycle for a PC1_Application__c:
 *
 *   1. createMandateForApplication  — POST /internal/gocardless/create-mandate
 *      after the sales agent has verified bank + read the DD terms.
 *   2. recordAward                  — sales agent captures the DWP award amount
 *      and advances Stage__c to 'Awarded' (fee formula recalcs on save).
 *   3. chargeFee                    — once the mandate is active + award
 *      recorded (20% of award), inserts the PC1_Fee_Installment__c rows of the
 *      plan (Fee_Plan_Installments__c, 1..6 monthly) and sends the Bacs
 *      advance notice for installment #1. It no longer calls GoCardless
 *      itself (audit 2026-11-11 PC-APEX-4): every payment, #1 included, is
 *      created by PC1_FeeInstallmentScheduler with the noticed charge date.
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
        'DWP_Lump_Sum_Received__c, Do_Not_Contact__c, Stage__c';

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
    // Earliest first-charge date chargeFee schedules, in days from today: the
    // advance notice the client is promised (NOTICE_DAYS) plus one day,
    // because the GoCardless payment is created by the next morning's sweep
    // and should still have the full notice period as lead time. A stored
    // date sooner than this (or in the past) is moved to it (audit
    // 2026-11-11 PC-APEX-4 / PC-SFUI-4).
    public static final Integer FIRST_CHARGE_MIN_DAYS = PC1_FeeInstallmentScheduler.NOTICE_DAYS + 1;

    // The award / plan freeze is also enforced on direct field writes (see
    // enforceFeeFreeze). chargeFee moves Fee_First_Charge_Date__c itself when
    // the stored date is too soon; that one write is let through.
    @TestVisible private static Boolean feeFreezeBypass = false;
    // The old text told the user to cancel the payments and installment
    // records and record the award again; that cannot work (Charge Fee then
    // answers "already charged" and GoCardless hands back the old payment for
    // the same installment), so it now sends them to an administrator
    // (audit 2026-11-11 PC-APEX-9).
    @TestVisible private static final String FEE_FROZEN_MSG =
        'The fee for this award is already being collected by Direct Debit, so the award amount, '
        + 'plan and first charge date can no longer be changed. If the award was recorded wrongly, '
        + 'contact an administrator: the remaining collection has to be re-planned by hand.';

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
            // Put on hold by the sweep before any GoCardless payment existed
            // (creation refused, or never possible before its date): there is
            // nothing to re-present, the installment is scheduled again.
            return requeueHeldInstallment(row);
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

    /**
     * Retry of an installment the sweep put on hold with no GoCardless payment
     * (port of AA retryInstallment, audit 2026-11-11 PC-APEX-3/4). The row
     * goes back to 'pending', dated FIRST_CHARGE_MIN_DAYS out with its notice
     * cleared; the client is emailed the new date now and the daily sweep
     * creates the payment for that date. Refused where the sweep would never
     * collect it, so no "we will collect" email goes out for nothing.
     */
    private static Map<String, Object> requeueHeldInstallment(PC1_Fee_Installment__c row) {
        PC1_Application__c app = loadApp(row.Application__c);
        if (app.DD_Mandate_Status__c != 'active' || String.isBlank(app.DD_Mandate_Id__c)) {
            throw new AuraHandledException('The Direct Debit is not active. Set up a new Direct Debit with the client first, then retry.');
        }
        if (app.Do_Not_Contact__c == true) {
            throw new AuraHandledException('This client is marked Do Not Contact, so the advance notice cannot be sent.');
        }
        if (!PC1_FeeInstallmentScheduler.isCollectableStage(app.Stage__c)) {
            throw new AuraHandledException('No fee can be collected at stage "' + app.Stage__c + '". ' +
                'Move the case back to Awarded or Fee Charged first, then retry.');
        }
        Date nd = Date.today().addDays(FIRST_CHARGE_MIN_DAYS);
        update new PC1_Fee_Installment__c(
            Id                     = row.Id,
            Payment_Status__c      = 'pending',
            Charged_At__c          = null,
            Scheduled_Date__c      = nd,
            Bacs_Notice_Sent__c    = false,
            Bacs_Notice_Sent_At__c = null
        );
        if (app.Fee_Plan_Next_Charge_Date__c == null || app.Fee_Plan_Next_Charge_Date__c > nd) {
            update new PC1_Application__c(Id = app.Id, Fee_Plan_Next_Charge_Date__c = nd);
        }
        Integer[] sent = PC1_FeeInstallmentScheduler.sendAdvanceNotices(Date.today(), new Set<Id>{ app.Id });
        // The notice step keeps a month between installments, so it may have
        // moved the row later than nd.
        Date scheduled = [SELECT Scheduled_Date__c FROM PC1_Fee_Installment__c WHERE Id = :row.Id].Scheduled_Date__c;
        insert new PC1_Stage_Log__c(
            Application__c = app.Id, From_Stage__c = app.Stage__c, To_Stage__c = app.Stage__c,
            Actor__c = 'human', Changed_At__c = Datetime.now(), Changed_By__c = UserInfo.getUserId(),
            Note__c = ('Installment ' + row.Installment_Number__c + ' put back for collection on ' + String.valueOf(scheduled)
                + ' (it was on hold with no GoCardless payment).').left(255));
        return new Map<String, Object>{
            'ok'          => true,
            'requeued'    => true,
            'notice_sent' => sent != null && sent[0] > 0,
            'charge_date' => String.valueOf(scheduled)
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
                resumeCancelledInstallments(app);
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

    /**
     * Audit 2026-11-11 PC-APEX-10. When a mandate dies mid-plan the GoCardless
     * webhook turns every installment not yet collected into 'cancelled', and
     * nothing turned them back once a replacement Direct Debit existed: the
     * sweep reads 'pending' only, Charge Fee answered "already charged" and
     * Retry refused, so the rest of the fee could not be collected at all.
     * Now, on a successful replacement:
     *   - a cancelled row that never reached GoCardless goes back to
     *     'pending' with its notice cleared; the sweep re-dates it, sends a
     *     fresh notice and collects once the new mandate is active;
     *   - a cancelled row that HAD a payment (cancelled at GoCardless, or the
     *     case is not at a collectable stage) is left alone and listed on a
     *     handoff, because the same payment cannot be collected again.
     * Best-effort: a failure here must not fail the mandate that was created.
     */
    private static void resumeCancelledInstallments(PC1_Application__c app) {
        try {
            List<PC1_Fee_Installment__c> cancelled = [
                SELECT Id, Installment_Number__c, Amount__c, Payment_Id__c
                  FROM PC1_Fee_Installment__c
                 WHERE Application__c = :app.Id AND Payment_Status__c = 'cancelled'
                 ORDER BY Installment_Number__c
            ];
            if (cancelled.isEmpty()) return;
            Boolean collectable = PC1_FeeInstallmentScheduler.isCollectableStage(app.Stage__c);
            List<PC1_Fee_Installment__c> back = new List<PC1_Fee_Installment__c>();
            List<String> manual = new List<String>();
            for (PC1_Fee_Installment__c row : cancelled) {
                if (collectable && String.isBlank(row.Payment_Id__c)) {
                    back.add(new PC1_Fee_Installment__c(
                        Id                     = row.Id,
                        Payment_Status__c      = 'pending',
                        Charged_At__c          = null,
                        Bacs_Notice_Sent__c    = false,
                        Bacs_Notice_Sent_At__c = null
                    ));
                } else {
                    manual.add(' - installment ' + row.Installment_Number__c + ', £' + row.Amount__c +
                        (String.isBlank(row.Payment_Id__c) ? '' : ' (GoCardless payment ' + row.Payment_Id__c + ', cancelled)'));
                }
            }
            if (!back.isEmpty()) update back;
            if (!manual.isEmpty()) {
                insert new PC1_Handoff__c(
                    CurrencyIsoCode    = 'GBP',
                    Application__c     = app.Id,
                    Escalation_Type__c = 'other',
                    Reason__c          = 'New Direct Debit set up: cancelled fee installments need a decision',
                    Next_Step_Suggestion__c = ('A replacement Direct Debit was created, but these installments stay cancelled and will '
                        + 'NOT be collected automatically' + (collectable ? '' : ' (the case is at stage "' + app.Stage__c + '")') + ':\n'
                        + String.join(manual, '\n') + '\n\n'
                        + 'Decide with the client how this part of the fee is settled. Contact an administrator to schedule '
                        + 'a new collection for it.').left(2000),
                    Resolved__c        = false
                );
            }
            if (!back.isEmpty()) {
                insert new PC1_Stage_Log__c(
                    Application__c = app.Id, From_Stage__c = app.Stage__c, To_Stage__c = app.Stage__c,
                    Actor__c = 'system', Changed_At__c = Datetime.now(), Changed_By__c = UserInfo.getUserId(),
                    Note__c = (back.size() + ' cancelled fee installment(s) put back to pending for the new Direct Debit; '
                        + 'each gets a fresh advance notice once the mandate is active.').left(255));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_GoCardlessController: resumeCancelledInstallments failed for ' + app.Id + ' — ' + e.getMessage());
        }
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
        Integer plan = normalisePlan(installments);

        PC1_Application__c app = loadApp(recordId);

        // A date sent back unchanged is not a new choice (audit 2026-11-11
        // PC-SFUI-10): the award card re-sends the stored date on every Edit,
        // and from the day after it was recorded that date is "in the past",
        // so no edit at all could be saved. chargeFee moves a stale date
        // forward itself.
        if (firstChargeDate != null && firstChargeDate == app.Fee_First_Charge_Date__c) {
            firstChargeDate = null;
        }
        if (firstChargeDate != null) {
            Date today = Date.today();
            if (firstChargeDate < today) {
                throw new AuraHandledException('First charge date cannot be in the past');
            }
            if (firstChargeDate > today.addDays(FIRST_CHARGE_MAX_DAYS_AHEAD)) {
                throw new AuraHandledException('First charge date must be within ' + FIRST_CHARGE_MAX_DAYS_AHEAD + ' days from today');
            }
        }

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
                throw new AuraHandledException(FEE_FROZEN_MSG);
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
    // First-click behaviour (plan model of 2026-08-25; notice rules ported
    // from AA on 2026-11-11, audit PC-APEX-4 / PC-SFUI-4):
    //   1. Snapshot the plan (Fee_Plan_Installments__c, defaults to 1) and
    //      the anchor date: Fee_First_Charge_Date__c, but never sooner than
    //      today + FIRST_CHARGE_MIN_DAYS. A stored date that is too close or
    //      already past is moved forward and the move is written back, so the
    //      card shows it. Before, a past date was used as it stood: installment
    //      #1 went out at once and #2 could be due days later, with no notice.
    //   2. Insert N PC1_Fee_Installment__c rows (row #1 on the anchor date,
    //      row #k on anchor.addMonths(k-1) — SF Date arithmetic snaps
    //      month-end automatically so Jan 31 → Feb 28, Mar 31 → Apr 30).
    //      Final row absorbs the sub-penny rounding remainder so the sum of
    //      amounts equals Fee_Amount__c exactly.
    //   3. Run the advance-notice step for this Application at once, so the
    //      client is emailed the date and amount of installment #1 today.
    //      The daily PC1_FeeInstallmentScheduler creates the GoCardless
    //      payment for that date on its next run.
    //   There is NO "fire now" any more: the old path created installment #1
    //   the moment the button was clicked, with no XtraPension notice and on
    //   a date GoCardless chose.
    //   4. The parent's Fee_Payment_Id__c / Stage 'Fee Charged' are written by
    //      the Node endpoint when installment #1's payment is created.
    //
    // Re-clicking Charge Fee on an app that already has installments returns
    // the current schedule without side effects (idempotent).
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
        // The status can read 'active' while the mandate id is still blank
        // (mandate document pending). Heroku refuses every charge for such a
        // record, so scheduling here would only email the client a notice
        // for a collection that cannot happen.
        if (String.isBlank(app.DD_Mandate_Id__c)) {
            throw new AuraHandledException('The Direct Debit document is still pending, so no fee can be scheduled yet. Try again in a few minutes.');
        }
        if (app.Award_Amount__c == null || app.Award_Amount__c <= 0) {
            throw new AuraHandledException('Award not recorded');
        }
        // A client marked Do Not Contact cannot be sent the advance notice,
        // so no collection may be scheduled.
        if (app.Do_Not_Contact__c == true) {
            throw new AuraHandledException('This client is marked Do Not Contact, so the Direct Debit advance notice cannot be sent. ' +
                'No collection can be scheduled until that flag is cleared.');
        }
        // The sweep notices and collects only at a collectable stage. A plan
        // built elsewhere would sit un-noticed, so refuse it with the reason.
        if (!PC1_FeeInstallmentScheduler.isCollectableStage(app.Stage__c)) {
            throw new AuraHandledException('No fee can be scheduled at stage "' + app.Stage__c + '". ' +
                'Fee collection only runs once the award is recorded (Awarded or Fee Charged).');
        }

        // Idempotent: a plan that already exists is never rebuilt. Rebuilding
        // deleted and re-inserted the rows, which wiped their notice stamps
        // (a second advance notice to the client).
        List<PC1_Fee_Installment__c> existing = [
            SELECT Installment_Number__c, Scheduled_Date__c, Amount__c
              FROM PC1_Fee_Installment__c
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
        Integer plan = normalisePlan(app.Fee_Plan_Installments__c == null ? null : app.Fee_Plan_Installments__c.intValue());
        Date earliest = Date.today().addDays(FIRST_CHARGE_MIN_DAYS);
        Date anchor = app.Fee_First_Charge_Date__c;
        if (anchor == null || anchor < earliest) anchor = earliest;

        List<PC1_Fee_Installment__c> installments = buildInstallmentRows(app.Id, feePounds, plan, anchor);
        PC1_Fee_Installment__c first = installments[0];
        insert installments;
        PC1_Application__c patch = new PC1_Application__c(
            Id                           = app.Id,
            Fee_Plan_Next_Charge_Date__c = first.Scheduled_Date__c
            // Fee_Payment_Id__c / Stage 'Fee Charged' land when the Node
            // endpoint creates installment #1's GoCardless payment.
        );
        if (app.Fee_First_Charge_Date__c != anchor) patch.Fee_First_Charge_Date__c = anchor;
        feeFreezeBypass = true;
        try { update patch; } finally { feeFreezeBypass = false; }

        // Notice now when installment #1 is within the notice horizon (always,
        // unless the agent picked a later date; then the daily sweep sends it).
        Integer[] sent = PC1_FeeInstallmentScheduler.sendAdvanceNotices(Date.today(), new Set<Id>{ app.Id });
        return new Map<String, Object>{
            'ok'                => true,
            'deferred'          => true,
            'notice_sent'       => sent != null && sent[0] > 0,
            'first_charge_date' => first.Scheduled_Date__c,
            'amount_pounds'     => first.Amount__c,
            'installments'      => plan,
            'installment_amount'=> first.Amount__c,
            'next_charge_date'  => first.Scheduled_Date__c
        };
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
            // Earliest date chargeFee will schedule installment 1 on, and the
            // advance notice period, so the cards show what the server uses.
            'fee_first_charge_min_date' => Date.today().addDays(FIRST_CHARGE_MIN_DAYS),
            'fee_notice_days'           => PC1_FeeInstallmentScheduler.NOTICE_DAYS,
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
            // To_Stage__c is required: without it this insert failed every
            // time and the catch hid it, so the failure trail was never
            // written (audit 2026-11-11 PC-APEX-13). A note-only row carries
            // the current stage on both sides, like the other note rows.
            String stage = [SELECT Stage__c FROM PC1_Application__c WHERE Id = :appId LIMIT 1].Stage__c;
            insert new PC1_Stage_Log__c(
                Application__c = appId,
                From_Stage__c  = stage,
                To_Stage__c    = stage,
                Actor__c       = 'system',
                Changed_At__c  = Datetime.now(),
                Changed_By__c  = UserInfo.getUserId(),
                Note__c        = safe(reason)
            );
        } catch (Exception ignored) { /* best-effort */ }
    }

    /**
     * BEFORE UPDATE (PC1_ApplicationTrigger). The award / plan freeze used to
     * live only in recordAward, so an inline edit or a data load of
     * Award_Amount__c after installment 1 changed the fee on the card, the
     * receipts and the notices while the installment rows kept the old
     * amounts (audit 2026-11-11 PC-APEX-9, the C7 scenario again). Once the
     * fee is being collected (a payment id on the record, or installment
     * rows) the three plan fields can no longer be changed by any write.
     */
    public static void enforceFeeFreeze(List<PC1_Application__c> newList, Map<Id, PC1_Application__c> oldMap) {
        if (feeFreezeBypass || newList == null || oldMap == null) return;
        List<PC1_Application__c> changed = new List<PC1_Application__c>();
        Set<Id> toCheck = new Set<Id>();
        for (PC1_Application__c a : newList) {
            PC1_Application__c o = oldMap.get(a.Id);
            if (o == null) continue;
            if (a.Award_Amount__c == o.Award_Amount__c
                    && a.Fee_Plan_Installments__c == o.Fee_Plan_Installments__c
                    && a.Fee_First_Charge_Date__c == o.Fee_First_Charge_Date__c) continue;
            changed.add(a);
            if (String.isBlank(o.Fee_Payment_Id__c)) toCheck.add(a.Id);
        }
        if (changed.isEmpty()) return;
        Set<Id> withRows = new Set<Id>();
        if (!toCheck.isEmpty()) {
            for (AggregateResult r : [
                SELECT Application__c app FROM PC1_Fee_Installment__c
                 WHERE Application__c IN :toCheck
                 GROUP BY Application__c
            ]) {
                withRows.add((Id) r.get('app'));
            }
        }
        for (PC1_Application__c a : changed) {
            PC1_Application__c o = oldMap.get(a.Id);
            if (String.isNotBlank(o.Fee_Payment_Id__c) || withRows.contains(a.Id)) {
                a.addError(FEE_FROZEN_MSG);
            }
        }
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