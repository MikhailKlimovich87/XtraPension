/**
 * PC1_PhoneNormalizer — E.164 phone-number normaliser applied before every
 * PC1_Application__c write. Mirrors src/lib/phone.js normaliseE164() (the
 * STRICT R5 H2 helper), not the loose Hostinger normalizePhone().
 *
 * Rules, in this order (keep them the same as src/lib/phone.js normaliseE164,
 * branch for branch: storage must equal lookup):
 *   - Strip non-digits.
 *   - "00" international prefix → drop it (implicit +).
 *   - '44' + '0' + national number ('+44 (0)20...') → trunk zero dropped.
 *   - Domestic UK '07' + 9 digits → '+447...'.
 *   - Domestic IE '08' + 8 digits → '+3538...' (only if IE explicitly).
 *   - '44' + 10 digits (GB) → '+44...'.
 *   - '353' + (12 or 13 digits) (IE) → '+353...'.
 *   - '1' + 10 digits (US/CA) → '+1...'.
 *   - Any other UK national number, '0' + 9 or 10 digits (landlines 01/02/03,
 *     08...) → '+44...' (audit 2026-11-11 PC-APEX-1).
 *   - Anything else starting with '0' → null (never '+0...').
 *   - Anything else short/malformed → null.
 * null = the caller keeps the value as typed.
 *
 * Also normalizes Helper_Phone__c (was left as-is by previous version).
 * Handling the STRICT rules means storage = lookup, killing suffix
 * collision misattribution (Twilio inbound / WhatsApp cross-record leak).
 */
public with sharing class PC1_PhoneNormalizer {
    private static final Integer GB_MOBILE_LEN = 12; // 44 + 10 digits

    public static void normalize(List<PC1_Application__c> newList) {
        if (newList == null) return;
        for (PC1_Application__c app : newList) {
            if (app.Phone__c != null) {
                String norm = toE164(app.Phone__c);
                if (norm != null && norm != app.Phone__c) app.Phone__c = norm;
            }
            if (app.Helper_Phone__c != null) {
                String norm = toE164(app.Helper_Phone__c);
                if (norm != null && norm != app.Helper_Phone__c) app.Helper_Phone__c = norm;
            }
        }
    }

    @TestVisible
    private static String toE164(String raw) {
        return toE164(raw, 'GB');
    }

    @TestVisible
    private static String toE164(String raw, String defaultCountry) {
        if (raw == null) return null;
        String digits = raw.replaceAll('[^0-9]', '');
        if (String.isBlank(digits)) return null;
        // Legacy 00-international prefix.
        if (digits.startsWith('00')) digits = digits.substring(2);
        // '+44 (0)20 7946 0018': the bracketed trunk zero is not part of the number.
        if (digits.startsWith('440') && digits.length() > 11) digits = '44' + digits.substring(3);
        // Domestic UK: 07 + 9 digits.
        if (digits.length() == 11 && digits.startsWith('07') && defaultCountry == 'GB') {
            return '+44' + digits.substring(1);
        }
        // Domestic IE: 08 + 8 digits (only when caller explicitly IE).
        if (digits.length() == 10 && digits.startsWith('08') && defaultCountry == 'IE') {
            return '+353' + digits.substring(1);
        }
        // Already country-prefixed forms.
        if (digits.startsWith('44') && digits.length() == GB_MOBILE_LEN) return '+' + digits;
        if (digits.startsWith('353') && (digits.length() == 12 || digits.length() == 13)) return '+' + digits;
        if (digits.startsWith('1') && digits.length() == 11) return '+' + digits;
        // Audit 2026-11-11 PC-APEX-1: a UK national number (landline 01/02/03,
        // 08..., 10 or 11 digits with the trunk zero) is +44 without the zero.
        // The R6 M6 strict port dropped this branch, so '020 7946 0018' fell
        // through to the last line and was stored as '+02079460018', which
        // nobody can dial and no caller id matches. Anything else that starts
        // with 0 is not a number we can make international: null, never '+0...'.
        // Same rule as src/lib/phone.js normaliseE164: a 10-digit 07 number is
        // a mobile missing a digit, never a valid number.
        if (digits.startsWith('0') && defaultCountry == 'GB'
                && (digits.length() == 11 || (digits.length() == 10 && !digits.startsWith('07')))) {
            return '+44' + digits.substring(1);
        }
        if (digits.startsWith('0')) return null;
        // Too short / unknown → return null so caller drops the value.
        if (digits.length() < 7 || digits.length() > 15) return null;
        // Best-effort intl assumed.
        return '+' + digits;
    }
}