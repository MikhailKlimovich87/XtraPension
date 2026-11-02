/**
 * pc1FeeChargeConfirmModal — safety dialog before triggering fee charge.
 *
 * Opened by pc1FeeChargeCard via LightningModal.open({ ... }); returns
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

export default class Pc1FeeChargeConfirmModal extends LightningModal {
    @api feeAmount;                // total fee (all installments)
    @api firstInstallmentAmount;   // amount fired NOW
    @api awardAmount;
    @api clientName;
    @api installments = 1;         // 1 / 2 / 3

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
        const base = new Date();
        const labels = [];
        for (let i = 1; i <= n; i++) {
            const d = new Date(base);
            d.setMonth(d.getMonth() + i);
            labels.push(d.toLocaleDateString('en-GB', {
                day: '2-digit', month: 'short', year: 'numeric',
                timeZone: 'Europe/London',
            }));
        }
        return labels.join(', ');
    }

    get confirmLabel() {
        return this.multiInstallment
            ? `Charge installment 1 of ${this.installments}`
            : 'Confirm Charge';
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