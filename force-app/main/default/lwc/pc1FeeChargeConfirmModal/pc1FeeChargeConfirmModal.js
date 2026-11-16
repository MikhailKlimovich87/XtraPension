/**
 * pc1FeeChargeConfirmModal — safety dialog before scheduling the fee.
 *
 * Opened by pc1FeeChargeCard via LightningModal.open({ ... }); returns
 * 'confirm' when both required checkboxes are ticked and the user clicks
 * Confirm, otherwise closes with 'cancel'. The parent handles the actual
 * chargeFee Apex call — this component is UI only.
 *
 * Since 2026-08-18 the modal is plan-aware: it displays the per-installment
 * amount as the headline figure and lists the remaining installment dates
 * so the val team knows exactly what will be collected when. Nothing is
 * collected on the day (audit 2026-11-11): the headline names the date of
 * the first payment, which the parent card passes in.
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class Pc1FeeChargeConfirmModal extends LightningModal {
    @api feeAmount;                // total fee (all installments)
    @api firstInstallmentAmount;   // amount of the first payment
    @api awardAmount;
    @api clientName;
    @api installments = 1;         // 1 / 2 / 3
    @api firstChargeDate;          // 'YYYY-MM-DD' first collection date (never sooner than today + 6)

    verifiedAmount = false;
    understandIrreversible = false;

    get multiInstallment() { return Number(this.installments) > 1; }
    get remainingCount()   { return Math.max(0, (Number(this.installments) || 1) - 1); }
    get remainingPlural()  { return this.remainingCount !== 1; }

    /**
     * Dates of installments 2..N: first charge date + 1..N-1 months, the
     * same arithmetic as buildInstallmentRows in PC1_GoCardlessController
     * (Date.addMonths, month-end snap). Ported from aaFeeChargeConfirmModal:
     * this used to count from today with setMonth, so a deferred plan and a
     * 31st showed dates the server does not use (audit 2026-11-11 PC-SFUI-4).
     */
    get remainingDates() {
        const n = this.remainingCount;
        if (n <= 0) return '';
        const parsed = this.firstChargeDate ? this.parseYmd(this.firstChargeDate) : null;
        const base = (parsed && !isNaN(parsed.getTime())) ? parsed : new Date();
        const labels = [];
        for (let i = 1; i <= n; i++) {
            const d = this.addMonths(base, i);
            labels.push(d.toLocaleDateString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric',
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
    addMonths(date, n) {
        const d = new Date(date);
        d.setDate(1);                          // avoid rollover while shifting month
        d.setMonth(d.getMonth() + n);
        const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
        d.setDate(Math.min(date.getDate(), lastDay));
        return d;
    }
    get firstChargeDateDisplay() {
        if (!this.firstChargeDate) return '';
        return this.parseYmd(this.firstChargeDate).toLocaleDateString('en-GB', {
            day: '2-digit', month: 'short', year: 'numeric',
        });
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