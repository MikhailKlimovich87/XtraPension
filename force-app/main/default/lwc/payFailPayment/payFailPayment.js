import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import chargePayment from '@salesforce/apex/PayFailPaymentController.chargePayment';

export default class PayFailPayment extends LightningElement {
    @api recordId;
    error;
    result;
    @track showSpinner = false;
    isDisable = false;

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleCharge() {
        this.showSpinner = !this.showSpinner;
        this.isDisable = !this.isDisable;
        chargePayment({
            paymentId : this.recordId
        }).then(result => {
            this.result = result;
                if (result) {
                    this.showSpinner = !this.showSpinner;
                    this.handleCancel();
                    this.showSuccessNotification();
                    setTimeout(() => {
                        window.location.reload();
                    }, 3000);
                }
        }).catch(error => {
            this.error = error.body.message;
            this.showSpinner = !this.showSpinner;
            this.showErrorNotification();
        });
    }

    showSuccessNotification() {
        const evt = new ShowToastEvent({
            title: 'Success',
            message: 'You\'ve charged payment successfully',
            variant: 'success',
        });
        this.dispatchEvent(evt);
    }

    showErrorNotification() {
        const evt = new ShowToastEvent({
            title: 'Error',
            message: 'Unsuccessful payment with error: ' + this.error,
            variant: 'error',
        });
        this.dispatchEvent(evt);
    }
}