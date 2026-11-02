import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

const CDC_APP_CHANNEL    = '/data/PC1_Application__ChangeEvent';
const CDC_ANSWER_CHANNEL = '/data/PC1_Answer__ChangeEvent';
import FULL_NAME_FIELD from '@salesforce/schema/PC1_Application__c.Full_Name__c';
import FIRST_NAME_FIELD from '@salesforce/schema/PC1_Application__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/PC1_Application__c.Last_Name__c';
import FLOW_URL       from '@salesforce/resourceUrl/pc1FlowConfig';
import getAnswers      from '@salesforce/apex/PC1_RecordPageService.getAnswers';
import getFlowConfig   from '@salesforce/apex/PC1_RecordPageService.getFlowConfig';
import saveField       from '@salesforce/apex/PC1_RecordPageService.saveField';
import getPathForRecord from '@salesforce/apex/PC1_FlowEngine.getPathForRecord';

// ── module-level singleton cache ────────────────────────────────────────────
// Salesforce mounts the record-page LWC twice (edit-mode preview + view-mode,
// or slds-scope re-parenting). Each instance runs connectedCallback → its
// own fetch(). Two racing fetches to the same StaticResource in one page
// causes the second one to fail with a Proxy(Object) error under Lightning
// Locker, and the visible-to-user instance is (unluckily) always the second.
// We share the parsed flow at module scope so the second instance uses the
// first's result instead of re-fetching.
let _flowCache = null;
let _flowPromise = null;
function loadFlowOnce() {
    if (_flowCache) return Promise.resolve(_flowCache);
    if (_flowPromise) return _flowPromise;
    _flowPromise = fetch(FLOW_URL)
        .then(r => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.text(); })
        .then(txt => JSON.parse(txt))
        .catch(e => {
            // Static-resource fetch can be redirected/blocked (LWS, CSP,
            // login redirects returning HTML). Fall back to Apex, which
            // reads the StaticResource body server-side.
            // eslint-disable-next-line no-console
            console.warn('[pc1ApplicationData] fetch(pc1FlowConfig) failed — falling back to Apex getFlowConfig', e);
            return getFlowConfig().then(body => JSON.parse(body));
        })
        .then(flow => {
            if (!flow || !Array.isArray(flow.PAGES)) throw new Error('pc1FlowConfig: unexpected shape');
            _flowCache = flow;
            return _flowCache;
        })
        .catch(e => {
            // Reset so a future mount can retry, but don't cache a bad value.
            _flowPromise = null;
            throw e;
        });
    return _flowPromise;
}

// Pages inside CHILD_PAGES / PENSION_PAGES / MONEY_PAGES carry NO `part`
// property (they're repeating sub-flow templates). Grouping them by
// `page.part` used to push `undefined` into the section list and
// `part.replace(...)` then threw a TypeError — which the old promise chain
// swallowed by resetting the flow to {PAGES:[]} → "0 / 0 across 0 parts".
const BUCKET_FALLBACK_PART = {
    CHILD_PAGES:   'Part 3 — Children and qualifying young people',
    PENSION_PAGES: 'Part 8 — Other pensions',
    MONEY_PAGES:   'Part 9 — Income and money'
};

/** Fields the human signs manually at submit time. Rendered in the "path"
 *  tab so operators can find + fill them without hunting through "All",
 *  but NEVER counted toward Progress_Filled / Progress_Total (declaration
 *  is outside "what Mary does" — see PC1_FlowEngine's Q3 decision). */
const DECLARATION_IDS = new Set(['decl', 'declname', 'decldate']);

/**
 * pc1ApplicationData — the centrepiece. Renders every PC1_Answer__c row for
 * the current Application, grouped by pc1-flow.json Part.
 *
 * Two sub-tabs (lightning-tabset):
 *   • "This client's path" (DEFAULT) — only fields the FlowEngine considers
 *     required for this client given current answers; sections with 0 fields
 *     are hidden.
 *   • "All possible fields" — every field in the flow (legacy behavior).
 *
 * Field locking (both tabs):
 *   • Fields in FlowEngine's blockedFieldIds show a 🔒 icon and grayed value.
 *   • Clicking the pencil or value on a locked field opens a LightningConfirm
 *     with the FlowEngine-supplied reason ("Requires an answer to <gate>").
 *
 * Rendering rules (unchanged):
 *   • Each Part is a collapsible section (chevron ▼)
 *   • Field row: [Q ID pill] question + value + source badge + pencil edit
 *   • Date fields render DD/MM/YYYY unified
 *   • radio/yesno/select show friendly labels
 *   • Empty answers show italic "Not collected"
 *   • Inline editor → Enter/Save persists via PC1_RecordPageService.saveField
 */
