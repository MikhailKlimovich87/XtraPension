/**
 * aaDataRules — pure helpers for aaApplicationData (no lwc / Salesforce
 * imports, so the logic can be exercised offline by copying this file to a
 * .mjs and importing it from Node).
 *
 * Three jobs:
 *   1. Repeating blocks ("loops"): health conditions, aids & adaptations and
 *      healthcare professionals are stored as one AA_Answer__c per entry field
 *      per entry, keyed "<field>__<n>". The catalogue (aaFlowConfig) only knows
 *      the bare ids, so without this the SF form showed those answers as "Not
 *      collected" and saved operator edits to the bare id, which the fill
 *      ignores whenever "__<n>" rows exist (audit 2026-10-02 F34/F49/F168).
 *      Mirrors src/lib/loop-folding.js (LOOP_ID_RE + MEMBER_TO_GROUP).
 *   2. Format checks on operator edits: NI number, UK phone, UK postcode,
 *      email and real calendar dates in the years the Apex accepts. The
 *      Heroku save paths run these through src/lib/mary-validator.js
 *      FORMAT_RULES; the SF form wrote anything verbatim (F40/F58/F171, F38).
 *   3. Small display helpers (source badge, option cleaning) and the editor
 *      state of option answers: care-needs-cause offers the client's own
 *      conditions, a saved tick that is not an option stays ticked
 *      (checkboxState), and a saved choice that is not an option stays
 *      selected (choiceState).
 */

// Copy of config/aa-flow.json LOOP_SNAPSHOT / LOOP_CLEAR. The aaFlowConfig
// static resource ships only PAGES today; when the generator starts emitting
// LOOP_SNAPSHOT / LOOP_CLEAR, buildLoopIndex prefers those over this copy.
const DEFAULT_LOOP_SNAPSHOT = {
    'health-conditions':               { fields: ['health-conditions'] },
    'health-conditions-manual':        { fields: ['health-conditions-manual'] },
    'aids-adaptations':                { fields: ['aids-adaptations-2'] },
    'healthcare-professional-details': { fields: ['healthcare-professional-name'] }
};
const DEFAULT_LOOP_CLEAR = {
    'health-conditions-added': ['health-conditions', 'health-conditions-manual', 'health-conditions-start-date'],
    'aids-adaptations-added':  ['aids-adaptations-2', 'aids-adaptations-difficulty-2']
};

// No leading zeros: "__05" must not alias "__5" (same rule as loop-folding.js).
const LOOP_ID_RE = /^(.*)__([1-9][0-9]?)$/;

// DWP's repeating blocks allow up to 20 entries.
export const MAX_LOOP_ENTRIES = 20;

export function parseFieldId(id) {
    const m = LOOP_ID_RE.exec(String(id || ''));
    if (!m) return { base: String(id || ''), n: null };
    return { base: m[1], n: Number(m[2]) };
}

/**
 * Loop membership, derived the same way src/lib/loop-folding.js derives it.
 * Returns:
 *   memberToGroup  field id -> group key (the group's entry field)
 *   entryFields    Set of group entry fields (where "Add another entry" lives)
 *   altOf          alternative entry field -> group key
 *                  (health-conditions-manual is the free-text twin of
 *                  health-conditions; an entry carries one or the other)
 */
export function buildLoopIndex(flow) {
    const snapshot = (flow && flow.LOOP_SNAPSHOT) || DEFAULT_LOOP_SNAPSHOT;
    const clear = (flow && flow.LOOP_CLEAR) || DEFAULT_LOOP_CLEAR;
    const snapEntry = new Set(Object.values(snapshot).map(s => s && s.fields && s.fields[0]).filter(Boolean));
    const memberToGroup = {};
    for (const members of Object.values(clear)) {
        const groupKey = members.find(m => snapEntry.has(m)) || members[0];
        for (const m of members) memberToGroup[m] = groupKey;
    }
    // Snapshot pages without a LOOP_CLEAR entry (healthcare-professional-details):
    // every field on the entry page belongs to that loop.
    const pagesByKey = {};
    for (const p of (flow && Array.isArray(flow.PAGES) ? flow.PAGES : [])) {
        if (p && p.key) pagesByKey[p.key] = p;
    }
    for (const [pageKey, snap] of Object.entries(snapshot)) {
        const groupKey = (snap && snap.fields && snap.fields[0]) || pageKey;
        const page = pagesByKey[pageKey];
        const names = page ? (page.fields || []).map(f => f.id) : [groupKey];
        for (const n of names) if (n && !(n in memberToGroup)) memberToGroup[n] = groupKey;
    }
    const entryFields = new Set();
    const altOf = {};
    for (const ef of snapEntry) {
        const g = memberToGroup[ef];
        if (g && g !== ef) altOf[ef] = g;
        else if (g) entryFields.add(g);
    }
    return { memberToGroup, entryFields, altOf };
}

