import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import sendEnvelopeMethod from '@salesforce/apex/RE_DocuSignController.sendEnvelopeMethod';
import getDocuments from '@salesforce/apex/RE_DocuSignController.getForSignatureDocuments';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const columns = [
    { label: 'Document', fieldName: 'Title', type: 'text' }
];

export default class ReDocusignModalWindow extends LightningElement {
    _recordId;
    error;
    errorMessage;
    result;
    @track showSpinner = false;
    data;
    columns = columns;
    isAvailable = true;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        console.log('recordId setter fired with:', value);
        this._recordId = value;
        if (value) {
            this.getForSignatureDocuments();
        }
    }

    // Remove connectedCallback — let the setter handle it
    // connectedCallback() { this.getForSignatureDocuments(); } // <-- REMOVE THIS

    async getForSignatureDocuments() {
        this.showSpinner = true;
        this.error = undefined;
        this.errorMessage = undefined;

        console.log('this.recordId ==== ', this.recordId);

        if (!this.recordId) {
            this.isAvailable = true;
            this.errorMessage = 'Record ID is missing. Open this action from a Reapply record.';
            this.showErrorNotification('Missing Record ID', this.errorMessage);
            this.showSpinner = false;
            return;
        }

        try {
            const result = await getDocuments({ applicationId: this.recordId });
            this.data = result;
            this.isAvailable = !(result && result.length > 0);
        } catch (error) {
            this.error = error;
            this.errorMessage = this.reduceErrors(error);
            this.isAvailable = true;
            this.showErrorNotification('Error loading documents', this.errorMessage);
        } finally {
            this.showSpinner = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSign() {
        this.showSpinner = true;
        this.error = undefined;
        this.errorMessage = undefined;
        
        try {
            const result = await sendEnvelopeMethod({ applicationId: this.recordId });
            this.result = result;
            this.showSuccessNotification();
            this.handleCancel();
        } catch (error) {
            this.error = error;
            this.errorMessage = this.reduceErrors(error);
            // Show error in the UI AND as a toast
            this.showErrorNotification('Error sending documents', this.errorMessage);
        } finally {
            this.showSpinner = false;
        }
    }

    // Helper to extract readable error messages from Apex errors
    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }
        return errors
            .filter(error => !!error)
            .map(error => {
                // Apex error
                if (error.body) {
                    if (Array.isArray(error.body)) {
                        return error.body.map(e => e.message).join(', ');
                    } else if (error.body.message) {
                        return error.body.message;
                    } else if (error.body.pageErrors && error.body.pageErrors.length) {
                        return error.body.pageErrors.map(e => e.message).join(', ');
                    } else if (error.body.fieldErrors) {
                        const fieldErrors = Object.values(error.body.fieldErrors)
                            .flat()
                            .map(e => e.message);
                        if (fieldErrors.length) return fieldErrors.join(', ');
                    }
                }
                // JS error
                return error.message || JSON.stringify(error);
            })
            .join(', ');
    }

    showSuccessNotification() {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: "You've sent documents for signature",
            variant: 'success',
        }));
    }

    showErrorNotification(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message || "An unknown error occurred",
            variant: 'error',
            mode: 'sticky' // Keeps the toast visible longer
        }));
    }
}