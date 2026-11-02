/**
 * PC1_CallScheduleService — @AuraEnabled surface for the pc1CallSchedule LWC.
 *
 *   createSchedule(appId, when)          → new Pending row Id
 *   cancelSchedule(scheduleId, reason)   → marks Cancelled + timestamps
 *   getActivePending(appId)              → single Pending row (cacheable)
 *   getScheduleHistory(appId, limitRows) → all rows DESC by CreatedDate
 *
 * Reads are cacheable=true because the LWC subscribes to CDC on the
 * PC1_Call_Schedule__ChangeEvent channel and calls refreshApex on any event
 * — so wire adapters + live push give us both instant paint and live updates.
 * Uniqueness + Next_Call_At__c mirroring are enforced by
 * PC1_CallScheduleTrigger; this class does not duplicate that work.
 */
public with sharing class PC1_CallScheduleService {

    // ── WRITES ───────────────────────────────────────────────────────────

    @AuraEnabled
    public static Id createSchedule(Id applicationId, Datetime scheduledAt) {
        if (applicationId == null) throw new AuraHandledException('applicationId is required');
        if (scheduledAt == null)   throw new AuraHandledException('scheduledAt is required');
        try {
            PC1_Call_Schedule__c row = new PC1_Call_Schedule__c(
                Application__c   = applicationId,
                Scheduled_At__c  = scheduledAt,
                Status__c        = 'Pending'
            );
            insert row;
            return row.Id;
        } catch (DmlException e) {
            // Surface the SF-facing error message (validation rule or trigger
            // addError) — AuraHandledException swallows it otherwise.
            throw new AuraHandledException(e.getDmlMessage(0) != null
                ? e.getDmlMessage(0)
                : e.getMessage());
        }
    }

    @AuraEnabled
    public static void cancelSchedule(Id scheduleId, String reason) {
        if (scheduleId == null) throw new AuraHandledException('scheduleId is required');
        List<PC1_Call_Schedule__c> rows = [
            SELECT Id, Status__c FROM PC1_Call_Schedule__c
             WHERE Id = :scheduleId LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Schedule not found');
        if (!'Pending'.equals(rows[0].Status__c)) {
            throw new AuraHandledException('Only Pending schedules can be cancelled (this one is ' + rows[0].Status__c + ').');
        }
        try {
            update new PC1_Call_Schedule__c(
                Id               = scheduleId,
                Status__c        = 'Cancelled',
                Cancelled_At__c  = Datetime.now(),
                Cancel_Reason__c = String.isBlank(reason) ? null : reason.left(255)
            );
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0) != null
                ? e.getDmlMessage(0)
                : e.getMessage());
        }
    }

    // ── READS ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static PC1_Call_Schedule__c getActivePending(Id applicationId) {
        if (applicationId == null) return null;
        List<PC1_Call_Schedule__c> rows = [
            SELECT Id, Name, Scheduled_At__c, Status__c,
                   Cancelled_At__c, Cancel_Reason__c, Fired_At__c,
                   Call_Log__c, Call_Log__r.Name, Notes__c,
                   CreatedById, CreatedBy.Name, CreatedDate, LastModifiedDate
              FROM PC1_Call_Schedule__c
             WHERE Application__c = :applicationId
               AND Status__c = 'Pending'
             ORDER BY Scheduled_At__c ASC
             LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<PC1_Call_Schedule__c> getScheduleHistory(Id applicationId, Integer limitRows) {
        if (applicationId == null) return new List<PC1_Call_Schedule__c>();
        Integer lim = (limitRows == null || limitRows <= 0) ? 200 : Math.min(limitRows, 1000);
        return [
            SELECT Id, Name, Scheduled_At__c, Status__c,
                   Cancelled_At__c, Cancel_Reason__c, Fired_At__c,
                   Call_Log__c, Call_Log__r.Name, Notes__c,
                   CreatedById, CreatedBy.Name, CreatedDate, LastModifiedDate
              FROM PC1_Call_Schedule__c
             WHERE Application__c = :applicationId
             ORDER BY CreatedDate DESC
             LIMIT :lim
        ];
    }
}