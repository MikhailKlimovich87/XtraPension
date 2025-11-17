import { LightningElement, api } from 'lwc';
import X1_FOLLOW_UP_CALL from '@salesforce/schema/Application__c.X1st_Follow_Up_Call__c';
import X2_FOLLOW_UP_CALL from '@salesforce/schema/Application__c.X2nd_Follow_Up_Call__c';
import X3_FOLLOW_UP_CALL from '@salesforce/schema/Application__c.X3rd_Follow_Up_Call__c';

export default class CallFollowUpModule extends LightningElement {
    fields = [X1_FOLLOW_UP_CALL, X2_FOLLOW_UP_CALL, X3_FOLLOW_UP_CALL];

    @api recordId;
    @api objectApiName;

    handleSubmit(event) {
        event.preventDefault(); // stop the form from submitting
        const fields = event.detail.fields;
        this.template.querySelector('lightning-record-form').submit(fields);
    }
}