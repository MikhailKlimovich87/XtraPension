import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getFillRunPanelData from '@salesforce/apex/PC1_HandoffService.getFillRunPanelData';

/**
 * PC Fill Run Panel — shows the latest PC1_Fill_Run__c with a human-readable
 * status badge, current step, an SLDS progress bar and elapsed duration.
 *
 * Polls every 5 seconds while status ∈ {queued, running} so Fernando can watch
 * the fill in near real-time without manual refresh.
 *
 * Status picklist (restricted, from PC1_Fill_Run__c.Status__c):
 *   queued · running · ready_for_review · submitted · failed · zombie
 *
 * Gate mode: if the Application is not yet ready to fill (Stage before
 * Data Complete OR Declaration_Complete__c=false), the card renders a
 * friendly precondition message instead of exposing whatever error the
 * engine emitted on a premature attempt. This stops the confusing
 * "No answer in the data for required question — (start)" text from
 * landing in front of ops when the real issue is "not ready yet".
 */

// Snake_case picklist value → Title-Case display label. If a new value lands
// in the picklist without being added here, `_titleCase` handles it as a
// graceful fallback so the UI never renders raw "ready_for_review".
const STATUS_LABEL_MAP = {
    queued:            'Queued',
    running:           'Running',
    ready_for_review:  'Ready for Review',
    submitted:         'Submitted',
    failed:            'Failed',
    zombie:            'Stalled'
};

// SLDS badge theme per status. `slds-badge` gets the base grey pill.
const STATUS_BADGE_CLASS_MAP = {
    queued:            'slds-badge',
    running:           'slds-badge slds-theme_inverse',
    ready_for_review:  'slds-badge slds-theme_warning',
    submitted:         'slds-badge slds-theme_success',
    failed:            'slds-badge slds-theme_error',
    zombie:            'slds-badge slds-theme_error'
};

const POLL_STATUSES = new Set(['queued', 'running']);

// Stages where "Fill on DWP" is a legitimate next step. Any stage BEFORE
// Data Complete means Mary hasn't finished collecting yet, so a fill
// attempt would just error out on missing fields.
const FILL_READY_STAGES = new Set([
    'Data Complete',
    'Reviewed',
    'Filling',
    'Ready for Submit',
    'Submitted'
]);

// Status values that represent an actual live/completed fill run. When
// the latest fill is in one of these, we always show the real card —
// even if the app somehow reverted stage — because the fill did happen.
const REAL_RUN_STATUSES = new Set([
    'queued', 'running', 'ready_for_review', 'submitted'
]);

export default class Pc1FillRunPanel extends LightningElement {
    @api recordId;
    fillRun;
    stage;
    declarationComplete;
    wired;
    _timer;

    @wire(getFillRunPanelData, { applicationId: '$recordId' })
    wiredData(result) {
        this.wired = result;
        const d = result.data || {};
        this.fillRun = d.fillRun || null;
        this.stage = d.stage || null;
        this.declarationComplete = d.declarationComplete === true;
        this._maybePoll();
    }

    disconnectedCallback() { this._stopPoll(); }

    _maybePoll() {
        this._stopPoll();
        if (this.fillRun && POLL_STATUSES.has(this.fillRun.Status__c)) {
            this._timer = setInterval(() => refreshApex(this.wired), 5000);
        }
    }
    _stopPoll() { if (this._timer) { clearInterval(this._timer); this._timer = null; } }

    // ── Gate logic ──────────────────────────────────────────────────────
    // If the latest fill is an ACTUAL live/succeeded run, always show the
    // real card. If the app isn't ready AND the latest is null / a failed
    // attempt from before it was ready, show the friendly gate instead.
    get stageReady() { return FILL_READY_STAGES.has(this.stage); }
    get appReadyToFill() { return this.stageReady && this.declarationComplete; }
    get hasRealRun() {
        return this.fillRun && REAL_RUN_STATUSES.has(this.fillRun.Status__c);
    }
    // A fill that FAILED usually moves the app to Needs Human, which is not a
    // fill-ready stage — the gate then hid the engine's error and showed
    // "not available yet" to the person who has to fix it (audit 2026-10-02).
    get failedIntoNeedsHuman() {
        return this.stage === 'Needs Human' && this.fillRun
            && (this.fillRun.Status__c === 'failed' || this.fillRun.Status__c === 'zombie');
    }
    get isGated() { return !this.appReadyToFill && !this.hasRealRun && !this.failedIntoNeedsHuman; }

