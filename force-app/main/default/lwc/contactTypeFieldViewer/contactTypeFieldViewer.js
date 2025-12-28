import { LightningElement, api } from 'lwc';
import CONTACT_TYPE_FIELD from '@salesforce/schema/Application__c.Contact_Type__c';
import WHO_FIELD from '@salesforce/schema/Application__c.Who__c';
import DAYS_CONTACT_FIELD from '@salesforce/schema/Application__c.Days_Since_Last_Contact__c';
import DAYS_SINCE_CONTACT_FIELD from '@salesforce/schema/Application__c.Date_Since_Contact__c';
import LAST_CONTACT_DATE_FIELD from '@salesforce/schema/Application__c.Last_Contact_Date__c';
import ID_FIELD from "@salesforce/schema/Application__c.Id";

import { updateRecord } from "lightning/uiRecordApi";

export default class ContactTypeFieldViewer extends LightningElement {
    fields = [CONTACT_TYPE_FIELD, WHO_FIELD, DAYS_SINCE_CONTACT_FIELD, DAYS_CONTACT_FIELD];

    @api recordId;
    @api objectApiName;

    handleSuccess() {
        let date = new Date().toLocaleDateString('en-GB');
        const fields = {};

        fields[ID_FIELD.fieldApiName] = this.recordId;
        fields[LAST_CONTACT_DATE_FIELD.fieldApiName] = date;

        const recordInput = {
            fields: fields
        };

        updateRecord(recordInput).then((record) => {
            console.log(record);
        });

    }
}