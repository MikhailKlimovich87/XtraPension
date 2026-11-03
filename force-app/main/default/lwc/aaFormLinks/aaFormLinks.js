import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import CLIENT_URL from '@salesforce/schema/AA_Application__c.Client_Form_URL__c';

// Only one form for now — the Client Form. When new forms are added, import
// their formula fields and turn this into a small list again.
const FIELDS = [CLIENT_URL];

export default class AaFormLinks extends LightningElement {
    @api recordId;
    record;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wired({ data }) { if (data) this.record = data; }

    get url() { return getFieldValue(this.record, CLIENT_URL); }
    get hasUrl() { return !!this.url; }
}