/**
 * aaAwardRecorder — capture the DWP award amount + DWP back-payment lump
 * sum + payment plan on a AA Application.
 *
 * Two modes:
 *   • empty (Award_Amount__c is null) → award input + lump-sum input +
 *     auto-recommended plan (with optional manual override) + Record button.
 *     Calls AA_GoCardlessController.recordAward which persists the award,
 *     the lump sum, snapshots the fee, writes Fee_Plan_Installments__c, and
 *     advances Stage__c.
 *   • recorded → big amount display + calculated fee (Fee_Amount__c is a
 *     formula = 20% of award, changed 25%→20% on 2026-08-18) + plan summary +
 *     lump-sum context + Edit button that flips back to empty mode without
 *     wiping the server-side value until Record is clicked again.
 *
 * Payment plan (2026-08-18 revision): plan is DEFAULTED based on
 * DWP_Lump_Sum_Received__c vs Fee_Amount__c:
 *   • lump_sum >= fee → default single charge (client already has the money)
 *   • lump_sum <  fee → default 3 monthly installments (spread across income)
 * Val team can still MANUALLY override to 1 / 2 / 3 via the "Override plan"
 * toggle — the underlying Fee_Plan_Installments__c validation rule still
 * accepts all 3 values, this is a UI-only default policy.
 *
 * The 2x option is NOT shown in the auto-recommended UI (abolished per
 * Fernando's ask). It is ONLY reachable via the manual override — kept as a
 * value for edge cases the val team judges appropriate.
 *
 * Sanity flags (surfaced inline BEFORE Record):
 *   • award outside £3,500..£7,200 → "does not look like an annual award"
 *     warning + a required "I have checked this amount" tick (audit
 *     2026-10-02 F111: the annual award is the weekly rate x 52, ~£3,988
 *     lower / ~£5,959 higher at 2026/27 rates; the old £100 / £50,000 flags
 *     were PC1 values and let a weekly figure through). The server enforces
 *     the same band (AA_GoCardlessController.AWARD_BAND_MIN/MAX).
 *   • VAT-included checkbox — off by default; explanatory copy only, the
 *     controller decides whether to strip VAT.
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import recordAward from '@salesforce/apex/AA_GoCardlessController.recordAward';

const FIELDS = [
    'AA_Application__c.Award_Amount__c',
    'AA_Application__c.Fee_Amount__c',
    'AA_Application__c.Fee_Plan_Installments__c',
    'AA_Application__c.Fee_Plan_Installment_Amount__c',
    'AA_Application__c.Fee_First_Charge_Date__c',
    'AA_Application__c.DWP_Lump_Sum_Received__c',
    'AA_Application__c.LastModifiedDate',
];

// Annual-award band; mirrors AA_GoCardlessController.AWARD_BAND_MIN/MAX.
const LOW_THRESHOLD  = 3500;
const HIGH_THRESHOLD = 7200;
const FEE_RATE_PCT = 20;  // 20% — changed 25%→20% on 2026-08-18
// Earliest first charge = today + 5 calendar days: the Bacs advance notice
// must reach the client first (audit 2026-10-02 F101). Mirrors
// AA_FeeInstallmentScheduler.NOTICE_DAYS; the server refuses anything sooner.
const NOTICE_DAYS = 5;

// Full 1..3 picker used ONLY when the val team clicks Override.
// Auto-recommend UI only ever shows 1 or 3 (no 2). PC1's 1..6 widening
// (2026-08-25) was cloned in here, but AA is capped at THREE instalments
// (Fernando 2026-09-09): AA_GoCardlessController.PLAN_MAX silently clamps
// anything above 3, Fee_Plan_Installments_In_Range rejects it on the object,
// and the charge-fee endpoint only accepts installment_1..3. While this
// picker still offered 4x/5x/6x, an agent could quote "6 monthly payments"
// on a recorded call, click Record, and get a 3-instalment plan persisted
// with no error — so it must never offer more than the server honours.
const PLAN_MAX = 3;
const PLAN_OPTIONS_OVERRIDE = [
    { label: 'Single charge (1x)',                   value: '1' },
    { label: 'Split in 2 monthly installments (2x)', value: '2' },
    { label: 'Split in 3 monthly installments (3x)', value: '3' },
];

// Agent-chosen first-charge date can be today+NOTICE_DAYS through today+90 days.
// Matches AA_GoCardlessController.FIRST_CHARGE_MAX_DAYS_AHEAD (server
// validates the same range — client picker is UX guidance, server is
// truth).
const FIRST_CHARGE_MAX_DAYS_AHEAD = 90;

// ── date helpers ────────────────────────────────────────────────────
function todayYmd() {
    const d = new Date();
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}
function ymdPlusDays(days) {
    const d = new Date();
    d.setDate(d.getDate() + days);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}
/**
 * Add `n` months to a Date preserving the "month-end snap" semantic Apex
 * uses. E.g. addMonthsSafe(Jan 31, 1) → Feb 28 (or 29 in a leap year), not
 * Mar 3 (which is what native `.setMonth` produces via overflow). Keeps the
 * client-side breakdown text in sync with what the server actually schedules.
 */