const DATE_PART_RE = /^(.*)-(day|month|year)$/;

/** group key -> sorted entry numbers present in the answers. */
export function collectLoopEntries(answers, memberToGroup) {
    const out = {};
    for (const a of answers || []) {
        const { base, n } = parseFieldId(a && a.Field_Id__c);
        if (n === null) continue;
        let g = memberToGroup[base];
        if (!g) { const dm = DATE_PART_RE.exec(base); if (dm) g = memberToGroup[dm[1]]; }
        if (!g) continue;
        if (a.Value__c == null || a.Value__c === '') continue;
        (out[g] = out[g] || new Set()).add(n);
    }
    const sorted = {};
    for (const [g, s] of Object.entries(out)) sorted[g] = [...s].sort((x, y) => x - y);
    return sorted;
}

// ── format rules (ported from src/lib/mary-validator.js FORMAT_RULES) ──────
const FORMAT_RULES = [
    {
        matcher: /(^|-)national-insurance$/,
        normalise: s => s.toUpperCase().replace(/\s+/g, ''),
        persist: true,
        re: /^(?!BG|GB|NK|KN|TN|NT|ZZ)[A-CEGHJ-PR-TW-Z][A-CEGHJ-NPR-TW-Z]\d{6}[A-D]$/,
        message: 'Enter a National Insurance number as two letters, six digits and one letter A to D, for example AB123456C.'
    },
    {
        matcher: /(telephone|contact-number)/,
        normalise: s => s.replace(/[\s\-().]/g, ''),
        persist: false, // validate the compact form, store what the operator typed
        re: /^(?:0|\+44|0044)[1-9]\d{8,9}$/,
        message: 'Enter a UK telephone number, for example 01632 960001 or 07700 900982. DWP rejects non-UK numbers.'
    },
    {
        matcher: /postcode$/,
        normalise: s => s.trim().toUpperCase(),
        persist: true,
        re: /^(GIR ?0AA|[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2})$/,
        message: 'Enter a real UK postcode, for example SW1A 2AA.'
    },
    {
        // contact-by-email(-confirm), supporting-documents-email(-confirm);
        // not email-submit (a yes/no radio, never reaches a text editor).
        matcher: /-email(-confirm)?$/,
        normalise: s => s.trim(),
        persist: true,
        re: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
        message: 'Enter an email address in the correct format, for example name@example.com.'
    }
];

/**
 * Check a free-text value before it is saved. Blank is always allowed (it
 * clears the answer). Returns { ok, value, error } where value is the
 * normalised string to persist.
 */
export function checkTextValue(fieldId, raw) {
    const value = raw == null ? '' : String(raw);
    if (value.trim() === '') return { ok: true, value: '' };
    const { base } = parseFieldId(fieldId);
    const rule = FORMAT_RULES.find(r => r.matcher.test(base));
    if (!rule) return { ok: true, value };
    const norm = rule.normalise(value);
    if (!rule.re.test(norm)) return { ok: false, value, error: rule.message };
    return { ok: true, value: rule.persist ? norm : value.trim() };
}

const BIRTH_DATE_RE = /(^|-)birth-date$/;

// The years AA_RecordPageService and mary-validator validateSave accept in a
// date part (field-catalog's DATE_PART_RANGE). A birth year is also held to
// this year at most: the "in the future" check below covers that.
const MIN_YEAR = 1900;
const MAX_YEAR = 2099;

/**
 * Validate a DD/MM/YYYY triplet. All blank = clear (allowed). Rejects partial
 * dates, impossible dates (31/02 used to be accepted and Apex Date.newInstance
 * silently rolled it into March, F38), years outside 1900 to 2099 and, for
 * dates of birth, dates in the future (they break the DOB_Reasonable rule on
 * the parent and fail the whole save). The Apex refuses those years too, but
 * the editor saves day, month and year in three calls, so a year refused
 * there left the new day and month saved with the old year: everything is
 * checked here, before any part is saved. Returns an error string or null.
 */
