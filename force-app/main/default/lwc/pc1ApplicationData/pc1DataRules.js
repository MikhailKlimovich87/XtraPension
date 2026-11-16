/**
 * pc1DataRules — pure helpers for pc1ApplicationData (no lwc / Salesforce
 * imports, so the logic can be exercised offline by copying this file to a
 * .mjs and importing it from Node). Same idea as aaDataRules in the AA twin.
 *
 * Operator edits get the checks the client form applies from the flow JSON
 * (web/form.html, the Continue handler): a real calendar date, dateMin /
 * dateMax, minLength / maxLength / pattern, each with the flow's own message.
 * Plus two rules of src/lib/mary-validator.js: a plausible year, and "none"
 * never ticked next to another option. The editor used to save anything
 * (31/02/1950, a date of birth in the future, any text): audit 2026-11-11
 * PC-SFUI-11.
 *
 * Blank always passes: it clears the answer.
 */

const UK_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'];

// Years src/lib/mary-validator.js accepts in a date.
const MIN_YEAR = 1900;
const MAX_YEAR = 2100;

/**
 * Date bound token of the flow JSON: "today" or "-Ny" / "-Nm" / "-Nd" (N years /
 * months / days before today). Same grammar as dateBound() in web/form.html and
 * src/lib/flow-date-tokens.js. Returns a Date at 00:00 local, or null.
 */
export function dateBound(tok, today) {
    const t = today instanceof Date ? new Date(today.getTime()) : new Date();
    t.setHours(0, 0, 0, 0);
    if (tok === 'today') return t;
    const m = /^-(\d+)([ymd])$/.exec(tok || '');
    if (!m) return null;
    const n = +m[1];
    if (m[2] === 'y') t.setFullYear(t.getFullYear() - n);
    else if (m[2] === 'm') t.setMonth(t.getMonth() - n);
    else t.setDate(t.getDate() - n);
    return t;
}

/** "{{date:-3m}}" inside a flow message becomes "11 August 2026". */
export function interpolateDateTokens(str, today) {
    if (typeof str !== 'string' || str.indexOf('{{date:') === -1) return str;
    return str.replace(/\{\{date:([a-z0-9-]+)\}\}/gi, (match, tok) => {
        const d = dateBound(tok, today);
        return d ? `${d.getDate()} ${UK_MONTHS[d.getMonth()]} ${d.getFullYear()}` : match;
    });
}

/**
 * Validate a DD/MM/YYYY triplet against the flow field. All blank = clear
 * (allowed). The editor saves day, month and year in three calls, so
 * everything is checked here, before any part is saved. Returns an error
 * string or null.
 */
export function checkDateParts(field, d, m, y, today) {
    if (!d && !m && !y) return null;
    if (!d || !m || !y) return 'Enter a full date: day, month and year.';
    if (!/^\d{1,2}$/.test(d) || !/^\d{1,2}$/.test(m)) return 'Day and month must be numbers.';
    if (!/^\d{4}$/.test(y)) return 'Enter the year as 4 digits, for example 1948.';
    const dn = Number(d), mn = Number(m), yn = Number(y);
    if (mn < 1 || mn > 12) return 'Month must be between 1 and 12.';
    if (dn < 1 || dn > 31) return 'Day must be between 1 and 31.';
    const dt = new Date(yn, mn - 1, dn);
    if (dt.getFullYear() !== yn || dt.getMonth() !== mn - 1 || dt.getDate() !== dn) {
        return (field && field.errorMessage) || `${d}/${m}/${y} is not a real date.`;
    }
    if (yn < MIN_YEAR || yn > MAX_YEAR) return `Year must be between ${MIN_YEAR} and ${MAX_YEAR}.`;
    const min = field && field.dateMin ? dateBound(field.dateMin, today) : null;
    const max = field && field.dateMax ? dateBound(field.dateMax, today) : null;
    if (min && dt < min) {
        return interpolateDateTokens(field.dateMinMessage || field.errorMessage, today) || 'The date is too early.';
    }
    if (max && dt > max) {
        return interpolateDateTokens(field.dateMaxMessage || field.errorMessage, today) || 'The date cannot be in the future.';
    }
    return null;
}

/**
 * Check a typed answer (text / textarea / number / amount) before it is
 * saved. Returns { ok, value, error }; value is the trimmed string to save,
 * the one the checks ran on.
 */
export function checkTextValue(field, raw) {
    const value = raw == null ? '' : String(raw).trim();
    if (value === '') return { ok: true, value: '' };
    const f = field || {};
    if (f.minLength && value.length < f.minLength) {
        return { ok: false, value, error: f.errorMessage || `Must be at least ${f.minLength} characters.` };
    }
    if (f.maxLength && value.length > f.maxLength) {
        return { ok: false, value, error: f.errorMessage || `Must be ${f.maxLength} characters or fewer.` };
    }
    if (f.pattern) {
        let re = null;
        try { re = new RegExp(f.pattern); } catch (_) { re = null; }
        if (re && !re.test(value)) {
            return { ok: false, value, error: f.errorMessage || 'Enter the answer in the correct format.' };
        }
    }
    return { ok: true, value };
}

/**
 * Tick-box answers: "none" contradicts any other option ticked with it.
 * Returns an error string or null.
 */
export function checkTicks(ticked) {
    const arr = Array.isArray(ticked) ? ticked.map(String) : [];
    if (arr.includes('none') && arr.length > 1) {
        return 'Tick "None of these" on its own, or the options that apply without it.';
    }
    return null;
}