import { LightningElement, api, track, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import {CurrentPageReference} from 'lightning/navigation';
import sendEnvelopeMethod from '@salesforce/apex/BP_DocuSignController.sendEnvelopeMethod';
import getDocuments from '@salesforce/apex/BP_DocuSignController.getForSignatureDocuments';
import sendMandateEnvelope from '@salesforce/apex/BP_DocuSignController.sendMandateEnvelope';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const columns = [
    { label: 'Document', fieldName: 'title', type: 'text' }
];

export default class BpDocusignModalWindow extends LightningElement {
    _recordId;

    @track showSpinner = false;
    @track data = [];
    columns = columns;
    error;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this._recordId = currentPageReference.state.recordId;
            this.getForSignatureDocuments();
        }
    }

    get hasDocuments() {
        return Array.isArray(this.data) && this.data.length > 0;
    }

    get isSendDisabled() {
        return !this.hasDocuments || this.showSpinner;
    }

    connectedCallback() {
        console.log('BP_DocuSignModalWindow recordId =', this._recordId);
        
    }

    async getForSignatureDocuments() {
        this.showSpinner = true;
        await Promise.resolve(); // let LWC render the spinner before awaiting Apex

        try {
            const result = await getDocuments({ applicationId: this._recordId });
            console.log('getForSignatureDocuments raw result:', JSON.stringify(result));

            const rows = (result || [])
                .filter(d => d && d.docId)
                .map(d => ({ id: d.docId, title: d.title }));

            console.log('getForSignatureDocuments mapped rows:', JSON.stringify(rows));
            this.data = rows;
        } catch (e) {
            console.error('getForSignatureDocuments error:', e);
            this.showErrorNotification(this.reduceErrors(e));
        } finally {
            this.showSpinner = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSend() {
        this.showSpinner = true;
        try {
            const first = await sendEnvelopeMethod({ applicationId: this._recordId });

            if (!first?.isSuccess) {
                this.showErrorNotification(
                    first?.errorMessage || 'You haven\'t sent documents for signature'
                );
                return;
            }

            if (first.needsSecondEnvelope) {
                const second = await sendMandateEnvelope({ applicationId: this._recordId });
                if (!second?.isSuccess) {
                    this.showErrorNotification(
                        second?.errorMessage || 'Direct Debit Mandate could not be sent'
                    );
                    return;
                }
            }

            this.showSuccessNotification();
            this.handleCancel();
        } catch (e) {
            this.showErrorNotification(this.reduceErrors(e));
        } finally {
            this.showSpinner = false;
        }
    }

    showSuccessNotification() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: 'You\'ve sent documents for signature',
            variant: 'success'
        }));
    }

    showErrorNotification(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: message || 'You haven\'t sent documents for signature',
            variant: 'error'
        }));
    }

    reduceErrors(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map(e => e.message).join(', ');
        }
        if (Array.isArray(error?.body?.pageErrors)) {
            return error.body.pageErrors.map(e => e.message).join(', ');
        }
        if (error?.body?.fieldErrors) {
            return Object.values(error.body.fieldErrors)
                .flat()
                .map(e => e.message)
                .join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}