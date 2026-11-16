/**
 * pc1FeeChargeCard — collect the 20% fee via GoCardless. Fee rate changed
 * 25% → 20% on 2026-08-18 (Fernando).
 *
 * The card is intentionally read-only until every gate is green:
 *   1. Mandate active            — DD_Mandate_Status__c = 'active' and a
 *                                  DD_Mandate_Id__c on the record
 *   2. Award amount recorded     — Award_Amount__c not null
 *   3. Not already scheduled     — no plan registered yet
 *                                  (Fee_Plan_Next_Charge_Date__c empty) and
 *                                  Fee_Payment_Id__c empty (installment #1 id
 *                                  lives there once it is at GoCardless)
 *
 * When all three are green, the "Schedule…" button opens a lightning-modal
 * (pc1FeeChargeConfirmModal). The modal returns 'confirm' only when both
 * checkboxes are ticked, then this component calls
 * PC1_GoCardlessController.chargeFee(recordId).
 *
 * Since the 2026-11-11 audit (PC-APEX-4 / PC-SFUI-4, port of the AA card)
 * the button never collects on the spot: chargeFee registers the plan with
 * installment 1 on the recorded first-charge date, never sooner than
 * today + FIRST_CHARGE_MIN_DAYS, emails the Bacs advance notice, and
 * PC1_FeeInstallmentScheduler (daily) creates each payment at GoCardless for
 * the date its notice gave. If Fee_Plan_Installments__c > 1 the amount shown
 * is the PER-INSTALLMENT amount, not the total.
 *
 * Once a plan exists the card renders the total fee, plan summary, next
 * charge date and (when there is one) installment #1's payment id instead of
 * the CTA; pc1FeeInstallments below lists every installment.
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import chargeFee from '@salesforce/apex/PC1_GoCardlessController.chargeFee';
import Pc1FeeChargeConfirmModal from 'c/pc1FeeChargeConfirmModal';

const FIELDS = [
    'PC1_Application__c.DD_Mandate_Status__c',
    'PC1_Application__c.DD_Mandate_Id__c',
    'PC1_Application__c.Award_Amount__c',
    'PC1_Application__c.Fee_Amount__c',
    'PC1_Application__c.Fee_Plan_Installments__c',
    'PC1_Application__c.Fee_Plan_Installment_Amount__c',
    'PC1_Application__c.Fee_Plan_Next_Charge_Date__c',
    'PC1_Application__c.Fee_First_Charge_Date__c',
    'PC1_Application__c.Fee_Payment_Id__c',
    'PC1_Application__c.Fee_Payment_Status__c',
    'PC1_Application__c.Fee_Charged_At__c',
    'PC1_Application__c.Full_Name__c',
];

/**
 * addMonthsSafe — replicate SF Apex Date.addMonths month-end semantics on
 * the client so the "next charge dates" preview matches what the server
 * actually schedules. Native .setMonth overflows (Jan 31 + 1 month → Mar 3);
 * this version snaps to the last day of the target month (Jan 31 + 1 → Feb 28).
 */