export default class Pc1ApplicationData extends LightningElement {
    @api recordId;

    answers = [];      // PC1_Answer__c list
    wiredAnswers;
    wiredPath;
    pathData = null;   // { requiredFieldIds, blockedFieldIds, blockedReasonById, filled, total, declarationComplete, ... }

    flow;              // parsed pc1-flow.json  { PAGES: [...] }
    flowLoaded = false;

    @track editingKey = null;   // fieldId currently being edited
    @track collapsed = new Set();
    @track allSections = [];    // every field grouped by part (legacy view)
    @track pathSections = [];   // only required fields on this client's path

    // ── wires ────────────────────────────────────────────────────────────
    @wire(getAnswers, { recordId: '$recordId' })
    wireAnswers(result) {
        this.wiredAnswers = result;
        if (result.data) {
            this.answers = result.data;
            this.safeRecompute();
        }
    }

    // Load Full_Name__c / First / Last so the declname row can show the
    // client name as a suggestion (copy-paste + one-click "Use it" button).
    @wire(getRecord, { recordId: '$recordId', fields: [FULL_NAME_FIELD, FIRST_NAME_FIELD, LAST_NAME_FIELD] })
    wireApp(result) {
        if (result.data) {
            const rec = result.data;
            const full  = getFieldValue(rec, FULL_NAME_FIELD);
            const first = getFieldValue(rec, FIRST_NAME_FIELD);
            const last  = getFieldValue(rec, LAST_NAME_FIELD);
            this.suggestedName = full || [first, last].filter(Boolean).join(' ') || '';
            this.safeRecompute();
        }
    }
    suggestedName = '';

    @wire(getPathForRecord, { recordId: '$recordId' })
    wirePath(result) {
        this.wiredPath = result;
        if (result.data) {
            this.pathData = result.data;
            this.safeRecompute();
        } else if (result.error) {
            // eslint-disable-next-line no-console
            console.warn('[pc1ApplicationData] getPathForRecord failed — path tab will be empty', result.error);
            this.pathData = null;
        }
    }

    // CDC subscriptions — live-refresh answers when Mary (or the fill
    // worker) writes to PC1_Answer__c mid-call. Without this the details
    // grid stays stale until the operator manually reloads.
    _appSub;
    _ansSub;

    async connectedCallback() {
        try {
            this.flow = await loadFlowOnce();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[pc1ApplicationData] flow load failed (fetch AND Apex fallback)', e);
            this.flow = { PAGES: [] };
        }
        const buckets = ['PAGES','CHILD_PAGES','PENSION_PAGES','MONEY_PAGES']
            .map(k => `${k}=${(this.flow[k]||[]).length}`).join(' ');
        // eslint-disable-next-line no-console
        console.log('[pc1ApplicationData] flow ready — buckets:', buckets);
        this.flowLoaded = true;
        this.safeRecompute();

        // Best-effort CDC — if not enabled at object level, the page still
        // works, just without live refresh.
        try {
            onError((err) => console.warn('[pc1ApplicationData] empApi error', err));
            this._appSub = await subscribe(CDC_APP_CHANNEL, -1, (msg) => {
                try {
                    const hdr = msg?.data?.payload?.ChangeEventHeader;
                    if (hdr?.recordIds?.includes(this.recordId)) {
                        if (this.wiredPath) refreshApex(this.wiredPath);
                    }
                } catch (_) {}
            });
            this._ansSub = await subscribe(CDC_ANSWER_CHANNEL, -1, () => {
                // Too many parents to filter cheaply; just refresh answers +
                // path — both SOQL queries are fast + scoped by recordId.
                try {
                    if (this.wiredAnswers) refreshApex(this.wiredAnswers);
                    if (this.wiredPath)    refreshApex(this.wiredPath);
                } catch (_) {}
            });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[pc1ApplicationData] CDC subscribe failed (will not live-refresh):', e?.message || e);
        }
    }

