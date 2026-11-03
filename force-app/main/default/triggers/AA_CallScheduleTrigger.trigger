/**
 * AA_CallScheduleTrigger — two responsibilities:
 *   1. before insert / before update: enforce "only one Pending row per
 *      Application". Validation rules can't count sibling rows, so this lives
 *      in Apex (checks Trigger.new for same-batch collisions AND the DB for
 *      other rows already Pending on the same Application).
 *   2. after insert / after update / after delete: mirror the current Pending
 *      row's Scheduled_At__c into AA_Application__c.Next_Call_At__c (or NULL
 *      if there is none). Preserves backwards-compat with the Heroku scheduler
 *      which polls that field every minute.
 *
 * Logic lives in AA_CallScheduleTriggerHelper so it stays unit-testable.
 */
trigger AA_CallScheduleTrigger on AA_Call_Schedule__c (
    before insert, before update,
    after insert, after update, after delete
) {
    if (Trigger.isBefore) {
        AA_CallScheduleTriggerHelper.enforceOnePendingPerApp(Trigger.new, Trigger.oldMap);
    } else {
        // Collect every Application whose child rows changed so we can
        // recompute Next_Call_At__c once per parent.
        Set<Id> touchedApps = new Set<Id>();
        List<AA_Call_Schedule__c> rows =
            Trigger.isDelete ? (List<AA_Call_Schedule__c>) Trigger.old : Trigger.new;
        for (AA_Call_Schedule__c s : rows) {
            if (s.Application__c != null) touchedApps.add(s.Application__c);
        }
        if (!touchedApps.isEmpty()) {
            AA_CallScheduleTriggerHelper.syncNextCallAt(touchedApps);
        }
    }
}