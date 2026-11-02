/**
 * AA_AnswerTrigger — keeps Progress_Filled__c on the parent Application in
 * sync whenever a real (mary/human) answer is inserted, updated, or deleted.
 *
 * Before insert/update: stamps Answer_Key__c = Application Id + '|' +
 * Field_Id__c (audit 2026-10-02 F39). Answer_Key__c is unique, so the
 * database itself now refuses a second row for the same (Application,
 * Field_Id) pair, and writers can upsert on it instead of query-then-insert.
 *
 * After DML: clear a signed declaration when an editor (client / Mary /
 * operator) changed an answer (AA_ProgressCalculator.voidDeclarationOnChange,
 * owner decision 2026-10-02), then recompute progress / declaration so the
 * SOQL count reflects committed state.
 */
trigger AA_AnswerTrigger on AA_Answer__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        AA_ProgressCalculator.stampAnswerKeys(Trigger.new);
        return;
    }

    Set<Id> appIds = new Set<Id>();
    List<AA_Answer__c> src = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (AA_Answer__c a : src) {
        if (a.Application__c != null) appIds.add(a.Application__c);
    }
    if (Trigger.isUpdate) {
        // Source__c or Application__c may have changed — recompute the previous parent too.
        for (AA_Answer__c a : Trigger.old) {
            if (a.Application__c != null) appIds.add(a.Application__c);
        }
    }
    // Owner decision 2026-10-02: an answer changed by the client, Mary or an
    // operator after the declaration was signed clears the declaration, so
    // the client signs again before Fill on DWP. Runs BEFORE the recompute so
    // the recompute below already sees the declaration rows gone. Returns the
    // apps whose declaration could not be cleared.
    Map<Id, String> voidLost = AA_ProgressCalculator.voidDeclarationOnChange(
        Trigger.isDelete ? null : Trigger.new,
        Trigger.isUpdate ? Trigger.oldMap : null,
        Trigger.isDelete ? Trigger.old : null
    );
    Map<Id, String> unsignLost = AA_ProgressCalculator.recompute(appIds);
    // Fail closed on the declaration (audit 2026-10-02, wave-2 review of
    // F37/F83). The parent update is partial (allOrNone=false) so a failing
    // Application validation rule no longer loses the client's answer, but
    // if that failed update was UNSIGNING the declaration, keeping the answer
    // would leave Declaration_Complete__c = true (the only DWP fill gate)
    // behind an unticked box. Fail those answer rows instead, as the old
    // all-or-nothing update did, so the row and the flag stay consistent.
    // Same for an edit whose declaration void did not land: the edit must
    // not be saved under the old signature.
    Map<Id, String> blocked = new Map<Id, String>(unsignLost);
    for (Id voidApp : voidLost.keySet()) {
        if (!blocked.containsKey(voidApp)) blocked.put(voidApp, voidLost.get(voidApp));
    }
    if (!blocked.isEmpty()) {
        for (Integer i = 0; i < src.size(); i++) {
            Id appId = src[i].Application__c;
            Id oldAppId = Trigger.isUpdate ? Trigger.old[i].Application__c : null;
            String reason = appId != null ? blocked.get(appId) : null;
            if (reason == null && oldAppId != null) reason = blocked.get(oldAppId);
            if (reason == null) continue;
            src[i].addError('This change was not saved, because the declaration on this application '
                + 'could not be updated (' + reason + '). Please try again in a few minutes.');
        }
    }
    // Mirror form/mary answers into scalar Application fields so the
    // header/highlights/Details tab always show live data. Pass the
    // affected fieldIds so deletes null out the parent scalar (a form
    // answer removed → parent field cleared), while leaving parents
    // untouched for fieldIds that weren't part of this DML (operator
    // edits via the Details pencil are preserved).
    Set<String> affectedFieldIds = new Set<String>();
    if (Trigger.new != null) {
        for (AA_Answer__c a : Trigger.new) {
            if (a.Field_Id__c != null) affectedFieldIds.add(a.Field_Id__c);
        }
    }
    if (Trigger.old != null) {
        for (AA_Answer__c a : Trigger.old) {
            if (a.Field_Id__c != null) affectedFieldIds.add(a.Field_Id__c);
        }
    }
    AA_ApplicationFieldSync.syncFromAnswers(appIds, affectedFieldIds);
}