    async disconnectedCallback() {
        try { if (this._appSub) await unsubscribe(this._appSub); } catch (_) {}
        try { if (this._ansSub) await unsubscribe(this._ansSub); } catch (_) {}
        this._appSub = null;
        this._ansSub = null;
    }

    safeRecompute() {
        try {
            this.recompute();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[pc1ApplicationData] recompute failed', e);
        }
    }

    // ── lookups ──────────────────────────────────────────────────────────
    get answerMap() {
        const m = {};
        for (const a of this.answers) m[a.Field_Id__c] = a;
        return m;
    }

    get requiredSet() {
        const s = new Set();
        const ids = this.pathData && this.pathData.requiredFieldIds;
        if (Array.isArray(ids)) for (const id of ids) s.add(id);
        return s;
    }

    get blockedSet() {
        const s = new Set();
        const ids = this.pathData && this.pathData.blockedFieldIds;
        if (Array.isArray(ids)) for (const id of ids) s.add(id);
        return s;
    }

    /** Optional fields ON the client's path — visible in the path tab so
     *  operators can edit them (phone numbers, address line 2, middle
     *  names, etc.) even though they don't count toward Progress totals. */
    get pathOptionalSet() {
        const s = new Set();
        const ids = this.pathData && this.pathData.pathOptionalFieldIds;
        if (Array.isArray(ids)) for (const id of ids) s.add(id);
        return s;
    }

    get blockedReasons() {
        return (this.pathData && this.pathData.blockedReasonById) || {};
    }

    // ── section computation ──────────────────────────────────────────────
    recompute() {
        if (!this.flowLoaded || !this.flow) { this.allSections = []; this.pathSections = []; return; }
        const map = this.answerMap;
        const groups = new Map(); // part -> fields[]
        const order = [];

        for (const bucket of ['PAGES', 'CHILD_PAGES', 'PENSION_PAGES', 'MONEY_PAGES']) {
            for (const page of (this.flow[bucket] || [])) {
                if (!page.fields || !page.fields.length) continue;
                const part = page.part || BUCKET_FALLBACK_PART[bucket] || 'Other';
                if (!groups.has(part)) {
                    groups.set(part, []);
                    order.push(part);
                }
                for (const f of page.fields) {
                    groups.get(part).push(f);
                }
            }
        }

        const requiredSet = this.requiredSet;
        const optionalSet = this.pathOptionalSet;
        const blockedSet = this.blockedSet;
        const reasons = this.blockedReasons;
        const knowPath = requiredSet.size > 0 || optionalSet.size > 0 || blockedSet.size > 0;

        const allSections = [];
        const pathSections = [];

        for (const part of order) {
            const fields = groups.get(part);
            const allRows = [];
            const pathRows = [];
            let filledAll = 0;
            let filledPath = 0;
            let totalPath = 0; // excludes declaration + optional rows so counter stays honest
            for (const f of fields) {
                const row = this.buildRow(f, map, blockedSet, reasons);
                if (row.answered) filledAll++;
                allRows.push(row);
                const isDecl = DECLARATION_IDS.has(f.id);
                const isOptional = optionalSet.has(f.id);
                if (requiredSet.has(f.id) || isDecl || isOptional) {
                    // Declaration + optional rows appear in the path list
                    // but don't count toward the section/tab counters.
                    if (!isDecl && !isOptional) {
                        totalPath++;
                        if (row.answered) filledPath++;
                    }
                    pathRows.push(row);
                }
            }
            const totalAll = allRows.length;

            allSections.push(this.buildSection(part, allRows, filledAll, totalAll));
            if (pathRows.length > 0) {
                pathSections.push(this.buildSection(part, pathRows, filledPath, totalPath));
            }
        }

        this.allSections = allSections;
        // If FlowEngine data hasn't arrived yet, don't render a misleading
        // empty "path" tab — mirror the all-fields view until we know better.
        this.pathSections = knowPath ? pathSections : [];
    }

