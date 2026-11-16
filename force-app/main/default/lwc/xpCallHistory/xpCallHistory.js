import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getHistory from '@salesforce/apex/XpCallHistoryController.getHistory';
import requestTranscript from '@salesforce/apex/XpCallHistoryController.requestTranscript';
import TIME_ZONE from '@salesforce/i18n/timeZone';

// On the record page the card stays small: the latest few, then View all.
const CARD_ITEMS = 4;
const PAGE = 25;
const FILTERS = [
    { key: 'all', label: 'All' },
    { key: 'spoke', label: 'Spoke' },
    { key: 'notReached', label: 'Not reached' },
    { key: 'missed', label: 'Missed' },
    { key: 'in', label: 'Inbound' },
    { key: 'out', label: 'Outbound' }
];
const WHO = { 'Related contact phone': 'the related contact', 'Helper phone': 'the helper' };
const WHO_CAP = { 'Related contact phone': 'Related contact', 'Helper phone': 'Helper' };
// A client's voicemail picks up, so the exchange says Answered: what the call really was (call-voicemail-check flow).
const CHECKS = {
    'Voicemail left': { title: 'left a voicemail', pill: 'Voicemail' },
    'Voicemail, no message': { title: 'voicemail, no message left', pill: 'No answer' },
    'No conversation': { title: 'nobody on the line', pill: 'No answer' }
};

/**
 * Call History on the Application and the Claim: every Nuacom call with the
 * client (who made or took it, how long, the recording) with the call notes
 * the team logged as Tasks attached to the call they are about.
 */
export default class XpCallHistory extends NavigationMixin(LightningElement) {
    @api recordId;
    // 'card' on the record page; 'full' on the View all page (xpCallHistoryFull).
    @api mode = 'card';
    data;
    error;
    loading = true;
    filter = 'all';
    agent = '';
    shown = PAGE;
    playing = new Set();
    openNotes = new Set();
    openTranscripts = new Set();
    asking = new Set();
    _wired;

    @wire(getHistory, { recordId: '$recordId' })
    wired(result) {
        this._wired = result;
        this.loading = false;
        if (result.data) {
            this.data = result.data;
            this.error = undefined;
            this.dispatchEvent(new CustomEvent('historyloaded', { detail: { name: result.data.recordName } }));
        } else if (result.error) {
            this.error = this.messageOf(result.error);
        }
    }

    // ---------------------------------------------------------------- header

    get isFull() { return this.mode === 'full'; }
    get cardTitle() {
        const name = this.data && this.data.recordName;
        return this.isFull && name ? `Call History · ${name}` : 'Call History';
    }
    get backLabel() { return this.data && this.data.recordName ? `Back to ${this.data.recordName}` : 'Back to the record'; }
    get allCount() { return ((this.data && this.data.calls) || []).length + ((this.data && this.data.loneNotes) || []).length; }
    get showViewAll() { return !this.isFull && this.allCount > CARD_ITEMS; }
    get viewAllLabel() { return `View all (${this.allCount})`; }

    get hasData() { return !!this.data && (this.data.total > 0 || (this.data.loneNotes || []).length > 0); }
    get isEmpty() { return !this.loading && !this.error && !this.hasData; }

    get lastTalkLine() {
        const d = this.data;
        if (!d || !d.total) return '';
        if (!d.lastTalkAt) return d.answered ? '' : 'Never spoken to on the phone yet';
        const who = d.lastTalkAgent ? ` with ${d.lastTalkAgent}` : '';
        return `Last spoke ${this.relDay(d.lastTalkAt)}${who} · ${this.talk(d.lastTalkSeconds)}`;
    }
    get hasLastTalk() { return !!this.lastTalkLine; }

    get alerts() {
        const d = this.data;
        const out = [];
        if (!d) return out;
        if (d.missedSinceTalk > 0) {
            out.push({ key: 'missed', cls: 'xp-ch__alert is-bad', text: `The client rang ${d.missedSinceTalk === 1 ? 'once' : d.missedSinceTalk + ' times'} and nobody answered${d.lastTalkAt ? ' since' : ''}` });
        }
        if (d.triesSinceTalk > 1) {
            out.push({ key: 'tries', cls: 'xp-ch__alert is-warn', text: `${d.triesSinceTalk} calls without getting through${d.lastTalkAt ? ' since' : ''}` });
        }
        return out;
    }
    get hasAlerts() { return this.alerts.length > 0; }

