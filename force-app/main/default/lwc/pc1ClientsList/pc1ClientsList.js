import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getClientsList  from '@salesforce/apex/PC1_RecordPageService.getClientsList';
import getClientsCount from '@salesforce/apex/PC1_RecordPageService.getClientsCount';

const FILTERS = [
    // Meta filters at the top…
    { key: 'all',                          label: 'All Clients' },
    { key: 'my_clients',                   label: 'My Clients' },
    // …then every Stage__c picklist value in workflow order. The Apex layer
    // allowlists against the known stage set so passing 'stage:<X>' as a
    // filter key is safe (no SOQL injection risk).
    { key: 'stage:New',                    label: 'New' },
    { key: 'stage:Awaiting First Call',    label: 'Awaiting First Call' },
    { key: 'stage:Call In Progress',       label: 'Call In Progress' },
    { key: 'stage:Partial Data',           label: 'Partial Data' },
    { key: 'stage:Data Complete',          label: 'Data Complete' },
    { key: 'stage:Ready for Review',       label: 'Ready for Review' },
    { key: 'stage:Reviewed',               label: 'Reviewed' },
    { key: 'stage:Filling',                label: 'Filling' },
    { key: 'stage:Ready for Submit',       label: 'Ready for Submit' },
    { key: 'stage:Submitted',              label: 'Submitted' },
    { key: 'stage:Needs Human',            label: 'Needs Human' }
];

const FILL_STAGES = new Set(['Reviewed', 'Ready for Submit', 'Data Complete']);

export default class Pc1ClientsList extends NavigationMixin(LightningElement) {
    @api pageSize = 100;
    filter = 'all';
    rows = [];
    total = 0;
    loading = true;
    offset = 0;
    hasMore = false;
    wiredList;
    wiredCount;

    @wire(getClientsList, { filter: '$filter', pageSize: '$pageSize', offset: '$offset' })
    wiredHandler(result) {
        this.wiredList = result;
        if (result.data) {
            const rows = result.data.map((r) => this.decorate(r));
            this.rows = this.offset > 0 ? [...this.rows, ...rows] : rows;
            this.hasMore = result.data.length >= this.pageSize;
            this.loading = false;
        } else if (result.error) {
            this.loading = false;
            this.toast(this.errMsg(result.error), 'error');
        }
    }

    @wire(getClientsCount, { filter: '$filter' })
    wiredCountHandler(result) {
        this.wiredCount = result;
        if (typeof result.data === 'number') this.total = result.data;
    }

    // ── decoration ──────────────────────────────────────────────────────
    decorate(r) {
        const stage = r.stage || '—';
        return {
            ...r,
            displayName: r.fullName || r.name,
            hasDescriptor: !!r.descriptor,
            phoneDisplay: r.phone || '—',
            stage,
            stageCls: this.stageClass(stage),
            nextCallFmt: r.nextCallAt
                ? new Date(r.nextCallAt).toLocaleString('en-GB', {
                    day: '2-digit', month: '2-digit', year: 'numeric',
                    hour: '2-digit', minute: '2-digit' })
                : '—',
            createdFmt: r.createdAt
                ? new Date(r.createdAt).toLocaleString('en-GB', {
                    day: '2-digit', month: '2-digit', year: 'numeric',
                    hour: '2-digit', minute: '2-digit' })
                : '—',
            pctInt: Math.min(100, Math.round(r.progressPct || 0)),
            progressText: `${r.progressFilled ?? 0}/${r.progressTotal ?? 0}`,
            progressStyle: `width:${Math.min(100, Math.round(r.progressPct || 0))}%`,
            canFill: FILL_STAGES.has(stage)
        };
    }

    stageClass(s) {
        const base = 'pc1-stage-badge';
        if (s === 'New' || s === 'Awaiting First Call')       return `${base} pc1-stage-badge--info`;
        if (s === 'Call In Progress' || s === 'Filling')      return `${base} pc1-stage-badge--pulse`;
        if (s === 'Partial Data')                             return `${base} pc1-stage-badge--warn`;
        if (s === 'Data Complete')                            return `${base} pc1-stage-badge--success-light`;
        if (s === 'Ready for Review')                         return `${base} pc1-stage-badge--success`;
        if (s === 'Reviewed' || s === 'Ready for Submit')     return `${base} pc1-stage-badge--success-dark`;
        if (s === 'Submitted')                                return `${base} pc1-stage-badge--muted`;
        if (s === 'Needs Human')                              return `${base} pc1-stage-badge--error`;
        return `${base} pc1-stage-badge--muted`;
    }

    // ── computed ────────────────────────────────────────────────────────
    get filters() {
        return FILTERS.map((f) => ({
            ...f,
            cls: f.key === this.filter
                ? 'slds-button slds-button_brand pc1-filter-btn'
                : 'slds-button slds-button_neutral pc1-filter-btn'
        }));
    }
    get headerTitle() {
        const n = this.total || 0;
        const noun = n === 1 ? 'client' : 'clients';
        return `Clients — ${n} ${noun} in the pipeline`;
    }
    get isEmpty()   { return !this.loading && this.rows.length === 0; }
    get showTable() { return !this.loading && this.rows.length > 0; }

    // ── handlers ────────────────────────────────────────────────────────
    handleFilterClick(e) {
        const key = e.currentTarget.dataset.filter;
        if (!key || key === this.filter) return;
        this.filter  = key;
        this.offset  = 0;
        this.rows    = [];
        this.loading = true;
    }

    async handleRefresh() {
        this.offset = 0; this.rows = []; this.loading = true;
        await Promise.all([
            refreshApex(this.wiredList),
            refreshApex(this.wiredCount)
        ]);
        this.loading = false;
    }

    handleLoadMore() {
        this.offset = this.rows.length;
    }

    handleNew() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'PC1_Application__c', actionName: 'new' }
        });
    }

    handleRowClick(e) {
        const id = e.currentTarget.dataset.id;
        if (!id) return;
        this.navToRecord(id);
    }

    handleView(e) {
        e.stopPropagation();
        this.navToRecord(e.currentTarget.dataset.id);
    }

    handleCallNow(e) {
        e.stopPropagation();
        this.toast('Call Now', 'info',
            'Wire this to your ElevenLabs / dial webhook (PC1_HerokuBridge.startCall).');
    }

    handleFill(e) {
        e.stopPropagation();
        this.toast('Fill on DWP', 'info',
            'Open the client record and use the Fill Run panel to launch a run.');
    }

    navToRecord(id) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: 'PC1_Application__c', actionName: 'view' }
        });
    }

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}