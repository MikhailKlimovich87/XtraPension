import { LightningElement, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendRequest from '@salesforce/apex/SarRequestController.sendSAREmail';

import {CurrentPageReference} from 'lightning/navigation';

export default class SarRequest extends LightningElement {

    _recordId;
    error;
    result;
    showSpinner = false;
    siteURL;
    bodyTemplate;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this._recordId = currentPageReference.state.recordId;
        }
    }

    connectedCallback() {
        this.siteURL = '/apex/SarRequest?id=' + this._recordId;
    }


    handleSend() {
        this.showSpinner = !this.showSpinner;
        sendRequest({
            appId : this._recordId
        }).then(result => {
            this.result = result;
            console.log('Sar result === ', this.result);
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
            message: 'SAR Request was sent successfully',
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
        }, 4000);
      }
}