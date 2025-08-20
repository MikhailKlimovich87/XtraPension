import { LightningElement, api} from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import insertCheckResult from '@salesforce/apex/CheckModuleController.createHMRCCheckRequestRecord';
import getApps from '@salesforce/apex/CheckModuleController.getApplicationNames';

export default class CheckModule extends LightningElement {
    checkRequest;
    error;
    appNames;

    connectedCallback() {
        getApps()
            .then(result => {
                this.appNames = result;
                this.error = undefined;
            })
            .catch(error => {
                this.error = error;
                this.appNames = undefined;
            });
    }

    async handleInsertReply(event) {
        await insertCheckResult({
            "checkReply" : JSON.stringify(event.detail)
        })
            .then(result => {
                if (result) {
                    this.checkRequest = result;
                    this.error = undefined;
                    this.showToastMessage(
                        'Success',
                        'You\'ve created HMRC Check Request record',
                        'success'
                    );
                    setTimeout(() => {
                        window.location.reload();
                    }, 3000);
                }
            })
            .catch(error => {
                this.error = error;
                this.checkRequest = undefined;
                console.log('error ==== ', error);
                
                this.showToastMessage(
                    'Error',
                    'You have error: ' + error.body.message,
                    'error'
                );
            });
    }

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }
}