function addMonthsSafe(baseDate, n) {
    const d = new Date(baseDate.getTime());
    const day = d.getDate();
    d.setDate(1);
    d.setMonth(d.getMonth() + n);
    const lastDayOfNewMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    d.setDate(Math.min(day, lastDayOfNewMonth));
    return d;
}
function ymdPlusDays(days) {
    const d = new Date();
    d.setDate(d.getDate() + days);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// Mirror PC1_FeeInstallmentScheduler.NOTICE_DAYS (5 calendar days of advance
// notice) and PC1_GoCardlessController.FIRST_CHARGE_MIN_DAYS (notice + 1 day:
// the payment is created by the next morning's sweep).
const NOTICE_DAYS = 5;
const FIRST_CHARGE_MIN_DAYS = NOTICE_DAYS + 1;

export default class Pc1FeeChargeCard extends LightningElement {
    @api recordId;

    wiredRecord;
    mandateStatus    = '';
    mandateId        = '';
    awardAmount      = null;
    feeAmount        = null;
    installments     = 1;
    installmentAmount = null;
    nextChargeDate   = null;
    firstChargeDate  = null;   // ISO YYYY-MM-DD; agent-chosen on pc1AwardRecorder
    feePaymentId     = '';
    feePaymentStatus = '';
    feeChargedAt     = null;
    clientName       = '';

    charging = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredHandler(res) {
        this.wiredRecord = res;
        if (res.data) {
            const f = res.data.fields;
            this.mandateStatus     = f.DD_Mandate_Status__c?.value || '';
            this.mandateId         = f.DD_Mandate_Id__c?.value || '';
            this.awardAmount       = f.Award_Amount__c?.value ?? null;
            this.feeAmount         = f.Fee_Amount__c?.value ?? null;
            this.installments      = f.Fee_Plan_Installments__c?.value ?? 1;
            this.installmentAmount = f.Fee_Plan_Installment_Amount__c?.value ?? null;
            this.nextChargeDate    = f.Fee_Plan_Next_Charge_Date__c?.value || null;
            this.firstChargeDate   = f.Fee_First_Charge_Date__c?.value || null;
            this.feePaymentId      = f.Fee_Payment_Id__c?.value || '';
            this.feePaymentStatus  = f.Fee_Payment_Status__c?.value || '';
            this.feeChargedAt      = f.Fee_Charged_At__c?.value || null;
            this.clientName        = f.Full_Name__c?.value || 'the client';
        }
    }

    // ── gates ────────────────────────────────────────────────────────
    // Status alone is not enough: the webhook can set 'active' while the
    // mandate id is still blank (mandate document pending), and chargeFee
    // refuses to schedule for such a record.
    get mandateActive() { return this.mandateStatus === 'active' && !!this.mandateId; }
    get awardRecorded() { return this.awardAmount !== null && this.awardAmount !== undefined && this.awardAmount !== ''; }
    // chargeFee stamps Fee_Plan_Next_Charge_Date__c when it registers the plan;
    // Fee_Payment_Id__c only arrives when the sweep creates installment 1.
    get hasPlan()       { return !!this.nextChargeDate; }
    get notCharged()    { return !this.feePaymentId && !this.hasPlan; }

    get alreadyCharged() { return !this.notCharged; }
    get bannerLabel()    { return this.feePaymentId ? 'Collection started' : 'Collection scheduled'; }

    get allGatesGreen() {
        return this.mandateActive && this.awardRecorded && this.notCharged;
    }

    get mandateGateClass() { return this.gateClass(this.mandateActive); }
    get awardGateClass()   { return this.gateClass(this.awardRecorded); }
    get notChargedClass()  { return this.gateClass(this.notCharged); }
    gateClass(ok) {
        return ok
            ? 'pc1-feecharge__gate pc1-feecharge__gate--ok'
            : 'pc1-feecharge__gate pc1-feecharge__gate--bad';
    }

    get mandateGateIcon() { return this.mandateActive ? 'utility:success' : 'utility:close'; }
    get awardGateIcon()   { return this.awardRecorded  ? 'utility:success' : 'utility:close'; }
    get notChargedIcon()  { return this.notCharged     ? 'utility:success' : 'utility:close'; }

    get chargeDisabled() { return !this.allGatesGreen || this.charging; }

    get chargeTooltip() {
        if (this.mandateStatus === 'active' && !this.mandateId) {
            return 'The Direct Debit document has not arrived yet, so no fee can be scheduled. Try again in a few minutes.';
        }
        if (!this.mandateActive) return 'DD mandate is not active yet — cannot charge.';
        if (!this.awardRecorded) return 'Award amount not recorded yet.';
        if (!this.notCharged)    return 'The fee is already scheduled for this application.';
        return '';
    }

    get chargedAtDisplay() { return this.fmt(this.feeChargedAt); }

    // ── payment plan helpers ────────────────────────────────────────
    get installmentsCount() { return Number(this.installments) || 1; }
    get multiInstallment()  { return this.installmentsCount > 1; }
    get firstInstallmentAmount() {
        return this.installmentAmount !== null && this.installmentAmount !== undefined
            ? this.installmentAmount
            : this.feeAmount;
    }
    // ── scheduling helpers ─────────────────────────────────────────
    /**
     * The date the server will actually use for installment #1: the recorded
     * first-charge date, but never sooner than today + FIRST_CHARGE_MIN_DAYS
     * (chargeFee moves a closer, past or missing date forward and writes it
     * back). The modal and the dates below are all counted from this one.
     */
    get effectiveFirstChargeDate() {
        const earliest = ymdPlusDays(FIRST_CHARGE_MIN_DAYS);
        return (this.firstChargeDate && this.firstChargeDate >= earliest) ? this.firstChargeDate : earliest;
    }
    get firstChargeDateDisplay() {
        const ymd = this.effectiveFirstChargeDate;
        try {
            const [y, m, d] = ymd.split('-').map(Number);
            return new Date(y, m - 1, d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
        } catch (_) { return ymd; }
    }
    get ctaLabel() {
        return this.multiInstallment
            ? `Schedule ${this.installmentsCount} monthly payments (first on ${this.firstChargeDateDisplay})`
            : `Schedule fee collection for ${this.firstChargeDateDisplay}`;
    }
    get planSummary() {
        const n = this.installmentsCount;
        if (n <= 1) return 'Single charge';
        const per = this.installmentAmount;
        const perStr = per !== null && per !== undefined ? `£${fmtMoney(per)}` : '£—';
        return `${n} × ${perStr} monthly`;
    }
    get remainingLabels() {
        // Human-readable list of scheduled charge dates for installments 2..N,
        // anchored to the agent-chosen first-charge date (Fee_First_Charge_Date__c)
        // so the val team sees the actual schedule the server will register.
        // Falls back to the earliest date the server accepts when the field
        // isn't populated yet or is sooner than that. Uses addMonthsSafe to
        // match the SF Apex Date.addMonths
        // month-end snap semantics — otherwise Jan 31 renders as Mar 3 here
        // but the server schedules Feb 28 and the preview lies.
        const n = this.installmentsCount;
        if (n <= 1) return '';
        const anchorYmd = this.effectiveFirstChargeDate;
        const [ay, am, ad] = anchorYmd.split('-').map(Number);
        const base = new Date(ay, am - 1, ad);
        const labels = [];
        for (let i = 1; i < n; i++) {
            const d = addMonthsSafe(base, i);
            labels.push(this.fmtDate(d.toISOString()));
        }
        return labels.join(', ');
    }
    get nextChargeDisplay() { return this.nextChargeDate ? this.fmtDate(this.nextChargeDate) : ''; }

    get prettyPaymentStatus() {
        const s = this.feePaymentStatus || '';
        if (!s) return '';
        const spaced = s.replace(/_/g, ' ');
        return spaced.charAt(0).toUpperCase() + spaced.slice(1);
    }

    get maskedPaymentId() {
        const id = this.feePaymentId || '';
        if (id.length <= 8) return id;
        return '…' + id.slice(-8);
    }

    // ── actions ──────────────────────────────────────────────────────
    async handleChargeClick() {
        if (!this.allGatesGreen) return;
        const result = await Pc1FeeChargeConfirmModal.open({
            size:          'small',
            description:   'Confirm fee charge',
            feeAmount:     this.feeAmount,
            firstInstallmentAmount: this.firstInstallmentAmount,
            awardAmount:   this.awardAmount,
            clientName:    this.clientName,
            installments:  this.installmentsCount,
            // Without this the modal counted the remaining dates from today
            // with no month-end clamp, whatever first date was recorded
            // (audit 2026-11-11 PC-SFUI-4).
            firstChargeDate: this.effectiveFirstChargeDate,
        });
        if (result !== 'confirm') return;
        await this.doCharge();
    }

    async doCharge() {
        this.charging = true;
        try {
            const r = await chargeFee({ recordId: this.recordId });
            if (r && r.ok) {
                if (r.existed && r.payment_id) {
                    // Installment 1 was already at GoCardless: nothing new was scheduled.
                    this.toast('Fee already scheduled', 'success', `Payment ${r.payment_id} is already with GoCardless.`);
                } else {
                    const firstCharge = r.first_charge_date ? this.fmtDate(r.first_charge_date) : 'TBD';
                    const plan = (r.installments && r.installments > 1)
                        ? `${r.installments} monthly payments, the first on ${firstCharge}.`
                        : `One payment on ${firstCharge}.`;
                    const notice = r.notice_sent
                        ? ' The advance notice for the first payment has been emailed to the client.'
                        : ` The client is emailed an advance notice at least ${NOTICE_DAYS} days before each payment.`;
                    this.toast(r.existed ? 'Fee already scheduled' : 'Fee collection scheduled', 'success', plan + notice);
                }
                await refreshApex(this.wiredRecord);
                const list = this.template.querySelector('c-pc1-fee-installments');
                if (list) await list.refresh();
            } else {
                this.toast('Charge failed', 'error', 'Controller returned ok=false');
            }
        } catch (err) {
            this.toast('Charge failed', 'error', this.errMsg(err));
        } finally {
            this.charging = false;
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
    fmtDate(iso) {
        if (!iso) return '';
        try {
            return new Date(iso).toLocaleDateString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric',
                timeZone: 'Europe/London',
            });
        } catch (_) { return iso; }
    }
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}

function fmtMoney(n) {
    return Number(n).toLocaleString('en-GB', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}