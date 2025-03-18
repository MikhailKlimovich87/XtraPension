import { LightningElement, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {CurrentPageReference} from 'lightning/navigation';
import sendDWPsmsMessage from '@salesforce/apex/DwpEmailController.sendDWPsmsMessage';

export default class DwpSmsMessageSender extends LightningElement {
    _recordId;
    showSpinner = false;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this._recordId = currentPageReference.state.recordId;
        }
    }

    handleSend() {
        this.showSpinner = !this.showSpinner;
        sendDWPsmsMessage({
            appId : this._recordId
        }).then(result => {
            this.result = result;
            console.log('this.result ==== ', this.result);
            if (result) {
                this.showSpinner = !this.showSpinner;
                this.showSuccessNotification();
            }
            this.handleClose();
        }).catch(error => {
            this.error = error.body.message;
            this.showSpinner = !this.showSpinner;
            this.showErrorNotification();
            this.handleClose();
        });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showSuccessNotification() {
        const evt = new ShowToastEvent({
            title: 'Success',
            message: 'DWP SMS message was sent successfully',
            variant: 'success',
        });
        this.dispatchEvent(evt);
    }

    showErrorNotification() {
        const evt = new ShowToastEvent({
            title: 'Error',
            message: 'Error: ' + this.error,
            variant: 'error',
        });
        this.dispatchEvent(evt);
    }

    handleClose() {
        setTimeout(() => {
            this.handleCancel();
        }, 3000);
      }
}