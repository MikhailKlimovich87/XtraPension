import { LightningElement, api, wire } from 'lwc';
import generateDwpDocs from '@salesforce/apex/DwpEmailController.generateDwpDocs';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {CurrentPageReference} from 'lightning/navigation';

export default class DwpEmail extends LightningElement {
    _recordId;
    summaryURL;
    workHistoryURL;
    error;
    result;
    showSpinner = false;

    @wire(CurrentPageReference)
        getStateParameters(currentPageReference) {
            if (currentPageReference) {
                this._recordId = currentPageReference.state.recordId;
            }
    }

    connectedCallback() {
        this.summaryURL = '/apex/DWPInfo?id=' + this._recordId;
        this.workHistoryURL = '/apex/DWPWorkHistory?id=' + this._recordId;
    }

    handleSend() {
        this.showSpinner = !this.showSpinner;
        generateDwpDocs({
            appId : this._recordId
        }).then(result => {
            this.result = result;
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
            message: 'DWP email was sent successfully',
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
        }, 2000);
    }
}