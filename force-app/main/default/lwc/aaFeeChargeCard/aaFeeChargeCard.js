/**
 * aaFeeChargeCard — collect the 20% fee via GoCardless. Fee rate changed
 * 25% → 20% on 2026-08-18 (Fernando).
 *
 * The card is intentionally read-only until every gate is green:
 *   1. Mandate active            — DD_Mandate_Status__c = 'active'
 *   2. Award amount recorded     — Award_Amount__c not null
 *   3. Not already scheduled     — no AA_Fee_Installment__c rows and no
 *                                  Fee_Payment_Id__c (legacy single charge)
 *
 * When all three are green, the "Schedule…" button opens a lightning-modal
 * (aaFeeChargeConfirmModal). The modal returns 'confirm' only when both
 * checkboxes are ticked, then this component calls
 * AA_GoCardlessController.chargeFee(recordId).
 *
 * Since audit 2026-10-02 (F101/F79) the button never collects on the spot:
 * the first collection is at least 5 calendar days out, the client is
 * emailed a Bacs advance notice 5 days before each collection, and
 * AA_FeeInstallmentScheduler (daily, 08:00 UK time) creates each payment
 * at GoCardless for the date the notice gave.
 *
 * Once a plan exists the card lists every instalment (date, amount, status,
 * notice) and offers "Retry" on a failed or cancelled one (audit 2026-10-02
 * F110: a failed instalment could not be re-collected in the system).
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import chargeFee from '@salesforce/apex/AA_GoCardlessController.chargeFee';
import getFeeInstallments from '@salesforce/apex/AA_GoCardlessController.getFeeInstallments';
import retryInstallment from '@salesforce/apex/AA_GoCardlessController.retryInstallment';
import AaFeeChargeConfirmModal from 'c/aaFeeChargeConfirmModal';

// Mirrors AA_FeeInstallmentScheduler.NOTICE_DAYS (5 calendar days).
const NOTICE_DAYS = 5;
const ROW_STATUS_LABEL = {
    pending:   'Scheduled',
    submitted: 'With the bank',
    paid:      'Collected',
    failed:    'Failed',
    cancelled: 'Cancelled',
    // Do Not Contact hold, set by the daily sweep (wave 4). Lowercase API
    // name, like the other values.
    paused:    'Paused: Do Not Contact',
};

const FIELDS = [
    'AA_Application__c.DD_Mandate_Status__c',
    'AA_Application__c.DD_Mandate_Id__c',
    'AA_Application__c.Award_Amount__c',
    'AA_Application__c.Fee_Amount__c',
    'AA_Application__c.Fee_Plan_Installments__c',
    'AA_Application__c.Fee_Plan_Installment_Amount__c',
    'AA_Application__c.Fee_Plan_Next_Charge_Date__c',
    'AA_Application__c.Fee_First_Charge_Date__c',
    'AA_Application__c.Fee_Payment_Id__c',
    'AA_Application__c.Fee_Payment_Status__c',
    'AA_Application__c.Fee_Charged_At__c',
    'AA_Application__c.Full_Name__c',
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
function ymdPlusDays(days) {
    const d = new Date();
    d.setDate(d.getDate() + days);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

export default class AaFeeChargeCard extends LightningElement {
    @api recordId;

    wiredRecord;
    mandateStatus    = '';
    mandateId        = '';
    awardAmount      = null;
    feeAmount        = null;
    installments     = 1;
    installmentAmount = null;
    nextChargeDate   = null;
    firstChargeDate  = null;   // ISO YYYY-MM-DD; agent-chosen on aaAwardRecorder
    feePaymentId     = '';
    feePaymentStatus = '';
    feeChargedAt     = null;
    clientName       = '';

    charging = false;
    retryingId = null;
    wiredInstallments;
    installmentRows = [];

    @wire(getFeeInstallments, { recordId: '$recordId' })
    wiredInstallmentsHandler(res) {
        this.wiredInstallments = res;
        if (res.data) {
            this.installmentRows = res.data.map((r) => ({
                id:          r.id,
                number:      r.number,
                dateDisplay: this.fmtDate(r.scheduled_date),
                amount:      r.amount,
                // Do Not Contact pauses collection (owner decision 2026-10-02).
                // The daily sweep stores it as 'paused'; until it runs a newly
                // flagged row is still 'pending', so paused_dnc covers both.
                // A row already created at GoCardless (dnc_at_gc) is NOT
                // paused: it will be collected unless ops cancels it there,
                // so it must never read "Paused" (integrator 2026-10-02).
                // 'resuming' = flag cleared, 'pending' again at the next run.
                statusLabel: r.dnc_at_gc ? 'Will be collected: cancel it at GoCardless'
                    : (r.paused_dnc ? 'Paused: Do Not Contact'
                        : (r.resuming ? 'Resuming' : (ROW_STATUS_LABEL[r.status] || r.status))),
                noticeLabel: r.dnc_at_gc ? 'Already set up at GoCardless, see the handoff'
                    : (r.paused_dnc ? ''
                        : (r.resuming ? 'A fresh notice goes out at the next daily run'
                            : (r.notice_sent ? 'Notice sent' : (r.status === 'pending' ? 'Notice not sent yet' : '')))),
                // Drives the "collection is paused" banner: true for an
                // at-GoCardless row too, since the client is Do Not Contact.
                paused:      r.paused_dnc === true || r.dnc_at_gc === true,
                canRetry:    r.can_retry === true,
            }));
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredHandler(res) {
        this.wiredRecord = res;
        if (res.data) {
            const f = res.data.fields;
            this.mandateStatus     = f.DD_Mandate_Status__c?.value || '';
            this.mandateId         = f.DD_Mandate_Id__c?.value || '';
            this.awardAmount      = f.Award_Amount__c?.value ?? null;
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
    // mandate id is still blank (mandate document pending, audit F103), and
    // Heroku refuses every charge for such a record (wave-2 W1).
    get mandateActive() { return this.mandateStatus === 'active' && !!this.mandateId; }
    get awardRecorded() { return this.awardAmount !== null && this.awardAmount !== undefined && this.awardAmount !== ''; }
    get hasPlan()       { return this.installmentRows.length > 0; }
    get pausedDnc()     { return this.installmentRows.some((r) => r.paused); }
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
            ? 'aa-feecharge__gate aa-feecharge__gate--ok'
            : 'aa-feecharge__gate aa-feecharge__gate--bad';
    }

    get mandateGateIcon() { return this.mandateActive ? 'utility:success' : 'utility:close'; }
    get awardGateIcon()   { return this.awardRecorded  ? 'utility:success' : 'utility:close'; }
    get notChargedIcon()  { return this.notCharged     ? 'utility:success' : 'utility:close'; }

    get chargeDisabled() { return !this.allGatesGreen || this.charging; }

    get chargeTooltip() {
        if (this.mandateStatus === 'active' && !this.mandateId) {
            return 'The Direct Debit document has not arrived yet. Click "Retry mandate document" on the Direct Debit card.';
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
     * The date the server will actually use for instalment #1: the recorded
     * first-charge date, but never sooner than today + NOTICE_DAYS (chargeFee
     * moves a closer date forward, audit 2026-10-02 F101).
     */
    get effectiveFirstChargeDate() {
        const earliest = ymdPlusDays(NOTICE_DAYS);
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
        // Falls back to today when the field isn't populated yet (pre-Record
        // preview). Uses addMonthsSafe to match the SF Apex Date.addMonths
        // month-end snap semantics — otherwise Jan 31 renders as Mar 3 here
        // but the server schedules Feb 28 and the preview lies.
        const n = this.installmentsCount;
        if (n <= 1) return '';
        const anchorYmd = this.effectiveFirstChargeDate || todayYmd();
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
        const result = await AaFeeChargeConfirmModal.open({
            size:          'small',
            description:   'Confirm fee charge',
            feeAmount:     this.feeAmount,
            firstInstallmentAmount: this.firstInstallmentAmount,
            awardAmount:   this.awardAmount,
            clientName:    this.clientName,
            installments:  this.installmentsCount,
            // audit 2026-10-02 F113: without this the modal counted the
            // remaining dates from today, not from the first charge date.
            firstChargeDate: this.effectiveFirstChargeDate,
        });
        if (result !== 'confirm') return;
        await this.doCharge();
    }

    async handleRetry(event) {
        const id = event.currentTarget.dataset.id;
        const ok = await LightningConfirm.open({
            label: 'Retry this instalment?',
            message: 'Only continue if you have spoken to the client and they agree. They will be emailed an advance '
                + `notice today, and the payment will be collected ${NOTICE_DAYS} days from now.`,
            theme: 'warning',
        });
        if (!ok) return;
        this.retryingId = id;
        try {
            const r = await retryInstallment({ installmentId: id });
            const when = r && r.charge_date ? this.fmtDate(r.charge_date) : `in ${NOTICE_DAYS} days`;
            if (r && r.notice_sent) {
                this.toast('Instalment rescheduled', 'success', `Advance notice sent. It will be collected on ${when}.`);
            } else {
                this.toast('Instalment rescheduled', 'warning',
                    `It is now due on ${when}, but the advance notice could not be sent yet (check the Bacs advance notice template is active). Nothing is collected until it is.`);
            }
            await refreshApex(this.wiredInstallments);
            await refreshApex(this.wiredRecord);
        } catch (err) {
            this.toast('Retry failed', 'error', this.errMsg(err));
        } finally {
            this.retryingId = null;
        }
    }
    get retryDisabled() { return !!this.retryingId; }

    async doCharge() {
        this.charging = true;
        try {
            const r = await chargeFee({ recordId: this.recordId });
            if (r && r.ok) {
                const firstCharge = r.first_charge_date ? this.fmtDate(r.first_charge_date) : 'TBD';
                const plan = (r.installments && r.installments > 1)
                    ? `${r.installments} monthly payments, the first on ${firstCharge}.`
                    : `One payment on ${firstCharge}.`;
                const notice = r.notice_sent
                    ? ' The advance notice for the first payment has been emailed to the client.'
                    : ` The client is emailed an advance notice ${NOTICE_DAYS} days before each payment.`;
                this.toast(r.existed ? 'Fee already scheduled' : 'Fee collection scheduled', 'success', plan + notice);
                await refreshApex(this.wiredInstallments);
                await refreshApex(this.wiredRecord);
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