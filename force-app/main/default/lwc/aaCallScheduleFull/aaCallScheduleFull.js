import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import LightningConfirm from 'lightning/confirm';
import LightningPrompt from 'lightning/prompt';
import getScheduleHistory from '@salesforce/apex/AA_CallScheduleService.getScheduleHistory';
import cancelScheduleApex from '@salesforce/apex/AA_CallScheduleService.cancelSchedule';
import getApplication from '@salesforce/apex/AA_RecordPageService.getApplication';

const CDC_SCHEDULE_CHANNEL = '/data/AA_Call_Schedule__ChangeEvent';
const DEFAULT_LIMIT = 200;

/**
 * Status → Display label. Fernando explicitly wants "Manual" rendered as
 * "Call Now" so operators can tell at a glance which rows came from the
 * header Call Now button vs a real scheduled slot.
 */
const STATUS_LABEL_MAP = {
    Pending:   'Pending',
    Fired:     'Fired',
    Cancelled: 'Cancelled',
    Missed:    'Missed',
    Manual:    'Call Now'
};

/**
 * Status → SLDS badge theme class. Pattern mirrors STATUS_BADGE_CLASS_MAP
 * in aaFillRunPanel (commit f6cf418).
 *
 * yellow  → slds-theme_warning
 * grey    → slds-badge (base)
 * dark    → slds-theme_inverse
 * red     → slds-theme_error
 * green   → slds-theme_success
 */
const STATUS_BADGE_CLASS_MAP = {
    Pending:   'slds-badge slds-theme_warning',
    Fired:     'slds-badge slds-theme_inverse',
    Cancelled: 'slds-badge',
    Missed:    'slds-badge slds-theme_error',
    Manual:    'slds-badge slds-theme_success'
};

/**
 * aaCallScheduleFull — App-page LWC that lists every AA_Call_Schedule__c
 * row for one Application, newest first. Reached via aaCallSchedule's
 * "View schedule history →" opening
 * /lightning/n/AA_Call_Schedule_History?c__recordId=<id> in a new tab.
 *
 * Mirrors the visual pattern of aaFilesFull + aaApplicationHistoryFull:
 *   • breadcrumb "Applications › PC00033 › Schedule History"
 *   • title + row count subtitle
 *   • sortable data table (SLDS <table>, not lightning-datatable — needed
 *     custom cell content: coloured Status badges + Call Log hyperlinks +
 *     inline Cancel button on Pending rows)
 *   • empty state message when no rows exist
 *
 * CDC subscription — live-refreshes the table on any Schedule change.
 * Degrades gracefully if CDC subscribe throws.
 */
export default class AaCallScheduleFull extends NavigationMixin(LightningElement) {
    @track recordId;
    @track applicationName;
    @track sortedBy = 'requestedAt';        // Requested At (CreatedDate)
    @track sortedDirection = 'desc';
    @track rawRows = [];
    @track cancellingId = null;
    error;

    wiredHistoryResult;
    _cdcSub;
    _pollTimer;

    @wire(CurrentPageReference)
    setPageRef(ref) {
        if (ref && ref.state) {
            const rid = ref.state.c__recordId || ref.state.recordId;
            if (rid && rid !== this.recordId) this.recordId = rid;
        }
    }

    @wire(getApplication, { recordId: '$recordId' })
    wireApp({ data }) {
        if (data) this.applicationName = data.Name;
    }

    @wire(getScheduleHistory, { applicationId: '$recordId', limitRows: DEFAULT_LIMIT })
    wired(result) {
        this.wiredHistoryResult = result;
        if (result.error) {
            this.error = result.error.body?.message || String(result.error);
            return;
        }
        this.rawRows = result.data || [];
    }

    // ── lifecycle: CDC subscribe ─────────────────────────────────────────
    async connectedCallback() {
        try {
            onError((err) => {
                // eslint-disable-next-line no-console
                console.warn('[aaCallScheduleFull] empApi error', err);
                this._startPollFallback(); // unselected CDC channel lands here (audit F52)
            });
            this._cdcSub = await subscribe(CDC_SCHEDULE_CHANNEL, -1, () => {
                try {
                    if (this.wiredHistoryResult) refreshApex(this.wiredHistoryResult);
                } catch (_) { /* noop */ }
            });
            if (!this._cdcSub) this._startPollFallback();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[aaCallScheduleFull] CDC subscribe failed (polling instead):', e?.message || e);
            this._startPollFallback();
        }
    }

    async disconnectedCallback() {
        try { if (this._cdcSub) await unsubscribe(this._cdcSub); } catch (_) { /* noop */ }
        this._cdcSub = null;
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    }

