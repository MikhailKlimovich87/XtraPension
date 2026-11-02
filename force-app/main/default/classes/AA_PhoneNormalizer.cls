/**
 * AA_PhoneNormalizer — E.164 phone-number normaliser applied before every
 * AA_Application__c write. Mirrors the JS helper in src/lib/phone.js so any
 * write path (LWC edit, Data Loader, Apex, Heroku) lands the same canonical
 * value in Phone__c.
 *
 * Rules (matches Hostinger normalizePhone in src/db.js):
 *   - leading "+" preserved
 *   - "00" international prefix → "+"
 *   - a leading "0" (UK trunk prefix) → "+44"
 *   - anything else without a "+" is digits-only (defensive — no country
 *     prefix is invented for ambiguous inputs)
 *   - empty / all-non-digit input is left untouched
 */
public with sharing class AA_PhoneNormalizer {

    public static void normalize(List<AA_Application__c> newList) {
        if (newList == null) return;
        for (AA_Application__c app : newList) {
            if (app.Phone__c == null) continue;
            String norm = toE164(app.Phone__c);
            if (norm != null && norm != app.Phone__c) app.Phone__c = norm;
        }
    }

    @TestVisible
    private static String toE164(String raw) {
        if (raw == null) return null;
        String s = raw.trim();
        if (String.isBlank(s)) return null;
        Boolean hasPlus = s.startsWith('+');
        // Strip everything except digits.
        String digits = s.replaceAll('[^0-9]', '');
        if (String.isBlank(digits)) return null;
        String out;
        if (hasPlus) out = '+' + digits;
        else if (digits.startsWith('00')) out = '+' + digits.substring(2);
        else if (digits.startsWith('0')) out = '+44' + digits.substring(1);
        else out = digits;
        // Audit 2026-10-02 F117: '+44 (0)7476 900311' kept the bracketed UK
        // trunk zero and became '+4407476900311', which the dialer cannot ring
        // and inbound caller-id never matches. Drop that zero.
        if (out.startsWith('+440') && out.length() > 4) out = '+44' + out.substring(4);
        // '447476900311' typed without the '+' came back as bare digits: a UK
        // number with its country code (12 or 11 digits) gets its '+'.
        if (!out.startsWith('+') && out.startsWith('44') && (out.length() == 12 || out.length() == 11)) out = '+' + out;
        return out;
    }
}