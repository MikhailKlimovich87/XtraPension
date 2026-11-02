/**
 * AA_CallScheduleTriggerHelper — logic for AA_CallScheduleTrigger.
 *
 *   enforceOnePendingPerApp(newRows, oldMap)
 *     For every row moving TO Pending (insert-as-Pending, or update-into-
 *     Pending), reject if another Pending row already exists on the same
 *     Application. Same-transaction collisions inside Trigger.new are also
 *     caught so a bulk insert with two Pending rows for the same App fails.
 *
 *   syncNextCallAt(applicationIds)
 *     For each Application, find its single Pending Call_Schedule (if any) and
 *     update AA_Application__c.Next_Call_At__c to that Scheduled_At__c value
 *     (or NULL if none). Keeps the legacy Heroku scheduler working while the
 *     new schedule table takes over as source of truth.
 */
public with sharing class AA_CallScheduleTriggerHelper {

    private static final String PENDING = 'Pending';

    // ── Uniqueness guard ─────────────────────────────────────────────────

    public static void enforceOnePendingPerApp(
        List<AA_Call_Schedule__c> newRows,
        Map<Id, AA_Call_Schedule__c> oldMap
    ) {
        if (newRows == null || newRows.isEmpty()) return;

        // (1) Which rows in this batch are landing as Pending?
        List<AA_Call_Schedule__c> movingToPending = new List<AA_Call_Schedule__c>();
        Set<Id> appsToCheck = new Set<Id>();
        for (AA_Call_Schedule__c s : newRows) {
            if (PENDING.equals(s.Status__c) && s.Application__c != null) {
                Boolean wasPending = false;
                if (oldMap != null && oldMap.containsKey(s.Id)) {
                    wasPending = PENDING.equals(oldMap.get(s.Id).Status__c);
                }
                // Insert-as-Pending OR update transitioning into Pending — both need the check.
                if (!wasPending) {
                    movingToPending.add(s);
                    appsToCheck.add(s.Application__c);
                }
            }
        }
        if (movingToPending.isEmpty()) return;

        // (2) Same-transaction collisions: two Pending rows for the same App
        //     inside Trigger.new. Only the second one gets flagged so the first
        //     write still wins deterministically.
        Map<Id, Id> firstPendingByApp = new Map<Id, Id>();
        for (AA_Call_Schedule__c s : movingToPending) {
            if (!firstPendingByApp.containsKey(s.Application__c)) {
                firstPendingByApp.put(s.Application__c, s.Id);
            } else {
                s.addError('This application already has a pending schedule. Cancel it first.');
            }
        }

        // (3) DB collisions: someone else already has a Pending row on the App.
        //     Excludes ids in this batch so an in-place update stays legal.
        Set<Id> batchIds = new Set<Id>();
        for (AA_Call_Schedule__c s : newRows) if (s.Id != null) batchIds.add(s.Id);

        Map<Id, Id> existingPendingByApp = new Map<Id, Id>();
        for (AA_Call_Schedule__c s : [
            SELECT Id, Application__c
              FROM AA_Call_Schedule__c
             WHERE Application__c IN :appsToCheck
               AND Status__c = :PENDING
               AND Id NOT IN :batchIds
        ]) {
            existingPendingByApp.put(s.Application__c, s.Id);
        }
        for (AA_Call_Schedule__c s : movingToPending) {
            if (existingPendingByApp.containsKey(s.Application__c) && !s.hasErrors()) {
                s.addError('This application already has a pending schedule. Cancel it first.');
            }
        }
    }

    // ── Mirror Pending → Application.Next_Call_At__c ─────────────────────

    public static void syncNextCallAt(Set<Id> applicationIds) {
        if (applicationIds == null || applicationIds.isEmpty()) return;

        // One SOQL, all Pending schedules for the touched Applications.
        Map<Id, Datetime> nextByApp = new Map<Id, Datetime>();
        for (AA_Call_Schedule__c s : [
            SELECT Id, Application__c, Scheduled_At__c
              FROM AA_Call_Schedule__c
             WHERE Application__c IN :applicationIds
               AND Status__c = :PENDING
             ORDER BY Scheduled_At__c ASC
        ]) {
            // First (earliest) Pending wins — the uniqueness guard normally
            // caps this at 1 per App, but ORDER BY is a safety net if a legacy
            // row slipped through before the trigger was in place.
            if (!nextByApp.containsKey(s.Application__c)) {
                nextByApp.put(s.Application__c, s.Scheduled_At__c);
            }
        }

        // Read current Application values so we only write when the mirror
        // actually needs to move — avoids unnecessary trigger re-entry on
        // AA_ApplicationTrigger.
        List<AA_Application__c> toUpdate = new List<AA_Application__c>();
        for (AA_Application__c a : [
            SELECT Id, Next_Call_At__c
              FROM AA_Application__c
             WHERE Id IN :applicationIds
        ]) {
            Datetime desired = nextByApp.get(a.Id); // null if no Pending row
            if (a.Next_Call_At__c != desired) {
                toUpdate.add(new AA_Application__c(Id = a.Id, Next_Call_At__c = desired));
            }
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}