/**
 * AA_ApplicationFieldSync — mirrors specific AA_Answer__c values into
 * scalar fields on AA_Application__c so the header / highlights panel /
 * Details tab display live data instead of dashes.
 *
 * Why this exists: the client form (and Mary's tools) only write to
 * AA_Answer__c. The record-page header LWC + highlightsPanel compact
 * layout read from Application-parent scalar fields (Phone__c, Email__c,
 * etc.). Without this sync a fully-completed form leaves the header
 * reading "email: —, address: —, DOB: —" and Highlights panel identically
 * empty.
 *
 * Fired from AA_AnswerTrigger (same transaction as FlowEngine recompute)
 * so the header + progress bar update atomically.
 *
 * Behaviour: FORM/MARY/HUMAN answers overwrite the parent scalar. This is
 * intentional — Mary calling a client and updating a value should reflect
 * on the header. Details-tab manual edits by an operator are considered
 * corrections that persist until the next call rewrites them.
 *
 * 2026-08-26 — AA field-id reconciliation. The map was ported verbatim from
 * PC1 and still used PC1 question ids (q3, q7_line1, q0_sp_sortcode, …) that
 * DO NOT EXIST in the DWP Attendance Allowance form. Rebuilt against the real
 * AA question set (config/aa-flow.json + docs/DATA-CONTRACT.md):
 *   - Name/contact/address ids are semantic DWP names (first-name, last-name,
 *     middle-name, contact-by-email, main-contact-number, home-address-*).
 *   - DOB is the `birth-date` 3-part date (birth-date-day/-month/-year).
 *   - BANK IS NOT COLLECTED BY THE DWP AA FORM. aa-flow.json has zero
 *     sort-code/account/roll/holder fields — bank details are captured at
 *     intake (sales) for the GoCardless Direct Debit and written straight to
 *     the AA_Application__c Bank_* scalars by src/webhooks/intake.js. There is
 *     therefore no answer→scalar bank mirror here, and the PC1 "bank digits
 *     changed → reset verification" block was removed (it keyed off answer ids
 *     that never exist in AA). See report for the flag: if bank edits on the
 *     scalar should reset Bank_Verification_Status__c, that must be enforced by
 *     a before-update comparison on AA_Application__c, not by this answer sync.
 *   - national-insurance HAS NO scalar target on AA_Application__c (no NI
 *     field on the object) — intentionally unmapped; Mary reads it straight off
 *     the answer row (see src/lib/known-vars.js known_ni_number).
 */