    buildSection(part, rows, filled, total) {
        const isCollapsed = this.collapsed.has(part);
        return {
            part,
            id: String(part).replace(/[^a-z0-9]+/gi, '-'),
            cls: `section${isCollapsed ? ' collapsed' : ''}`,
            bodyCls: `section-body${isCollapsed ? ' hidden' : ''}`,
            chevron: isCollapsed ? '▶' : '▼',
            expandedAttr: isCollapsed ? 'false' : 'true',
            fields: rows,
            filled, total,
            headerBadge: `${filled}/${total}`
        };
    }

    buildRow(field, map, blockedSet, reasons) {
        const isEditing = this.editingKey === field.id;

        let answered = false;
        let valueHtml;
        let src = null;
        let editorSpec = { kind: 'text', value: '', options: [] };

        if (field.type === 'date') {
            let d = map[field.id + '_day']?.Value__c;
            let m = map[field.id + '_month']?.Value__c;
            let y = map[field.id + '_year']?.Value__c;
            if (!(d && m && y)) {
                const iso = map[field.id]?.Value__c;
                const hit = typeof iso === 'string' && iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
                if (hit) { y = hit[1]; m = hit[2]; d = hit[3]; }
            }
            answered = !!(d && m && y);
            if (answered) valueHtml = `${d} / ${m} / ${y}`;
            else          valueHtml = null;
            src = map[field.id + '_day']?.Source__c || map[field.id + '_month']?.Source__c || map[field.id + '_year']?.Source__c || map[field.id]?.Source__c;
            editorSpec = { kind: 'date', day: d || '', month: m || '', year: y || '' };
        } else {
            const a = map[field.id];
            const raw = a?.Value__c;
            src = a?.Source__c;
            answered = raw != null && raw !== '';
            if (field.type === 'yesno') {
                valueHtml = raw === 'yes' ? 'Yes' : raw === 'no' ? 'No' : (raw || null);
                editorSpec = { kind: 'select', value: raw || '', options: [
                    { value: '',    label: '— not collected —', selected: !raw },
                    { value: 'yes', label: 'Yes',                selected: raw === 'yes' },
                    { value: 'no',  label: 'No',                 selected: raw === 'no'  }
                ]};
            } else if ((field.type === 'radio' || field.type === 'select') && field.options) {
                const hit = field.options.find(o => o[0] === raw);
                valueHtml = hit ? hit[1] : (raw || null);
                editorSpec = { kind: 'select', value: raw || '', options: [{ value: '', label: '— not collected —', selected: !raw }]
                    .concat(field.options.map(o => ({ value: o[0], label: o[1], selected: raw === o[0] })))
                };
            } else if (field.type === 'checkboxes') {
                let arr = [];
                try {
                    if (Array.isArray(raw)) arr = raw;
                    else if (typeof raw === 'string' && raw.trim().startsWith('[')) arr = JSON.parse(raw);
                    else if (typeof raw === 'string') arr = raw.split(/[,;]\s*/).filter(Boolean);
                } catch (_) { arr = []; }
                const opts = field.options || [];
                const labels = arr.map(v => (opts.find(o => o[0] === v) || [null, v])[1]);
                valueHtml = labels.length ? labels.join(', ') : null;
                answered = labels.length > 0;
                editorSpec = { kind: 'checkboxes', values: arr, options: opts.map(o => ({ value: o[0], label: o[1], checked: arr.includes(o[0]) })) };
            } else if (field.type === 'textarea') {
                valueHtml = raw || null;
                editorSpec = { kind: 'textarea', value: raw || '' };
            } else {
                valueHtml = raw || null;
                editorSpec = { kind: 'text', value: raw || '' };
            }
        }

        const srcBadge = this.srcBadge(src);
        const isBlocked = blockedSet.has(field.id);
        const blockedReason = isBlocked ? (reasons[field.id] || 'This field depends on an earlier answer that has not been provided yet.') : '';

        // Value styling: empty & blocked both share the muted gray look.
        let valueCls = 'fvalue';
        if (!answered) valueCls += ' empty';
        if (isBlocked) valueCls += ' locked';

        return {
            key: field.id,
            qTag: field.q && field.q !== '—' ? field.q : '',
            hasQTag: !!(field.q && field.q !== '—'),
            label: field.label || field.id,
            hint: field.hint || '',
            hasHint: !!field.hint,
            answered,
            valueHtml: valueHtml,
            displayValue: answered ? valueHtml : (isBlocked ? 'Locked — depends on an earlier answer' : 'Not collected'),
            valueCls,
            srcLabel: srcBadge.label,
            srcCls: srcBadge.cls,
            hasSrc: !!srcBadge.label,
            isEditing,
            isBlocked,
            blockedReason,
            pencilCls: isBlocked ? 'pencil locked' : 'pencil',
            pencilTitle: isBlocked ? blockedReason : 'Edit',
            editorSpec,
            editorIsText:       editorSpec.kind === 'text',
            editorIsTextarea:   editorSpec.kind === 'textarea',
            editorIsSelect:     editorSpec.kind === 'select',
            editorIsCheckboxes: editorSpec.kind === 'checkboxes',
            editorIsDate:       editorSpec.kind === 'date',
            fieldType: field.type || 'text',
            editAriaLabel: isBlocked ? `Locked: ${field.label || field.id}` : `Edit ${field.label || field.id}`,
            // Declaration-only helpers surfaced by the row template:
            // declname row shows a "Use client name" quick-fill button;
            // decldate row shows a "Today" quick-fill button.
            isDeclName: field.id === 'declname',
            isDeclDate: field.id === 'decldate',
            suggestedName: field.id === 'declname' ? (this.suggestedName || '') : '',
            hasSuggestedName: field.id === 'declname' && !!this.suggestedName
        };
    }

