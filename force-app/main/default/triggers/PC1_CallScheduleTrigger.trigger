/**
 * PC1_CallScheduleTrigger — two responsibilities:
 *   1. before insert / before update: enforce "only one Pending row per
 *      Application". Validation rules can't count sibling rows, so this lives
 *      in Apex (checks Trigger.new for same-batch collisions AND the DB for
 *      other rows already Pending on the same Application).
 *   2. after insert / after update / after delete: mirror the current Pending
 *      row's Scheduled_At__c into PC1_Application__c.Next_Call_At__c (or NULL
 *      if there is none). Preserves backwards-compat with the Heroku scheduler
 *      which polls that field every minute.
 *
 * Logic lives in PC1_CallScheduleTriggerHelper so it stays unit-testable.
 */
trigger PC1_CallScheduleTrigger on PC1_Call_Schedule__c (
    before insert, before update,
    after insert, after update, after delete
) {
    if (Trigger.isBefore) {
        PC1_CallScheduleTriggerHelper.enforceOnePendingPerApp(Trigger.new, Trigger.oldMap);
    } else {
        // Collect every Application whose child rows changed so we can
        // recompute Next_Call_At__c once per parent.
        Set<Id> touchedApps = new Set<Id>();
        List<PC1_Call_Schedule__c> rows =
            Trigger.isDelete ? (List<PC1_Call_Schedule__c>) Trigger.old : Trigger.new;
        for (PC1_Call_Schedule__c s : rows) {
            if (s.Application__c != null) touchedApps.add(s.Application__c);
        }
        if (!touchedApps.isEmpty()) {
            PC1_CallScheduleTriggerHelper.syncNextCallAt(touchedApps);
        }
    }
}