export function checkDateParts(fieldId, d, m, y, today) {
    if (!d && !m && !y) return null;
    if (!d || !m || !y) return 'Enter a full date: day, month and year.';
    if (!/^\d{1,2}$/.test(d) || !/^\d{1,2}$/.test(m)) return 'Day and month must be numbers.';
    if (!/^\d{4}$/.test(y)) return 'Enter the year as 4 digits, for example 1948.';
    const dn = Number(d), mn = Number(m), yn = Number(y);
    if (mn < 1 || mn > 12) return 'Month must be between 1 and 12.';
    if (dn < 1 || dn > 31) return 'Day must be between 1 and 31.';
    const isBirthDate = BIRTH_DATE_RE.test(parseFieldId(fieldId).base);
    const yearRange = `Year must be between ${MIN_YEAR} and ${MAX_YEAR}.`;
    if (yn < MIN_YEAR) return isBirthDate ? 'A date of birth must be in 1900 or later.' : yearRange;
    if (yn > MAX_YEAR) return isBirthDate ? 'A date of birth cannot be in the future.' : yearRange;
    const probe = new Date(Date.UTC(yn, mn - 1, dn));
    if (probe.getUTCFullYear() !== yn || probe.getUTCMonth() !== mn - 1 || probe.getUTCDate() !== dn) {
        return `${d}/${m}/${y} is not a real date.`;
    }
    if (isBirthDate) {
        const now = today instanceof Date ? today : new Date();
        const todayUtc = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
        if (probe.getTime() > todayUtc) return 'A date of birth cannot be in the future.';
    }
    return null;
}

/** Drop [null, null] option pairs the generator copies from DWP's empty
 *  address-lookup select (F41). */
export function cleanOptions(options) {
    return (Array.isArray(options) ? options : []).filter(o => Array.isArray(o) && o[0] != null && o[0] !== '');
}

// ── tick-box options (e2e 2026-10-08) ──────────────────────────────────────
// care-needs-cause asks which of the client's OWN health conditions cause the
// difficulties. Its catalogue options hold only none-of-these: DWP and
// web/form.html build the other boxes from the conditions the client entered,
// and scripts/gen-aa-flow-config.cjs marks the field with dynamicOptions.
// Built from cleanOptions alone, the editor offered "None of these" only, and
// saving the field dropped every condition already ticked. Copy of the
// generator's DYNAMIC_OPTIONS, used when the resource carries no such hint.
const DEFAULT_DYNAMIC_OPTIONS = {
    'care-needs-cause': {
        fromLoop: ['health-conditions', 'health-conditions-manual'],
        rows: 'health-conditions-rows',
        keep: ['none-of-these']
    }
};

// Editor hints (operator-facing copy).
const NO_NAMES_HINT = {
    'care-needs-cause': 'No health condition is saved for this client yet. ' +
        'Add the conditions first, then tick the ones that cause the difficulties.'
};
export const OFF_LIST_HINT =
    'Saved answers that are not among the current options are listed last. Untick one to remove it.';

function dynamicSpec(field) {
    if (!field) return null;
    const spec = field.dynamicOptions;
    return spec && typeof spec === 'object' ? spec : (DEFAULT_DYNAMIC_OPTIONS[field.id] || null);
}

/**
 * The names a dynamic option list is built from, read from the same answers
 * AA_RecordPageService.conditionNames and mary-validator
 * conditionNamesFromAnswers read: the rows snapshot (the JSON list the client
 * form saves), then the fromLoop ids and their "__<n>" entries, newest row per
 * id. Each name is trimmed and the first spelling wins, ignoring case: the
 * strings the client form offers and the Apex accepts for care-needs-cause.
 * The entries are taken in entry order, as the client form lists them (the
 * answers arrive by Field_Id__c, which puts manual entries first and "__10"
 * before "__2"): a bare id first, then by entry number, the fromLoop order
 * within an entry.
 */