function addMonthsSafe(baseDate, n) {
    const d = new Date(baseDate.getTime());
    const day = d.getDate();
    d.setDate(1);              // avoid overflow while advancing months
    d.setMonth(d.getMonth() + n);
    const lastDayOfNewMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    d.setDate(Math.min(day, lastDayOfNewMonth));
    return d;
}

export default class AaAwardRecorder extends LightningElement {
    @api recordId;

    wiredRecord;
    awardAmount       = null;
    feeAmount         = null;
    installments      = 1;
    installmentAmount = null;
    firstChargeDate   = null;        // ISO YYYY-MM-DD from SF (Fee_First_Charge_Date__c)
    lumpSumReceived   = null;
    lastModifiedIso   = null;

    // Draft (only meaningful when editing or first-entry)
    draftAmount           = null;
    draftLumpSum          = null;
    draftIncludesVat      = false;
    draftPlan             = '1';          // lightning-radio-group values are strings
    draftOverride         = false;        // false = auto-recommend, true = manual picker
    draftFirstChargeDate  = ymdPlusDays(NOTICE_DAYS);   // default: earliest legal date
    draftConfirmUnusual   = false;        // F111: operator ticked "amount checked"
    saving                = false;
    editing               = false;        // true = show input even when awardAmount is set

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredHandler(res) {
        this.wiredRecord = res;
        if (res.data) {
            const f = res.data.fields;
            this.awardAmount       = f.Award_Amount__c?.value ?? null;
            this.feeAmount         = f.Fee_Amount__c?.value ?? null;
            this.installments      = f.Fee_Plan_Installments__c?.value ?? 1;
            this.installmentAmount = f.Fee_Plan_Installment_Amount__c?.value ?? null;
            this.firstChargeDate   = f.Fee_First_Charge_Date__c?.value || null;
            this.lumpSumReceived   = f.DWP_Lump_Sum_Received__c?.value ?? null;
            this.lastModifiedIso   = f.LastModifiedDate?.value || null;
        }
    }

    // ── first-charge date bounds + display ─────────────────────────
    get firstChargeDateMin() { return ymdPlusDays(NOTICE_DAYS); }
    get firstChargeDateMax() { return ymdPlusDays(FIRST_CHARGE_MAX_DAYS_AHEAD); }

    /**
     * Inline warning under the date picker. Only surfaces when the picked
     * date is meaningfully in the future — helps the val team catch a
     * typo before Record. Also surfaces when they pick today so the value
     * is confirmed.
     */
    get firstChargeDateFlag() {
        if (!this.draftFirstChargeDate) return '';
        const today = todayYmd();
        if (this.draftFirstChargeDate < ymdPlusDays(NOTICE_DAYS)) {
            return `The first charge must be at least ${NOTICE_DAYS} days from today so the client gets the advance notice first. The server will reject an earlier date.`;
        }
        const [y, m, d] = this.draftFirstChargeDate.split('-').map(Number);
        const picked = new Date(y, m - 1, d);
        const daysAhead = Math.round((picked - new Date(today.split('-')[0], Number(today.split('-')[1]) - 1, Number(today.split('-')[2]))) / 86400000);
        if (daysAhead > FIRST_CHARGE_MAX_DAYS_AHEAD) return `Max is ${FIRST_CHARGE_MAX_DAYS_AHEAD} days from today — the server will reject on save.`;
        if (daysAhead === NOTICE_DAYS) return '';
        return `First charge ${daysAhead} days from today. The client is emailed an advance notice ${NOTICE_DAYS} days before each collection.`;
    }

    get firstChargeDisplay() {
        if (!this.firstChargeDate) return '';
        try {
            const [y, m, d] = this.firstChargeDate.split('-').map(Number);
            const dt = new Date(y, m - 1, d);
            return dt.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
        } catch (_) { return this.firstChargeDate; }
    }

