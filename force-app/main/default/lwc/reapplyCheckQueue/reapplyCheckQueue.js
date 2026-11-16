import { LightningElement, api } from 'lwc';
import getLetterRequests from '@salesforce/apex/ReapplyCheckController.getLetterRequests';

// Reapply stages still waiting on HMRC (same list the colour formula uses)
const OPEN_STAGES = ['Posted', 'HMRC Reply 1', 'Pending Info', 'HMRC Appeal', 'HMRC Reply 2'];
const PAGE = 50;

const BADGES = [
    ['Not_Received__c', 'Not Received'],
    ['C2__c', 'C2'],
    ['C3__c', 'C3'],
    ['Processing_Received__c', 'Processing'],
    ['BadNINO__c', 'BadNINO'],
    ['BadInfo__c', 'Bad Info'],
    ['Reject__c', 'Reject'],
    ['Work_Item__c', 'Work Item'],
    ['X64_8__c', '64-8'],
    ['DWP__c', 'DWP'],
    ['DWP_Call__c', 'DWP Call']
];

const FILTERS = [
    { key: 'todo', label: 'To check', hint: 'Everything still open except the ones HMRC already received (green)' },
    { key: 'never', label: 'Never checked', hint: 'Posted and no check yet' },
    { key: 'red', label: 'Not received / problem', hint: 'Last check red: Not Received, Bad NINO, Bad Info or Reject' },
    { key: 'yellow', label: 'Attention', hint: 'Last check yellow: Work Item, 64-8, DWP, or C2/C3 while still Posted' },
    { key: 'green', label: 'Received', hint: 'Last check green: HMRC has it' },
    { key: 'asked', label: 'Letter asked', hint: 'We emailed the client asking for the HMRC letter (after a C2/C3 or 64-8 check)' },
    { key: 'all', label: 'All open', hint: 'Every reapply still waiting on HMRC' }
];

const numberKey = value => (value || '').trim().replace(/^[A-Za-z]+/, '').replace(/^0+/, '');
const DAY = 24 * 60 * 60 * 1000;
const toDate = value => (value ? new Date(value.length === 10 ? value + 'T00:00:00Z' : value) : null);
const fmt = date => (date ? date.toISOString().slice(0, 10).split('-').reverse().join('/') : '');

export default class ReapplyCheckQueue extends LightningElement {
    @api reapplies;
    filter = 'todo';
    query = '';
    limit = PAGE;
    // Reapply Id -> latest "Has HMRC's letter reached you?" email
    asked = {};

    connectedCallback() {
        getLetterRequests()
            .then(list => {
                const byId = {};
                (list || []).forEach(x => { byId[x.reapplyId] = x; });
                this.asked = byId;
            })
            .catch(() => { this.asked = {}; });
    }

    get items() {
        const today = Date.now();
        return (this.reapplies || [])
            .filter(r => OPEN_STAGES.includes(r.Status__c) && r.Tracking_Number_Send_Date__c)
            .map(r => {
                const checks = r.Reapply_Checks__r || [];
                const last = checks[0];
                const posted = toDate(r.Tracking_Number_Send_Date__c);
                const lastDate = last ? toDate(last.Check_Date__c || last.CreatedDate) : null;
                const since = lastDate || posted;
                const colour = last ? (last.Colour_Label__c || 'NONE') : 'NEVER';
                const ask = this.asked[r.Id];
                const result = last ? BADGES.filter(([field]) => last[field] === true).map(([, label]) => label).join(', ') : 'Never checked';
                return {
                    id: r.Id,
                    name: r.Name,
                    url: '/lightning/r/Reapply__c/' + r.Id + '/view',
                    client: [r.First_Name__c, r.Second_Name__c].filter(Boolean).join(' '),
                    status: r.Status__c,
                    posted: fmt(posted),
                    lastCheck: lastDate ? fmt(lastDate) + (last.Check_Agents__c ? ' · ' + last.Check_Agents__c : '') : '',
                    result,
                    notes: last ? last.Notes__c : '',
                    colour,
                    resultCss: 'result result-' + colour.toLowerCase(),
                    days: Math.max(0, Math.floor((today - since.getTime()) / DAY)),
                    checks: checks.length,
                    letter: ask ? fmt(toDate(ask.sentDate)) + ' · ' + ask.version : '',
                    letterHint: ask ? (ask.version === 'approved'
                        ? 'Emailed: HMRC approved your REAPPLY, has their letter reached you?'
                        : 'Emailed: Your REAPPLY, has HMRC written to you?') : ''
                };
            });
    }

    matches(item, key) {
        switch (key) {
            case 'todo': return item.colour !== 'GREEN';
            case 'never': return item.colour === 'NEVER';
            case 'red': return item.colour === 'RED';
            case 'yellow': return item.colour === 'YELLOW';
            case 'green': return item.colour === 'GREEN';
            case 'asked': return !!item.letter;
            default: return true;
        }
    }

    get filtered() {
        const q = this.query.trim().toLowerCase();
        // R08694, A08694, 08694 and 8694 all find the same reapply
        const number = /\d/.test(q) ? numberKey(q) : '';
        return this.items
            .filter(i => this.matches(i, this.filter))
            .filter(i => !q || (number && numberKey(i.name).startsWith(number)) || i.client.toLowerCase().includes(q))
            .sort((a, b) => b.days - a.days || a.name.localeCompare(b.name));
    }

    get rows() {
        return this.filtered.slice(0, this.limit).map((r, i) => ({ ...r, position: i + 1 }));
    }

    get moreCount() {
        return Math.max(0, this.filtered.length - this.limit);
    }

    get moreLabel() {
        return 'Show more (' + this.moreCount + ' left)';
    }

    get filterButtons() {
        const items = this.items;
        return FILTERS.map(f => ({
            ...f,
            count: items.filter(i => this.matches(i, f.key)).length,
            css: 'chip chip-' + f.key + (this.filter === f.key ? ' chip-active' : '')
        }));
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.key;
        this.limit = PAGE;
    }

    handleSearch(event) {
        this.query = event.target.value || '';
        this.limit = PAGE;
    }

    handleMore() {
        this.limit += PAGE;
    }

    handleCheck(event) {
        this.dispatchEvent(new CustomEvent('checkreapply', { detail: event.target.dataset.name }));
    }
}