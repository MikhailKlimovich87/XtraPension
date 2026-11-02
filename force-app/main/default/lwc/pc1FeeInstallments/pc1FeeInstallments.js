/**
 * pc1FeeInstallments — the fee plan, one row per installment, with a Retry
 * button on installments GoCardless reported as failed.
 *
 * Added 2026-10-02 (audit): installments had no screen at all, and a failed
 * installment could never be collected. Retry re-presents the SAME payment
 * at GoCardless (PC1_GoCardlessController.retryInstallment) — no second
 * charge; the usual webhooks then move the row to paid / failed.
 *
 * Embedded in pc1FeeChargeCard; renders nothing until a plan exists.
 */
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getInstallments from '@salesforce/apex/PC1_GoCardlessController.getInstallments';
import retryInstallment from '@salesforce/apex/PC1_GoCardlessController.retryInstallment';

const STATUS_LABEL = {
    pending: 'Scheduled',
    submitted: 'Sent to the bank',
    paid: 'Paid',
    failed: 'Failed',
    cancelled: 'Cancelled',
    charged_back: 'Charged back',
    refund_pending: 'Refund pending',
    refunded: 'Refunded',
    customer_approval_denied: 'Declined by client',
};
const STATUS_TONE = {
    paid: 'ok', submitted: 'info', pending: 'muted',
    failed: 'bad', charged_back: 'bad', customer_approval_denied: 'bad',
    cancelled: 'muted', refund_pending: 'warn', refunded: 'warn',
};

export default class Pc1FeeInstallments extends LightningElement {
    _recordId;
    rows = [];
    loading = false;
    retryingId = null;
    loadError = '';

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        this._recordId = v;
        if (v) this.load();
    }

    /** Parent card calls this after it charges / refreshes. */
    @api refresh() { return this.load(); }

    async load() {
        this.loading = true;
        this.loadError = '';
        try {
            const data = await getInstallments({ recordId: this._recordId });
            this.rows = (data || []).map((r) => this.decorate(r));
        } catch (e) {
            this.loadError = 'Could not load the installments. Refresh the page to try again.';
        } finally {
            this.loading = false;
        }
    }

    decorate(r) {
        const status = r.Payment_Status__c || 'pending';
        const tone = STATUS_TONE[status] || 'muted';
        return {
            id: r.Id,
            number: r.Installment_Number__c,
            date: r.Scheduled_Date__c,
            amount: r.Amount__c,
            statusLabel: STATUS_LABEL[status] || status,
            pillClass: `pc1-inst__pill pc1-inst__pill--${tone}`,
            canRetry: status === 'failed' && !!r.Payment_Id__c,
        };
    }

    get hasRows() { return this.rows.length > 0; }
    get failedCount() { return this.rows.filter((r) => r.canRetry).length; }
    get hasFailed() { return this.failedCount > 0; }

    async handleRetry(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        const ok = await LightningConfirm.open({
            label: `Retry installment ${row.number}`,
            message: 'GoCardless will try to collect this same payment again on the next possible date. '
                + 'Only do this after speaking to the client (for example, once they have funds in the account).',
            theme: 'warning',
        });
        if (!ok) return;
        this.retryingId = id;
        try {
            const r = await retryInstallment({ installmentId: id });
            this.dispatchEvent(new ShowToastEvent({
                title: `Installment ${row.number} sent again`,
                message: r && r.charge_date ? `GoCardless will collect it on ${r.charge_date}.` : 'GoCardless accepted the retry.',
                variant: 'success',
            }));
            await this.load();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Retry not possible',
                message: (e && e.body && e.body.message) || 'GoCardless did not accept the retry.',
                variant: 'error',
            }));
        } finally {
            this.retryingId = null;
        }
    }
}