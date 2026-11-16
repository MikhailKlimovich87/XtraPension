import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getPreview from '@salesforce/apex/XpClaimSendToValidation.preview';
import sendClaim from '@salesforce/apex/XpClaimSendToValidation.send';

// "Send to Validation" on the Claim page: same rule as the long form's Summary button
// (complete = Form completed + documents; anything missing = Pending Client with the list).
export default class XpClaimSendToValidation extends LightningElement {
    _recordId;
    state;
    loading = false;
    errorMessage;

    // Screen actions set recordId after connectedCallback, so the load starts here.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.load();
        }
    }

    get agentLine() {
        return this.state?.validationAgent ? `Validation agent: ${this.state.validationAgent}` : 'No validation agent on this claim yet.';
    }

    get missingCount() {
        return this.state?.missing?.length || 0;
    }

    // Position in the key: two items can read the same (e.g. two employers both missing an address)
    get missingItems() {
        return (this.state?.missing || []).map((text, i) => ({ key: `${i}:${text}`, text }));
    }

    get missingTitle() {
        return `Still missing (${this.missingCount})`;
    }

    get afterNote() {
        if (!this.state) return '';
        const agent = this.state.validationAgent || 'the validation agent';
        return this.state.complete
            ? 'Nothing is missing: the claim goes to Form completed and the documents are built.'
            : `The claim goes to Pending Client and ${agent} chases the client for these.`;
    }

    get cannotSend() {
        return this.loading || !this.state?.allowed;
    }

    async load() {
        this.loading = true;
        this.errorMessage = undefined;
        try {
            this.state = await getPreview({ claimId: this._recordId });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.loading = false;
        }
    }

    async handleSend() {
        this.loading = true;
        this.errorMessage = undefined;
        try {
            const result = await sendClaim({ claimId: this._recordId });
            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.dispatchEvent(new ShowToastEvent({
                title: `${result.name} sent to validation`,
                message: result.nextStatus === 'Form completed'
                    ? 'Form completed: the documents are being built.'
                    : `Pending Client - ${result.validationAgent || 'the validation agent'} has the list of what is missing.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.loading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Something went wrong. Try again.';
    }
}