import { LightningElement, api } from 'lwc';

// Claim stages still waiting on the DWP
const OPEN_STAGES = ['Posted to DWP', '45D Check', 'Awaiting Lump Sum Letter', 'Agent Call', 'Decision Posted to DWP', 'Awaiting DWP Payment'];
const PAGE = 50;

const BADGES = [
    ['Not_Received__c', 'Not Received'],
    ['Received_by_DWP__c', 'Received'],
    ['Processing__c', 'Processing'],
    ['More_Info_Requested__c', 'More info'],
    ['Approved__c', 'Approved'],
    ['Rejected__c', 'Rejected'],
    ['Lump_Sum_Letter__c', 'Lump Sum Letter'],
    ['Payment_Started__c', 'Payment Started'],
    ['Called_DWP__c', 'Called DWP']
];

const FILTERS = [
    { key: 'todo', label: 'To check', hint: 'Everything still open except the ones the DWP already has (green)' },
    { key: 'never', label: 'Never checked', hint: 'Sent to the DWP and no check yet' },
    { key: 'red', label: 'Not received / rejected', hint: 'Last check red: Not Received or Rejected' },
    { key: 'yellow', label: 'More info', hint: 'Last check yellow: the DWP asked for more info' },
    { key: 'green', label: 'With the DWP', hint: 'Last check green: received, processing, approved, lump sum letter or payment started' },
    { key: 'all', label: 'All open', hint: 'Every claim still waiting on the DWP' }
];

const numberKey = value => (value || '').trim().replace(/^[A-Za-z]+/, '').replace(/^0+/, '');
const DAY = 24 * 60 * 60 * 1000;
const toDate = value => (value ? new Date(value.length === 10 ? value + 'T00:00:00Z' : value) : null);
const fmt = date => (date ? date.toISOString().slice(0, 10).split('-').reverse().join('/') : '');

export default class ClaimCheckQueue extends LightningElement {
    @api claims;
    filter = 'todo';
    query = '';
    limit = PAGE;

    get items() {
        const today = Date.now();
        return (this.claims || [])
            .filter(c => OPEN_STAGES.includes(c.Status__c))
            .map(c => {
                const checks = c.Claim_Checks__r || [];
                const last = checks[0];
                const posted = toDate(c.Stage_1_Pack_Posted_Date__c || c.Big_Envelop_Posted_Date__c);
                const lastDate = last ? toDate(last.Check_Date__c || last.CreatedDate) : null;
                // no posted date yet: count from when the claim was created
                const since = lastDate || posted || toDate(c.CreatedDate);
                const colour = last ? (last.Colour_Label__c || 'NONE') : 'NEVER';
                const result = last ? BADGES.filter(([field]) => last[field] === true).map(([, label]) => label).join(', ') : 'Never checked';
                return {
                    id: c.Id,
                    name: c.Name,
                    url: '/lightning/r/Basic__c/' + c.Id + '/view',
                    client: [c.First_Name__c, c.Last_Name__c].filter(Boolean).join(' '),
                    status: c.Status__c,
                    posted: fmt(posted),
                    lastCheck: lastDate ? fmt(lastDate) + (last.Check_Agents__c ? ' · ' + last.Check_Agents__c : '') : '',
                    result,
                    notes: last ? last.Notes__c : '',
                    colour,
                    resultCss: 'result result-' + colour.toLowerCase(),
                    days: since ? Math.max(0, Math.floor((today - since.getTime()) / DAY)) : 0,
                    checks: checks.length
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
            default: return true;
        }
    }

    get filtered() {
        const q = this.query.trim().toLowerCase();
        // C00123, 00123 and 123 all find the same claim
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
        this.dispatchEvent(new CustomEvent('checkclaim', { detail: event.target.dataset.name }));
    }
}