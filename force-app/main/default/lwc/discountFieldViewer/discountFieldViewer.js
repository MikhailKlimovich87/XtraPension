import { LightningElement, api } from 'lwc';
import DISCOUNT_FIELD from '@salesforce/schema/Application__c.Discount__c';

export default class DiscountFieldViewer extends LightningElement {
    fields = [DISCOUNT_FIELD];

    @api recordId;
    @api objectApiName;
}