    // ── computed ─────────────────────────────────────────────────────
    get hasAward()    { return this.awardAmount !== null && this.awardAmount !== undefined && this.awardAmount !== ''; }
    get showInput()   { return !this.hasAward || this.editing; }
    get showSummary() { return this.hasAward && !this.editing; }

    // Override picker exposes all 3 options; auto-recommend chooses 1 or 3.
    get planOptionsOverride() { return PLAN_OPTIONS_OVERRIDE; }

    get draftAwardNum() {
        if (this.draftAmount === null || this.draftAmount === undefined || this.draftAmount === '') return null;
        const n = Number(this.draftAmount);
        return Number.isFinite(n) ? n : null;
    }
    get draftLumpNum() {
        if (this.draftLumpSum === null || this.draftLumpSum === undefined || this.draftLumpSum === '') return null;
        const n = Number(this.draftLumpSum);
        return Number.isFinite(n) ? n : null;
    }
    get draftValid() {
        const n = this.draftAwardNum;
        return n !== null && n > 0;
    }

    get lowFlag()  { return this.draftAwardNum !== null && this.draftAwardNum > 0     && this.draftAwardNum < LOW_THRESHOLD; }
    get highFlag() { return this.draftAwardNum !== null && this.draftAwardNum > HIGH_THRESHOLD; }
    get unusualAmount() { return this.lowFlag || this.highFlag; }

    get saveDisabled() {
        return this.saving || !this.draftValid || (this.unusualAmount && !this.draftConfirmUnusual);
    }

    get lastModifiedDisplay() { return this.fmt(this.lastModifiedIso); }

    /**
     * Draft fee — 20% of the entered award (before save). Live-updated so the
     * "lump vs fee" comparator and per-installment breakdown stay accurate.
     */
    get draftFee() {
        const n = this.draftAwardNum;
        if (n === null || n <= 0) return null;
        return feePence(n) / 100;
    }

    get draftFeeDisplay() {
        const f = this.draftFee;
        return f === null ? '' : `£${fmtMoney(f)}`;
    }

    /**
     * Auto-recommend policy (Fernando 2026-08-18):
     *   lump >= fee → single charge (1)
     *   lump <  fee → 3 monthly installments (3)
     *   lump null   → 3 monthly (default assumption: no back-payment context,
     *                 spread the fee — val team can override to single if the
     *                 client insists)
     */
    get recommendedPlan() {
        const fee  = this.draftFee;
        const lump = this.draftLumpNum;
        if (fee === null) return 1;               // no award yet
        if (lump === null) return 3;              // unknown → default spread
        return lump >= fee ? 1 : 3;
    }

    get lumpCoversFee()    { return this.draftLumpNum !== null && this.draftFee !== null && this.draftLumpNum >= this.draftFee; }
    get lumpShortByAmount() {
        if (this.draftFee === null || this.draftLumpNum === null) return null;
        const short = this.draftFee - this.draftLumpNum;
        return short > 0 ? round2(short) : 0;
    }

    get lumpCoverageMsg() {
        const fee  = this.draftFee;
        const lump = this.draftLumpNum;
        if (fee === null) return '';
        if (lump === null) return 'Client\'s back-payment covers fee?  Unknown — enter lump sum above';
        if (this.lumpCoversFee) {
            return `Client's back-payment covers fee?  YES (£${fmtMoney(lump - fee)} to spare)`;
        }
        return `Client's back-payment covers fee?  NO (short by £${fmtMoney(this.lumpShortByAmount)})`;
    }

    get recommendationHeadline() {
        if (this.draftFee === null) return '';
        if (this.recommendedPlan === 1) {
            return 'Recommended: Single charge — client\'s back-payment covers the fee';
        }
        return 'Recommended: Split in 3 monthly installments';
    }

    /**
     * Effective plan the val team is about to save. In auto mode this is
     * `recommendedPlan`; in override mode it's whatever they picked.
     */
    get effectivePlan() {
        return this.draftOverride ? (Number(this.draftPlan) || 1) : this.recommendedPlan;
    }

