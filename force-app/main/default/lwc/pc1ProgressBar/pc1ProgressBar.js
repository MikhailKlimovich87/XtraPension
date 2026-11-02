import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'PC1_Application__c.Progress_Filled__c',
    'PC1_Application__c.Progress_Total__c',
    'PC1_Application__c.Progress_Percent__c',
    'PC1_Application__c.Progress_Missing_Sections__c',
    'PC1_Application__c.Declaration_Complete__c'
];

/**
 * pc1ProgressBar — one-glance data-collection progress for the Application
 * record page. Reads the numeric progress fields + the
 * Progress_Missing_Sections__c JSON payload produced by PC1_FlowEngine.
 *
 * Display modes (chosen by PC1_FlowEngine based on the missing count):
 *   fields   — <10 missing → compact bullet list of specific field labels
 *   sections — ≥10 missing → bullet list of the Parts that are incomplete
 *   empty    — nothing left to collect → checkmark line
 *
 * Numbers are clamped (filled ≤ total) so the "51 / 48" race window during a
 * recompute doesn't produce a broken-looking bar.
 */
export default class Pc1ProgressBar extends LightningElement {
    @api recordId;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    application;

    get rawFilled() {
        return Number(this.application?.data?.fields?.Progress_Filled__c?.value ?? 0);
    }
    get rawTotal() {
        return Number(this.application?.data?.fields?.Progress_Total__c?.value ?? 0);
    }
    get filled() {
        // Clamp during recompute race — filled must never render above total.
        return Math.min(this.rawFilled, this.rawTotal || this.rawFilled);
    }
    get total() { return this.rawTotal; }

    get percent() {
        const rawPct = Number(this.application?.data?.fields?.Progress_Percent__c?.value ?? 0);
        return Math.min(Math.max(rawPct, 0), 100);
    }
    get widthStyle() { return `width:${this.percent}%`; }
    get summary()    { return `${this.filled} / ${this.total} fields collected (${Math.round(this.percent)}%)`; }

    // ── Missing payload (JSON) ───────────────────────────────────────────

    get missingPayload() {
        const raw = this.application?.data?.fields?.Progress_Missing_Sections__c?.value;
        if (!raw) return null;
        try {
            return JSON.parse(raw);
        } catch (_e) {
            return null;
        }
    }

    get mode() {
        return this.missingPayload?.mode ?? null;
    }

    get isEmpty() {
        const p = this.missingPayload;
        if (!p) return this.total > 0 && this.filled >= this.total;
        const missingCount = Array.isArray(p.missing) ? p.missing.length : 0;
        return missingCount === 0;
    }

    get showFields()   { return !this.isEmpty && this.mode === 'fields'; }
    get showSections() { return !this.isEmpty && this.mode === 'sections'; }

    // ── Declaration state ────────────────────────────────────────────────

    get declarationComplete() {
        return this.application?.data?.fields?.Declaration_Complete__c?.value === true;
    }
    /** Data is 100% but the human still needs to sign the 3 declaration fields
     *  (decl checkbox + declname + decldate triplet) before Fill DWP is allowed. */
    get declarationPending() {
        return this.isEmpty && !this.declarationComplete;
    }
    /** All data + declaration signed → the app is truly ready for Fill DWP. */
    get readyForFill() {
        return this.isEmpty && this.declarationComplete;
    }

    /** [{key, label, part}] for the compact fields-mode list. */
    get missingFields() {
        const p = this.missingPayload;
        if (!p || !Array.isArray(p.missing)) return [];
        return p.missing.map((m, i) => ({
            key: (m && m.id) || `missing-${i}`,
            label: (m && (m.label || m.id)) || 'Unknown field',
            part: m && m.part
        }));
    }

    /** [{key, name}] for the sections-mode list. */
    get missingSections() {
        const p = this.missingPayload;
        if (!p || !Array.isArray(p.sections)) return [];
        return p.sections.map((s, i) => ({ key: `sec-${i}`, name: s }));
    }
}