export function dynamicOptionNames(spec, answers) {
    const from = spec && Array.isArray(spec.fromLoop) ? spec.fromLoop : [];
    const latest = new Map();
    for (const a of answers || []) {
        if (a && a.Field_Id__c) latest.set(a.Field_Id__c, a.Value__c);
    }
    const names = [];
    const seen = new Set();
    const add = (v) => {
        if (v == null || typeof v === 'object') return;
        const s = String(v).trim();
        if (s && !seen.has(s.toLowerCase())) { seen.add(s.toLowerCase()); names.push(s); }
    };
    let rows = spec && spec.rows ? latest.get(spec.rows) : null;
    if (typeof rows === 'string' && rows.trim().startsWith('[')) {
        try { rows = JSON.parse(rows); } catch (_) { rows = null; }
    }
    if (Array.isArray(rows)) rows.forEach(add);
    const entries = [];
    for (const id of latest.keys()) {
        const { base, n } = parseFieldId(id);
        if (from.includes(base)) entries.push({ id, n: n || 0, f: from.indexOf(base) });
    }
    entries.sort((x, y) => x.n - y.n || x.f - y.f);
    for (const e of entries) add(latest.get(e.id));
    return names;
}

// The options of a tick-box field, and how many are names saved for it.
function optionsFor(field, spec, answers) {
    const options = cleanOptions(field && field.options);
    if (!spec) return { options, named: 0 };
    const kept = Array.isArray(spec.keep) ? options.filter(o => spec.keep.includes(o[0])) : options;
    const keptCodes = new Set(kept.map(o => String(o[0]).toLowerCase()));
    const named = dynamicOptionNames(spec, answers)
        .filter(n => !keptCodes.has(n.toLowerCase()))
        .map(n => [n, n]);
    return { options: named.concat(kept), named: named.length };
}

/**
 * The [code, label] options a tick-box field offers this client. Most fields
 * offer their catalogue options (cleanOptions). A field with dynamicOptions
 * offers the names saved for it, each as its own code and label, then the
 * catalogue options it keeps (none-of-these, with its catalogue label).
 */
export function checkboxOptions(field, answers) {
    return optionsFor(field, dynamicSpec(field), answers).options;
}

// A saved tick matches its option exactly, else the way the Apex holds it to
// one: a code after trimming, ignoring case (canonCode), a dynamic name also
// ignoring repeated spaces (matchCondition, as validateCareNeedsCause does).
// So one option is never shown twice in two spellings, which a save would
// store as a duplicate code.
const foldCode = (s) => s.trim().toLowerCase();
const foldName = (s) => s.trim().replace(/\s+/g, ' ').toLowerCase();

/** The saved ticks of a tick-box answer: a JSON list, else the raw value. */
function savedTicks(raw, isOption) {
    if (Array.isArray(raw)) return raw;
    const s = raw == null ? '' : String(raw);
    if (s.trim() === '') return [];
    if (s.trim().startsWith('[')) {
        try {
            const list = JSON.parse(s);
            if (Array.isArray(list)) return list;
        } catch (_) { /* not a JSON list: kept whole */ }
        return [s];
    }
    // A bare value: one option as a whole, else a legacy comma / semicolon list.
    return isOption(s) ? [s] : s.split(/[,;]\s*/).filter(Boolean);
}

/**
 * Display and editor state of a tick-box answer. Every option comes with its
 * checked state. Each saved value that is not an option (a legacy code, a
 * condition no longer on file, a value that is not a JSON list) follows,
 * ticked and labelled with the raw value: the editor saves only what is
 * ticked, so leaving it out dropped it on the next save without the operator
 * seeing it. The Apex refuses an off-list code with a message naming it, and
 * unticking it removes it.
 * Returns { values, labels, options: [{ value, label, checked }], offList, hint }:
 * values is what Save sends when nothing is changed, labels the row's display.
 */
export function checkboxState(field, raw, answers) {
    const spec = dynamicSpec(field);
    const { options, named } = optionsFor(field, spec, answers);
    const fold = spec ? foldName : foldCode;
    const exact = new Map();
    const folded = new Map();
    for (const o of options) {
        const code = String(o[0]);
        if (!exact.has(code)) exact.set(code, o);
        if (!folded.has(fold(code))) folded.set(fold(code), o); // first wins, as in the Apex
    }
    const find = (s) => exact.get(s.trim()) || folded.get(fold(s));
    const ticked = new Set();
    const offList = [];
    const labels = [];
    for (const v of savedTicks(raw, s => !!find(s))) {
        const s = v == null ? '' : (typeof v === 'object' ? JSON.stringify(v) : String(v));
        if (s.trim() === '') continue;
        const hit = find(s);
        if (hit) {
            if (!ticked.has(hit[0])) { ticked.add(hit[0]); labels.push(hit[1]); }
        } else if (!offList.includes(s)) {
            offList.push(s);
            labels.push(s);
        }
    }
    const shown = options.map(o => ({ value: o[0], label: o[1], checked: ticked.has(o[0]) }))
        .concat(offList.map(s => ({ value: s, label: s, checked: true })));
    const hints = [];
    if (spec && !named && NO_NAMES_HINT[field.id]) hints.push(NO_NAMES_HINT[field.id]);
    if (offList.length) hints.push(OFF_LIST_HINT);
    return {
        values: shown.filter(o => o.checked).map(o => o.value),
        labels,
        options: shown,
        offList,
        hint: hints.join(' ')
    };
}

