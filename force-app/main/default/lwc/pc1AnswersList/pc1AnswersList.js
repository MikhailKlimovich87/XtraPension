import { LightningElement, api, wire, track } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import FLOW_URL from '@salesforce/resourceUrl/pc1FlowConfig';
import getAnswers from '@salesforce/apex/PC1_AnswersController.getAnswers';

/**
 * pc1AnswersList — "Application data" panel, Hostinger-parity.
 *
 * Joins PC1_Answer__c rows with the master DWP flow (pc1FlowConfig static
 * resource — same file that drives the client-facing form) so each answer
 * appears under the human question label ("What is your date of birth?")
 * grouped under its Part ("Part 1 — About you"), instead of the raw
 * Field_Id__c which is only meaningful to devs. Radio/select values are
 * mapped from option code -> option label. Missing labels for an id (Mary
 * emitted a key the flow doesn't know) are surfaced under "Unmapped" so
 * bugs are visible, not silent.
 */
export default class Pc1AnswersList extends LightningElement {
    @api recordId;
    @track parts = [];
    @track totalFilled = 0;
    @track totalKnown = 0;
    error;

    flowIndex; // { fieldId -> { label, part, q, options: [[code,label]] } }
    partsOrder = [];
    answers;

    connectedCallback() {
        this.loadFlow();
    }

    async loadFlow() {
        try {
            const res = await fetch(FLOW_URL);
            const flow = await res.json();
            const buckets = [
                ...(flow.PAGES || []),
                ...(flow.CHILD_PAGES || []),
                ...(flow.PENSION_PAGES || []),
                ...(flow.MONEY_PAGES || [])
            ];
            const idx = {};
            const seenParts = [];
            for (const page of buckets) {
                if (page.part && !seenParts.includes(page.part)) seenParts.push(page.part);
                for (const f of (page.fields || [])) {
                    idx[f.id] = {
                        id: f.id,
                        label: f.label,
                        part: page.part || 'Other',
                        q: f.q && f.q !== '—' ? f.q : '',
                        type: f.type,
                        options: f.options || null
                    };
                }
            }
            this.flowIndex = idx;
            this.partsOrder = seenParts;
            this.rebuild();
        } catch (e) {
            this.error = 'Failed to load flow config: ' + (e.message || e);
        }
    }

    @wire(getAnswers, { applicationId: '$recordId' })
    wired({ data, error }) {
        if (error) { this.error = error.body?.message || String(error); return; }
        this.answers = data || [];
        this.rebuild();
    }

    rebuild() {
        if (!this.flowIndex || !this.answers) return;
        // Bucket answers by part.
        const byPart = {}; // part -> [{q, label, valueFormatted, source, badge}]
        const unmapped = [];
        for (const a of this.answers) {
            const meta = this.flowIndex[a.Field_Id__c];
            const row = {
                id: a.Id,
                q: meta?.q || '',
                label: meta?.label || a.Field_Id__c,
                value: this.formatValue(a.Value__c, meta),
                isEmpty: !a.Value__c || a.Value__c === '' || a.Value__c === 'demo-value',
                source: a.Source__c,
                badgeLabel: this.badgeLabel(a.Source__c),
                badgeClass: this.badgeClass(a.Source__c)
            };
            const part = meta?.part || 'Unmapped';
            (byPart[part] = byPart[part] || []).push(row);
            if (!meta) unmapped.push(a.Field_Id__c);
        }
        // Build parts in flow order, then append any unknown parts + Unmapped.
        const seenPartNames = new Set();
        const ordered = [];
        for (const p of this.partsOrder) {
            if (byPart[p] && !seenPartNames.has(p)) {
                ordered.push({ name: p, rows: byPart[p] });
                seenPartNames.add(p);
            }
        }
        for (const p of Object.keys(byPart)) {
            if (!seenPartNames.has(p)) ordered.push({ name: p, rows: byPart[p] });
        }
        // Count filled and known-total per part for the X/Y badge.
        this.parts = ordered.map(p => {
            const filled = p.rows.filter(r => !r.isEmpty).length;
            return {
                name: p.name,
                rows: p.rows,
                filled,
                total: p.rows.length,
                counter: `${filled}/${p.rows.length}`
            };
        });
        this.totalFilled = this.parts.reduce((s, p) => s + p.filled, 0);
        this.totalKnown = this.parts.reduce((s, p) => s + p.total, 0);
        if (unmapped.length) {
            // Log-only for now — surfaced as an "Unmapped" section too.
            // eslint-disable-next-line no-console
            console.debug('[pc1AnswersList] unmapped field ids:', unmapped);
        }
    }

    formatValue(raw, meta) {
        if (raw == null || raw === '') return '(empty)';
        if (raw === 'demo-value') return '(empty)';
        if (meta && meta.options && Array.isArray(meta.options)) {
            const hit = meta.options.find(o => o[0] === raw);
            if (hit) return hit[1];
        }
        // Date-ish: yyyy-mm-dd -> dd / mm / yyyy (Hostinger renders that way).
        if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
            const [y, m, d] = raw.split('-');
            return `${+d} / ${+m} / ${y}`;
        }
        return raw;
    }

    badgeLabel(src) {
        if (src === 'mary')  return 'Mary';
        if (src === 'human') return 'Human';
        if (src === 'default') return 'Default';
        return src;
    }
    badgeClass(src) {
        // SLDS badge palette
        if (src === 'mary')  return 'slds-badge slds-badge_lightest';
        if (src === 'human') return 'slds-badge slds-theme_success';
        return 'slds-badge';
    }

    get isEmpty() { return !this.error && (!this.answers || this.answers.length === 0); }
    get counter() { return `${this.totalFilled}/${this.totalKnown}`; }
    get subtitle() { return `${this.counter} fields collected — the client's own DWP question path`; }
}