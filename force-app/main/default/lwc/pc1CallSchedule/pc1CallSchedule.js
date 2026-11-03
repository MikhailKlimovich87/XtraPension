import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import LightningConfirm from 'lightning/confirm';
import LightningPrompt from 'lightning/prompt';
import callNow from '@salesforce/apex/PC1_MaryBridge.callNow';
import getActivePending from '@salesforce/apex/PC1_CallScheduleService.getActivePending';
import createSchedule from '@salesforce/apex/PC1_CallScheduleService.createSchedule';
import cancelScheduleApex from '@salesforce/apex/PC1_CallScheduleService.cancelSchedule';

const CDC_SCHEDULE_CHANNEL = '/data/PC1_Call_Schedule__ChangeEvent';

const INPUT_DISABLED_TOOLTIP = 'Cancel the pending call first to reschedule.';

/**
 * pc1CallSchedule — "Call Scheduling" card on the Application record page.
 *
 * State A (no pending schedule) — DD/MM/YYYY HH:MM input + [Schedule] +
 *   [Call Now] + explainer.
 * State B (pending schedule exists) — inputs disabled with tooltip; a
 *   "Next call scheduled" block appears with absolute time + live relative
 *   time + requester + cancel button. Cancel opens a LightningConfirm, then
 *   an optional LightningPrompt for reason, then calls cancelSchedule.
 *
 * "View schedule history →" always visible at the bottom; opens
 * pc1CallScheduleFull in a new tab (mirrors pc1FilesCard's View All
 * pattern — window.open on the raw /lightning/n/ URL, avoids the SF
 * nav-menu cache issue).
 *
 * Live refresh — CDC on /data/PC1_Call_Schedule__ChangeEvent triggers
 * refreshApex on the pending wire whenever any Call Schedule row
 * changes. If CDC subscribe throws (channel not enabled), degrade
 * gracefully — the card still renders and works, just without live
 * push (wire caches will still refresh on user action).
 */
export default class Pc1CallSchedule extends LightningElement {
    @api recordId;
    // Native date + time inputs give us a calendar picker + 5-min-step time
    // wheel (via type="time" step="300") — matches the SF cron granularity.
    dateValue = '';   // yyyy-mm-dd (native <input type="date"> value shape)
    timeValue = '';   // HH:MM      (native <input type="time"> value shape)
    scheduling = false;
    calling = false;
    cancelling = false;

    @track pendingRow = null;
    wiredPending;
    _cdcSub;
    _relTimer;
    @track _relTick = 0; // bumped to re-evaluate pendingWhenRel getter

    // ── wires ────────────────────────────────────────────────────────────
    @wire(getActivePending, { applicationId: '$recordId' })
    wireActivePending(result) {
        this.wiredPending = result;
        if (result.data !== undefined) {
            this.pendingRow = result.data || null;
            this._maybeStartRelTimer();
        }
    }

    // ── lifecycle ────────────────────────────────────────────────────────
    async connectedCallback() {
        try {
            onError((err) => {
                // eslint-disable-next-line no-console
                console.warn('[pc1CallSchedule] empApi error', err);
            });
            this._cdcSub = await subscribe(CDC_SCHEDULE_CHANNEL, -1, (msg) => {
                // Any change to a Call Schedule row — refresh the pending wire.
                // Filtering by Application__c would require decoding the
                // change payload; the query is cheap enough to just refresh.
                try {
                    if (this.wiredPending) refreshApex(this.wiredPending);
                } catch (_) { /* noop */ }
            });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[pc1CallSchedule] CDC subscribe failed (no live refresh):', e?.message || e);
        }
    }

    async disconnectedCallback() {
        try { if (this._cdcSub) await unsubscribe(this._cdcSub); } catch (_) { /* noop */ }
        this._cdcSub = null;
        this._stopRelTimer();
    }

    _maybeStartRelTimer() {
        this._stopRelTimer();
        if (this.pendingRow) {
            // Cheap re-render trigger every 30s so "in 2h 45min" stays fresh
            // without touching the server. No wire refresh here.
            this._relTimer = setInterval(() => { this._relTick++; }, 30000);
        }
    }
    _stopRelTimer() {
        if (this._relTimer) { clearInterval(this._relTimer); this._relTimer = null; }
    }

    // ── computed state ───────────────────────────────────────────────────
    get hasPending() { return !!this.pendingRow; }
    get inputDisabled() { return this.hasPending; }
    get inputDisabledTooltip() { return this.hasPending ? INPUT_DISABLED_TOOLTIP : ''; }
    get scheduleDisabled() { return this.scheduling || this.hasPending; }
    get callDisabled()     { return this.calling; }