public with sharing class AA_ApplicationFieldSync {

    /** AA answer Field_Id__c → parent AA_Application__c scalar. Only fields the
     *  record page displays are mirrored — no full flow copy. Every id below is
     *  a real, verified aa-flow.json field name. */
    private static final Map<String, String> ANSWER_TO_PARENT = new Map<String, String>{
        'first-name'                    => 'First_Name__c',
        'middle-name'                   => 'Middle_Name__c',   // DWP AA1 /full-name page: firstName, middleName (optional), lastName
        'last-name'                     => 'Last_Name__c',
        'contact-by-email'              => 'Email__c',         // AA "email-confirm" page — claimant contact email
        'main-contact-number'           => 'Phone__c',         // AA "telephone-number" page — single claimant number (no landline/mobile split)
        // Home address — the client-facing Form Link routes claimants to the
        // MANUAL address page (CLIENT_REROUTE), so every structured field the
        // client can see and correct — INCLUDING the postcode — is written under
        // the `home-address-manual-*` ids. The DWP postcode-lookup id
        // `home-address-postcode` is NEVER written by the form: it is seeded once
        // at intake (aa-intake-answer-seeder.js) and re-read live from Postcode__c
        // by the fill worker. Sourcing the scalar from that lookup id would leave
        // Postcode__c (and the Full_Address__c formula, header, highlights) frozen
        // at the stale intake value whenever a client corrects their postcode. So
        // Postcode__c is mirrored from the MANUAL postcode — the only postcode id
        // the Form Link actually writes.
        //
        // Representative address (representative-address-manual-*) has NO scalar
        // target on AA_Application__c — the object carries only the claimant
        // Address_*/Postcode__c fields — so it is intentionally unmapped and lives
        // solely as AA_Answer__c rows.
        'home-address-manual-line-one'  => 'Address_Line1__c',
        'home-address-manual-line-two'  => 'Address_Line2__c',
        'home-address-manual-town'      => 'City__c',
        'home-address-manual-county'    => 'County__c',
        'home-address-manual-postcode'  => 'Postcode__c'       // client's corrected postcode via the Form Link (manual page)
        // NOTE on Mary + postcode: Mary works off the ENGINE flow, whose postcode
        // field is the lookup id `home-address-postcode`. We deliberately do NOT
        // ALSO map that id to Postcode__c — two answer ids driving one scalar makes
        // the no-context re-sync order-dependent. It isn't needed for the common
        // cases: (a) form edits use the manual id (mapped above); (b) on a
        // non-seeded record Mary's `home-address-postcode` is filled while
        // Postcode__c is empty, so the fill worker's Postcode__c→answer override is
        // skipped and Mary's value is typed as-is. The only uncovered edge is Mary
        // CORRECTING an already-seeded postcode mid-call (worker would re-read the
        // stale scalar) — rare (address is pre-seeded from the sale and confirmed,
        // not re-collected); closing it properly needs the flow to route Mary's
        // address capture through the manual ids.
    };

    /** Parent fields marked `required=true` at the object level — cannot be
     *  nulled via DML (throws "Required fields are missing"). When the source
     *  answer is deleted for these, we leave the parent scalar alone rather
     *  than fail the whole trigger. Operator can edit via the Details pencil. */
    private static final Set<String> REQUIRED_PARENTS = new Set<String>{
        'First_Name__c', 'Last_Name__c'
    };

    /** DOB date stem — birth-date-day/-month/-year → DOB__c as a real Date.
     *  AA date parts use a HYPHEN separator (DWP/DATA-CONTRACT §1.3), not the
     *  underscore PC1 used (q5_day). */
    private static final String DOB_ID = 'birth-date';

    /**
     * Convenience overload for callers without trigger context — treats
     * every mapped field as "affected" so deletes propagate. Use the
     * two-arg version from AA_AnswerTrigger.
     */
    public static void syncFromAnswers(Set<Id> appIds) {
        syncFromAnswers(appIds, ANSWER_TO_PARENT.keySet());
    }

    /**
     * Sync scalar Application fields from Answer rows for a set of Apps.
     *   `affectedFieldIds` — the union of Trigger.new + Trigger.old Field_Id__c
     *   values, so we can distinguish "answer was deleted → null the parent"
     *   from "answer never existed → leave the parent alone" (protects
     *   operator edits made via the Details pencil).
     * Bulk-safe: one SOQL, one DML, no per-record loops beyond field mapping.
     * Idempotent — safe to call from every trigger firing.
     */
    public static void syncFromAnswers(Set<Id> appIds, Set<String> affectedFieldIds) {
        if (appIds == null || appIds.isEmpty()) return;
        if (affectedFieldIds == null) affectedFieldIds = new Set<String>();

        // Preload existing Application values so we only DML when something
        // actually differs — cuts trigger recursion and audit noise.
        Map<Id, AA_Application__c> current = new Map<Id, AA_Application__c>([
            SELECT Id, First_Name__c, Middle_Name__c, Last_Name__c, Email__c, Phone__c,
                   Address_Line1__c, Address_Line2__c, City__c, County__c, Postcode__c, DOB__c
              FROM AA_Application__c
             WHERE Id IN :appIds
        ]);

        // Read only the answer field ids we care about (mapped scalars + the
        // three DOB parts).
        Set<String> ids = new Set<String>(ANSWER_TO_PARENT.keySet());
        ids.add(DOB_ID + '-day');
        ids.add(DOB_ID + '-month');
        ids.add(DOB_ID + '-year');

        // Group answers by Application → fieldId → value. Order by
        // LastModifiedDate DESC and keep the FIRST (most recent) row per
        // (App, Field_Id) so that when duplicate rows exist (leftover from
        // stress tests, race conditions, etc.) the newest one wins.
        Map<Id, Map<String, String>> answersByApp = new Map<Id, Map<String, String>>();
        for (Id id : appIds) answersByApp.put(id, new Map<String, String>());
        for (AA_Answer__c a : [
            SELECT Application__c, Field_Id__c, Value__c
              FROM AA_Answer__c
             WHERE Application__c IN :appIds
               AND Field_Id__c IN :ids
             ORDER BY LastModifiedDate DESC
        ]) {
            if (a.Application__c == null || String.isBlank(a.Field_Id__c)) continue;
            if (a.Value__c == null || a.Value__c == '') continue;
            Map<String, String> m = answersByApp.get(a.Application__c);
            if (!m.containsKey(a.Field_Id__c)) m.put(a.Field_Id__c, a.Value__c);
        }

        List<AA_Application__c> toUpdate = new List<AA_Application__c>();
        for (Id id : appIds) {
            AA_Application__c existing = current.get(id);
            if (existing == null) continue;
            Map<String, String> ans = answersByApp.get(id);
            AA_Application__c patch = new AA_Application__c(Id = id);
            Boolean dirty = false;

            for (String aId : ANSWER_TO_PARENT.keySet()) {
                String parentApi = ANSWER_TO_PARENT.get(aId);
                String newVal = ans.get(aId);
                Object oldRaw = existing.get(parentApi);
                String oldVal = oldRaw == null ? null : String.valueOf(oldRaw);
                if (newVal != null) {
                    // Phone__c drives outbound dialing + inbound caller-id
                    // recognition, both of which need E.164. Mary/the form save
                    // 'main-contact-number' as raw typed text ("07476 900311"),
                    // which used to poison Phone__c and break both (audit). Normalise;
                    // skip the write if it can't be parsed rather than storing junk.
                    if (parentApi == 'Phone__c') {
                        String e164 = normalizePhoneE164(newVal);
                        if (String.isBlank(e164)) continue;
                        newVal = e164;
                    }
                    if (newVal == oldVal) continue;
                    patch.put(parentApi, newVal);
                    dirty = true;
                } else if (affectedFieldIds.contains(aId) && oldVal != null && !REQUIRED_PARENTS.contains(parentApi)) {
                    // Answer for this mapped id was deleted (or blanked and then
                    // destroyed by the form's diff-flush) — clear the parent
                    // scalar so it doesn't linger with stale data no one can
                    // trace back. Skip required parents (First/Last Name) —
                    // nulling them would fail the whole DML.
                    patch.put(parentApi, null);
                    dirty = true;
                }
            }

            // DOB triplet → Date. Sync when all three parts present + parse ok.
            String d = ans.get(DOB_ID + '-day');
            String m = ans.get(DOB_ID + '-month');
            String y = ans.get(DOB_ID + '-year');
            Boolean dobTouched = affectedFieldIds.contains(DOB_ID + '-day')
                || affectedFieldIds.contains(DOB_ID + '-month')
                || affectedFieldIds.contains(DOB_ID + '-year');
            if (!String.isBlank(d) && !String.isBlank(m) && !String.isBlank(y)) {
                Date parsed = parseDob(d, m, y);
                // null = not a real, plausible date of birth: leave DOB__c
                // alone rather than write a wrong one or fail the answer save.
                if (parsed != null && parsed != existing.DOB__c) {
                    patch.DOB__c = parsed;
                    dirty = true;
                }
            } else if (dobTouched && existing.DOB__c != null) {
                // At least one part was just deleted → DOB is incomplete
                // now, clear the parent so nothing downstream reads stale.
                patch.DOB__c = null;
                dirty = true;
            }

            if (dirty) toUpdate.add(patch);
        }

        if (toUpdate.isEmpty()) return;
        // allOrNone=false (audit 2026-10-02 F37/F83): this runs inside
        // AA_AnswerTrigger. A plain `update` that tripped any Application
        // validation rule (Next_Call_At_In_Future while a Pending slot has just
        // passed undialled, DOB_Reasonable, ...) rolled back the client's answer
        // itself. The scalars are a display mirror and re-sync on the next
        // save; the answer must not be lost. Log instead.
        Database.SaveResult[] saved = Database.update(toUpdate, false);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) continue;
            System.debug(LoggingLevel.ERROR, 'AA_ApplicationFieldSync: scalar sync skipped for '
                + toUpdate[i].Id + ': ' + saved[i].getErrors()[0].getMessage());
        }
    }

    /**
     * Build DOB__c from the three answer parts, or null when they do not make a
     * real, plausible date of birth.
     *
     * audit 2026-10-02 F38: Date.newInstance silently rolls impossible parts
     * over (31/02/1948 became 02/03/1948, month 13 became January of the next
     * year), so a mistyped part wrote a WRONG DOB__c. And a year such as 1850
     * or 2030 produced a date that failed the DOB_Reasonable validation rule
     * in the parent update, which rolled back the answer save. Requiring the
     * parts to round-trip and the date to sit in 1900-01-01 .. yesterday
     * prevents both. The answer row itself is kept, so the bad part stays
     * visible for the operator to correct.
     */
    @TestVisible
    private static Date parseDob(String d, String m, String y) {
        Integer di, mi, yi;
        try {
            di = Integer.valueOf(d.trim());
            mi = Integer.valueOf(m.trim());
            yi = Integer.valueOf(y.trim());
        } catch (Exception e) {
            return null;
        }
        if (di < 1 || di > 31 || mi < 1 || mi > 12 || yi < 1900) return null;
        Date parsed = Date.newInstance(yi, mi, di);
        if (parsed.day() != di || parsed.month() != mi || parsed.year() != yi) return null;
        if (parsed >= Date.today()) return null;
        return parsed;
    }

    /**
     * Normalise a UK phone number to E.164 (+44…) for Phone__c so outbound
     * dialing + inbound caller-id recognition work. Returns '' for anything that
     * can't be parsed as a UK number, so the caller skips the write rather than
     * poisoning Phone__c (audit).
     */
    @TestVisible
    private static String normalizePhoneE164(String raw) {
        if (String.isBlank(raw)) return '';
        String t = raw.trim();
        if (t.startsWith('+')) {
            String digits = t.substring(1).replaceAll('[^0-9]', '');
            return (digits.length() >= 10 && digits.length() <= 15) ? '+' + digits : '';
        }
        String d = t.replaceAll('[^0-9]', '');
        if (d.startsWith('00')) d = d.substring(2);           // 0044… → 44…
        if (d.startsWith('44')) return d.length() >= 11 ? '+' + d : '';
        if (d.startsWith('0'))  { String rest = d.substring(1); return rest.length() == 10 ? '+44' + rest : ''; }
        if (d.length() == 10)   return '+44' + d;             // bare UK national, no leading 0
        return '';
    }
}