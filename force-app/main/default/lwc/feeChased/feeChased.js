import { LightningElement, api } from 'lwc';
import FEE_CHASED_FIELD from '@salesforce/schema/Application__c.Fee_Chased__c';

export default class FeeChased extends LightningElement {
    fields = [FEE_CHASED_FIELD];

    @api recordId;
    @api objectApiName;
}