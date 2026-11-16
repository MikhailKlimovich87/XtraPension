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
        // The answers being written right now come FROM the record
        // (mirrorToAnswers): there is nothing to copy back, and a re-sync of
        // every mapped field here would undo another record field edited in
        // the same save (a phone number, an address line).
        if (mirroringToAnswers) return;
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
        // The flag tells afterRecordEdit (AA_ApplicationTrigger) that this
        // scalar write is the mirror of an answer, not an edit on the record.
        Database.SaveResult[] saved;
        syncingFromAnswers = true;
        try {
            saved = Database.update(toUpdate, false);
        } finally {
            syncingFromAnswers = false;
        }
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) continue;
            System.debug(LoggingLevel.ERROR, 'AA_ApplicationFieldSync: scalar sync skipped for '
                + toUpdate[i].Id + ': ' + saved[i].getErrors()[0].getMessage());
        }
    }

    // ── record edit -> answers / declaration (audit 2026-11-11 AA-SFUI-2, AA-SFUI-3) ──

    /** True while syncFromAnswers writes the scalars (answer -> record). */
    public static Boolean syncingFromAnswers = false;
    /** True while mirrorToAnswers writes the answers (record -> answer). */
    private static Boolean mirroringToAnswers = false;

    /**
     * Record fields an operator can edit on the Details tab whose value the
     * DWP fill takes from an ANSWER row (src/fill/adapter.js builds the fill
     * from AA_Answer__c only). Until 2026-11-11 the sync ran one way (answer
     * to record), so a name, date of birth or email corrected on the record
     * changed the header and nothing else: DWP still got the old answer, and
     * the next answer save overwrote the correction. Phone__c is left out on
     * purpose: the record holds E.164 for dialling, the answer holds the
     * number as the client gave it, and DWP gets the answer.
     */
    private static final Map<String, String> PARENT_TO_ANSWER = new Map<String, String>{
        'First_Name__c'  => 'first-name',
        'Middle_Name__c' => 'middle-name',
        'Last_Name__c'   => 'last-name',
        'Email__c'       => 'contact-by-email'
    };

    /** Record fields the DWP fill types the home address from (src/fill/address-match.js). */
    private static final List<String> ADDRESS_FILL_FIELDS = new List<String>{
        'Postcode__c', 'Address_Line1__c', 'Address_Line2__c'
    };

    /**
     * After update of AA_Application__c (AA_ApplicationTrigger). For an edit
     * made on the record itself, not for the mirror of an answer:
     *   1. a changed home address clears a signed declaration, exactly as an
     *      answer change does (AA_ProgressCalculator.voidDeclarationOnRecordChange).
     *      The record is what the fill types, so there is no answer to write;
     *   2. a changed name, date of birth or email is written to the answer
     *      rows the fill reads, with Source__c 'human'. AA_AnswerTrigger then
     *      does the rest (declaration void, progress).
     * Fail closed: when the declaration cannot be cleared or an answer cannot
     * be written, the record edit itself is refused, so the record and what
     * DWP would receive never disagree.
     */
    public static void afterRecordEdit(List<AA_Application__c> newList, Map<Id, AA_Application__c> oldMap) {
        if (syncingFromAnswers || mirroringToAnswers || newList == null || oldMap == null) return;

        Map<Id, String> addressChanged = new Map<Id, String>();
        for (AA_Application__c app : newList) {
            AA_Application__c prev = oldMap.get(app.Id);
            if (prev == null) continue;
            for (String f : ADDRESS_FILL_FIELDS) {
                if (!text(app.get(f)).equals(text(prev.get(f)))) {
                    addressChanged.put(app.Id, 'home address (' + f + ' on the record)');
                    break;
                }
            }
        }
        if (!addressChanged.isEmpty()) {
            Map<Id, String> notCleared = AA_ProgressCalculator.voidDeclarationOnRecordChange(addressChanged);
            for (AA_Application__c app : newList) {
                if (!notCleared.containsKey(app.Id)) continue;
                app.addError('The address was not saved, because the signed declaration on this application could not be cleared ('
                    + notCleared.get(app.Id) + '). Please try again in a few minutes.');
            }
        }
        mirrorToAnswers(newList, oldMap);
    }

    private static void mirrorToAnswers(List<AA_Application__c> newList, Map<Id, AA_Application__c> oldMap) {
        // appId -> answer field id -> the value it must now hold (null = no answer)
        Map<Id, Map<String, String>> wanted = new Map<Id, Map<String, String>>();
        Set<String> fieldIds = new Set<String>();
        for (AA_Application__c app : newList) {
            AA_Application__c prev = oldMap.get(app.Id);
            if (prev == null) continue;
            Map<String, String> w = new Map<String, String>();
            for (String parentApi : PARENT_TO_ANSWER.keySet()) {
                String nv = text(app.get(parentApi));
                if (!nv.equals(text(prev.get(parentApi)))) {
                    w.put(PARENT_TO_ANSWER.get(parentApi), String.isEmpty(nv) ? null : nv);
                }
            }
            if (app.DOB__c != prev.DOB__c) {
                // No leading zeros, like the intake seeder and the form.
                Date d = app.DOB__c;
                w.put(DOB_ID + '-day',   d == null ? null : String.valueOf(d.day()));
                w.put(DOB_ID + '-month', d == null ? null : String.valueOf(d.month()));
                w.put(DOB_ID + '-year',  d == null ? null : String.valueOf(d.year()));
            }
            if (w.isEmpty()) continue;
            wanted.put(app.Id, w);
            fieldIds.addAll(w.keySet());
        }
        if (wanted.isEmpty()) return;

        Map<String, List<AA_Answer__c>> rowsByKey = new Map<String, List<AA_Answer__c>>();
        for (AA_Answer__c a : [
            SELECT Id, Application__c, Field_Id__c, Value__c
              FROM AA_Answer__c
             WHERE Application__c IN :wanted.keySet() AND Field_Id__c IN :fieldIds
        ]) {
            String k = String.valueOf(a.Application__c) + '|' + a.Field_Id__c;
            if (!rowsByKey.containsKey(k)) rowsByKey.put(k, new List<AA_Answer__c>());
            rowsByKey.get(k).add(a);
        }

        List<AA_Answer__c> toInsert = new List<AA_Answer__c>();
        List<AA_Answer__c> toChange = new List<AA_Answer__c>();
        List<AA_Answer__c> toDelete = new List<AA_Answer__c>();
        Set<Id> touched = new Set<Id>();
        for (Id appId : wanted.keySet()) {
            Map<String, String> w = wanted.get(appId);
            for (String fieldId : w.keySet()) {
                String v = w.get(fieldId);
                List<AA_Answer__c> rows = rowsByKey.get(String.valueOf(appId) + '|' + fieldId);
                if (v == null) {
                    // The record field was emptied: no answer, as when the
                    // client clears the field on the form.
                    if (rows != null) { toDelete.addAll(rows); touched.add(appId); }
                } else if (rows == null) {
                    toInsert.add(new AA_Answer__c(
                        Application__c = appId, Field_Id__c = fieldId, Value__c = v, Source__c = 'human'));
                    touched.add(appId);
                } else {
                    for (AA_Answer__c r : rows) {
                        if (text(r.Value__c).equals(v)) continue;
                        toChange.add(new AA_Answer__c(Id = r.Id, Value__c = v, Source__c = 'human'));
                        touched.add(appId);
                    }
                }
            }
        }
        if (touched.isEmpty()) return;

        mirroringToAnswers = true;
        try {
            if (!toDelete.isEmpty()) delete toDelete;
            if (!toChange.isEmpty()) update toChange;
            if (!toInsert.isEmpty()) insert toInsert;
        } catch (DmlException e) {
            for (AA_Application__c app : newList) {
                if (!touched.contains(app.Id)) continue;
                app.addError('This change was not saved, because the matching answer in the application data could not be updated ('
                    + e.getDmlMessage(0) + ').');
            }
        } finally {
            mirroringToAnswers = false;
        }
    }

    /** A record value as trimmed text; null and blank are the same. */
    private static String text(Object v) {
        return v == null ? '' : String.valueOf(v).trim();
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