    // Audit F52: only the AA_Application__c ChangeEvent member is selected
    // (one free CDC slot in the org, wave 3), so the Call Schedule channel
    // never fires and the table went stale until a manual refresh. Poll the
    // cacheable wire every 30 s instead while the tab is visible.
    _startPollFallback() {
        if (this._pollTimer) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => {
            if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
            try { if (this.wiredHistoryResult) refreshApex(this.wiredHistoryResult); } catch (_) { /* noop */ }
        }, 30000);
    }

    // ── computed: rows + sorting ─────────────────────────────────────────
    get itemCount() { return this.rawRows.length; }
    get hasRows() { return this.itemCount > 0; }
    get breadcrumbLabel() { return this.applicationName || '…'; }
    get titleText() {
        const name = this.applicationName ? ` for ${this.applicationName}` : '';
        return `Schedule History${name}`;
    }
    get subtitle() {
        const sortLabel =
            this.sortedBy === 'requestedAt' ? 'Requested At' :
            this.sortedBy === 'scheduledAt' ? 'Scheduled At' :
            this.sortedBy === 'firedAt'     ? 'Fired At'     :
            this.sortedBy === 'status'      ? 'Status'       :
            this.sortedBy === 'createdByName' ? 'By'         : 'Requested At';
        const n = this.itemCount;
        return `${n} item${n === 1 ? '' : 's'} · Sorted by ${sortLabel}`;
    }

    get sortedRows() {
        const arr = this.rawRows.map((r) => this._shapeRow(r));
        const key = this.sortedBy;
        const dir = this.sortedDirection === 'asc' ? 1 : -1;
        arr.sort((a, b) => {
            const av = a['_sort_' + key];
            const bv = b['_sort_' + key];
            if (av == null && bv == null) return 0;
            if (av == null) return 1;   // nulls last regardless of direction
            if (bv == null) return -1;
            if (av < bv) return -1 * dir;
            if (av > bv) return 1 * dir;
            return 0;
        });
        // Assign row numbers AFTER sorting so the leftmost # column tracks
        // the visible order (matches the aaFilesFull pattern).
        return arr.map((r, i) => ({ ...r, rowNum: i + 1 }));
    }

    _shapeRow(r) {
        const status = r.Status__c || '';
        const callLogId = r.Call_Log__c;
        const callLogName = r.Call_Log__r ? r.Call_Log__r.Name : null;
        const createdByName = r.CreatedBy ? r.CreatedBy.Name : 'System';
        return {
            id: r.Id,
            statusRaw: status,
            statusLabel: STATUS_LABEL_MAP[status] || status || '—',
            statusBadgeClass: STATUS_BADGE_CLASS_MAP[status] || 'slds-badge',
            requestedAtFmt: this._fmtDate(r.CreatedDate),
            scheduledAtFmt: this._fmtDate(r.Scheduled_At__c),
            firedAtFmt: r.Fired_At__c ? this._fmtDate(r.Fired_At__c) : '—',
            hasCallLog: !!callLogId,
            callLogUrl: callLogId ? `/lightning/r/AA_Call_Log__c/${callLogId}/view` : '',
            callLogName: callLogName || '',
            createdByName,
            isCancellable: status === 'Pending',
            // Sort keys — precomputed so the sorter can work on primitives
            _sort_requestedAt: r.CreatedDate || '',
            _sort_scheduledAt: r.Scheduled_At__c || '',
            _sort_firedAt:     r.Fired_At__c || '',
            _sort_status:      STATUS_LABEL_MAP[status] || status || '',
            _sort_createdByName: (createdByName || '').toLowerCase()
        };
    }

    // ── formatting ───────────────────────────────────────────────────────
    _fmtDate(iso) {
        if (!iso) return '';
        try {
            const d = new Date(iso);
            const dd = String(d.getDate()).padStart(2, '0');
            const mm = String(d.getMonth() + 1).padStart(2, '0');
            const yy = d.getFullYear();
            const hh = String(d.getHours()).padStart(2, '0');
            const mn = String(d.getMinutes()).padStart(2, '0');
            return `${dd}/${mm}/${yy}, ${hh}:${mn}`;
        } catch (_) { return iso; }
    }

    // ── sort arrows for the header buttons ──────────────────────────────
    _arrow(key) {
        return this.sortedBy === key ? (this.sortedDirection === 'asc' ? '↑' : '↓') : '';
    }
    get requestedSortArrow() { return this._arrow('requestedAt'); }
    get scheduledSortArrow() { return this._arrow('scheduledAt'); }
    get firedSortArrow()     { return this._arrow('firedAt'); }
    get statusSortArrow()    { return this._arrow('status'); }
    get bySortArrow()        { return this._arrow('createdByName'); }

    handleSort(evt) {
        const key = evt.currentTarget.dataset.key;
        if (!key) return;
        if (this.sortedBy === key) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = key;
            // Descending default for time-ish columns; ascending for text.
            this.sortedDirection = (key === 'createdByName' || key === 'status') ? 'asc' : 'desc';
        }
    }

    // ── breadcrumbs ──────────────────────────────────────────────────────
    handleBreadcrumbApps(evt) {
        evt.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: 'AA_Application__c', actionName: 'list' }
        });
    }

    handleBreadcrumbRecord(evt) {
        evt.preventDefault();
        if (!this.recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'AA_Application__c', actionName: 'view' }
        });
    }

    // ── row-level cancel ────────────────────────────────────────────────
    async handleCancelRow(evt) {
        const scheduleId = evt.currentTarget.dataset.scheduleid;
        if (!scheduleId || this.cancellingId) return;

        const confirmed = await LightningConfirm.open({
            message: "Cancel this scheduled call? You'll be able to schedule a new one.",
            variant: 'header',
            theme: 'warning',
            label: 'Cancel scheduled call'
        });
        if (!confirmed) return;

        let reason = '';
        try {
            const promptResult = await LightningPrompt.open({
                message: 'Why are you cancelling? (optional — leave blank to skip)',
                label: 'Cancel reason',
                defaultValue: '',
                theme: 'info'
            });
            if (typeof promptResult === 'string') reason = promptResult;
        } catch (_) { /* skip */ }

        this.cancellingId = scheduleId;
        try {
            await cancelScheduleApex({ scheduleId, reason: reason || null });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Schedule cancelled',
                variant: 'success'
            }));
            try { await refreshApex(this.wiredHistoryResult); } catch (_) { /* noop */ }
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: e?.body?.message || e.message || 'Cancel failed',
                variant: 'error'
            }));
        } finally {
            this.cancellingId = null;
        }
    }

    handleRefresh(evt) {
        evt.preventDefault();
        try { refreshApex(this.wiredHistoryResult); } catch (_) { /* noop */ }
    }
}