    // Gate messaging — 2 sub-cases: (a) stage not ready yet, (b) stage ready
    // but declaration missing. Both share the same "not blocking, just
    // waiting" tone so ops never mistakes it for a system error.
    get gateHeadline() {
        if (!this.stageReady) return 'Fill on DWP not available yet';
        return 'Waiting for signed declaration';
    }
    get gateMessage() {
        if (!this.stageReady) {
            return 'The DWP fill can only run once Mary has finished collecting all the data (Stage: Data Complete) and the declaration is signed.';
        }
        return 'All the data is collected — the declaration just needs to be signed before the fill can run.';
    }

    // ── Real-run rendering (unchanged) ──────────────────────────────────
    get hasRun() { return this.fillRun != null; }

    get rawStatus() { return this.fillRun?.Status__c || ''; }
    get statusLabel() {
        const s = this.rawStatus;
        return STATUS_LABEL_MAP[s] || this._titleCase(s) || '—';
    }
    get statusBadgeClass() {
        return STATUS_BADGE_CLASS_MAP[this.rawStatus] || 'slds-badge';
    }
    _titleCase(s) {
        if (!s) return '';
        return String(s)
            .split('_')
            .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
            .join(' ');
    }

    get hasProgress() { return this.fillRun?.Progress_Percent__c != null; }
    get rawPercent()  { return Number(this.fillRun?.Progress_Percent__c ?? 0); }
    get percent()     { return Math.min(Math.max(this.rawPercent, 0), 100); }
    get widthStyle()  { return `width:${this.percent}%`; }
    get percentLabel() { return Math.round(this.percent); }

    get hasStep() {
        return this.fillRun?.Current_Step__c != null || this.fillRun?.Total_Steps__c != null;
    }
    get stepSummary() {
        if (!this.fillRun) return '';
        const cur = this.fillRun.Current_Step__c ?? '?';
        const tot = this.fillRun.Total_Steps__c  ?? '?';
        return `Step ${cur} of ${tot}`;
    }
    get currentPage() { return this.fillRun?.Current_Page__c || ''; }
    get hasCurrentPage() { return !!this.currentPage; }

    get duration() { return this.fillRun?.Duration_Min__c; }
    get durationLabel() {
        const m = Number(this.duration);
        if (!m) return '';
        return m < 1 ? `${Math.round(m * 60)}s` : `${m.toFixed(1)} min`;
    }
    get hasDuration() { return !!this.durationLabel; }

    /** "94% · 47s" — assembled so the template stays flat. */
    get progressLine() {
        const parts = [];
        if (this.hasProgress) parts.push(`${this.percentLabel}%`);
        if (this.hasDuration) parts.push(this.durationLabel);
        return parts.join(' · ');
    }
    get hasProgressLine() { return this.hasProgress || this.hasDuration; }

    get startedAt()  { return this.fillRun?.Started_At__c || null; }
    get finishedAt() { return this.fillRun?.Finished_At__c || null; }
    get hasStartedAt()  { return !!this.startedAt; }
    get hasFinishedAt() { return !!this.finishedAt; }

    get liveViewUrl() { return this.fillRun?.Live_View_URL__c || null; }
    get hasLiveView() { return !!this.liveViewUrl && POLL_STATUSES.has(this.rawStatus); }
    get errorMessage() { return this.fillRun?.Error_Message__c || null; }
    // Only surface engine errors when the app was actually ready — otherwise
    // it's a premature-attempt error the gate should have shown instead.
    get hasError() { return !!this.errorMessage && !this.isGated; }
}