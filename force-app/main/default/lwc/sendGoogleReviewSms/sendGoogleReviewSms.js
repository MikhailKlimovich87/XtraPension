import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import sendGoogleReviewMessage from '@salesforce/apex/SendGoogleReviewSmsController.sendGoogleReviewMessage';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class SendGoogleReviewSms extends LightningElement {
    @api recordId;
    @track showSpinner = false;

    constructor(){
        super();
    }

    handleSend() {
        this.showSpinner = true;
        sendGoogleReviewMessage({
            "appId" : this.recordId
        })
        .then(result => {
            const evt = new ShowToastEvent({
                title: result.title,
                message: result.message,
                variant: result.variant
            });
            this.showSpinner = false;
            this.dispatchEvent(evt);
        })
        .catch(error => {
            console.log('error: ', error)
            this.showSpinner = false;
        })
        this.showSpinner = false;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}