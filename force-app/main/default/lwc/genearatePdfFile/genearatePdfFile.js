import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplication from '@salesforce/apex/GeneratePdfFileController.getApplication';

export default class GenearatePdfFile extends LightningElement {
    @api recordId;
    @track result;
    @track error;
    @track showSpinner = false;

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    @api async handleGenerate() {
        this.showSpinner = !this.showSpinner;
        await getApplication({
            recordId : this.recordId
        })
            .then(result => {
                this.result = result;
                this.error  = undefined;
                this.showSpinner = !this.showSpinner;
                const evt = new ShowToastEvent({
                    title: 'Success',
                    message: 'You generated pdf files',
                    variant: 'success',
                });
                this.dispatchEvent(evt);

            }).catch(error => {
                this.error = error;
                this.contacts = undefined;
                this.showSpinner = !this.showSpinner;
                const evt = new ShowToastEvent({
                    title: 'Error',
                    message: 'You didn\'t generate pdf files. Error is ' + this.error,
                    variant: 'error',
                });
                this.dispatchEvent(evt);
        });
    }

    showNotification() {
        const evt = new ShowToastEvent({
            title: 'Success',
            message: 'You generated pdf files',
            variant: 'success',
        });
        this.dispatchEvent(evt);
    }

}