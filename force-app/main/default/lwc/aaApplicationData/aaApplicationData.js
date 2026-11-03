import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import {
    buildLoopIndex, collectLoopEntries, checkTextValue, checkDateParts,
    choiceOptions, choiceState, checkboxState, sourceBadge, postcodeRowState, MAX_LOOP_ENTRIES,
    declarationVoided, DECLARATION_VOID_NOTICE
} from './aaDataRules';

const CDC_APP_CHANNEL    = '/data/AA_Application__ChangeEvent';
const CDC_ANSWER_CHANNEL = '/data/AA_Answer__ChangeEvent';
// Polling fallback when CDC is unavailable (audit 2026-10-02 F52): without it
// Mary's mid-call saves never appeared until a manual reload. Only the
// AA_Application__c change event is selected (wave 3, CDC slot limit), so the
// AA_Answer__c subscribe fails. Answer edits still arrive live through the
// application event (the answer trigger rewrites Progress_* on the parent),
// and this poll covers anything that event misses.
const POLL_MS = 30000;
import FULL_NAME_FIELD from '@salesforce/schema/AA_Application__c.Full_Name__c';
import FIRST_NAME_FIELD from '@salesforce/schema/AA_Application__c.First_Name__c';
import LAST_NAME_FIELD from '@salesforce/schema/AA_Application__c.Last_Name__c';
import POSTCODE_FIELD from '@salesforce/schema/AA_Application__c.Postcode__c';
import NOTES_FIELD    from '@salesforce/schema/AA_Application__c.Notes__c';
import FLOW_URL       from '@salesforce/resourceUrl/aaFlowConfig';
import getAnswers      from '@salesforce/apex/AA_RecordPageService.getAnswers';
import getFlowConfig   from '@salesforce/apex/AA_RecordPageService.getFlowConfig';
import saveField       from '@salesforce/apex/AA_RecordPageService.saveField';
import getPathForRecord from '@salesforce/apex/AA_FlowEngine.getPathForRecord';

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
            console.warn('[aaApplicationData] fetch(aaFlowConfig) failed — falling back to Apex getFlowConfig', e);
            return getFlowConfig().then(body => JSON.parse(body));
        })
        .then(flow => {
            if (!flow || !Array.isArray(flow.PAGES)) throw new Error('aaFlowConfig: unexpected shape');
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

// (The PC1 CHILD_PAGES / PENSION_PAGES / MONEY_PAGES buckets and their
// fallback part labels were removed 2026-10-02: AA has no children, pensions
// or means-tested money parts, and aaFlowConfig ships only PAGES.)

/** When the record has a Postcode__c and the home-address-postcode answer is
 *  blank or the same postcode, the fill uses Postcode__c (src/fill/
 *  address-match.js prepareAddressAnswers), so editing the answer row would
 *  be ignored (audit F35): the row is read-only and points operators to the
 *  Address card, which writes Postcode__c. When the two DIFFER the row stays
 *  editable with a warning instead (see postcodeRowState): a Mary/human
 *  answer that differs halts the fill, and the operator must be able to fix
 *  whichever one is wrong. */
const RECORD_POSTCODE_REASON =
    'The DWP fill uses the postcode saved on the record, not this answer. ' +
    'Change the address with the Address card on this page.';

/** Fields the human signs manually at submit time. Rendered in the "path"
 *  tab so operators can find + fill them without hunting through "All",
 *  but NEVER counted toward Progress_Filled / Progress_Total (declaration
 *  is outside "what Mary does" — see AA_FlowEngine's Q3 decision). */
const DECLARATION_IDS = new Set(['decl', 'declname', 'decldate']);

/** Id of one part of a date triplet. AA stores date parts HYPHEN-delimited
 *  everywhere EXCEPT the XtraPension declaration date, which Apex reads as
 *  decldate_day/_month/_year (AA_FlowEngine.cls:163 and
 *  AA_MaryProgressCalculator.cls:16). Those two are the authority, and they
 *  are the ids handleToday already writes — so the generic editor path has to
 *  agree with them, or a pencil-edited date saves rows nothing ever reads and
 *  Declaration_Complete__c never flips. */
const datePartId = (id, part) => (id === 'decldate' ? `${id}_${part}` : `${id}-${part}`);

/**
 * aaApplicationData — the centrepiece. Renders every AA_Answer__c row for
 * the current Application, grouped by aa-flow.json Part.
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
 *   • Inline editor → Enter/Save persists via AA_RecordPageService.saveField
 *   • Repeating blocks (health conditions, aids, healthcare professionals)
 *     render one row per "<field>__<n>" entry and save to that id; never to
 *     the bare id, which the fill ignores once entries exist (aaDataRules).
 *   • Text and date edits are format-checked before saving (aaDataRules).
 *   • Tick-box editors offer the client's own conditions on care-needs-cause
 *     and keep a saved tick that is not an option ticked (aaDataRules).
 *   • Select editors keep a saved choice that is not an option selected
 *     (aaDataRules).
 */
export default class AaApplicationData extends LightningElement {
    @api recordId;

    answers = [];      // AA_Answer__c list
    wiredAnswers;
    wiredPath;
    pathData = null;   // { requiredFieldIds, blockedFieldIds, blockedReasonById, filled, total, declarationComplete, ... }

    flow;              // parsed aa-flow.json  { PAGES: [...] }
    flowLoaded = false;
    loopIndex = null;  // { memberToGroup, entryFields, altOf } — see aaDataRules
    extraEntries = {}; // loop group -> entry number opened via "Add another entry", not saved yet
    recordPostcode = '';
    declVoided = false; // signed declaration later cleared: client must re-sign (aaDataRules declarationVoided)
    liveOff = false;  // CDC unavailable: polling instead (shown as a hint)
    _pollTimer = null;

    @track editingKey = null;   // "<part>::<save id>" of the row being edited
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
    // Notes__c carries the "Declaration cleared:" line the Apex void writes,
    // the only trace of a void once its rows are deleted (aaDataRules
    // declarationVoided). optionalFields, not fields: a user without read
    // access on Notes__c must still get the name and postcode instead of a
    // failed wire.
    @wire(getRecord, {
        recordId: '$recordId',
        fields: [FULL_NAME_FIELD, FIRST_NAME_FIELD, LAST_NAME_FIELD, POSTCODE_FIELD],
        optionalFields: [NOTES_FIELD]
    })
    wireApp(result) {
        if (result.data) {
            const rec = result.data;
            const full  = getFieldValue(rec, FULL_NAME_FIELD);
            const first = getFieldValue(rec, FIRST_NAME_FIELD);
            const last  = getFieldValue(rec, LAST_NAME_FIELD);
            this.suggestedName = full || [first, last].filter(Boolean).join(' ') || '';
            const pc = getFieldValue(rec, POSTCODE_FIELD);
            this.recordPostcode = pc == null ? '' : String(pc).trim();
            const notes = getFieldValue(rec, NOTES_FIELD);
            this.appNotes = notes == null ? '' : String(notes);
            this.safeRecompute();
        }
    }
    suggestedName = '';
    appNotes = '';

    @wire(getPathForRecord, { recordId: '$recordId' })
    wirePath(result) {
        this.wiredPath = result;
        if (result.data) {
            const wasSigned = this.pathData && this.pathData.declarationComplete === true;
            this.pathData = result.data;
            // Signed -> not signed while the page is open is the Apex void
            // landing (Mary, the client form or another tab changed an
            // answer). The CDC handler and the poll refresh this wire but not
            // LDS, so getRecord would keep the Notes__c from before the void
            // and the re-sign notice would not show until a reload.
            if (wasSigned && result.data.declarationComplete !== true) this.notifyParentChanged();
            this.safeRecompute();
        } else if (result.error) {
            // eslint-disable-next-line no-console
            console.warn('[aaApplicationData] getPathForRecord failed — path tab will be empty', result.error);
            this.pathData = null;
        }
    }

    // CDC subscriptions — live-refresh answers when Mary (or the fill
    // worker) writes to AA_Answer__c mid-call. Without this the details
    // grid stays stale until the operator manually reloads. Only the
    // AA_Application__c event has a channel member, so _appSub is the live
    // one; _ansSub fails today and the 30 s poll (POLL_MS) runs alongside.
    _appSub;
    _ansSub;

    async connectedCallback() {
        try {
            this.flow = await loadFlowOnce();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[aaApplicationData] flow load failed (fetch AND Apex fallback)', e);
            this.flow = { PAGES: [] };
        }
        try {
            this.loopIndex = buildLoopIndex(this.flow);
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[aaApplicationData] loop index failed', e);
            this.loopIndex = { memberToGroup: {}, entryFields: new Set(), altOf: {} };
        }
        // eslint-disable-next-line no-console
        console.log('[aaApplicationData] flow ready — pages:', (this.flow.PAGES || []).length);
        this.flowLoaded = true;
        this.safeRecompute();

        // Best-effort CDC. If the channel is not enabled, fall back to a
        // 30 s poll so the card still catches Mary's mid-call saves.
        try {
            onError((err) => {
                // eslint-disable-next-line no-console
                console.warn('[aaApplicationData] empApi error', err);
                this.startPolling();
            });
            this._appSub = await subscribe(CDC_APP_CHANNEL, -1, (msg) => {
                try {
                    const hdr = msg?.data?.payload?.ChangeEventHeader;
                    if (hdr?.recordIds?.includes(this.recordId)) {
                        // Answers too: the AA_Answer__c channel is not
                        // selected (CDC slot limit), and every answer save
                        // rewrites Progress_* on this parent, so the
                        // application event is the live signal for answers.
                        // Skipped while an editor is open, like the poll, so
                        // a re-render cannot reset what the operator types.
                        if (this.wiredAnswers && !this.editingKey) refreshApex(this.wiredAnswers);
                        if (this.wiredPath) refreshApex(this.wiredPath);
                    }
                } catch (_) {}
            });
            this._ansSub = await subscribe(CDC_ANSWER_CHANNEL, -1, () => {
                // Too many parents to filter cheaply; just refresh answers +
                // path — both SOQL queries are fast + scoped by recordId.
                // Dormant until an AA_Answer__ChangeEvent channel member is
                // deployed (CDC slot limit); kept so adding one needs no code.
                try {
                    if (this.wiredAnswers) refreshApex(this.wiredAnswers);
                    if (this.wiredPath)    refreshApex(this.wiredPath);
                } catch (_) {}
            });
            if (!this._appSub || !this._ansSub) this.startPolling();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[aaApplicationData] CDC subscribe failed (polling instead):', e?.message || e);
            this.startPolling();
        }
    }

    async disconnectedCallback() {
        this.stopPolling();
        try { if (this._appSub) await unsubscribe(this._appSub); } catch (_) {}
        try { if (this._ansSub) await unsubscribe(this._ansSub); } catch (_) {}
        this._appSub = null;
        this._ansSub = null;
    }

    startPolling() {
        this.liveOff = true;
        if (this._pollTimer) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => {
            // Skip while the tab is hidden or an editor is open: a re-render
            // mid-edit could reset what the operator is typing.
            if (this.editingKey) return;
            if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
            try {
                if (this.wiredAnswers) refreshApex(this.wiredAnswers);
                if (this.wiredPath)    refreshApex(this.wiredPath);
            } catch (_) { /* never break the page */ }
        }, POLL_MS);
    }

    stopPolling() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
    }

    safeRecompute() {
        try {
            this.recompute();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('[aaApplicationData] recompute failed', e);
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
        // Declaration voided on change (owner decision 2026-10-02): flag it
        // once here so buildRow can put the re-sign notice on the decl row.
        this.declVoided = declarationVoided(
            this.answers, this.pathData && this.pathData.declarationComplete, this.appNotes
        );
        const map = this.answerMap;
        const groups = new Map(); // part -> fields[]
        const order = [];

        for (const page of (this.flow.PAGES || [])) {
            if (!page.fields || !page.fields.length) continue;
            const part = page.part || 'Other';
            if (!groups.has(part)) {
                groups.set(part, { fields: [], seen: new Set() });
                order.push(part);
            }
            const g = groups.get(part);
            for (const f of page.fields) {
                // A field id can sit on two pages of the same part
                // (health-conditions-start-date is on both the list and the
                // manual condition page). Listing it twice gave duplicate
                // for:each keys and two editors where only the first one's
                // input was ever saved (audit F63).
                if (g.seen.has(f.id)) continue;
                g.seen.add(f.id);
                g.fields.push(f);
            }
        }

        const requiredSet = this.requiredSet;
        const optionalSet = this.pathOptionalSet;
        const blockedSet = this.blockedSet;
        const reasons = this.blockedReasons;
        const knowPath = requiredSet.size > 0 || optionalSet.size > 0 || blockedSet.size > 0;
        const loopEntries = this.loopIndex
            ? collectLoopEntries(this.answers, this.loopIndex.memberToGroup)
            : {};

        const allSections = [];
        const pathSections = [];

        for (const part of order) {
            const fields = groups.get(part).fields;
            const allRows = [];
            const pathRows = [];
            let filledAll = 0;
            let filledPath = 0;
            let totalPath = 0; // excludes declaration + optional rows so counter stays honest
            for (const f of fields) {
                // Loop members render one row per stored "<field>__<n>" entry;
                // every other field renders exactly one row. Counters count
                // the field once, answered when any of its rows is.
                const rows = this.buildRowsForField(part, f, map, blockedSet, reasons, loopEntries);
                const answered = rows.some(r => r.answered);
                if (answered) filledAll++;
                allRows.push(...rows);
                const isDecl = DECLARATION_IDS.has(f.id);
                const isOptional = optionalSet.has(f.id);
                if (requiredSet.has(f.id) || isDecl || isOptional) {
                    // Declaration + optional rows appear in the path list
                    // but don't count toward the section/tab counters.
                    if (!isDecl && !isOptional) {
                        totalPath++;
                        if (answered) filledPath++;
                    }
                    pathRows.push(...rows);
                }
            }
            const totalAll = fields.length;

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

    /**
     * Rows for one catalogue field. A loop member (see aaDataRules
     * buildLoopIndex) gets one row per stored "<field>__<n>" entry and edits
     * save back to that exact id; the fill folds those rows into _loops and
     * ignores a bare-id value whenever they exist (audit F34/F49/F168).
     * When a group has no "__<n>" rows yet, one row shows the legacy bare
     * value (still what the fill uses then) and an edit writes "__1".
     */
    buildRowsForField(part, field, map, blockedSet, reasons, loopEntries) {
        const li = this.loopIndex;
        const group = li && li.memberToGroup[field.id];
        if (!group) return [this.buildRow(part, field, map, blockedSet, reasons, { suffix: '', n: null })];

        const stored = loopEntries[group] || [];
        const extra = this.extraEntries[group];
        const entries = stored.slice();
        if (extra && !entries.includes(extra)) entries.push(extra);
        const has = (id) => { const v = map[id]?.Value__c; return v != null && v !== ''; };

        // health-conditions-manual is the free-text twin of health-conditions:
        // one entry carries one or the other, so each shows only where used.
        const altGroup = li.altOf[field.id];
        const altField = field.id === group
            ? Object.keys(li.altOf).find(a => li.altOf[a] === group)
            : null;

        if (!entries.length) {
            return [this.buildRow(part, field, map, blockedSet, reasons, { suffix: '__1', n: 1, bareFallback: true, labelSuffix: '' })];
        }
        const rows = [];
        const maxN = entries[entries.length - 1];
        for (const n of entries) {
            if (altGroup && !has(`${field.id}__${n}`) && n !== extra) continue;
            if (altField && !has(`${field.id}__${n}`) && has(`${altField}__${n}`)) continue;
            rows.push(this.buildRow(part, field, map, blockedSet, reasons, {
                suffix: `__${n}`, n, bareFallback: n === 1, labelSuffix: ` (entry ${n})`
            }));
        }
        if (altGroup && rows.length === 0 && maxN < MAX_LOOP_ENTRIES) {
            // No condition typed in by hand yet: one empty row that starts a
            // new entry, so it never overwrites an existing entry's condition.
            const next = Math.min(maxN + 1, MAX_LOOP_ENTRIES);
            rows.push(this.buildRow(part, field, map, blockedSet, reasons, {
                suffix: `__${next}`, n: next, bareFallback: false, labelSuffix: ' (new entry)'
            }));
        }
        // "Add another entry" sits on the last row of the group's entry field.
        if (li.entryFields.has(field.id) && rows.length && maxN < MAX_LOOP_ENTRIES && !extra) {
            const last = rows[rows.length - 1];
            if (last.answered && !last.isBlocked) {
                last.canAddEntry = true;
                last.addGroup = group;
                last.addNext = String(maxN + 1);
            }
        }
        return rows;
    }

    buildRow(part, field, map, blockedSet, reasons, ctx) {
        const suffix = ctx.suffix || '';
        const saveId = field.id + suffix;
        const editKey = `${part}::${saveId}`;
        const isEditing = this.editingKey === editKey;
        // Loop entry 1 falls back to the bare row: with no "__1" value for
        // this member, the fill still reads the bare value on entry 1.
        const val = (id) => {
            const a = map[id + suffix];
            if (a && a.Value__c != null && a.Value__c !== '') return a;
            return ctx.bareFallback && suffix ? (map[id] || a) : a;
        };

        let answered = false;
        let valueHtml;
        let src = null;
        let editorSpec = { kind: 'text', value: '', options: [] };
        let hint = field.hint || '';

        if (field.type === 'date') {
            let d = val(datePartId(field.id, 'day'))?.Value__c;
            let m = val(datePartId(field.id, 'month'))?.Value__c;
            let y = val(datePartId(field.id, 'year'))?.Value__c;
            if (!(d && m && y)) {
                const iso = val(field.id)?.Value__c;
                const hit = typeof iso === 'string' && iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
                if (hit) { y = hit[1]; m = hit[2]; d = hit[3]; }
            }
            answered = !!(d && m && y);
            if (answered) valueHtml = `${d} / ${m} / ${y}`;
            else          valueHtml = null;
            src = val(datePartId(field.id, 'day'))?.Source__c || val(datePartId(field.id, 'month'))?.Source__c || val(datePartId(field.id, 'year'))?.Source__c || val(field.id)?.Source__c;
            editorSpec = { kind: 'date', day: d || '', month: m || '', year: y || '' };
        } else {
            const a = val(field.id);
            const raw = a?.Value__c;
            src = a?.Source__c;
            answered = raw != null && raw !== '';
            // The address-lookup selects arrive with only [null,null] options
            // (DWP's empty lookup list, audit F41). Never offer blank choices:
            // fall back to a text editor and explain the '1' sentinel.
            const choices = choiceOptions(field);
            if (choices.length) {
                // e2e 2026-10-08 follow-up: a saved value that matched no
                // option exactly opened the select on "not collected", and a
                // plain Save cleared it. A case or padding variant of a code
                // now selects that option (Save stores the code); any other
                // value is listed last, selected (aaDataRules choiceState).
                const ch = choiceState(choices, raw);
                valueHtml = ch.label;
                editorSpec = { kind: 'select', value: ch.value, options: [{ value: '', label: '— not collected —', selected: !ch.value }]
                    .concat(ch.options)
                };
                if (ch.hint) hint = hint ? `${hint} ${ch.hint}` : ch.hint;
            } else if (field.type === 'checkboxes') {
                // e2e 2026-10-08: care-needs-cause offers the client's own
                // conditions (its catalogue holds only none-of-these), and a
                // saved tick that is not an option stays ticked under its raw
                // value. Both used to be missing from the editor, so the next
                // save dropped them (aaDataRules checkboxState).
                const cb = checkboxState(field, raw, this.answers);
                valueHtml = cb.labels.length ? cb.labels.join(', ') : null;
                answered = cb.labels.length > 0;
                editorSpec = { kind: 'checkboxes', values: cb.values, options: cb.options };
                if (cb.hint) hint = hint ? `${hint} ${cb.hint}` : cb.hint;
            } else if (field.type === 'textarea') {
                valueHtml = raw || null;
                editorSpec = { kind: 'textarea', value: raw || '' };
            } else {
                if (/address-select$/.test(field.id)) {
                    valueHtml = raw === '1' ? '1 (first address the DWP lookup returns)' : (raw || null);
                    hint = "1 means the first address DWP's lookup returns for the postcode. To pick a specific one, type the address exactly as DWP lists it.";
                } else {
                    valueHtml = raw || null;
                }
                editorSpec = { kind: 'text', value: raw || '' };
            }
        }

        const srcBadge = sourceBadge(src);
        const isBlocked = blockedSet.has(field.id);
        const blockedReason = isBlocked ? (reasons[field.id] || 'This field depends on an earlier answer that has not been provided yet.') : '';
        // Read-only (not blocked): the value shows, but the edit belongs on
        // another card (audit F35, see RECORD_POSTCODE_REASON). Only while the
        // answer is blank or matches Postcode__c; a differing answer stays
        // editable and carries a warning (wave-2 review of F35).
        let readOnlyReason = '';
        let warning = '';
        if (!isBlocked && field.id === 'home-address-postcode' && !suffix) {
            const pcAns = val(field.id);
            const st = postcodeRowState(pcAns && pcAns.Value__c, pcAns && pcAns.Source__c, this.recordPostcode);
            if (st.mode === 'readonly') readOnlyReason = RECORD_POSTCODE_REASON;
            else if (st.mode === 'conflict') warning = st.warning;
        }
        // The re-sign notice sits on the decl row (the first declaration row,
        // in both tabs), so the operator sees it next to what must be signed.
        if (field.id === 'decl' && !suffix && this.declVoided) warning = DECLARATION_VOID_NOTICE;
        // Also shown under the editor, where the display-mode warning is hidden.
        if (warning) hint = hint ? `${hint} ${warning}` : warning;
        const isLocked = isBlocked || !!readOnlyReason;
        const lockReason = blockedReason || readOnlyReason;
        const label = (field.label || field.id) + (ctx.labelSuffix || '');

        // Value styling: empty & blocked both share the muted gray look.
        let valueCls = 'fvalue';
        if (!answered) valueCls += ' empty';
        if (isBlocked) valueCls += ' locked';

        return {
            key: saveId,
            editKey,
            fieldId: field.id,
            suffix,
            part,
            qTag: field.q && field.q !== '—' ? field.q : '',
            hasQTag: !!(field.q && field.q !== '—'),
            label,
            hint,
            hasHint: !!hint,
            warning,
            hasWarning: !!warning,
            answered,
            valueHtml: valueHtml,
            displayValue: answered ? valueHtml : (isBlocked ? 'Locked — depends on an earlier answer' : 'Not collected'),
            valueCls,
            srcLabel: srcBadge.label,
            srcCls: srcBadge.cls,
            hasSrc: !!srcBadge.label,
            isEditing,
            isBlocked: isLocked,
            lockKind: isBlocked ? 'blocked' : (readOnlyReason ? 'readonly' : ''),
            blockedReason: lockReason,
            pencilCls: isLocked ? 'pencil locked' : 'pencil',
            pencilTitle: isLocked ? lockReason : 'Edit',
            editorSpec,
            editorIsText:       editorSpec.kind === 'text',
            editorIsTextarea:   editorSpec.kind === 'textarea',
            editorIsSelect:     editorSpec.kind === 'select',
            editorIsCheckboxes: editorSpec.kind === 'checkboxes',
            editorIsDate:       editorSpec.kind === 'date',
            fieldType: field.type || 'text',
            editAriaLabel: isLocked ? `Locked: ${label}` : `Edit ${label}`,
            // Set by buildRowsForField on the last entry of a loop group.
            canAddEntry: false,
            addGroup: '',
            addNext: '',
            // Declaration-only helpers surfaced by the row template:
            // declname row shows a "Use client name" quick-fill button;
            // decldate row shows a "Today" quick-fill button.
            isDeclName: field.id === 'declname',
            isDeclDate: field.id === 'decldate',
            suggestedName: field.id === 'declname' ? (this.suggestedName || '') : '',
            hasSuggestedName: field.id === 'declname' && !!this.suggestedName
        };
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
                || 'This field depends on an earlier answer that has not been provided yet.';
            const readOnly = evt.currentTarget.dataset.lockkind === 'readonly';
            await LightningConfirm.open({
                message: reason,
                variant: 'header',
                theme: 'warning',
                label: readOnly ? 'Edit this on another card' : 'This field is not yet editable'
            });
            return;
        }
        this.editingKey = key;
        this.recompute();
    }

    cancelEditor() {
        this.editingKey = null;
        this.extraEntries = {};
        this.recompute();
    }

    /** "Add another entry" on a loop group: opens an empty editor for
     *  "<entry field>__<max+1>". Nothing is written until Save. */
    handleAddEntry(evt) {
        const { group, next, part } = evt.currentTarget.dataset;
        const n = Number(next);
        if (!group || !n || n > MAX_LOOP_ENTRIES) return;
        this.extraEntries = { [group]: n };
        this.editingKey = `${part}::${group}__${n}`;
        this.recompute();
    }

    async saveEditor(evt) {
        // Scope to the editor the Save button sits in. A page-wide
        // querySelector returned the FIRST editor with that key, so an edit
        // typed into a second copy of the field was silently dropped (F63).
        const wrap = evt.currentTarget.closest('.editor');
        if (!wrap) return;
        const kind = wrap.dataset.kind;
        const fieldId = wrap.dataset.fieldid;
        const suffix = wrap.dataset.suffix || '';
        const key = fieldId + suffix;
        const saves = []; // [fieldId, value]

        if (kind === 'date') {
            const d = wrap.querySelector('[data-p="day"]').value.trim();
            const m = wrap.querySelector('[data-p="month"]').value.trim();
            const y = wrap.querySelector('[data-p="year"]').value.trim();
            // Real calendar date (31/02 used to pass and Apex rolled it into
            // March) and a sane date of birth (F38/F58).
            const err = checkDateParts(fieldId, d, m, y, new Date());
            if (err) return this.toast(err, 'error');
            saves.push([datePartId(fieldId, 'day') + suffix, d]);
            saves.push([datePartId(fieldId, 'month') + suffix, m]);
            saves.push([datePartId(fieldId, 'year') + suffix, y]);
        } else if (kind === 'checkboxes') {
            const checked = [...wrap.querySelectorAll('input[type="checkbox"]:checked')].map(i => i.value);
            // Save '' (not '[]') when nothing is ticked. Apex treats only null/''
            // as unanswered (AA_FlowEngine.cls:165), so '[]' would leave an
            // un-ticked declaration reading as signed.
            saves.push([key, checked.length ? JSON.stringify(checked) : '']);
        } else {
            const el = wrap.querySelector('[data-input]');
            const raw = el ? el.value : '';
            if (kind === 'text' || kind === 'textarea') {
                // Same NI / phone / postcode / email rules the Heroku save
                // paths apply (mary-validator FORMAT_RULES); the SF form used
                // to store anything verbatim (F40/F58/F171).
                const chk = checkTextValue(fieldId, raw);
                if (!chk.ok) return this.toast(chk.error, 'error');
                saves.push([key, chk.value]);
            } else {
                saves.push([key, raw]);
            }
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
            this.extraEntries = {};
            this.recompute();
            this.notifyParentChanged();
        } catch (e) {
            this.toast(e?.body?.message || e.message || 'Save failed', 'error');
        }
    }

    /** Answer saves change parent fields server-side (Declaration_Complete__c,
     *  Progress_*, DOB__c via the answer trigger), which LDS cannot see. Tell
     *  LDS to refetch so getRecord-based cards (progress bar, stage) stop
     *  showing stale values until a reload (F57). */
    notifyParentChanged() {
        try {
            if (this.recordId) notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        } catch (_) { /* best effort */ }
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
            this.notifyParentChanged();
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
            this.notifyParentChanged();
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
        if (this.declVoided) return 'Declaration cleared, the client must sign it again';
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