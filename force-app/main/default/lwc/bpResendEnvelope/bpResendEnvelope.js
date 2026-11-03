import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import resendEnvelope from '@salesforce/apex/ResendEnvelopeController.resendEnvelope';

export default class ResendEnvelope extends LightningElement {
    @api recordId; // Automatically populated by the Quick Action
    isProcessing = false;
    statusMessage = '';
    statusIcon = '';
    statusVariant = '';

    // Dynamic label so the button visually signals progress
    get buttonLabel() {
        return this.isProcessing ? 'Sending...' : 'Resend Big Envelope';
    }

    handleResend() {
        // Prevent double-clicks (safety net even with disabled attr)
        if (this.isProcessing) {
            return;
        }

        this.isProcessing = true;
        this.statusMessage = '';
        this.statusIcon = '';
        this.statusVariant = '';

        resendEnvelope({ recordId: this.recordId })
            .then(result => {
                this.statusMessage = result;
                this.statusIcon = 'utility:success';
                this.statusVariant = 'success';

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result,
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                // ApexHandledException message is under error.body.message
                const msg = (error.body && error.body.message)
                    ? error.body.message
                    : (error.message || 'Unknown error');

                this.statusMessage = msg;
                this.statusIcon = 'utility:error';
                this.statusVariant = 'error';

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: msg,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                // Always turn off spinner, success or failure
                this.isProcessing = false;
            });
    }
}