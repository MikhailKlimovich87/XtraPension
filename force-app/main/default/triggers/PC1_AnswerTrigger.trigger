/**
 * PC1_AnswerTrigger — keeps Progress_Filled__c on the parent Application in
 * sync whenever a real (mary/human) answer is inserted, updated, or deleted.
 *
 * Fires after DML so the SOQL count reflects committed state.
 */
trigger PC1_AnswerTrigger on PC1_Answer__c (after insert, after update, after delete, after undelete) {
    Set<Id> appIds = new Set<Id>();
    List<PC1_Answer__c> src = Trigger.isDelete ? Trigger.old : Trigger.new;
    for (PC1_Answer__c a : src) {
        if (a.Application__c != null) appIds.add(a.Application__c);
    }
    if (Trigger.isUpdate) {
        // Source__c or Application__c may have changed — recompute the previous parent too.
        for (PC1_Answer__c a : Trigger.old) {
            if (a.Application__c != null) appIds.add(a.Application__c);
        }
    }
    PC1_ProgressCalculator.recompute(appIds);
    // Mirror form/mary answers into scalar Application fields so the
    // header/highlights/Details tab always show live data. Pass the
    // affected fieldIds so deletes null out the parent scalar (a form
    // answer removed → parent field cleared), while leaving parents
    // untouched for fieldIds that weren't part of this DML (operator
    // edits via the Details pencil are preserved).
    Set<String> affectedFieldIds = new Set<String>();
    if (Trigger.new != null) {
        for (PC1_Answer__c a : Trigger.new) {
            if (a.Field_Id__c != null) affectedFieldIds.add(a.Field_Id__c);
        }
    }
    if (Trigger.old != null) {
        for (PC1_Answer__c a : Trigger.old) {
            if (a.Field_Id__c != null) affectedFieldIds.add(a.Field_Id__c);
        }
    }
    PC1_ApplicationFieldSync.syncFromAnswers(appIds, affectedFieldIds);
}