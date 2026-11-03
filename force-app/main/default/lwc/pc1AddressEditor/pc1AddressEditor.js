import { LightningElement, api, wire } from 'lwc';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import findAddress     from '@salesforce/apex/PC1_AddressLookup.findAddress';
import retrieveAddress from '@salesforce/apex/PC1_AddressLookup.retrieveAddress';

const FIELDS = [
    'PC1_Application__c.Address_Line1__c',
    'PC1_Application__c.Address_Line2__c',
    'PC1_Application__c.City__c',
    'PC1_Application__c.County__c',
    'PC1_Application__c.Postcode__c',
];

export default class Pc1AddressEditor extends LightningElement {
    @api recordId;

    // Working copy (edited state)
    draft = { line1:'', line2:'', city:'', county:'', postcode:'' };
    editing = false;
    saving = false;

    // Loqate search state
    query = '';
    results = [];
    stack = [];              // container drill breadcrumb
    lookupStatus = '';       // helper text under search
    lookupBusy = false;
    _debounce = null;

    wiredRecord;
    original = { line1:'', line2:'', city:'', county:'', postcode:'' };

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredHandler(res) {
        this.wiredRecord = res;
        if (res.data) {
            const f = res.data.fields;
            this.original = {
                line1: f.Address_Line1__c?.value || '',
                line2: f.Address_Line2__c?.value || '',
                city:  f.City__c?.value || '',
                county:f.County__c?.value || '',
                postcode: f.Postcode__c?.value || '',
            };
            if (!this.editing) this.draft = { ...this.original };
        }
    }

    // ── computed ────────────────────────────────────────────────────
    get displayLines() {
        return [this.original.line1, this.original.line2, this.original.city, this.original.county, this.original.postcode]
            .filter(Boolean);
    }
    get hasAddress()   { return this.displayLines.length > 0; }
    get showResults()  { return this.results && this.results.length > 0; }
    get showNoResults(){ return !this.lookupBusy && !this.results.length && this.query.trim().length > 0; }
    get breadcrumbs()  { return this.stack.map((s, i) => ({ ...s, idx: i })); }
    get saveDisabled() {
        if (this.saving) return true;
        return !this.draft.line1.trim() || !this.draft.city.trim() || !this.draft.postcode.trim();
    }

    // ── edit-mode handlers ─────────────────────────────────────────
    handleEdit() {
        this.draft = { ...this.original };
        this.editing = true;
    }
    handleCancel() {
        this.editing = false;
        this.draft = { ...this.original };
        this.query = '';
        this.results = [];
        this.stack = [];
        this.lookupStatus = '';
    }
    handleFieldChange(e) {
        const key = e.currentTarget.dataset.key;
        this.draft = { ...this.draft, [key]: e.currentTarget.value };
    }

    async handleSave() {
        this.saving = true;
        try {
            await updateRecord({ fields: {
                Id: this.recordId,
                Address_Line1__c: this.draft.line1.trim(),
                Address_Line2__c: this.draft.line2.trim(),
                City__c:          this.draft.city.trim(),
                County__c:        this.draft.county.trim(),
                Postcode__c:      this.draft.postcode.trim().toUpperCase(),
            }});
            this.editing = false;
            await refreshApex(this.wiredRecord);
            this.toast('Address saved', 'success');
        } catch (err) {
            this.toast('Save failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ── Loqate handlers ────────────────────────────────────────────
    handleSearchInput(e) {
        this.query = e.currentTarget.value;
        clearTimeout(this._debounce);
        this._debounce = setTimeout(() => this.runFind(), 250);
    }
    async runFind() {
        const q = (this.query || '').trim();
        const lastId = this.stack.length ? this.stack[this.stack.length - 1].id : '';
        if (!q && !lastId) { this.results = []; this.lookupStatus = ''; return; }
        this.lookupBusy = true; this.lookupStatus = 'Searching…';
        try {
            const rows = await findAddress({ search: q, lastId, container: '' });
            this.results = rows || [];
            this.lookupStatus = this.results.length ? '' : 'No matches — try a UK postcode (e.g. SW1A 1AA).';
        } catch (err) {
            this.results = [];
            this.lookupStatus = this.errMsg(err) || 'Lookup failed.';
        } finally { this.lookupBusy = false; }
    }

    async handleResultClick(e) {
        const idx = Number(e.currentTarget.dataset.idx);
        const r = this.results[idx];
        if (!r) return;
        if (r.type === 'Container') {
            this.stack = [...this.stack, { id: r.id, text: r.text }];
            this.lookupStatus = 'Loading ' + (r.text || 'group') + '…';
            this.runFind();
            return;
        }
        this.lookupStatus = 'Loading address…';
        this.lookupBusy = true;
        try {
            const a = await retrieveAddress({ id: r.id });
            this.draft = {
                line1: a.line1 || '',
                line2: a.line2 || '',
                city:  a.town  || '',
                county:a.county || '',
                postcode: (a.postcode || '').toUpperCase(),
            };
            this.stack = [];
            this.results = [];
            this.query = [this.draft.line1, this.draft.city, this.draft.postcode].filter(Boolean).join(', ');
            this.lookupStatus = '✓ Filled below — review then Save.';
        } catch (err) {
            this.lookupStatus = this.errMsg(err) || 'Retrieve failed.';
        } finally { this.lookupBusy = false; }
    }

    handleCrumbClick(e) {
        const idx = Number(e.currentTarget.dataset.idx);
        this.stack = this.stack.slice(0, idx + 1);
        this.runFind();
    }
    handleStartOver() {
        this.stack = [];
        this.runFind();
    }

    // ── util ───────────────────────────────────────────────────────
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}