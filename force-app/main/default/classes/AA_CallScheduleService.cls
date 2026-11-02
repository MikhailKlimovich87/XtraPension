/**
 * AA_CallScheduleService — @AuraEnabled surface for the aaCallSchedule LWC.
 *
 *   createSchedule(appId, when)          → new Pending row Id
 *   cancelSchedule(scheduleId, reason)   → marks Cancelled + timestamps
 *   getActivePending(appId)              → single Pending row (cacheable)
 *   getScheduleHistory(appId, limitRows) → all rows DESC by CreatedDate
 *
 * createSchedule also refuses Do Not Contact apps and stages the tick never
 * dials (audit F84), not only off-hours slots.
 *
 * Reads are cacheable=true; the LWCs refresh them with refreshApex. They
 * subscribe to AA_Call_Schedule__ChangeEvent, but the org has a single free
 * CDC slot and sf-src selects only the AA_Application__c member (wave 3), so
 * that channel is silent and the LWCs' 30 s poll is what refreshes them.
 * Uniqueness + Next_Call_At__c mirroring are enforced by
 * AA_CallScheduleTrigger; this class does not duplicate that work.
 *
 * UK call-hours gate (review 2026-09-11): createSchedule refuses slots
 * outside Mon–Fri 07:00–17:30 Europe/London (bank holidays excluded). The
 * Heroku scheduler-tick never dials outside that window, so before this
 * gate an evening or weekend slot could be BOOKED here, was never dialled,
 * aged past the reaper cutoff and charged the client a phantom
 * No_Answer_Streak__c miss (15 of those = 'unreachable' Needs Human). The
 * window and holiday list mirror isWithinUkBusinessHours / UK_BANK_HOLIDAYS
 * in src/lib/retry.js — keep the two in step.
 */