    get stats() {
        const d = this.data;
        if (!d || !d.total) return [];
        const s = [
            { key: 'calls', value: d.total, label: d.total === 1 ? 'call' : 'calls' },
            { key: 'spoke', value: d.answered, label: 'answered' },
            { key: 'missed', value: d.missed, label: 'missed' },
            { key: 'talk', value: this.talkLong(d.talkSeconds), label: 'talking' }
        ];
        return s;
    }
    /** The card's one-line version of the counters. */
    get statsLine() {
        const d = this.data;
        if (!d || !d.total) return '';
        const parts = [`${d.total} ${d.total === 1 ? 'call' : 'calls'}`, `${d.answered} answered`];
        if (d.missed) parts.push(`${d.missed} missed`);
        if (d.talkSeconds) parts.push(`${this.talkLong(d.talkSeconds)} talking`);
        return parts.join(' · ');
    }
    get sinceLine() {
        const d = this.data;
        if (!d || !d.firstCallAt) return '';
        return `In: ${d.inbound} · Out: ${d.outbound} · since ${this.monthYear(d.firstCallAt)}`;
    }
    get truncatedLine() {
        return this.data && this.data.truncated ? `Showing the latest ${this.data.calls.length} of ${this.data.total} calls.` : '';
    }

    // --------------------------------------------------------------- filters

    get filterButtons() {
        return FILTERS.map((f) => ({ ...f, cls: `xp-ch__chip${this.filter === f.key ? ' is-on' : ''}`, pressed: String(this.filter === f.key) }));
    }
    get agentOptions() {
        const names = new Set();
        for (const c of (this.data && this.data.calls) || []) if (c.agent) names.add(c.agent);
        return [{ label: 'Everyone', value: '' }, ...[...names].sort().map((n) => ({ label: n, value: n }))];
    }
    get showAgentPicker() { return this.agentOptions.length > 2; }

    handleFilter(e) {
        this.filter = e.currentTarget.dataset.key;
        this.shown = PAGE;
    }
    handleAgent(e) {
        this.agent = e.detail.value;
        this.shown = PAGE;
    }

    matches(c) {
        if (this.agent && c.agent !== this.agent) return false;
        switch (this.filter) {
            case 'spoke': return c.spoke;
            case 'notReached': return c.direction === 'Outbound' && !c.spoke;
            case 'missed': return c.outcome === 'Missed';
            case 'in': return c.direction === 'Inbound';
            case 'out': return c.direction === 'Outbound';
            default: return true;
        }
    }

    // -------------------------------------------------------------- timeline

    get entries() {
        const d = this.data;
        if (!d) return [];
        const items = [];
        for (const c of d.calls || []) if (this.matches(c)) items.push(this.callEntry(c));
        // Notes with no call only make sense in the unfiltered view.
        if (this.filter === 'all' && !this.agent) for (const n of d.loneNotes || []) items.push(this.noteEntry(n));
        items.sort((a, b) => b.at - a.at);
        return items;
    }

    get visible() {
        // The card: the latest few, the date on each line instead of day headings.
        if (!this.isFull) return this.entries.slice(0, CARD_ITEMS);
        const out = [];
        let day = null;
        for (const e of this.entries.slice(0, this.shown)) {
            const label = this.relDay(e.at, true);
            if (label !== day) {
                out.push({ key: `day-${e.key}`, isDay: true, label });
                day = label;
            }
            out.push(e);
        }
        return out;
    }
    get listClass() { return this.isFull ? 'xp-ch__list is-full' : 'xp-ch__list'; }
    get hasVisible() { return this.entries.length > 0; }
    get noneForFilter() { return this.hasData && !this.hasVisible; }
    get hasMore() { return this.isFull && this.entries.length > this.shown; }
    get moreLabel() { return `Show ${Math.min(PAGE, this.entries.length - this.shown)} more`; }
    handleMore() { this.shown += PAGE; }

