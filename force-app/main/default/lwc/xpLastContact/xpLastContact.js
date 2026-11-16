import { LightningElement, api, wire } from 'lwc';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import TIME_ZONE from '@salesforce/i18n/timeZone';

const FIELDS = ['Contact_Type__c', 'Who__c', 'Date_Since_Contact__c', 'Days_Since_Last_Contact__c', 'Last_Contact_At__c'];

/**
 * Last Contact on the Application and the Claim, in place of the old editable form.
 * Calls (Nuacom), emails sent from Salesforce and WhatsApp messages a person sent fill it in by
 * themselves. It only shows: nothing is typed by hand.
 */
export default class XpLastContact extends LightningElement {
    @api recordId;
    @api objectApiName;
    record;
    error;

    get optionalFields() {
        return this.objectApiName ? FIELDS.map((f) => `${this.objectApiName}.${f}`) : [];
    }

    @wire(getRecord, { recordId: '$recordId', optionalFields: '$optionalFields' })
    wired({ data, error }) {
        if (data) {
            this.record = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.messageOf(error);
        }
    }

    field(name) {
        const f = this.record && this.record.fields && this.record.fields[name];
        return f ? { value: f.value, display: f.displayValue != null ? f.displayValue : f.value } : { value: null, display: null };
    }

    get loading() { return !this.record && !this.error; }
    get contactType() { return this.field('Contact_Type__c').display || '—'; }
    get who() { return this.field('Who__c').display || '—'; }
    get hasContact() { return !!this.field('Contact_Type__c').value || !!this.field('Date_Since_Contact__c').value; }

    get dateLine() {
        const day = this.field('Date_Since_Contact__c').value;
        if (!day) return '—';
        const [y, m, d] = String(day).split('-').map(Number);
        let text = new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(y, m - 1, d));
        // The time only when Last Contact At is that same day (a date typed by hand before the change has none).
        const at = this.field('Last_Contact_At__c').value;
        if (at && this.dayKey(at) === String(day)) text += `, ${this.fmt(at, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })}`;
        return text;
    }

    get daysLine() {
        const raw = this.field('Days_Since_Last_Contact__c').value;
        if (raw == null || raw === '') return '—';
        const n = Number(raw);
        if (Number.isNaN(n)) return String(raw);
        return n === 1 ? '1 day' : `${n} days`;
    }

    async handleRefresh() {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    }

    fmt(value, opts) {
        try { return new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, ...opts }).format(new Date(value)); }
        catch (e) { return new Date(value).toLocaleString('en-GB', opts); }
    }

    /** yyyy-MM-dd of a datetime in the user's time zone. */
    dayKey(value) {
        const parts = {};
        for (const p of new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(value))) parts[p.type] = p.value;
        return `${parts.year}-${parts.month}-${parts.day}`;
    }

    messageOf(err) {
        const b = err && err.body;
        if (Array.isArray(b)) return b.map((x) => x.message).join(', ');
        return (b && b.message) || (err && err.message) || 'Something went wrong.';
    }
}