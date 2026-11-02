/**
 * pc1FeeChargeCard — collect the 20% fee via GoCardless. Fee rate changed
 * 25% → 20% on 2026-08-18 (Fernando).
 *
 * The card is intentionally read-only until every gate is green:
 *   1. Mandate active            — DD_Mandate_Status__c = 'active'
 *   2. Award amount recorded     — Award_Amount__c not null
 *   3. Not already charged       — Fee_Payment_Id__c is empty (installment #1
 *                                  id lives here for backward compat with the
 *                                  pre-plan single-charge flow)
 *
 * When all three are green, the "Charge Fee £X" button opens a
 * lightning-modal (pc1FeeChargeConfirmModal). The modal returns 'confirm'
 * only when both checkboxes are ticked, then this component calls
 * PC1_GoCardlessController.chargeFee(recordId).
 *
 * Payment plan (2026-08-18): if Fee_Plan_Installments__c > 1, the CTA is
 * relabelled "Charge installment 1 of N" and the amount displayed is the
 * PER-INSTALLMENT amount, not the total. The remaining installments are
 * fired automatically by PC1_FeeInstallmentScheduler (daily 08:00 UTC).
 *
 * If the fee has already been charged (Fee_Payment_Id__c populated), the
 * card renders the total fee, plan summary, next-charge date, and
 * installment #1 payment id + status + charge date instead of the CTA.
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import chargeFee from '@salesforce/apex/PC1_GoCardlessController.chargeFee';
import Pc1FeeChargeConfirmModal from 'c/pc1FeeChargeConfirmModal';

const FIELDS = [
    'PC1_Application__c.DD_Mandate_Status__c',
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
function todayYmd() {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export default class Pc1FeeChargeCard extends LightningElement {
    @api recordId;

    wiredRecord;
    mandateStatus    = '';
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
    get mandateActive() { return this.mandateStatus === 'active'; }
    get awardRecorded() { return this.awardAmount !== null && this.awardAmount !== undefined && this.awardAmount !== ''; }
    get notCharged()    { return !this.feePaymentId; }

    get alreadyCharged() { return !!this.feePaymentId; }

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
        if (!this.mandateActive) return 'DD mandate is not active yet — cannot charge.';
        if (!this.awardRecorded) return 'Award amount not recorded yet.';
        if (!this.notCharged)    return 'Fee has already been charged for this application.';
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
    // ── deferred-charge helpers ────────────────────────────────────
    /**
     * `true` when the agent chose a first-charge date that hasn't arrived
     * yet. The CTA relabels and the modal copy calls out the deferral —
     * important because the button no longer fires today, it just registers
     * the schedule with the daily sweeper.
     */
    get isDeferred() {
        if (!this.firstChargeDate) return false;
        return this.firstChargeDate > todayYmd();
    }
    get firstChargeDateDisplay() {
        if (!this.firstChargeDate) return '';
        try {
            const [y, m, d] = this.firstChargeDate.split('-').map(Number);
            return new Date(y, m - 1, d).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
        } catch (_) { return this.firstChargeDate; }
    }
    get ctaLabel() {
        if (this.isDeferred) {
            return this.multiInstallment
                ? `Schedule 6-part fee (starts ${this.firstChargeDateDisplay})`.replace('6-part', `${this.installmentsCount}-part`)
                : `Schedule fee for ${this.firstChargeDateDisplay}`;
        }
        return this.multiInstallment
            ? `Charge installment 1 of ${this.installmentsCount}`
            : 'Charge Fee';
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
        // Falls back to today when the field isn't populated yet (pre-Record
        // preview). Uses addMonthsSafe to match the SF Apex Date.addMonths
        // month-end snap semantics — otherwise Jan 31 renders as Mar 3 here
        // but the server schedules Feb 28 and the preview lies.
        const n = this.installmentsCount;
        if (n <= 1) return '';
        const anchorYmd = this.firstChargeDate || todayYmd();
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
        });
        if (result !== 'confirm') return;
        await this.doCharge();
    }

    async doCharge() {
        this.charging = true;
        try {
            const r = await chargeFee({ recordId: this.recordId });
            if (r && r.ok) {
                if (r.deferred) {
                    const firstCharge = r.first_charge_date ? this.fmtDate(r.first_charge_date) : 'TBD';
                    const planTail = (r.installments && r.installments > 1)
                        ? ` — schedule of ${r.installments} monthly, first on ${firstCharge}`
                        : ` — scheduled for ${firstCharge}`;
                    this.toast(
                        'Fee charge scheduled',
                        'success',
                        `Client mandate on record. Daily sweeper will attempt DD on the scheduled date${planTail}. Client gets a 5-day-advance email before each charge.`
                    );
                } else {
                    const chargeDate = r.charge_date ? ` (settles ${r.charge_date})` : '';
                    const planTail = (r.installments && r.installments > 1)
                        ? ` — installment 1 of ${r.installments}, next on ${this.fmtDate(r.next_charge_date) || 'TBD'}`
                        : '';
                    this.toast(
                        'Fee charge submitted',
                        'success',
                        `Payment ${r.payment_id || ''}${chargeDate}${planTail}`
                    );
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