    callEntry(c) {
        const at = new Date(c.startedAt).getTime();
        const answered = c.outcome === 'Answered';
        const inbound = c.direction === 'Inbound';
        const check = answered && !inbound ? CHECKS[c.check] : null;
        const who = WHO[c.matchedOn] || 'the client';
        const Who = WHO_CAP[c.matchedOn] || 'The client';
        const agent = c.agent || (c.extension ? `ext ${c.extension}` : 'Someone');
        let title;
        if (inbound) title = answered ? `${Who} called · ${agent} answered` : `${Who} called · nobody answered`;
        else if (check) title = `${agent} called ${who} · ${check.title}`;
        else title = answered ? `${agent} called ${who}` : `${agent} called ${who} · ${String(c.outcome || 'no answer').toLowerCase()}`;

        const meta = [this.when(at)];
        const voicemail = inbound && !answered && /(^| · )voicemail$/.test(c.rang || '');
        const rang = (c.rang || '').replace(/(^| · )voicemail$/, '');
        if (!this.isFull) {
            // The card keeps one short line; lines, queues and numbers are on the full page.
            if (voicemail) meta.push('went to voicemail');
        } else {
            if (c.line) meta.push(inbound ? `to ${c.line}` : `from ${c.line}`);
            if (c.queue) meta.push(`queue ${c.queue}`);
            if (inbound && !answered && c.rang) meta.push(voicemail ? (rang ? `rang ${rang}, went to voicemail` : 'went to voicemail') : `rang ${rang}`);
            if (c.transferred) meta.push('transferred');
            if (c.clientNumber) meta.push(c.clientNumber + (c.callerIdName ? ` (${c.callerIdName})` : ''));
        }

        const notes = (c.notes || []).map((n) => this.noteView(n));
        const pill = check ? check.pill : c.outcome || '';
        return {
            key: c.id,
            id: c.id,
            at,
            isCall: true,
            title,
            meta: meta.join(' · '),
            iconCls: `xp-ch__dot ${answered && !check ? 'is-ok' : c.outcome === 'Missed' ? 'is-bad' : 'is-muted'}`,
            arrow: inbound ? '↙' : '↗',
            arrowLabel: inbound ? 'Inbound call' : 'Outbound call',
            pill,
            pillCls: `xp-ch__pill ${answered && !check ? 'is-ok' : c.outcome === 'Missed' ? 'is-bad' : 'is-muted'}`,
            duration: answered ? this.talk(c.talkSeconds) : (c.totalSeconds ? `rang ${this.talk(c.totalSeconds)}` : ''),
            who: c.matchedOn && WHO_CAP[c.matchedOn] ? WHO_CAP[c.matchedOn] : '',
            hasRecording: c.hasRecording,
            recordingUrl: c.recordingUrl,
            isPlaying: this.playing.has(c.id),
            // A missed call with a recording is the message the client left.
            playLabel: this.playing.has(c.id) ? 'Hide player' : (c.outcome === 'Missed' ? 'Play voicemail' : 'Play recording'),
            nuacomNote: c.nuacomNote,
            // A transcript someone asked XP AI for (Salesforce or Slack).
            hasTranscript: !!c.hasTranscript,
            transcriptOpen: this.openTranscripts.has(c.id),
            transcriptLabel: this.openTranscripts.has(c.id) ? 'Hide transcript' : 'Transcript',
            transcriptSummary: c.transcriptSummary || '',
            transcriptText: this.isFull ? (c.transcript || '') : '',
            canEmail: !!c.hasTranscript,
            canTranscribe: !c.hasTranscript && !c.transcribing && !!c.hasRecording && answered,
            transcribing: !!c.transcribing,
            transcriptProblem: c.transcriptProblem || '',
            asking: this.asking.has(c.id),
            hasNotes: notes.length > 0,
            notes
        };
    }

    noteEntry(n) {
        const v = this.noteView(n);
        return {
            ...v,
            key: n.id,
            at: new Date(n.createdAt).getTime(),
            isNote: true,
            meta: this.isFull
                ? `${this.when(new Date(n.createdAt).getTime())} · logged call with no phone record (a mobile, or before March 2024)`
                : `${this.when(new Date(n.createdAt).getTime())} · logged call`
        };
    }