// ── one-choice options (e2e 2026-10-08 follow-up) ──────────────────────────
// The select editor of a radio, select or yesno field selected the option
// equal to the saved value and nothing else. A saved value that is not an
// option (a legacy code, a case variant such as 'yes' where the catalogue
// spells 'Yes', a value saved before validation) opened the editor on the
// "not collected" entry, and a plain Save cleared the answer: the tick-box
// trap above, one choice at a time.
export const OFF_LIST_CHOICE_HINT =
    'The saved answer is not among the current options and is listed last. Choose another option to replace it.';

const YES_NO_OPTIONS = [['yes', 'Yes'], ['no', 'No']];

/**
 * The [code, label] options of a one-choice field: yes and no for a yesno
 * field (the codes the Apex and validateSave hold it to), the catalogue
 * options of a radio or select (cleanOptions), else none. A radio or select
 * left with no option (the address-lookup selects, F41) is edited as text.
 */
export function choiceOptions(field) {
    if (!field) return [];
    if (field.type === 'yesno') return YES_NO_OPTIONS;
    if (field.type === 'radio' || field.type === 'select') return cleanOptions(field.options);
    return [];
}

/**
 * Display and editor state of a one-choice answer, given its choiceOptions.
 * The saved value selects its option exactly, else the way the Apex holds it
 * to one (canonCode: trimmed, ignoring case), so a plain Save stores the code
 * as the catalogue spells it. A saved value that is not an option follows the
 * options, selected and labelled with the raw value: a plain Save sends it
 * back as saved (the Apex refuses it with a message naming it), and choosing
 * another option replaces it.
 * Returns { value, label, options: [{ value, label, selected }], offList, hint }:
 * value is what Save sends when nothing is changed ('' when nothing is saved),
 * label the row's display.
 */
export function choiceState(options, raw) {
    const list = Array.isArray(options) ? options : [];
    const s = raw == null ? '' : String(raw);
    const t = s.trim();
    const hit = t === '' ? null
        : list.find(o => String(o[0]) === t) || list.find(o => foldCode(String(o[0])) === foldCode(t)) || null;
    const offList = t !== '' && !hit ? s : '';
    const shown = list.map(o => ({ value: o[0], label: o[1], selected: o === hit }));
    if (offList) shown.push({ value: offList, label: offList, selected: true });
    return {
        value: hit ? hit[0] : offList,
        label: hit ? hit[1] : (s || null),
        options: shown,
        offList,
        hint: offList ? OFF_LIST_CHOICE_HINT : ''
    };
}

/** Same comparison src/fill/address-match.js normPostcode makes (uppercase,
 *  all whitespace removed), so the SF form and the fill agree on "differs". */
export function normPostcode(s) {
    return String(s == null ? '' : s).toUpperCase().replace(/\s+/g, '');
}

/**
 * How the home-address-postcode answer row should behave, given the record's
 * Postcode__c (audit F35, wave-2 review).
 *   { mode: 'editable' }               no record postcode: the answer is used
 *   { mode: 'readonly' }               answer blank or same as the record: the
 *                                      fill uses Postcode__c, edit via Address card
 *   { mode: 'conflict', warning }      they differ: keep the row editable. The
 *                                      fill HALTS when the answer came from Mary
 *                                      or a human (prepareAddressAnswers), so a
 *                                      read-only row left the operator stuck.
 */
