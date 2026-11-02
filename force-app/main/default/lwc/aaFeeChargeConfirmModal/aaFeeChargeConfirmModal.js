/**
 * aaFeeChargeConfirmModal — safety dialog before triggering fee charge.
 *
 * Opened by aaFeeChargeCard via LightningModal.open({ ... }); returns
 * 'confirm' when both required checkboxes are ticked and the user clicks
 * Confirm, otherwise closes with 'cancel'. The parent handles the actual
 * chargeFee Apex call — this component is UI only.
 *
 * Since 2026-08-18 the modal is plan-aware: it displays the per-installment
 * amount as the headline "charge now" figure and lists the remaining
 * installment dates so the val team knows exactly what will fire when.
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class AaFeeChargeConfirmModal extends LightningModal {
    @api feeAmount;                // total fee (all installments)
    @api firstInstallmentAmount;   // amount fired NOW
    @api awardAmount;
    @api clientName;
    @api installments = 1;         // 1 / 2 / 3
    @api firstChargeDate;          // 'YYYY-MM-DD' first collection date (never sooner than today+5)

    verifiedAmount = false;
    understandIrreversible = false;

    get multiInstallment() { return Number(this.installments) > 1; }
    get remainingCount()   { return Math.max(0, (Number(this.installments) || 1) - 1); }
    get remainingPlural()  { return this.remainingCount !== 1; }

    /**
     * Approximate dates for installments 2..N — actual dates snap to the
     * scheduler's daily 08:00 UTC sweep after each Charged_At__c stamp; this
     * label is a preview only, so day precision is enough.
     */
    get remainingDates() {
        const n = this.remainingCount;
        if (n <= 0) return '';
        // audit #88: base off the deferred first-charge date when the parent passes
        // one (installments 2..N are relative to installment 1's charge), else today.
        const parsed = this.firstChargeDate ? this.parseYmd(this.firstChargeDate) : null;
        const base = (parsed && !isNaN(parsed.getTime())) ? parsed : new Date();
        const labels = [];
        for (let i = 1; i <= n; i++) {
            // audit #88: naive setMonth overflows (31 Jan + 1 month → 3 Mar). Clamp
            // to the target month's last valid day.
            const d = this.addMonths(base, i);
            labels.push(d.toLocaleDateString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric',
                timeZone: 'Europe/London',
            }));
        }
        return labels.join(', ');
    }

    // 'YYYY-MM-DD' as a LOCAL date: new Date('2026-10-07') is UTC midnight,
    // which renders as the previous day west of UTC.
    parseYmd(ymd) {
        const [y, m, d] = String(ymd).slice(0, 10).split('-').map(Number);
        return new Date(y, m - 1, d);
    }
    get firstChargeDateDisplay() {
        if (!this.firstChargeDate) return '';
        return this.parseYmd(this.firstChargeDate).toLocaleDateString('en-GB', {
            day: '2-digit', month: 'short', year: 'numeric',
        });
    }

    addMonths(date, n) {
        const d = new Date(date);
        d.setDate(1);                          // avoid rollover while shifting month
        d.setMonth(d.getMonth() + n);
        const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
        d.setDate(Math.min(date.getDate(), lastDay));
        return d;
    }

    get confirmLabel() {
        return this.multiInstallment
            ? `Schedule ${this.installments} payments`
            : 'Schedule collection';
    }

    get canConfirm() {
        return this.verifiedAmount && this.understandIrreversible;
    }
    get canConfirmDisabled() {
        return !this.canConfirm;
    }

    handleVerifiedChange(e) {
        this.verifiedAmount = e.target.checked;
    }
    handleIrreversibleChange(e) {
        this.understandIrreversible = e.target.checked;
    }

    handleCancel() {
        this.close('cancel');
    }
    handleConfirm() {
        if (!this.canConfirm) return;
        this.close('confirm');
    }
}