    /**
     * Live breakdown shown under the plan display so the val team can quote
     * the exact per-installment amount + dates on the call before saving.
     * Uses the DRAFT amount + DRAFT first-charge date so it updates
     * keystroke-by-keystroke. Mirrors the Fee_Plan_Installment_Amount__c
     * formula (rounding remainder falls on the FINAL installment) and the
     * Apex buildInstallmentRows date arithmetic (addMonthsSafe = SF
     * Date.addMonths semantics, month-end snap: Jan 31 → Feb 28).
     */
    get planBreakdown() {
        const n = this.draftAwardNum;
        if (n === null || n <= 0) return '';
        // audit 2026-10-02 F114b: integer pence with half-up division, the
        // same arithmetic as Apex buildInstallmentRows. Float round2(fee/plan)
        // disagreed with the server by a penny on odd-penny fees.
        const feeP = feePence(n);
        const plan = this.effectivePlan;
        // Anchor to draft date; fall back to the earliest legal date.
        const anchorYmd = this.draftFirstChargeDate || ymdPlusDays(NOTICE_DAYS);
        const [ay, am, ad] = anchorYmd.split('-').map(Number);
        const anchor = new Date(ay, am - 1, ad);
        const anchorLabel = anchor.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
        if (plan === 1) {
            return `You'll charge £${fmtMoney(feeP / 100)} on ${anchorLabel} in a single Direct Debit.`;
        }
        const perP = divHalfUp(feeP, plan);
        const finalP = feeP - perP * (plan - 1);
        const parts = [];
        for (let i = 0; i < plan; i++) {
            const amt = fmtMoney((i === plan - 1 ? finalP : perP) / 100);
            const d = addMonthsSafe(anchor, i);
            const dLabel = d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
            parts.push(`£${amt} on ${dLabel}`);
        }
        const spacing = plan === 2 ? 'one month apart' : `across ${plan} months`;
        return `You'll charge ${parts.join(', ')} (${spacing}, starting ${anchorLabel}).`;
    }

    /**
     * Radio options for the auto-recommend UI — narrows to just the
     * recommended plan (as the selected default) + a disabled counterpoint
     * so the val team sees the alternative was considered but rejected.
     * The "Override manually" toggle exposes the full 1/2/3 picker.
     */
    get planOptionsAuto() {
        const rec = this.recommendedPlan;
        const feeStr = this.draftFee === null ? '—' : `£${fmtMoney(this.draftFee)}`;
        if (rec === 1) {
            return [
                { label: `Single charge (${feeStr})`, value: '1' },
            ];
        }
        // rec === 3
        const per = this.draftFee === null ? null : divHalfUp(Math.round(this.draftFee * 100), 3) / 100;
        const perStr = per === null ? '—' : `£${fmtMoney(per)}`;
        return [
            { label: `Split in 3 monthly (${perStr} × 3)`, value: '3' },
        ];
    }

    /**
     * Value bound to the auto-recommend radio group. Always the recommended
     * plan — the group only shows one option, so this is really just a
     * visual anchor.
     */
    get autoPlanValue() {
        return String(this.recommendedPlan);
    }

    get overrideToggleLabel() {
        return this.draftOverride ? 'Using manual override' : 'Override plan manually';
    }

    /**
     * Summary-mode plan label. Shown above the fee amount once recorded.
     */
    get planSummary() {
        const plan = Number(this.installments) || 1;
        const per  = this.installmentAmount;
        if (plan === 1) return 'Single charge';
        const perStr = per !== null && per !== undefined ? `£${fmtMoney(per)}` : '£—';
        return `${plan} × ${perStr} monthly`;
    }

    get lumpSummary() {
        if (this.lumpSumReceived === null || this.lumpSumReceived === undefined) return 'Not recorded';
        return `£${fmtMoney(this.lumpSumReceived)}`;
    }

