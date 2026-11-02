/**
 * AA_ProgressCalculator — recomputes Progress_Filled__c / Progress_Total__c
 * (and the new Progress_Missing_Sections__c JSON) on AA_Application__c from
 * its child AA_Answer__c rows.
 *
 * Phase 2 rewrite: hardcoded TOTAL=67 is gone. All the real work lives in
 * AA_FlowEngine — this class is now a thin trigger-facing shim that keeps
 * the existing entry-point signature (recompute(Set<Id>)) so AA_AnswerTrigger
 * needs no change.
 *
 * Filled = fields whose answer is non-empty for the branch this application
 *          is actually walking, including Source__c='default' policy pre-fills
 *          (per Phase 1 Q2). Declaration fields (decl/declname/decldate) never
 *          count (per Phase 1 Q3).
 * Total  = the number of fields the walker will ask on this branch — 48 on the
 *          happy single-adult path, 30-something on early stages, more when a
 *          partner or shares expand the flow.
 */
public with sharing class AA_ProgressCalculator {

    /**
     * Recompute progress for a set of Application Ids. Bulk-safe.
     *
     * Returns appId -> error for Applications whose declaration UNSIGN could
     * not be written (see AA_FlowEngine.recomputeAndUpdate). AA_AnswerTrigger
     * fails the answer rows of those apps so Declaration_Complete__c never
     * stays true behind an unticked declaration.
     */
    public static Map<Id, String> recompute(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return new Map<Id, String>();
        return AA_FlowEngine.recomputeAndUpdate(appIds);
    }

    /**
     * Test seam: when true, stampAnswerKeys leaves Answer_Key__c blank, which
     * is how every row written before the key existed looks (including the 12
     * legacy duplicate pairs). Lets tests build those legacy duplicates, which
     * the unique key otherwise makes impossible. Never set outside tests.
     */
    @TestVisible private static Boolean skipAnswerKeyForTest = false;

    /**
     * Before insert/update on AA_Answer__c: Answer_Key__c = Application Id
     * (18 chars) + '|' + Field_Id__c (audit 2026-10-02 F39). The field is
     * unique, so the database refuses a second row for the same
     * (Application, Field_Id) pair, and writers can upsert on the key. Always
     * recomputed, never trusted from the writer: a reparented row or a renamed
     * Field_Id__c moves its key with it. 18 + 1 + 80 (Field_Id__c) fits the
     * 120-char field.
     */
    public static void stampAnswerKeys(List<AA_Answer__c> rows) {
        if (rows == null) return;
        if (Test.isRunningTest() && skipAnswerKeyForTest) return;
        for (AA_Answer__c a : rows) {
            a.Answer_Key__c = (a.Application__c == null || String.isBlank(a.Field_Id__c))
                ? null
                : String.valueOf(a.Application__c) + '|' + a.Field_Id__c;
        }
    }

    // ── Declaration voids on change (owner decision, 2026-10-02) ──────────

    /**
     * Every Field_Id__c that makes up the declaration. 'decldate' is the bare
     * id Mary's DECLARATION_FIELDS uses; the form and the record page store
     * the three parts. None of them voids the declaration when edited.
     */
    @TestVisible
    private static final Set<String> DECLARATION_FIELD_IDS = new Set<String>{
        'decl', 'declname', 'decldate', 'decldate_day', 'decldate_month', 'decldate_year'
    };

    /**
     * Who counts as "editing the answers": the client on the form, Mary on a
     * call, an operator on the record page. 'default' (policy pre-fills,
     * including Mary's seedPolicyDefaults backstop) and 'intake' (seeded from
     * the sale) are system writes and never void a signature.
     */
    @TestVisible
    private static final Set<String> EDITOR_SOURCES = new Set<String>{ 'mary', 'human', 'form' };

    /**
     * Stages where the claim has already been sent to DWP, and everything
     * after. Wave-4 review: the void had no
     * stage scope, so an operator correcting an answer on an Awarded app, or
     * a Mary save on an inbound call, deleted the decl/declname/decldate rows,
     * which are the only record of the signature DWP received. The owner's
     * reason for the void is "re-sign before Fill on DWP"; from Submitted on
     * there is no fill left to guard, so the declaration is kept.
     * Filling and Ready for Submit still void on purpose: nothing has reached
     * DWP yet, and a cleared declaration tells ops the filled DWP form no
     * longer matches the answers.
     * NOT 'Awaiting Posted Pack Return' (integrator 2026-10-02): that stage is
     * PRE-submission (the paper AA1A was posted to the CLIENT and we wait for
     * the signed pack; signed pack returned -> Submitted, aa-workflow-manual
     * stage 22). Nothing has reached DWP, and ops can move the case back to
     * Filling when the client cannot manage the paper route, so an edit there
     * must still clear the declaration or Fill on DWP would run under a
     * signature that does not cover the changed answer.
     * Keep in step with mary.js KEEP_STAGE_ON_FLAG (the "already sent to DWP"
     * set, minus 'Needs Human'). form.js LOCKED_STAGES is a different list on
     * purpose: it also holds pre-filed stages (Ready for Review, Reviewed,
     * Filling, Ready for Submit) that must still void.
     */
    @TestVisible
    private static final Set<String> FILED_STAGES = new Set<String>{
        'Submitted', 'Awaiting DWP Decision', 'Awarded', 'Fee Charged',
        'Closed - Paid', 'Closed - Refused', 'Closed - Fee Failed', 'DD Chargeback',
        'Mandatory Reconsideration Requested',
        'Appeal Lodged', 'Change of Circumstances Review'
    };

    /** Recursion guard: the declaration rows this deletes re-fire AA_AnswerTrigger. */
    private static Boolean voiding = false;

    /**
     * Owner decision (Fernando, 2026-10-02): DECLARATION VOIDS ON CHANGE.
     * When a client, Mary or an operator changes an answer after the
     * declaration was signed (Declaration_Complete__c = true), the signature
     * no longer covers what would be sent to DWP. Delete the declaration rows
     * so Declaration_Complete__c drops to false (it is the only gate before
     * Fill on DWP) and the client has to sign again.
     *
     * What does NOT void it: an application already in a FILED_STAGES stage
     * (the rows are the record of what DWP received), rows written by a system source (default /
     * intake), a save that leaves the value as it was (whitespace aside),
     * edits to the declaration fields themselves, and the form's derived
     * '<loop>-rows' snapshot (rebuilt from the '__n' entries on every load;
     * a real change to an entry is caught on the entry itself).
     *
     * Deletes count too: the form clears an answer by deleting its row. A
     * delete only counts when the row held a value written by an editor
     * source and no other row for the same field still holds that value (a
     * legacy duplicate being tidied is not a change).
     *
     * Rows are deleted rather than blanked because "no row" is how the form,
     * Mary and the flow walk already read "not answered".
     *
     * Returns appId -> reason for apps whose declaration could NOT be cleared.
     * AA_AnswerTrigger fails the triggering rows of those apps (fail closed:
     * an edit must never land while the old signature stays valid).
     *
     * @param changedRows Trigger.new on insert / update / undelete, else null
     * @param oldMap      Trigger.oldMap on update, else null
     * @param deletedRows Trigger.old on delete, else null
     */
    public static Map<Id, String> voidDeclarationOnChange(
        List<AA_Answer__c> changedRows, Map<Id, AA_Answer__c> oldMap, List<AA_Answer__c> deletedRows
    ) {
        Map<Id, String> notCleared = new Map<Id, String>();
        if (voiding) return notCleared;

        // appId -> the first changed field id, for the audit note.
        Map<Id, String> changedFieldByApp = new Map<Id, String>();
        Map<Id, String> changedSourceByApp = new Map<Id, String>();

        if (changedRows != null) {
            for (AA_Answer__c a : changedRows) {
                if (a.Application__c == null || !countsAsEdit(a.Field_Id__c, a.Source__c)) continue;
                AA_Answer__c prev = oldMap == null ? null : oldMap.get(a.Id);
                Boolean changed;
                if (prev == null) {
                    changed = !isBlank(a.Value__c); // insert / undelete
                } else {
                    // equals(), not !=: Apex string != ignores case, and a
                    // case-only fix (a name) still changes what DWP receives.
                    changed = !norm(prev.Value__c).equals(norm(a.Value__c))
                        || prev.Field_Id__c != a.Field_Id__c
                        || prev.Application__c != a.Application__c;
                }
                if (changed && !changedFieldByApp.containsKey(a.Application__c)) {
                    changedFieldByApp.put(a.Application__c, a.Field_Id__c);
                    changedSourceByApp.put(a.Application__c, a.Source__c);
                }
            }
        }

        if (deletedRows != null) {
            List<AA_Answer__c> candidates = new List<AA_Answer__c>();
            Set<Id> candApps = new Set<Id>();
            Set<String> candFields = new Set<String>();
            for (AA_Answer__c a : deletedRows) {
                if (a.Application__c == null || isBlank(a.Value__c)) continue;
                if (!countsAsEdit(a.Field_Id__c, a.Source__c)) continue;
                candidates.add(a);
                candApps.add(a.Application__c);
                candFields.add(a.Field_Id__c);
            }
            if (!candidates.isEmpty()) {
                // Values still held by surviving rows (legacy duplicates).
                Set<String> surviving = new Set<String>();
                for (AA_Answer__c s : [
                    SELECT Application__c, Field_Id__c, Value__c FROM AA_Answer__c
                     WHERE Application__c IN :candApps AND Field_Id__c IN :candFields
                ]) {
                    surviving.add(s.Application__c + '|' + s.Field_Id__c + '|' + norm(s.Value__c));
                }
                for (AA_Answer__c a : candidates) {
                    if (surviving.contains(a.Application__c + '|' + a.Field_Id__c + '|' + norm(a.Value__c))) continue;
                    if (!changedFieldByApp.containsKey(a.Application__c)) {
                        changedFieldByApp.put(a.Application__c, a.Field_Id__c);
                        changedSourceByApp.put(a.Application__c, a.Source__c);
                    }
                }
            }
        }
        if (changedFieldByApp.isEmpty()) return notCleared;

        // Only apps whose declaration is signed right now and whose claim has
        // not been filed yet (see FILED_STAGES).
        Set<Id> signed = new Set<Id>();
        for (AA_Application__c app : [
            SELECT Id, Stage__c FROM AA_Application__c
             WHERE Id IN :changedFieldByApp.keySet() AND Declaration_Complete__c = true
        ]) {
            if (FILED_STAGES.contains(app.Stage__c)) continue;
            signed.add(app.Id);
        }
        if (signed.isEmpty()) return notCleared;

        voiding = true;
        try {
            notCleared = new DeclarationVoider().clear(signed, changedFieldByApp, changedSourceByApp);
        } finally {
            voiding = false;
        }
        return notCleared;
    }

    private static Boolean countsAsEdit(String fieldId, String source) {
        if (String.isBlank(fieldId)) return false;
        if (DECLARATION_FIELD_IDS.contains(fieldId)) return false;
        if (fieldId.endsWith('-rows')) return false;
        return source != null && EDITOR_SOURCES.contains(source);
    }

    private static Boolean isBlank(String v) { return String.isBlank(v); }

    /** Whitespace-only differences are not a change; null and '' are the same. */
    private static String norm(String v) { return v == null ? '' : v.trim(); }

    /**
     * without sharing on purpose: clearing the signature is an integrity side
     * effect of an edit the user was already allowed to make. A val agent who
     * can edit an answer must not have that edit refused only because the
     * running user's sharing does not cover deleting the declaration rows.
     */
    private without sharing class DeclarationVoider {
        Map<Id, String> clear(Set<Id> appIds, Map<Id, String> fieldByApp, Map<Id, String> sourceByApp) {
            Map<Id, String> notCleared = new Map<Id, String>();
            List<AA_Answer__c> declRows = [
                SELECT Id, Application__c FROM AA_Answer__c
                 WHERE Application__c IN :appIds AND Field_Id__c IN :DECLARATION_FIELD_IDS
            ];
            if (!declRows.isEmpty()) {
                // Partial delete: one app that cannot be cleared must not drag
                // down the others. Its triggering rows are failed instead.
                Database.DeleteResult[] res = Database.delete(declRows, false);
                for (Integer i = 0; i < res.size(); i++) {
                    if (res[i].isSuccess()) continue;
                    notCleared.put(declRows[i].Application__c, res[i].getErrors()[0].getMessage());
                }
            }

            // Leave a line in Notes__c so ops can see why the declaration is
            // pending again. Best effort: a note that cannot be written never
            // undoes the clear.
            List<AA_Application__c> notes = new List<AA_Application__c>();
            String stamp = Datetime.now().format('d MMM yyyy HH:mm', 'Europe/London');
            for (AA_Application__c app : [SELECT Id, Notes__c FROM AA_Application__c WHERE Id IN :appIds]) {
                if (notCleared.containsKey(app.Id)) continue;
                String line = '[' + stamp + ' UK] Declaration cleared: the answer "' + fieldByApp.get(app.Id)
                    + '" was changed (by ' + sourceByApp.get(app.Id) + ') after the declaration was signed. '
                    + 'The declaration must be signed again before Fill on DWP.';
                String merged = String.isBlank(app.Notes__c) ? line : app.Notes__c + '\n\n' + line;
                notes.add(new AA_Application__c(Id = app.Id, Notes__c = merged.right(32768)));
            }
            if (!notes.isEmpty()) {
                Database.SaveResult[] saved = Database.update(notes, false);
                for (Integer i = 0; i < saved.size(); i++) {
                    if (saved[i].isSuccess()) continue;
                    System.debug(LoggingLevel.ERROR, 'AA_ProgressCalculator: declaration-void note not written for '
                        + notes[i].Id + ': ' + saved[i].getErrors()[0].getMessage());
                }
            }
            return notCleared;
        }
    }
}