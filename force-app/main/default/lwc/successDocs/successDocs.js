import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateDocs from '@salesforce/apex/SuccessDocsController.generateDocs';

export default class SuccessDocs extends LightningElement {
    @api recordId;
    result;
    error;
    showSpinner = false;

    closeModal() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    @api async handleGenerate() {
        this.showSpinner = !this.showSpinner;
        await generateDocs({
            recordId : this.recordId
        })
            .then(result => {
                this.result = result;
                this.showSpinner = !this.showSpinner;
                this.closeModal();
                this.showNotification('Success', 'You\'ve generated pdf files', 'success');
            }).catch(error => {
                this.error = error;
                console.log(' this.error ==== ',  this.error );
                this.showSpinner = !this.showSpinner;
                this.closeModal();
                this.showNotification('Error', 'You haven\'t generated pdf files. Error is ' + this.error.body.message, 'error');
        });
    }

    showNotification(name, info, type) {
        const evt = new ShowToastEvent({
            title: name,
            message: info,
            variant: type,
        });
        this.dispatchEvent(evt);
    }
}