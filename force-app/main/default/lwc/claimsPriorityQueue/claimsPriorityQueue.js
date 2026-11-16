import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getQueue from '@salesforce/apex/ClaimsPriorityQueueController.getQueue';

const PAGE = 50;
const STORAGE_KEY = 'claimsPriorityQueue.filters';
// Lane hints for the chips. The rules and the days are in ClaimsPriorityQueueController (DAYS).
const HINTS = {
    problem: 'The big envelope or the Stage 2 pack is stuck',
    reply: 'The client wrote or rang and nobody answered yet',
    next: 'Our own next step: check the forms, QC, DocuSign, Send to Validation, Stage 2',
    call: 'Book the validation call, do it, then Send to Validation',
    chase: 'Pending Client: ask the client for what Missing Info lists',
    esign: 'DocuSign sent and not signed: follow up with the client',
    pack: 'Big envelope posted and the signed pages are not back',
    dwp: 'The DWP needs something from the client, Agent Call or Charge DD',
    hold: 'On Hold for a while: check if it can move on'
};
const COLUMNS = [
    { key: 'priority', label: '#' },
    { key: 'claim', label: 'Claim' },
    { key: 'client', label: 'Client' },
    { key: 'stage', label: 'Stage' },
    { key: 'agent', label: 'Agent' },
    { key: 'action', label: 'What to do', noSort: true },
    { key: 'waiting', label: 'Waiting' },
    { key: 'due', label: 'Due' },
    { key: 'contact', label: 'Last contact' }
];
const DAY = 24 * 60 * 60 * 1000;

const fmt = value => (value ? value.split('-').reverse().join('/') : '');
const plural = (n, word) => n + ' ' + word + (n === 1 ? '' : 's');
const isDue = action => action.daysOverdue >= 0;
const dueText = overdue =>
    overdue > 0 ? plural(overdue, 'day') + ' overdue' : overdue === 0 ? 'Due today' : 'In ' + plural(-overdue, 'day');

export default class ClaimsPriorityQueue extends NavigationMixin(LightningElement) {
    items = [];
    agents = [];
    lanes = [];
    laneLabels = {};
    days = {};
    me;
    qcOwner = 'QC';
    liveMissingMax = 50;
    updatedAt;
    truncated = false;
    loading = true;
    error;
    showHelp = false;

    view = 'due';
    agent;
    stage = 'all';
    query = '';
    sortKey = 'priority';
    sortDir = 1;
    limit = PAGE;

    connectedCallback() {
        try {
            const saved = JSON.parse(window.sessionStorage.getItem(STORAGE_KEY) || 'null');
            if (saved) Object.assign(this, { view: saved.view || 'due', agent: saved.agent, stage: saved.stage || 'all' });
        } catch (e) {
            // no storage: start with the defaults
        }
        this.load();
    }

