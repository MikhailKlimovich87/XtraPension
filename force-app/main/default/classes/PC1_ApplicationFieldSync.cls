/**
 * PC1_ApplicationFieldSync — mirrors specific PC1_Answer__c values into
 * scalar fields on PC1_Application__c so the header / highlights panel /
 * Details tab display live data instead of dashes.
 *
 * Why this exists: the client form (and Mary's tools) only write to
 * PC1_Answer__c. The record-page header LWC + highlightsPanel compact
 * layout read from Application-parent scalar fields (Phone__c, Email__c,
 * etc.). Without this sync a fully-completed form leaves the header
 * reading "email: —, address: —, DOB: —" and Highlights panel identically
 * empty.
 *
 * Fired from PC1_AnswerTrigger (same transaction as FlowEngine recompute)
 * so the header + progress bar update atomically.
 *
 * Behaviour: FORM/MARY/HUMAN answers overwrite the parent scalar. This is
 * intentional — Mary calling a client and updating a value should reflect
 * on the header. Details-tab manual edits by an operator are considered
 * corrections that persist until the next call rewrites them.
 */
public with sharing class PC1_ApplicationFieldSync {

    /** answerId → parentApiName mapping. Only the fields the record page
     *  displays are mirrored — no full flow copy. */
    private static final Map<String, String> ANSWER_TO_PARENT = new Map<String, String>{
        'q3'              => 'First_Name__c',
        'q3m'             => 'Middle_Name__c',     // 2026-08-25: DWP AA1 /your-name page has 3 inputs (firstName, middleNames, lastName). Middle is optional but Mary should confirm it if present. Sync bidirectionally so val-team edits on the scalar propagate + client-form q3m rewrites the scalar.
        'q2'              => 'Last_Name__c',
        'q_email_address' => 'Email__c',
        'q9'              => 'Phone__c',           // landline; overwritten by q9_mobile if present after
        'q9_mobile'       => 'Phone__c',           // mobile wins when both present (last-write)
        'q7_line1'        => 'Address_Line1__c',
        'q7_line2'        => 'Address_Line2__c',
        'q7_town'         => 'City__c',
        'q7_county'       => 'County__c',
        'q7_postcode'     => 'Postcode__c',
        // Bank — mirrored so the record page + PC1_BankLookup workflow see
        // whatever the client last submitted through the form, regardless
        // of whether the Verify button was clicked.
        'q0_sp_sortcode'  => 'Bank_Sort_Code__c',
        'q0_sp_account'   => 'Bank_Account_Number__c',
        'q_bank_holder'   => 'Bank_Account_Holder__c',
        'q_bank_roll'     => 'Bank_Roll_Number__c',
        'q_bank_name'     => 'Bank_Name__c',
        'q_bank_verification_status' => 'Bank_Verification_Status__c'
    };

    /** Parent fields marked `required=true` at the object level — cannot be
     *  nulled via DML (throws "Required fields are missing"). When the source
     *  answer is deleted for these, we leave the parent scalar alone rather
     *  than fail the whole trigger. Operator can edit via the Details pencil. */
    private static final Set<String> REQUIRED_PARENTS = new Set<String>{
        'First_Name__c', 'Last_Name__c'
    };

    /** Date triplet — q5_day/_month/_year → DOB__c as a real Date. */
    private static final String DOB_ID = 'q5';

    /** Mandate statuses that are already unusable — nothing to park. */
    private static final Set<String> DEAD_MANDATE_STATUSES = new Set<String>{
        'failed', 'cancelled', 'expired', 'consumed', 'blocked'
    };

    /** Bank statuses that unlock a mandate (PC1_MandateEligibility). */
    private static final Set<String> GREEN_BANK_STATUSES = PC1_MandateEligibility.VERIFIED_STATUSES;

    /** Recursion guards between the two directions of the sync. */
    @TestVisible private static Boolean syncingFromAnswers = false;
    @TestVisible private static Boolean syncingFromParent = false;

    /** parentApiName → answer id for the reverse direction. Phone__c is
     *  left out: two answers feed it (landline / mobile) and the record
     *  page cannot say which one the operator meant. */
    private static Map<String, String> parentToAnswer() {
        Map<String, String> m = new Map<String, String>();
        for (String aId : ANSWER_TO_PARENT.keySet()) {
            String parentApi = ANSWER_TO_PARENT.get(aId);
            if (parentApi == 'Phone__c') continue;
            m.put(parentApi, aId);
        }
        return m;
    }

    /**
     * BEFORE UPDATE. Bank digits edited straight on the Application (bank
     * editor LWC, inline edit, data load) get the same safety as an answer
     * change: an unchanged green status is reset to Unverified, and a live
     * mandate on the old account is parked so nothing is charged there.
     * Without this the record-page bank editor updated the account while
     * the mandate kept collecting from the old one (audit 2026-10-02 C10).
     */
    public static void onParentBankChange(List<PC1_Application__c> newList, Map<Id, PC1_Application__c> oldMap) {
        if (syncingFromAnswers) return; // syncFromAnswers already did this in its patch
        for (PC1_Application__c a : newList) {
            PC1_Application__c o = oldMap.get(a.Id);
            if (o == null) continue;
            Boolean digitsChanged = onlyDigits(a.Bank_Sort_Code__c) != onlyDigits(o.Bank_Sort_Code__c)
                || onlyDigits(a.Bank_Account_Number__c) != onlyDigits(o.Bank_Account_Number__c);
            if (!digitsChanged) continue;
            // Same DML set a fresh status (bank editor verified the new
            // digits) → keep it. Otherwise the old verdict no longer applies.
            if (a.Bank_Verification_Status__c == o.Bank_Verification_Status__c
                    && GREEN_BANK_STATUSES.contains(a.Bank_Verification_Status__c)) {
                a.Bank_Verification_Status__c = 'Unverified';
                a.Bank_Verified_At__c = null;
            }
            if (String.isNotBlank(a.DD_Mandate_Id__c)
                    && a.DD_Mandate_Id__c == o.DD_Mandate_Id__c
                    && !DEAD_MANDATE_STATUSES.contains(a.DD_Mandate_Status__c)) {
                a.DD_Mandate_Status__c = 'cancelled';
                a.DD_Mandate_Failure_Reason__c = 'Bank details changed on ' + String.valueOf(Date.today())
                    + '. The old Direct Debit will not be charged; set up a new one for the new account.';
            }
        }
    }

    /**
     * AFTER UPDATE. Mirror direct edits of the mapped scalars back into the
     * answers. The DWP fill reads PC1_Answer__c, and syncFromAnswers copies
     * answers onto the parent on the next answer save, so an edit made only
     * on the parent was (a) never sent to DWP and (b) silently reverted
     * later (audit 2026-10-02 C10). Blank parent → answer rows deleted.
     */
    public static void mirrorParentToAnswers(List<PC1_Application__c> newList, Map<Id, PC1_Application__c> oldMap) {
        if (syncingFromAnswers || syncingFromParent) return;
        Map<String, String> p2a = parentToAnswer();
        Map<Id, Map<String, String>> changes = new Map<Id, Map<String, String>>();
        Set<String> touchedIds = new Set<String>();
        for (PC1_Application__c a : newList) {
            PC1_Application__c o = oldMap.get(a.Id);
            if (o == null) continue;
            for (String parentApi : p2a.keySet()) {
                Object nv = a.get(parentApi);
                Object ov = o.get(parentApi);
                if (nv == ov) continue;
                String aId = p2a.get(parentApi);
                if (!changes.containsKey(a.Id)) changes.put(a.Id, new Map<String, String>());
                changes.get(a.Id).put(aId, nv == null ? null : String.valueOf(nv));
                touchedIds.add(aId);
            }
        }
        if (changes.isEmpty()) return;

        Map<String, List<PC1_Answer__c>> existing = new Map<String, List<PC1_Answer__c>>();
        for (PC1_Answer__c r : [
            SELECT Id, Application__c, Field_Id__c FROM PC1_Answer__c
             WHERE Application__c IN :changes.keySet() AND Field_Id__c IN :touchedIds
        ]) {
            String k = r.Application__c + '|' + r.Field_Id__c;
            if (!existing.containsKey(k)) existing.put(k, new List<PC1_Answer__c>());
            existing.get(k).add(r);
        }
        List<PC1_Answer__c> ups = new List<PC1_Answer__c>();
        List<PC1_Answer__c> ins = new List<PC1_Answer__c>();
        List<PC1_Answer__c> dels = new List<PC1_Answer__c>();
        for (Id appId : changes.keySet()) {
            Map<String, String> m = changes.get(appId);
            for (String aId : m.keySet()) {
                String v = m.get(aId);
                List<PC1_Answer__c> rows = existing.get(appId + '|' + aId);
                if (String.isBlank(v)) {
                    if (rows != null) dels.addAll(rows);
                } else if (rows != null) {
                    for (PC1_Answer__c r : rows) ups.add(new PC1_Answer__c(Id = r.Id, Value__c = v, Source__c = 'human'));
                } else {
                    ins.add(new PC1_Answer__c(Application__c = appId, Field_Id__c = aId, Value__c = v, Source__c = 'human'));
                }
            }
        }
        syncingFromParent = true;
        try {
            if (!ups.isEmpty()) update ups;
            if (!ins.isEmpty()) insert ins;
            if (!dels.isEmpty()) delete dels;
        } finally {
            syncingFromParent = false;
        }
    }

    /**
     * Convenience overload for callers without trigger context — treats
     * every mapped field as "affected" so deletes propagate. Use the
     * two-arg version from PC1_AnswerTrigger.
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
        // Answers being written FROM the parent already match it.
        if (syncingFromParent) return;
        if (affectedFieldIds == null) affectedFieldIds = new Set<String>();

        // Preload existing Application values so we only DML when something
        // actually differs — cuts trigger recursion and audit noise.
        Map<Id, PC1_Application__c> current = new Map<Id, PC1_Application__c>([
            SELECT Id, First_Name__c, Middle_Name__c, Last_Name__c, Email__c, Phone__c,
                   Address_Line1__c, Address_Line2__c, City__c, County__c, Postcode__c, DOB__c,
                   Bank_Sort_Code__c, Bank_Account_Number__c, Bank_Account_Holder__c,
                   Bank_Roll_Number__c, Bank_Name__c, Bank_Verification_Status__c,
                   Bank_Verified_At__c, Stage__c, DD_Mandate_Id__c, DD_Mandate_Status__c
              FROM PC1_Application__c
             WHERE Id IN :appIds
        ]);

        // Read only the answer field ids we care about.
        Set<String> ids = new Set<String>(ANSWER_TO_PARENT.keySet());
        ids.add(DOB_ID + '_day');
        ids.add(DOB_ID + '_month');
        ids.add(DOB_ID + '_year');

        // Group answers by Application → fieldId → value. Order by
        // LastModifiedDate DESC and use `putIfAbsent`-style guard so that
        // when duplicate (App, Field_Id) rows exist (leftover from stress
        // tests, race conditions, etc.), the MOST RECENT one wins. Before
        // this ordering was undefined and a stale "TestFN" q3 row kept
        // reverting First_Name__c to TestFN on every trigger fire.
        Map<Id, Map<String, String>> answersByApp = new Map<Id, Map<String, String>>();
        for (Id id : appIds) answersByApp.put(id, new Map<String, String>());
        for (PC1_Answer__c a : [
            SELECT Application__c, Field_Id__c, Value__c
              FROM PC1_Answer__c
             WHERE Application__c IN :appIds
               AND Field_Id__c IN :ids
             ORDER BY LastModifiedDate DESC
        ]) {
            if (a.Application__c == null || String.isBlank(a.Field_Id__c)) continue;
            if (a.Value__c == null || a.Value__c == '') continue;
            Map<String, String> m = answersByApp.get(a.Application__c);
            if (!m.containsKey(a.Field_Id__c)) m.put(a.Field_Id__c, a.Value__c);
        }

        List<PC1_Application__c> toUpdate = new List<PC1_Application__c>();
        List<PC1_Stage_Log__c> bankResetLogs = new List<PC1_Stage_Log__c>();
        for (Id id : appIds) {
            PC1_Application__c existing = current.get(id);
            if (existing == null) continue;
            Map<String, String> ans = answersByApp.get(id);
            PC1_Application__c patch = new PC1_Application__c(Id = id);
            Boolean dirty = false;

            // 2026-08-01: Phone__c gets special handling because it's the ONE
            // parent field with two source answers (q9 landline + q9_mobile).
            // Old loop was order-dependent: deleting mobile after q9 was set
            // would silently wipe the landline via the "answer deleted" branch.
            // Fix — resolve Phone__c explicitly here (mobile wins if present,
            // else landline), then skip both keys in the generic loop.
            {
                String mob  = ans.get('q9_mobile');
                String land = ans.get('q9');
                String newPhone = !String.isBlank(mob) ? mob : (!String.isBlank(land) ? land : null);
                String oldPhone = existing.Phone__c;
                Boolean phoneAffected = affectedFieldIds.contains('q9') || affectedFieldIds.contains('q9_mobile');
                if (newPhone != null && newPhone != oldPhone) {
                    patch.Phone__c = newPhone;
                    dirty = true;
                } else if (newPhone == null && phoneAffected && oldPhone != null) {
                    patch.Phone__c = null;
                    dirty = true;
                }
            }

            // Bank digit-change detector — when q0_sp_sortcode or q0_sp_account
            // actually change (normalized digits differ), reset all downstream
            // verification trust in the same DML. Compare BEFORE mirroring so
            // we look at old parent vs new answer digits without any partial
            // update racing in.
            Boolean bankDigitsChanged = false;
            String newSortDigits = onlyDigits(ans.get('q0_sp_sortcode'));
            String newAcctDigits = onlyDigits(ans.get('q0_sp_account'));
            String oldSortDigits = onlyDigits(existing.Bank_Sort_Code__c);
            String oldAcctDigits = onlyDigits(existing.Bank_Account_Number__c);
            if (affectedFieldIds.contains('q0_sp_sortcode')
                && newSortDigits.length() > 0
                && newSortDigits != oldSortDigits) {
                bankDigitsChanged = true;
            }
            if (affectedFieldIds.contains('q0_sp_account')
                && newAcctDigits.length() > 0
                && newAcctDigits != oldAcctDigits) {
                bankDigitsChanged = true;
            }

            for (String aId : ANSWER_TO_PARENT.keySet()) {
                if (aId == 'q9' || aId == 'q9_mobile') continue; // handled above
                String parentApi = ANSWER_TO_PARENT.get(aId);
                String newVal = ans.get(aId);
                // Canonicalize sort code to XX-XX-XX BEFORE writing to the
                // parent. The intake form now accepts anything the user
                // types ("200000", "20 00 00", "20-00-00"); DWP + downstream
                // consumers all want the dashed shape.
                if (aId == 'q0_sp_sortcode' && !String.isBlank(newVal)) {
                    String d = onlyDigits(newVal);
                    if (d.length() == 6) {
                        newVal = d.substring(0,2) + '-' + d.substring(2,4) + '-' + d.substring(4,6);
                    }
                }
                Object oldRaw = existing.get(parentApi);
                String oldVal = oldRaw == null ? null : String.valueOf(oldRaw);
                if (newVal != null) {
                    if (newVal == oldVal) continue;
                    patch.put(parentApi, newVal);
                    dirty = true;
                } else if (affectedFieldIds.contains(aId) && oldVal != null && !REQUIRED_PARENTS.contains(parentApi)) {
                    // Answer for this mapped id was deleted (or updated to
                    // blank and then destroyed by the form's diff-flush) —
                    // clear the parent scalar so it doesn't linger with
                    // stale data no one can trace back. Skip required
                    // parents (First/Last Name) — nulling them would fail
                    // the whole DML with "Required fields are missing".
                    patch.put(parentApi, null);
                    dirty = true;
                }
            }

            // Bank digits changed → every downstream trust indicator is now
            // stale. Reset status back to Unverified and wipe verified-at
            // so agents see the requirement to re-verify. Log a stage-log
            // note so the audit trail explains why the badge went red.
            //
            // (2026-08-17) — verbal-confirm fields dropped; nothing to reset
            // there anymore.
            if (bankDigitsChanged) {
                patch.Bank_Verification_Status__c = 'Unverified';
                patch.Bank_Verified_At__c = null;
                dirty = true;
                // A live mandate is on the OLD account. Park it so nothing is
                // charged there (Node's charge-fee refuses non-active
                // mandates) and the DD card offers "Set up new Direct Debit"
                // once the new details are verified. Before 2026-10-02 the
                // old mandate stayed active and installments kept collecting
                // from the account the client had just replaced (audit).
                // The "Bank details changed" prefix is matched by the
                // GoCardless webhook so a late event for the old mandate
                // cannot flip it back to active.
                if (String.isNotBlank(existing.DD_Mandate_Id__c)
                        && !DEAD_MANDATE_STATUSES.contains(existing.DD_Mandate_Status__c)) {
                    patch.DD_Mandate_Status__c = 'cancelled';
                    patch.DD_Mandate_Failure_Reason__c = 'Bank details changed on ' + String.valueOf(Date.today())
                        + '. The old Direct Debit will not be charged; set up a new one for the new account.';
                }
                bankResetLogs.add(new PC1_Stage_Log__c(
                    Application__c = id,
                    From_Stage__c  = existing.Stage__c,
                    To_Stage__c    = existing.Stage__c,
                    Actor__c       = 'system',
                    Note__c        = 'Bank details edited — verification reset',
                    Changed_At__c  = Datetime.now(),
                    Changed_By__c  = UserInfo.getUserId()
                ));
            }

            // DOB triplet → Date. Sync when all three parts present + parse ok.
            String d = ans.get(DOB_ID + '_day');
            String m = ans.get(DOB_ID + '_month');
            String y = ans.get(DOB_ID + '_year');
            Boolean dobTouched = affectedFieldIds.contains(DOB_ID + '_day')
                || affectedFieldIds.contains(DOB_ID + '_month')
                || affectedFieldIds.contains(DOB_ID + '_year');
            if (!String.isBlank(d) && !String.isBlank(m) && !String.isBlank(y)) {
                try {
                    Date parsed = Date.newInstance(
                        Integer.valueOf(y),
                        Integer.valueOf(m),
                        Integer.valueOf(d)
                    );
                    if (parsed != existing.DOB__c) {
                        patch.DOB__c = parsed;
                        dirty = true;
                    }
                } catch (Exception e) {
                    // silent — partial/bad date; leave the parent field alone.
                }
            } else if (dobTouched && existing.DOB__c != null) {
                // At least one part was just deleted → DOB is incomplete
                // now, clear the parent so nothing downstream reads stale.
                patch.DOB__c = null;
                dirty = true;
            }

            if (dirty) toUpdate.add(patch);
        }

        if (!toUpdate.isEmpty()) {
            syncingFromAnswers = true;
            try { update toUpdate; } finally { syncingFromAnswers = false; }
        }
        if (!bankResetLogs.isEmpty()) insert bankResetLogs;
    }

    private static String onlyDigits(String s) {
        return s == null ? '' : s.replaceAll('\\D', '');
    }
}