export function postcodeRowState(answerValue, answerSource, recordPostcode) {
    const rec = String(recordPostcode == null ? '' : recordPostcode).trim();
    if (!rec) return { mode: 'editable', warning: '' };
    const ans = answerValue == null ? '' : String(answerValue);
    if (ans.trim() === '' || normPostcode(ans) === normPostcode(rec)) return { mode: 'readonly', warning: '' };
    const halts = /^(mary|human)$/i.test(String(answerSource || ''));
    const warning = halts
        ? `This differs from the record postcode (${rec}). The DWP fill stops until they match. ` +
          'Fix whichever is wrong: edit this answer, or change the address with the Address card.'
        : `This differs from the record postcode (${rec}). The DWP fill uses the record postcode. ` +
          'If this answer is the right one, change the address with the Address card.';
    return { mode: 'conflict', warning };
}

// ── declaration voided on change (owner decision, Fernando 2026-10-02) ─────
// When an answer changes after the client signed, Apex clears the
// declaration answers (and so Declaration_Complete__c), and the client must
// sign again before Fill on DWP. Operator-facing copy, shown on the decl row.
export const DECLARATION_VOID_NOTICE =
    'The declaration was cleared after the client signed it. This happens when an answer ' +
    'is changed after signing. The client must sign the declaration again before Fill on DWP can run.';

// The rows AA_FlowEngine.isDeclarationSigned reads (decldate is stored as
// _day/_month/_year, unlike every other date).
const DECLARATION_ROW_IDS = new Set(['decl', 'declname', 'decldate_day', 'decldate_month', 'decldate_year']);

function isBlankDeclValue(id, v) {
    if (v == null) return true;
    const s = String(v).trim();
    if (s === '') return true;
    // '[]' is how the pre-fix LWC saved an unticked box (F151/F175); Apex
    // treats it as unsigned too, so it counts as cleared.
    return id === 'decl' && s === '[]';
}

// The line AA_ProgressCalculator.DeclarationVoider appends to Notes__c:
// '[2 Oct 2026 14:05 UK] Declaration cleared: the answer "..." was changed ...'
const VOID_NOTE_RE = /\] Declaration cleared:/;

/** True when Notes__c holds the audit line the Apex void writes. */
export function notesShowDeclarationVoid(notes) {
    return notes != null && VOID_NOTE_RE.test(String(notes));
}

/**
 * True when the declaration was signed at some point but has since been
 * cleared, so the operator must get the client to sign again.
 *
 * There is no "voided" marker field, so two signals are read:
 *   1. The Apex void (AA_ProgressCalculator.voidDeclarationOnChange) DELETES
 *      the declaration rows, which leaves nothing in the answers to tell it
 *      apart from a declaration nobody has started (wave-3 review). What
 *      survives the delete is the "Declaration cleared:" line it appends to
 *      Notes__c, so that line plus a known-false Declaration_Complete__c
 *      means voided. The void only runs on signed apps, so the line can never
 *      appear for a declaration that was never signed. Once the client signs
 *      again the flag is true and the old line no longer counts. The flag
 *      must be known false (not just "not loaded yet"): a stale line with an
 *      unloaded flag would flash the notice on a re-signed record.
 *   2. A declaration row that EXISTS but is blank: an operator cleared it by
 *      hand through saveField (signing always writes non-blank values). The
 *      newest row per id wins, the same rule getAnswers / AA_FlowEngine use
 *      (answers arrive oldest-first, audit F39).
 * declarationComplete === true always wins: the flag is what the fill checks.
 */
export function declarationVoided(answers, declarationComplete, notes) {
    if (declarationComplete === true) return false;
    if (declarationComplete === false && notesShowDeclarationVoid(notes)) return true;
    const latest = {};
    for (const a of answers || []) {
        if (a && DECLARATION_ROW_IDS.has(a.Field_Id__c)) latest[a.Field_Id__c] = a.Value__c;
    }
    return Object.keys(latest).some(id => isBlankDeclValue(id, latest[id]));
}

/** Source__c picklist: default | mary | human | intake | form. */
export function sourceBadge(source) {
    if (!source) return { label: '', cls: '' };
    if (source === 'mary')    return { label: 'Mary',        cls: 'src-badge src-mary' };
    if (source === 'default') return { label: 'default',     cls: 'src-badge src-default' };
    if (source === 'form')    return { label: 'Client form', cls: 'src-badge src-form' };
    if (source === 'intake')  return { label: 'Intake',      cls: 'src-badge src-intake' };
    return { label: 'Human', cls: 'src-badge src-human' };
}