    srcBadge(source) {
        if (!source) return { label: '', cls: '' };
        if (source === 'mary')    return { label: 'Mary',    cls: 'src-badge src-mary' };
        if (source === 'default') return { label: 'default', cls: 'src-badge src-default' };
        return { label: 'Human', cls: 'src-badge src-human' };
    }

    // ── interactions ─────────────────────────────────────────────────────
    toggleSection(evt) {
        const part = evt.currentTarget.dataset.part;
        if (this.collapsed.has(part)) this.collapsed.delete(part);
        else                          this.collapsed.add(part);
        this.recompute();
    }

    async openEditor(evt) {
        const key = evt.currentTarget.dataset.key;
        const blocked = evt.currentTarget.dataset.blocked === 'true';
        if (!key) return;
        if (blocked) {
            const reason = evt.currentTarget.dataset.reason
                || this.blockedReasons[key]
                || 'This field depends on an earlier answer that has not been provided yet.';
            await LightningConfirm.open({
                message: reason,
                variant: 'header',
                theme: 'warning',
                label: 'This field is not yet editable'
            });
            return;
        }
        this.editingKey = key;
        this.recompute();
    }

    cancelEditor() {
        this.editingKey = null;
        this.recompute();
    }

    async saveEditor(evt) {
        const key = evt.currentTarget.dataset.key;
        const wrap = this.template.querySelector(`[data-editor-key="${key}"]`);
        if (!wrap) return;
        const kind = wrap.dataset.kind;
        const saves = []; // [fieldId, value]

        if (kind === 'date') {
            const d = wrap.querySelector('[data-p="day"]').value.trim();
            const m = wrap.querySelector('[data-p="month"]').value.trim();
            const y = wrap.querySelector('[data-p="year"]').value.trim();
            if (d || m || y) {
                if (!d || !m || !y) return this.toast('Enter a full date', 'error');
                if (Number(d) < 1 || Number(d) > 31) return this.toast('Day 1–31', 'error');
                if (Number(m) < 1 || Number(m) > 12) return this.toast('Month 1–12', 'error');
                if (!/^\d{4}$/.test(y))              return this.toast('Year 4-digit', 'error');
            }
            saves.push([key + '_day', d]);
            saves.push([key + '_month', m]);
            saves.push([key + '_year', y]);
        } else if (kind === 'checkboxes') {
            const checked = [...wrap.querySelectorAll('input[type="checkbox"]:checked')].map(i => i.value);
            saves.push([key, JSON.stringify(checked)]);
        } else {
            const el = wrap.querySelector('[data-input]');
            saves.push([key, el ? el.value : '']);
        }

        try {
            for (const [fid, val] of saves) {
                await saveField({ applicationId: this.recordId, fieldId: fid, value: val, source: 'human' });
            }
            this.toast('Saved', 'success');
            this.editingKey = null;
            // Refresh BOTH wires so blocked / required lists reflect the newly-
            // answered gate immediately (unlocking downstream fields).
            await Promise.all([
                refreshApex(this.wiredAnswers),
                refreshApex(this.wiredPath)
            ]);
        } catch (e) {
            this.toast(e?.body?.message || e.message || 'Save failed', 'error');
        }
    }