public with sharing class AA_CallScheduleService {

    // ── UK call hours ────────────────────────────────────────────────────

    /** 07:00 UK, inclusive. */
    @TestVisible private static final Integer OPEN_MINUTES  = 7 * 60;
    /** 17:30 UK, exclusive — a 17:30 slot is already outside (same bound as retry.js). */
    @TestVisible private static final Integer CLOSE_MINUTES = 17 * 60 + 30;
    /** gov.uk England-and-Wales bank holidays, yyyy-MM-dd. Twin of retry.js UK_BANK_HOLIDAYS. */
    @TestVisible private static final Set<String> UK_BANK_HOLIDAYS = new Set<String>{
        // 2026
        '2026-01-01', '2026-04-03', '2026-04-06', '2026-05-04', '2026-05-25',
        '2026-08-31', '2026-12-25', '2026-12-28',
        // 2027
        '2027-01-01', '2027-03-26', '2027-03-29', '2027-05-03', '2027-05-31',
        '2027-08-30', '2027-12-27', '2027-12-28',
        // 2028 (audit F96): derived from the statutory rules (gov.uk had not
        // published 2028 yet); re-check when it does. 1 Jan is a Saturday.
        '2028-01-03', '2028-04-14', '2028-04-17', '2028-05-01', '2028-05-29',
        '2028-08-28', '2028-12-25', '2028-12-26'
    };

    /**
     * Stages whose Pending row the Heroku tick will actually dial (its due
     * SOQL: Awaiting First Call / Partial Data), plus 'Call In Progress' so an
     * operator can book the follow-up while Mary is on the line (the post-call
     * lands the app on Partial Data and the tick then dials the slot).
     */
    @TestVisible private static final Set<String> BOOKABLE_STAGES = new Set<String>{
        'Awaiting First Call', 'Partial Data', 'Call In Progress'
    };

    /**
     * True when `dt` falls on a UK business day inside 07:00–17:30 London
     * wall-clock. Datetime.format with the zone id resolves BST/GMT, so the
     * verdict does not depend on the running user's timezone.
     */
    @TestVisible
    private static Boolean isWithinUkCallHours(Datetime dt) {
        if (AA_BusinessDayHelper.isWeekend(AA_UkTime.dateUk(dt))) return false;
        if (UK_BANK_HOLIDAYS.contains(dt.format('yyyy-MM-dd', 'Europe/London'))) return false;
        Integer mins = AA_UkTime.hourUk(dt) * 60 + Integer.valueOf(dt.format('m', 'Europe/London'));
        return mins >= OPEN_MINUTES && mins < CLOSE_MINUTES;
    }

    // ── WRITES ───────────────────────────────────────────────────────────

    @AuraEnabled
    public static Id createSchedule(Id applicationId, Datetime scheduledAt) {
        if (applicationId == null) throw new AuraHandledException('applicationId is required');
        if (scheduledAt == null)   throw new AuraHandledException('scheduledAt is required');
        if (!isWithinUkCallHours(scheduledAt)) {
            // setMessage: a bare AuraHandledException reads 'Script-thrown
            // exception' inside Apex tests; setting it makes the same text
            // reach both the LWC toast and the test assertion.
            String msg = 'Mary can only call Monday to Friday, 07:00-17:30 UK time (not on bank holidays). '
                + scheduledAt.format('EEE d MMM HH:mm', 'Europe/London')
                + ' UK is outside those hours - pick another slot.';
            AuraHandledException outsideHours = new AuraHandledException(msg);
            outsideHours.setMessage(msg);
            throw outsideHours;
        }
        // Audit F84: the hours gate alone booked slots Mary never dials. A
        // Do Not Contact app, or one outside the dialable stages, kept a
        // Pending row that fed the 07:00 "Mary will call today" reminder, was
        // never rung, and once its time passed its mirrored Next_Call_At__c
        // blocked every update to the Application (Next_Call_At_In_Future).
        List<AA_Application__c> apps = [
            SELECT Id, Stage__c, Do_Not_Contact__c FROM AA_Application__c
             WHERE Id = :applicationId LIMIT 1
        ];
        if (apps.isEmpty()) throwReadable('Application not found.');
        if (apps[0].Do_Not_Contact__c == true) {
            throwReadable('This client is marked Do Not Contact, so Mary cannot call them. Clear Do Not Contact first if it was set by mistake.');
        }
        if (!BOOKABLE_STAGES.contains(apps[0].Stage__c)) {
            throwReadable('Mary only calls applications at Awaiting First Call or Partial Data. This one is at "'
                + apps[0].Stage__c + '". Move the stage first if Mary should call.');
        }
        try {
            AA_Call_Schedule__c row = new AA_Call_Schedule__c(
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

    /** setMessage so the same text reaches the LWC toast and Apex tests. */
    private static void throwReadable(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        throw e;
    }

    @AuraEnabled
    public static void cancelSchedule(Id scheduleId, String reason) {
        if (scheduleId == null) throw new AuraHandledException('scheduleId is required');
        List<AA_Call_Schedule__c> rows = [
            SELECT Id, Status__c FROM AA_Call_Schedule__c
             WHERE Id = :scheduleId LIMIT 1
        ];
        if (rows.isEmpty()) throw new AuraHandledException('Schedule not found');
        if (!'Pending'.equals(rows[0].Status__c)) {
            throw new AuraHandledException('Only Pending schedules can be cancelled (this one is ' + rows[0].Status__c + ').');
        }
        try {
            update new AA_Call_Schedule__c(
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
    public static AA_Call_Schedule__c getActivePending(Id applicationId) {
        if (applicationId == null) return null;
        List<AA_Call_Schedule__c> rows = [
            SELECT Id, Name, Scheduled_At__c, Status__c,
                   Cancelled_At__c, Cancel_Reason__c, Fired_At__c,
                   Call_Log__c, Call_Log__r.Name, Notes__c,
                   CreatedById, CreatedBy.Name, CreatedDate, LastModifiedDate
              FROM AA_Call_Schedule__c
             WHERE Application__c = :applicationId
               AND Status__c = 'Pending'
             ORDER BY Scheduled_At__c ASC
             LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    @AuraEnabled(cacheable=true)
    public static List<AA_Call_Schedule__c> getScheduleHistory(Id applicationId, Integer limitRows) {
        if (applicationId == null) return new List<AA_Call_Schedule__c>();
        Integer lim = (limitRows == null || limitRows <= 0) ? 200 : Math.min(limitRows, 1000);
        return [
            SELECT Id, Name, Scheduled_At__c, Status__c,
                   Cancelled_At__c, Cancel_Reason__c, Fired_At__c,
                   Call_Log__c, Call_Log__r.Name, Notes__c,
                   CreatedById, CreatedBy.Name, CreatedDate, LastModifiedDate
              FROM AA_Call_Schedule__c
             WHERE Application__c = :applicationId
             ORDER BY CreatedDate DESC
             LIMIT :lim
        ];
    }
}