    get explainer() {
        return "The scheduler checks every 5 minutes and triggers Mary's call when the time arrives (stages: Awaiting First Call / Partial Data).";
    }

    // Native <input type="date"> uses yyyy-mm-dd for its min attribute;
    // block picking dates before today so we can't schedule into the past.
    get todayIso() {
        const d = new Date();
        const yyyy = d.getFullYear();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }

    // ── pending-card getters ─────────────────────────────────────────────
    get pendingWhenAbs() {
        const iso = this.pendingRow?.Scheduled_At__c;
        if (!iso) return '';
        try {
            // 2026-08-01: force Europe/London (BST/GMT-aware) so a rep whose
            // laptop is in a non-UK TZ (travel, external dev) still sees the
            // UK-local slot Mary will dial at. Prior code used browser locale
            // which drifted ±1-4h off UK time.
            const parts = new Intl.DateTimeFormat('en-GB', {
                timeZone: 'Europe/London',
                day: '2-digit', month: '2-digit', year: 'numeric',
                hour: '2-digit', minute: '2-digit', hour12: false,
            }).formatToParts(new Date(iso));
            const g = (t) => parts.find(p => p.type === t)?.value || '';
            return `${g('day')}/${g('month')}/${g('year')} ${g('hour')}:${g('minute')}`;
        } catch (_) { return iso; }
    }

    /** Live relative time — recomputed on every render (getter runs each
     *  reactive tick). No interval strictly needed for correctness but a
     *  30s timer forces a repaint so the number visibly ticks even if the
     *  user isn't interacting. */
    get pendingWhenRel() {
        // Reference _relTick so LWC's reactivity tracks it.
        // eslint-disable-next-line no-unused-vars
        const _ = this._relTick;
        const iso = this.pendingRow?.Scheduled_At__c;
        if (!iso) return '';
        const target = new Date(iso).getTime();
        const now = Date.now();
        const diffMs = target - now;
        return this._formatRelative(diffMs, /*futurePrefix=*/true);
    }

    get pendingRequestedBy() {
        return this.pendingRow?.CreatedBy?.Name || 'Unknown';
    }

    /** "30 min ago" — how long ago the schedule row was created. */
    get pendingRequestedAgo() {
        // eslint-disable-next-line no-unused-vars
        const _ = this._relTick;
        const iso = this.pendingRow?.CreatedDate;
        if (!iso) return '';
        const diffMs = Date.now() - new Date(iso).getTime();
        return this._formatRelative(diffMs, /*futurePrefix=*/false, /*agoSuffix=*/true);
    }

    /**
     * @param diffMs — positive means future when futurePrefix=true, else past
     * @param futurePrefix — prepend "in " for future values
     * @param agoSuffix    — append " ago" for past values (when !futurePrefix)
     */
    _formatRelative(diffMs, futurePrefix, agoSuffix) {
        const abs = Math.abs(diffMs);
        const s = Math.floor(abs / 1000);
        const m = Math.floor(s / 60);
        const h = Math.floor(m / 60);
        const d = Math.floor(h / 24);
        let core;
        if (s < 60)      core = `${s} sec`;
        else if (m < 60) core = h > 0 ? `${h}h ${m % 60}min` : `${m} min`;
        else if (h < 48) core = `${h}h ${m % 60}min`;
        else             core = `${d}d ${h % 24}h`;
        if (futurePrefix) {
            // If the target is already in the past, treat as "due now"
            return diffMs >= 0 ? `in ${core}` : `${core} overdue`;
        }
        if (agoSuffix) return `${core} ago`;
        return core;
    }

    // ── input handlers ───────────────────────────────────────────────────
    handleDateChange(e) {
        this.dateValue = e.detail?.value || e.target?.value || '';
    }
    handleTimeChange(e) {
        // Native time input returns HH:MM (or HH:MM:SS if step<60). Snap
        // seconds off + round minutes to nearest 5 so anything the user
        // pastes still lands on a 5-min slot the cron will fire.
        let v = (e.detail?.value || e.target?.value || '').slice(0, 5);
        const m = v.match(/^(\d{2}):(\d{2})$/);
        if (m) {
            const rounded = Math.round(Number(m[2]) / 5) * 5;
            const mi = String(Math.min(55, rounded)).padStart(2, '0');
            v = `${m[1]}:${mi}`;
        }
        this.timeValue = v;
    }