    noteView(n) {
        const text = (n.description || '').trim();
        const isOpen = this.openNotes.has(n.id);
        // The card shows a note in one short line; the full page in full, with More.
        const cut = this.isFull ? 160 : 90;
        const isLong = text.length > cut;
        return {
            id: n.id,
            noteKey: `note-${n.id}`,
            author: n.author || 'Someone',
            subject: n.subject || 'Call',
            text: !isLong || (isOpen && this.isFull) ? text : `${text.slice(0, cut)}…`,
            hasText: !!text,
            isLong: isLong && this.isFull,
            toggleLabel: isOpen ? 'Less' : 'More'
        };
    }

    handlePlay(e) {
        const id = e.currentTarget.dataset.id;
        const next = new Set(this.playing);
        if (next.has(id)) next.delete(id); else next.add(id);
        this.playing = next;
    }
    handleTranscript(e) {
        const id = e.currentTarget.dataset.id;
        const next = new Set(this.openTranscripts);
        if (next.has(id)) next.delete(id); else next.add(id);
        this.openTranscripts = next;
    }
    async handleTranscribe(e) {
        const id = e.currentTarget.dataset.id;
        this.asking = new Set(this.asking).add(id);
        try {
            const outcome = await requestTranscript({ callLogId: id });
            this.dispatchEvent(new ShowToastEvent(outcome === 'emailed'
                ? { title: 'Sent to your email', message: 'The transcript is on its way.', variant: 'success' }
                : { title: 'Transcribing', message: 'It takes a minute or two. You will get it by email and it stays on this call.', variant: 'info' }));
            await refreshApex(this._wired);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Not transcribed', message: this.messageOf(err), variant: 'error' }));
        } finally {
            const next = new Set(this.asking);
            next.delete(id);
            this.asking = next;
        }
    }
    handleNoteToggle(e) {
        const id = e.currentTarget.dataset.id;
        const next = new Set(this.openNotes);
        if (next.has(id)) next.delete(id); else next.add(id);
        this.openNotes = next;
    }
    handleOpen(e) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: e.currentTarget.dataset.id, actionName: 'view' }
        });
    }
    handleViewAll() {
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: { componentName: 'c__xpCallHistoryFull' },
            state: { c__recordId: this.recordId }
        });
    }
    handleBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, actionName: 'view' }
        });
    }
    async handleRefresh() {
        this.loading = true;
        try { await refreshApex(this._wired); } finally { this.loading = false; }
    }

    // ------------------------------------------------------------ formatting

    talk(sec) {
        const s = Math.max(0, Number(sec) || 0);
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const r = s % 60;
        if (h) return `${h}h ${String(m).padStart(2, '0')}m`;
        return `${m}:${String(r).padStart(2, '0')}`;
    }
    talkLong(sec) {
        const s = Math.max(0, Number(sec) || 0);
        if (s < 3600) return `${Math.round(s / 60)} min`;
        return `${Math.floor(s / 3600)}h ${String(Math.round((s % 3600) / 60)).padStart(2, '0')}m`;
    }
    fmt(ms, opts) {
        try { return new Intl.DateTimeFormat('en-GB', { timeZone: TIME_ZONE, ...opts }).format(new Date(ms)); }
        catch (e) { return new Date(ms).toLocaleString('en-GB', opts); }
    }
    dayKey(ms) { return this.fmt(ms, { year: 'numeric', month: '2-digit', day: '2-digit' }); }
    relDay(value, heading) {
        const ms = typeof value === 'number' ? value : new Date(value).getTime();
        const today = this.dayKey(Date.now());
        const yesterday = this.dayKey(Date.now() - 86400000);
        const key = this.dayKey(ms);
        if (key === today) return heading ? 'Today' : 'today';
        if (key === yesterday) return heading ? 'Yesterday' : 'yesterday';
        return this.fmt(ms, { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
    }
    time(ms) { return this.fmt(ms, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }); }
    /** On the full page the day is in the heading; on the card it goes on the line. */
    when(ms) { return this.isFull ? this.time(ms) : `${this.relDay(ms, true)}, ${this.time(ms)}`; }
    monthYear(value) { return this.fmt(new Date(value).getTime(), { month: 'short', year: 'numeric' }); }

    messageOf(err) {
        const b = err && err.body;
        if (Array.isArray(b)) return b.map((x) => x.message).join(', ');
        return (b && b.message) || (err && err.message) || 'Could not load the call history.';
    }
}