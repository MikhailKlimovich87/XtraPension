import { LightningElement } from 'lwc';
import getAppStatusCount from '@salesforce/apex/AppsStatusCountReportController.getAppStatusCount';

export default class AppsStatusCount extends LightningElement {
    appStatuses;
    error;

    connectedCallback() {
        getAppStatusCount()
            .then(result => {
                this.appStatuses = JSON.parse(JSON.stringify(result.statusData));
        }).catch(error =>
                this.error = error
        );
    }
}