    // yyyy-mm-dd + HH:MM (both in the user's local timezone as SF/native
    // inputs do) → Date. Returns null if incomplete or invalid.
    parseWhen() {
        const d = (this.dateValue || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
        const t = (this.timeValue || '').match(/^(\d{2}):(\d{2})$/);
        if (!d || !t) return null;
        const [, yyyy, mo, dd] = d.map(Number);
        const [, hh, mi] = t.map(Number);
        const dt = new Date(yyyy, mo - 1, dd, hh, mi, 0, 0);
        if (dt.getDate() !== dd || dt.getMonth() !== mo - 1 || dt.getHours() !== hh) return null;
        return dt;
    }

    // Human echo for toasts — the calendar/time inputs don't give us a
    // pre-formatted string like the old free-form field did.
    _humanWhen(dt) {
        const pad = (n) => String(n).padStart(2, '0');
        return `${pad(dt.getDate())}/${pad(dt.getMonth() + 1)}/${dt.getFullYear()} ${pad(dt.getHours())}:${pad(dt.getMinutes())}`;
    }

    async handleSchedule() {
        // Defensive — the button is already disabled when hasPending,
        // but if a race lands us here, surface a helpful toast rather
        // than a raw trigger error.
        if (this.hasPending) {
            this.toast('Pending schedule exists', 'warning', INPUT_DISABLED_TOOLTIP);
            return;
        }
        const dt = this.parseWhen();
        if (!dt) {
            this.toast('Missing date or time', 'error', 'Pick a date and a time (5-min steps) before clicking Schedule.');
            return;
        }
        if (dt.getTime() <= Date.now()) {
            this.toast('Time must be in the future', 'error', 'Scheduled call must be after now.');
            return;
        }
        this.scheduling = true;
        try {
            // Creates a Pending PC1_Call_Schedule__c row; trigger mirrors
            // its Scheduled_At__c into Application.Next_Call_At__c for the
            // Heroku scheduler poll. Old scheduleCall (which wrote directly
            // to Next_Call_At__c) skipped the row entirely, leaving state B
            // dark and the history empty.
            await createSchedule({ applicationId: this.recordId, scheduledAt: dt.toISOString() });
            this.toast('Call scheduled', 'success', `Mary will call at ${this._humanWhen(dt)}.`);
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(new CustomEvent('schedulechange', { bubbles: true, composed: true }));
            // CDC will refresh the pending wire; also refresh manually so the
            // UI updates immediately for the acting user.
            try { await refreshApex(this.wiredPending); } catch (_) { /* noop */ }
            this.dateValue = '';
            this.timeValue = '';
        } catch (e) {
            this.toast(this.errMsg(e), 'error');
        } finally {
            this.scheduling = false;
        }
    }

    async handleCallNow() {
        this.calling = true;
        try {
            await callNow({ applicationId: this.recordId });
            this.toast('Call Now', 'success', 'Mary is dialling — the call will appear in Call History shortly.');
        } catch (e) {
            this.toast(this.errMsg(e), 'error');
        } finally {
            this.calling = false;
        }
    }

    // ── pending-card interactions ────────────────────────────────────────
    async handleCancelPending() {
        if (!this.pendingRow || this.cancelling) return;
        const confirmed = await LightningConfirm.open({
            message: "Cancel this scheduled call? You'll be able to schedule a new one.",
            variant: 'header',
            theme: 'warning',
            label: 'Cancel scheduled call'
        });
        if (!confirmed) return;

        // Reason is optional — user can hit Cancel on the prompt to skip.
        let reason = '';
        try {
            const promptResult = await LightningPrompt.open({
                message: 'Why are you cancelling? (optional — leave blank to skip)',
                label: 'Cancel reason',
                defaultValue: '',
                theme: 'info'
            });
            // LightningPrompt returns null on Cancel, string on OK
            if (typeof promptResult === 'string') reason = promptResult;
        } catch (_) { /* prompt closed — treat as skip */ }

        this.cancelling = true;
        try {
            await cancelScheduleApex({ scheduleId: this.pendingRow.Id, reason: reason || null });
            this.toast('Schedule cancelled', 'success');
            try { await refreshApex(this.wiredPending); } catch (_) { /* noop */ }
        } catch (e) {
            this.toast(this.errMsg(e), 'error');
        } finally {
            this.cancelling = false;
        }
    }

    handleViewHistory(evt) {
        evt.preventDefault();
        // Mirrors pc1FilesCard: window.open on the raw /lightning/n/ URL
        // sidesteps the SF nav-menu cache issue Fernando hit before with
        // "View All Files" (standard__navItemPage 404s until reindex).
        const url = `/lightning/n/PC1_Call_Schedule_History?c__recordId=${encodeURIComponent(this.recordId)}`;
        window.open(url, '_blank', 'noopener');
    }

    // ── helpers ──────────────────────────────────────────────────────────
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message || '', variant }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}