import { LightningElement, api } from 'lwc';
import APPLICATION from '@salesforce/schema/Application__c';
import APPLICATION_NAME from '@salesforce/schema/Application__c.Name';

export default class EditCustomerAddess extends LightningElement {

    fields = [APPLICATION_NAME];
    @api recordId;
    @api objectApiName = APPLICATION;
}