    load() {
        this.loading = true;
        this.error = undefined;
        getQueue()
            .then(result => {
                this.items = result.items || [];
                this.agents = result.agents || [];
                this.lanes = result.lanes || [];
                this.laneLabels = result.laneLabels || {};
                this.days = result.days || {};
                this.me = result.me;
                this.qcOwner = result.qcOwner || 'QC';
                this.liveMissingMax = result.liveMissingMax;
                this.truncated = result.truncated === true;
                this.updatedAt = new Date(result.generatedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                // first visit: the user's own work when the user is a validation agent or the QC person, else everyone's
                if (this.agent === undefined || this.agent === null) {
                    this.agent = this.me && (this.me === this.qcOwner || this.agents.includes(this.me)) ? this.me : 'all';
                }
            })
            .catch(error => {
                this.error = 'Could not load the list: ' + (error && error.body ? error.body.message : error);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    saveFilters() {
        try {
            window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ view: this.view, agent: this.agent, stage: this.stage }));
        } catch (e) {
            // ignore
        }
    }

    // ------------------------------------------------------------------ filtering

    // who does an action: the QC person for the QC of an Agent Check claim, else the claim's validation agent
    ownerOf(action, item) {
        return action.owner || item.agent || null;
    }

    // the actions of a claim the chosen agent (or QC) does
    actionsFor(item) {
        if (this.agent === 'all') return item.actions;
        if (this.agent === 'none') return item.actions.filter(a => !this.ownerOf(a, item));
        return item.actions.filter(a => this.ownerOf(a, item) === this.agent);
    }

    // agent, stage and search: the chip counts follow these. Each entry: { item, actions } with the actions left to show
    get scoped() {
        const q = this.query.trim().toLowerCase();
        const digits = q.replace(/^c/, '').replace(/^0+/, '');
        const out = [];
        this.items.forEach(i => {
            if (this.stage !== 'all' && i.stage !== this.stage) return;
            if (q && !((/\d/.test(q) && digits && i.name.replace(/^C0*/i, '').startsWith(digits)) || (i.client || '').toLowerCase().includes(q))) return;
            const actions = this.actionsFor(i);
            if (actions.length) out.push({ item: i, actions });
        });
        return out;
    }

    // the action a claim shows in a view, or null when the claim is not in that view
    shownAction(actions, view) {
        if (view === 'upcoming') return actions.some(isDue) ? null : actions[0];
        if (view === 'due') return isDue(actions[0]) ? actions[0] : null;
        return actions.find(a => a.lane === view && isDue(a)) || null;
    }

    get counts() {
        const scoped = this.scoped;
        const counts = { due: 0, upcoming: 0 };
        this.lanes.forEach(l => {
            counts[l] = 0;
        });
        scoped.forEach(({ actions }) => {
            const lanes = new Set(actions.filter(isDue).map(a => a.lane));
            if (lanes.size) counts.due++;
            else counts.upcoming++;
            lanes.forEach(l => {
                counts[l] = (counts[l] || 0) + 1;
            });
        });
        return counts;
    }

    get chips() {
        const counts = this.counts;
        const chips = [{ key: 'due', label: 'All due', hint: 'Every claim with something due today or overdue' }];
        this.lanes.forEach(l => chips.push({ key: l, label: this.laneLabels[l] || l, hint: HINTS[l] }));
        chips.push({ key: 'upcoming', label: 'Upcoming', hint: 'Nothing due yet, something due in the next ' + plural(this.days.upcoming || 7, 'day') });
        return chips.map(c => ({
            ...c,
            count: counts[c.key] || 0,
            css: 'chip chip-' + c.key + (this.view === c.key ? ' chip-active' : '') + (counts[c.key] ? '' : ' chip-empty')
        }));
    }

    get dueByAgentText() {
        const by = {};
        this.items.forEach(i => {
            // each claim once, under whoever does its first due action
            const first = i.actions.find(isDue);
            if (first) {
                const key = this.ownerOf(first, i) || 'No agent';
                by[key] = (by[key] || 0) + 1;
            }
        });
        const keys = Object.keys(by).sort();
        return keys.length ? 'Due now by agent: ' + keys.map(k => k + ' ' + by[k]).join(' · ') : '';
    }

    // ------------------------------------------------------------------ rows

    get visible() {
        const view = this.view;
        const list = [];
        this.scoped.forEach(({ item, actions }) => {
            const shown = this.shownAction(actions, view);
            if (shown) list.push({ item, actions, shown, owner: this.ownerOf(shown, item) });
        });
        const dir = this.sortDir;
        const byPriority = (a, b) =>
            a.shown.rank - b.shown.rank || b.shown.daysOverdue - a.shown.daysOverdue || a.item.name.localeCompare(b.item.name);
        const contactTime = i => (i.lastContactAt ? Date.parse(i.lastContactAt) : i.lastContactDate ? Date.parse(i.lastContactDate) : 0);
        const compare = {
            priority: byPriority,
            claim: (a, b) => a.item.name.localeCompare(b.item.name),
            client: (a, b) => (a.item.client || '').localeCompare(b.item.client || ''),
            stage: (a, b) => (a.item.stage || '').localeCompare(b.item.stage || '') || byPriority(a, b),
            agent: (a, b) => (a.owner || '~').localeCompare(b.owner || '~') || byPriority(a, b),
            waiting: (a, b) => (b.shown.daysWaiting || 0) - (a.shown.daysWaiting || 0) || byPriority(a, b),
            due: (a, b) => b.shown.daysOverdue - a.shown.daysOverdue || byPriority(a, b),
            contact: (a, b) => contactTime(a.item) - contactTime(b.item) || byPriority(a, b)
        }[this.sortKey];
        return list.sort((a, b) => dir * compare(a, b));
    }

    get visibleCount() {
        return this.visible.length;
    }

    get rows() {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        return this.visible.slice(0, this.limit).map(({ item, actions, shown, owner }, index) => {
            const overdue = shown.daysOverdue;
            const others = actions
                .filter(a => a !== shown)
                .map((a, n) => ({ key: item.claimId + '-' + n, text: a.text, due: dueText(a.daysOverdue), css: 'also-due ' + (isDue(a) ? 'due-over' : 'due-soon') }));
            let contact = '';
            if (item.lastContactAt) {
                const at = new Date(item.lastContactAt);
                const day = new Date(at.getTime());
                day.setHours(0, 0, 0, 0);
                const ago = Math.round((today.getTime() - day.getTime()) / DAY);
                contact = at.toLocaleDateString('en-GB') + (ago <= 0 ? ' (today)' : ago === 1 ? ' (yesterday)' : ' (' + plural(ago, 'day') + ' ago)');
            } else if (item.lastContactDate) {
                contact = fmt(item.lastContactDate);
            }
            const how = [item.lastContactType, item.lastContactWho].filter(Boolean).join(' · ');
            return {
                key: item.claimId,
                position: index + 1,
                url: '/lightning/r/Basic__c/' + item.claimId + '/view',
                name: item.name,
                client: item.client,
                phone: item.phone,
                stage: item.stage,
                inStage: item.daysInStage == null ? '' : plural(item.daysInStage, 'day') + ' in stage',
                agent: owner || 'No agent',
                agentNote: shown.owner && item.agent ? 'Validation agent: ' + item.agent : '',
                laneLabel: shown.laneLabel,
                laneCss: 'lane lane-' + shown.lane,
                text: shown.text,
                why: shown.why,
                others,
                hasOthers: others.length > 0,
                waiting: shown.daysWaiting == null ? '' : shown.daysWaiting <= 0 ? 'Today' : plural(shown.daysWaiting, 'day'),
                since: shown.since ? 'since ' + fmt(shown.since) : '',
                dueText: dueText(overdue),
                dueDate: fmt(shown.due),
                dueCss: 'due ' + (overdue > 7 ? 'due-late' : overdue > 0 ? 'due-over' : overdue === 0 ? 'due-today' : 'due-soon'),
                contact: contact || 'None',
                contactHow: how
            };
        });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get moreCount() {
        return Math.max(0, this.visibleCount - this.limit);
    }

    get moreLabel() {
        return 'Show more (' + this.moreCount + ' left)';
    }

    get emptyText() {
        const who = this.agent && this.agent !== 'all' && this.agent !== 'none' ? ' for ' + this.agent : '';
        if (this.view === 'upcoming') return 'Nothing coming up' + who + ' in the next ' + plural(this.days.upcoming || 7, 'day') + '.';
        if (this.view === 'due') return 'Nothing due' + who + ' right now. Upcoming shows what comes next.';
        return 'Nothing in "' + (this.laneLabels[this.view] || this.view) + '"' + who + ' right now.';
    }

    get columns() {
        return COLUMNS.map(c => ({
            ...c,
            css: 'sort' + (this.sortKey === c.key ? ' sort-active' : ''),
            arrow: this.sortKey === c.key ? (this.sortDir === 1 ? ' ▲' : ' ▼') : ''
        }));
    }

    // ------------------------------------------------------------------ options

    get agentOptions() {
        const options = [{ label: 'All agents', value: 'all' }];
        options.push({ label: 'QC (Agent Check and DocuSign)' + (this.me === this.qcOwner ? ' (me)' : ''), value: this.qcOwner });
        this.agents.forEach(a => options.push({ label: a + (a === this.me ? ' (me)' : ''), value: a }));
        options.push({ label: 'No agent', value: 'none' });
        return options;
    }

    get stageOptions() {
        const stages = [...new Set(this.items.map(i => i.stage))].sort();
        return [{ label: 'All stages', value: 'all' }, ...stages.map(s => ({ label: s, value: s }))];
    }

    // "1 day" / "3 days" for the How it works panel, from the class's DAYS
    get d() {
        const out = {};
        Object.keys(this.days).forEach(k => {
            out[k] = plural(this.days[k], 'day');
        });
        return out;
    }

    // ------------------------------------------------------------------ handlers

    handleView(event) {
        this.view = event.currentTarget.dataset.key;
        this.limit = PAGE;
        this.saveFilters();
    }

    handleAgent(event) {
        this.agent = event.detail.value;
        this.limit = PAGE;
        this.saveFilters();
    }

    handleStage(event) {
        this.stage = event.detail.value;
        this.limit = PAGE;
        this.saveFilters();
    }

    handleSearch(event) {
        this.query = event.target.value || '';
        this.limit = PAGE;
    }

    handleSort(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) return;
        if (this.sortKey === key) this.sortDir = -this.sortDir;
        else {
            this.sortKey = key;
            this.sortDir = 1;
        }
    }

    handleMore() {
        this.limit += PAGE;
    }

    toggleHelp() {
        this.showHelp = !this.showHelp;
    }

    openClaimCheck() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'Claim_Check' } });
    }
}