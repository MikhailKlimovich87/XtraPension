import { LightningElement } from 'lwc';
import getAppsStatusChangedData from '@salesforce/apex/ChangedAppsStatusesController.getAppsStatusChangedData';

export default class ChangedAppsStatuses extends LightningElement {
    appStatuses;
    error;

    connectedCallback() {
        getAppsStatusChangedData()
            .then(result => {
                this.appStatuses = result.statusData;
        }).catch(error =>
                this.error = error
        );
    }
}