import { LightningElement} from 'lwc';
import getApplications from '@salesforce/apex/ClearingHouseController.getApplications';
import { NavigationMixin } from "lightning/navigation";
import APPLICATION_OBJECT from '@salesforce/schema/Application__c';

export default class ClearingHouse extends NavigationMixin(LightningElement) {
    appsUp = [];
    appsDown = [];
    total;
    totalResult;
    isOpenFullTable = false;
    showButtonLabel = '+ SHOW ALL DATA';

    connectedCallback() {
        this.getRecords();
    }

    async getRecords() {
        await getApplications()
        .then(result => {
            let apps = JSON.parse(JSON.stringify(result));
            this.appsUp = apps.tableUp;
            this.appsDown = apps.tableDown;
            this.total = apps.totalResult.total;
            this.totalResult = apps.totalResult;
            console.log(this.total);

        }).catch(error => {
            console.error(error);
        })
    }

    navigateToRecord(event) {
        let appId = event.currentTarget.getAttribute("value");
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:appId,
                objectApiName: APPLICATION_OBJECT.Application__c,
                actionName: 'view'
            }
        });
    }

    showFullTable() {
        this.isOpenFullTable = !this.isOpenFullTable;
        if (!this.isOpenFullTable) {
            this.showButtonLabel = '+ SHOW ALL DATA';
        } else this.showButtonLabel = '- HIDE ALL DATA';
    }
}