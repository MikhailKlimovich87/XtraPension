import { LightningElement, api } from 'lwc';
import getApplication from '@salesforce/apex/BP_GeneratePdfFileController.getApplication';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GenerateIPC1394BPAction extends LightningElement {
    @api recordId;
    isLoading = false;

    handleClick() {
        this.isLoading = true;

        getApplication({ recordId: this.recordId})
            .then(result => {
                console.log(result);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'File generated successfully',
                        variant: 'success'
                    })
                );
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || error.message,
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}