    // ── handlers ─────────────────────────────────────────────────────
    handleAmountChange(e) {
        this.draftAmount = e.target.value;
    }
    handleLumpSumChange(e) {
        this.draftLumpSum = e.target.value;
    }
    handleVatChange(e) {
        this.draftIncludesVat = e.target.checked;
    }
    handlePlanChange(e) {
        this.draftPlan = e.detail.value;
    }
    handleOverrideToggle(e) {
        this.draftOverride = e.target.checked;
        if (this.draftOverride) {
            // When flipping into manual override, seed the picker with the
            // current recommendation so val team doesn't accidentally save
            // a stale default.
            this.draftPlan = String(this.recommendedPlan);
        }
    }
    handleFirstChargeDateChange(e) {
        this.draftFirstChargeDate = e.target.value || ymdPlusDays(NOTICE_DAYS);
    }
    handleConfirmUnusualChange(e) {
        this.draftConfirmUnusual = e.target.checked;
    }
    handleEdit() {
        this.editing = true;
        this.draftAmount     = this.awardAmount;
        this.draftLumpSum    = this.lumpSumReceived;
        this.draftIncludesVat = false;
        this.draftOverride   = false;
        // Preserve the existing plan when re-editing (val team is usually just
        // fixing the amount, not the plan).
        this.draftPlan = String(this.installments || 1);
        // Preserve the existing first-charge date on edit unless it is now
        // inside the notice window; then default to the earliest legal date.
        const earliest = ymdPlusDays(NOTICE_DAYS);
        this.draftFirstChargeDate = (this.firstChargeDate && this.firstChargeDate >= earliest)
            ? this.firstChargeDate : earliest;
        this.draftConfirmUnusual = false;
    }
    handleCancelEdit() {
        this.editing = false;
        this.draftAmount     = null;
        this.draftLumpSum    = null;
        this.draftIncludesVat = false;
        this.draftPlan       = '1';
        this.draftOverride   = false;
        this.draftFirstChargeDate = ymdPlusDays(NOTICE_DAYS);
        this.draftConfirmUnusual = false;
    }

    async handleRecord() {
        if (!this.draftValid) return;
        this.saving = true;
        try {
            const chosenPlan = this.effectivePlan;
            const lumpArg = this.draftLumpNum;
            const r = await recordAward({
                recordId:        this.recordId,
                amount:          Number(this.draftAmount),
                installments:    chosenPlan,
                lumpSum:         lumpArg === null ? null : Number(lumpArg),
                firstChargeDate: this.draftFirstChargeDate || null,
                confirmUnusualAmount: this.unusualAmount ? this.draftConfirmUnusual : false,
            });
            if (r && r.ok) {
                // The picker only offers 1..PLAN_MAX, but the controller still
                // clamps silently (normalisePlan) for legacy/null callers. If the
                // persisted plan ever differs from what the agent chose, say so —
                // otherwise the schedule quoted on the call and the one stored
                // disagree and nothing on screen reveals it.
                const savedPlan = Number(r.installments);
                if (Number.isFinite(savedPlan) && savedPlan !== chosenPlan) {
                    this.toast('Plan adjusted by server', 'warning',
                        `You chose ${chosenPlan} installment(s) but ${savedPlan} were stored (AA maximum is ${PLAN_MAX}). Confirm the stored plan with the client.`);
                }
                const feeMsg = r.fee_amount !== undefined
                    ? ` Fee snapshotted at £${Number(r.fee_amount).toFixed(2)}` +
                      (r.installments > 1
                          ? ` (${r.installments} × £${Number(r.installment_amount).toFixed(2)} monthly).`
                          : ' (single charge).')
                    : '';
                this.toast('Award recorded', 'success', 'Stage advanced.' + feeMsg);
                this.editing = false;
                this.draftAmount     = null;
                this.draftLumpSum    = null;
                this.draftIncludesVat = false;
                this.draftPlan       = '1';
                this.draftOverride   = false;
                this.draftFirstChargeDate = ymdPlusDays(NOTICE_DAYS);
                this.draftConfirmUnusual = false;
                await refreshApex(this.wiredRecord);
            } else {
                this.toast('Record award failed', 'error', 'Controller returned ok=false');
            }
        } catch (err) {
            this.toast('Record award failed', 'error', this.errMsg(err));
        } finally {
            this.saving = false;
        }
    }

    // ── util ─────────────────────────────────────────────────────────
    fmt(iso) {
        if (!iso) return '';
        try {
            return new Date(iso).toLocaleString('en-GB', {
                day: '2-digit', month: '2-digit', year: 'numeric',
                hour: '2-digit', minute: '2-digit',
                timeZone: 'Europe/London',
            });
        } catch (_) { return iso; }
    }
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}

function round2(n) {
    return Math.round(Number(n) * 100) / 100;
}
// Integer-pence helpers mirroring Apex Decimal.setScale(2, HALF_UP).
// Award amounts carry at most 2 decimals, so Math.round(award*100) is exact.
function divHalfUp(a, b) {
    return Math.floor((2 * a + b) / (2 * b));   // positive integers only
}
function feePence(award) {
    const awardP = Math.round(Number(award) * 100);
    return divHalfUp(awardP * FEE_RATE_PCT, 100);
}
function fmtMoney(n) {
    return Number(n).toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}