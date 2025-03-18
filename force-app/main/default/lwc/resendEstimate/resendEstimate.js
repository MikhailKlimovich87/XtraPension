import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import resendEstimateEmail from '@salesforce/apex/ResendEstimateController.resendEstimateEmail';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ResendEstimate extends LightningElement {
    @api recordId;
    result;
    error;
    showSpinner = false;

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSend() {
        this.showSpinner = !this.showSpinner;
        resendEstimateEmail({
            recordId : this.recordId
        })
            .then(result => {
                this.result = result;
                this.error  = undefined;
                this.showSpinner = !this.showSpinner;
                this.showToast('Success',
                               'You\'ve resend pdf files',
                               'success')
            }).catch(error => {
                this.error = error;
                this.contacts = undefined;
                this.showSpinner = !this.showSpinner;
                this.showToast('Error',
                               'You didn\'t resend estimate. System has error: ' +this.error.body.message, 
                               'error');
        });
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message:  message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
}