    handleEditorKey(evt) {
        if (evt.key === 'Escape') this.cancelEditor();
    }

    // ── Declaration quick-fill helpers ───────────────────────────────────
    // Save the client's name straight into declname without opening the
    // pencil — matches the paper-flow of an operator copying the name from
    // the top of the record card.
    async handleUseSuggestedName() {
        if (!this.suggestedName || !this.recordId) return;
        try {
            await saveField({
                applicationId: this.recordId,
                fieldId: 'declname',
                value: this.suggestedName,
                source: 'human'
            });
            this.toast(`Signature name set to "${this.suggestedName}"`, 'success');
            await refreshApex(this.wiredAnswers);
            if (this.wiredPath) await refreshApex(this.wiredPath);
        } catch (e) {
            this.toast(e?.body?.message || e.message || 'Save failed', 'error');
        }
    }

    // Save today's date across the decldate triplet (_day/_month/_year) in
    // one click — the DWP submission's date-of-signature field.
    async handleToday() {
        if (!this.recordId) return;
        const now = new Date();
        const day   = String(now.getDate());
        const month = String(now.getMonth() + 1);
        const year  = String(now.getFullYear());
        try {
            await Promise.all([
                saveField({ applicationId: this.recordId, fieldId: 'decldate_day',   value: day,   source: 'human' }),
                saveField({ applicationId: this.recordId, fieldId: 'decldate_month', value: month, source: 'human' }),
                saveField({ applicationId: this.recordId, fieldId: 'decldate_year',  value: year,  source: 'human' })
            ]);
            this.toast(`Declaration date set to ${day}/${month}/${year}`, 'success');
            await refreshApex(this.wiredAnswers);
            if (this.wiredPath) await refreshApex(this.wiredPath);
        } catch (e) {
            this.toast(e?.body?.message || e.message || 'Save failed', 'error');
        }
    }

    toast(title, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, variant }));
    }

    // ── header / totals ─────────────────────────────────────────────────
    get hasAny() {
        return this.allSections.length > 0;
    }

    get allSummary() {
        const t = this.allSections.reduce((a, s) => a + s.total, 0);
        const f = this.allSections.reduce((a, s) => a + s.filled, 0);
        return `${f} / ${t} fields collected across ${this.allSections.length} parts`;
    }

    get allSubtitle() {
        return "Not all of these apply to the current client — see 'This client's path' for the filtered view.";
    }

    get pathSummary() {
        const filled = this.pathData?.filled ?? 0;
        const total = this.pathData?.total ?? 0;
        const modeMessage = this.pathModeMessage;
        return `${filled} / ${total} collected on this path — ${modeMessage}`;
    }

    get pathModeMessage() {
        if (!this.pathData) return 'Loading…';
        const filled = this.pathData.filled ?? 0;
        const total = this.pathData.total ?? 0;
        const declComplete = this.pathData.declarationComplete === true;
        const missing = total - filled;
        if (total === 0) return 'No fields required yet';
        if (missing > 0) return `${missing} field${missing === 1 ? '' : 's'} still needed`;
        if (declComplete) return 'Ready for Fill on DWP';
        // All required data present; declaration not yet complete.
        return 'All required data collected ✓ — Declaration pending';
    }

    get hasPathSections() {
        return this.pathSections.length > 0;
    }

    get pathEmptyMessage() {
        if (!this.pathData) return 'Loading client path…';
        const filled = this.pathData.filled ?? 0;
        const total = this.pathData.total ?? 0;
        if (total === 0) return 'No fields are required on this client\'s path yet. As gates get answered, the required fields will appear here.';
        if (filled === total) return 'All required data collected ✓';
        return 'No required fields on this path.';
    }
}