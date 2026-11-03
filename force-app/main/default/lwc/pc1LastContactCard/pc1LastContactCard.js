import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import TYPE_FIELD  from '@salesforce/schema/PC1_Application__c.Last_Contact_Type__c';
import WHO_FIELD   from '@salesforce/schema/PC1_Application__c.Last_Contact_Who__c';
import DATE_FIELD  from '@salesforce/schema/PC1_Application__c.Last_Contact_Date__c';
import AT_FIELD    from '@salesforce/schema/PC1_Application__c.Last_Contact_At__c';
import DAYS_FIELD  from '@salesforce/schema/PC1_Application__c.Days_Since_Last_Contact__c';

const FIELDS = [TYPE_FIELD, WHO_FIELD, DATE_FIELD, AT_FIELD, DAYS_FIELD];

/**
 * pc1LastContactCard — read-only 2×2 grid showing the latest touch surface,
 * who did it, when, and how long ago. Populated by PC1_CallLogTrigger for
 * calls; Node webhooks (WhatsApp send, email quick-action) write the fields
 * directly for surfaces that don't create a Call Log row.
 *
 * Uses uiRecordApi so it re-renders live as the trigger runs and CDC fires.
 */
export default class Pc1LastContactCard extends LightningElement {
    @api recordId;
    _record;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wired({ data }) {
        if (data) this._record = data;
    }

    get contactType() {
        return getFieldValue(this._record, TYPE_FIELD) || '—';
    }
    get who() {
        return getFieldValue(this._record, WHO_FIELD) || '—';
    }
    get dateDisplay() {
        const raw = getFieldValue(this._record, DATE_FIELD);
        if (!raw) return 'Never';
        try {
            const d = new Date(raw);
            return d.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
        } catch (_) { return raw; }
    }
    get daysSince() {
        const raw = getFieldValue(this._record, DAYS_FIELD);
        return raw || 'Never';
    }
}