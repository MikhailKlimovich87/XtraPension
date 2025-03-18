import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import sendEnvelopeMethod from '@salesforce/apex/ApexToolkit.sendEnvelopeMethod';
import getDocuments from '@salesforce/apex/ApexToolkit.getForSignatureDocuments';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const columns = [
    { label: 'Document', fieldName: 'Title', type: 'text' }
];

export default class DocusignModalWindow extends LightningElement {
    @api recordId;
    error;
    result;
    @track showSpinner = false;
    data;
    columns = columns;
    isAvailable = true;

    connectedCallback() {
        setTimeout(() => {
            this.getForSignatureDocuments();
        }, 5);
    }

    @api
    async getForSignatureDocuments() {
        await getDocuments({
            applicationId : this.recordId
        })
        .then(result => {
            this.data = result;
            this.isAvailable = !this.isAvailable;
        }).catch(error => {
            console.log('error = ', error);
        });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSign() {
        this.showSpinner = !this.showSpinner;
        sendEnvelopeMethod({
            applicationId : this.recordId
        })
            .then(result => {
                this.result = result;
                this.showSpinner = !this.showSpinner;
                this.showSuccessNotification();
                this.handleCancel();
            }).catch(error => {
                this.error = error;
                this.showSpinner = !this.showSpinner;
                this.showErrorNotification();
                this.handleCancel();
        });
    }

    showSuccessNotification() {
        const evt = new ShowToastEvent({
            title: 'Success',
            message: 'You\'ve sent documents for signature',
            variant: 'success',
        });
        this.dispatchEvent(evt);
    }

    showErrorNotification() {
        const evt = new ShowToastEvent({
            title: 'Error',
            message: 'You haven\'t sent documents for signature',
            variant: 'error',
        });
        this.dispatchEvent(evt);
    }
}