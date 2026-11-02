/**
 * AA_StageTransitionHelper — stamps Stage_Changed_At and writes a
 * AA_Stage_Log__c audit row every time Stage__c changes.
 *
 * State-machine guardrail removed 2026-07-30 per Fernando: he needs to be
 * able to move Applications through any stage he wants without being
 * blocked by a validation rule. The audit trail below still records every
 * transition so we can reconstruct history + spot unusual patterns; only
 * the "Illegal Stage transition" hard block is gone.
 */
public with sharing class AA_StageTransitionHelper {

    /**
     * Optional per-transition context, keyed by Application Id, set by a caller
     * (e.g. AA_RecordPageService.changeStage) right before it updates Stage__c.
     * The trigger is the SINGLE writer of AA_Stage_Log__c (audit #55) — callers
     * used to update Stage__c AND insert their own log, producing two rows per
     * change. Now they just stash the note here and let the trigger log once.
     * Cleared after each fire so it can't bleed into a later transaction.
     */
    public static Map<Id, String> noteByApp = new Map<Id, String>();

    public static void handleTransitions(List<AA_Application__c> newList, Map<Id, AA_Application__c> oldMap) {
        List<AA_Stage_Log__c> logs = new List<AA_Stage_Log__c>();
        Set<Id> submittedIds = new Set<Id>();
        Datetime now = Datetime.now();
        Id userId = UserInfo.getUserId();

        for (AA_Application__c app : newList) {
            AA_Application__c prev = oldMap.get(app.Id);
            if (app.Stage__c == prev.Stage__c) continue;

            app.Stage_Changed_At__c = now;
            logs.add(new AA_Stage_Log__c(
                Application__c = app.Id,
                From_Stage__c  = prev.Stage__c,
                To_Stage__c    = app.Stage__c,
                Actor__c       = 'human',
                Note__c        = noteByApp.get(app.Id),
                Changed_At__c  = now,
                Changed_By__c  = userId
            ));

            // Message dispatcher hook — fire the "Application Submitted to DWP"
            // template pack whenever an app transitions INTO Submitted. Ignore
            // resaves that were already in Submitted (guarded by the stage-
            // change short-circuit above). Batched into one Queueable per
            // trigger fire so bulk updates don't blow the async cap.
            if ('Submitted'.equalsIgnoreCase(app.Stage__c)) {
                submittedIds.add(app.Id);
            }
        }
        if (!logs.isEmpty()) insert logs;
        noteByApp.clear(); // don't let a note bleed into a later transition this txn
        if (!submittedIds.isEmpty()) {
            AA_MessageDispatcher.dispatch(submittedIds, 'Application_Submitted_DWP');
        }
    }

    /**
     * Stages the Heroku scheduler tick dials from, plus the in-call stage it
     * moves through. Twin of the tick's filter in src/webhooks/scheduler.js
     * (Stage__c IN ('Awaiting First Call','Partial Data')).
     */
    @TestVisible
    private static final Set<String> DIALABLE_STAGES = new Set<String>{
        'Awaiting First Call', 'Partial Data', 'Call In Progress'
    };

    /**
     * After update: cancel the Pending AA_Call_Schedule__c rows of any
     * Application that has just left the dialable stages or just been marked
     * Do Not Contact.
     *
     * audit 2026-10-02 F84/F70: every cancel path lived in Node (Mary
     * reschedule/flag, retry give-up, inbound DNC). An operator moving a record
     * to Needs Human / Closed / Data Complete, the client submitting the form,
     * or a post-call Data Complete left the Pending row in place. The tick never
     * dials those stages, so the row sat there: the client still got the 07:00
     * "Mary will call you today" SMS (AA_MorningReminderScheduler reads Pending
     * rows), Next_Call_At__c kept a slot that then went stale (blocking every
     * Application save under Next_Call_At_In_Future), and after 30 minutes the
     * reaper flipped it to Missed. Cancelling here also clears Next_Call_At__c
     * through AA_CallScheduleTriggerHelper.syncNextCallAt.
     *
     * Partial DML on purpose: a schedule row that cannot be cancelled must
     * never roll back the stage change itself.
     */
    public static void cancelPendingSchedulesOnExit(List<AA_Application__c> newList, Map<Id, AA_Application__c> oldMap) {
        if (newList == null || oldMap == null) return;
        Map<Id, String> reasonByApp = new Map<Id, String>();
        for (AA_Application__c app : newList) {
            AA_Application__c prev = oldMap.get(app.Id);
            if (prev == null) continue;
            if (app.Do_Not_Contact__c == true && prev.Do_Not_Contact__c != true) {
                reasonByApp.put(app.Id, 'Marked Do Not Contact');
            } else if (app.Stage__c != prev.Stage__c
                    && DIALABLE_STAGES.contains(prev.Stage__c)
                    && !DIALABLE_STAGES.contains(app.Stage__c)) {
                reasonByApp.put(app.Id, 'Stage moved to ' + app.Stage__c + ' (no longer dialled)');
            }
        }
        if (reasonByApp.isEmpty()) return;

        List<AA_Call_Schedule__c> rows = new List<AA_Call_Schedule__c>();
        Datetime now = Datetime.now();
        for (AA_Call_Schedule__c s : [
            SELECT Id, Application__c
              FROM AA_Call_Schedule__c
             WHERE Application__c IN :reasonByApp.keySet()
               AND Status__c = 'Pending'
        ]) {
            rows.add(new AA_Call_Schedule__c(
                Id               = s.Id,
                Status__c        = 'Cancelled',
                Cancelled_At__c  = now,
                Cancel_Reason__c = reasonByApp.get(s.Application__c).left(255)
            ));
        }
        if (rows.isEmpty()) return;
        Database.SaveResult[] saved = Database.update(rows, false);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) continue;
            System.debug(LoggingLevel.ERROR, 'AA_StageTransitionHelper: could not cancel schedule '
                + rows[i].Id + ': ' + saved[i].getErrors()[0].getMessage());
        }
    }

    // ── Auto re-book Mary's first call (owner decision, 2026-10-02) ───────

    /** Intake parks an application here when the bank details are deferred. */
    @TestVisible
    private static final String BANK_DEFERRED_STAGE = 'Awaiting Bank Details';

    /**
     * Stages that mean "bank details are in, Mary still has to collect the
     * answers": the two stages the Heroku tick dials. A move from Awaiting
     * Bank Details to Data Complete or later means the client already gave
     * the answers another way, so no call is booked; Call In Progress means
     * a call is already happening.
     */
    @TestVisible
    private static final Set<String> FIRST_CALL_STAGES = new Set<String>{ 'Awaiting First Call', 'Partial Data' };

    /** UK wall-clock hour of the auto-booked first call. */
    @TestVisible
    private static final Integer FIRST_CALL_HOUR_UK = 10;

    /**
     * After update: when an application leaves 'Awaiting Bank Details' for a
     * first-call stage, book Mary's first call for the next UK business day at
     * 10:00, unless the client is Do Not Contact or already has a future
     * Pending slot.
     *
     * Owner decision (Fernando, 2026-10-02): intake no longer books Mary's
     * first call while bank details are deferred (that slot was never dialled
     * and lapsed into a Missed row plus an ops handoff). It is booked here,
     * once the bank details are in.
     *
     * Runs in a Queueable: AA_CallScheduleService.createSchedule is a
     * single-record API (one query and one insert per call, and its trigger
     * writes Next_Call_At__c back onto this same Application), so it cannot be
     * looped inside this trigger for a bulk update. The job re-checks every
     * condition when it runs.
     */
    public static void bookFirstCallAfterBankDetails(List<AA_Application__c> newList, Map<Id, AA_Application__c> oldMap) {
        if (newList == null || oldMap == null) return;
        List<Id> ready = new List<Id>();
        for (AA_Application__c app : newList) {
            AA_Application__c prev = oldMap.get(app.Id);
            if (prev == null || app.Do_Not_Contact__c == true) continue;
            if (prev.Stage__c == BANK_DEFERRED_STAGE && FIRST_CALL_STAGES.contains(app.Stage__c)) {
                ready.add(app.Id);
            }
        }
        if (ready.isEmpty()) return;
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            // Already inside an async job that used its one enqueue. Rare (the
            // stage is moved by an operator or the Heroku API), but say so.
            System.debug(LoggingLevel.ERROR, 'AA_StageTransitionHelper: no Queueable slot left, Mary\'s first call '
                + 'was NOT booked for ' + ready + '. Book it from the Call Schedule card.');
            return;
        }
        System.enqueueJob(new FirstCallBooker(ready));
    }

    /**
     * Next UK business day after `nowUtc` (never today), at FIRST_CALL_HOUR_UK.
     * Weekends are skipped here; bank holidays are skipped by the caller,
     * because AA_CallScheduleService owns that list and refuses those days.
     */
    @TestVisible
    private static Datetime nextBusinessDaySlot(Datetime nowUtc, Integer extraDays) {
        Date d = AA_UkTime.dateUk(nowUtc).addDays(1 + extraDays);
        Integer guard = 0;
        while (AA_BusinessDayHelper.isWeekend(d) && guard < 7) { d = d.addDays(1); guard++; }
        return AA_BusinessDayHelper.buildUkDatetime(d, FIRST_CALL_HOUR_UK);
    }

    /** First line of AA_CallScheduleService.createSchedule's off-hours refusal. */
    private static final String OUTSIDE_HOURS_PREFIX = 'Mary can only call';

    /** Rough query cost of one createSchedule (its own query plus the schedule trigger's). */
    private static final Integer QUERIES_PER_BOOKING = 10;

    public with sharing class FirstCallBooker implements Queueable {
        private final List<Id> appIds;
        public FirstCallBooker(List<Id> appIds) { this.appIds = appIds; }

        public void execute(QueueableContext ctx) {
            Datetime now = Datetime.now();
            Map<Id, AA_Application__c> apps = new Map<Id, AA_Application__c>([
                SELECT Id, Stage__c, Do_Not_Contact__c FROM AA_Application__c WHERE Id IN :appIds
            ]);

            // A future Pending slot means a call is already booked: leave it.
            // A PAST Pending slot is a stale one (for example booked at intake
            // before bank details were deferred stopped booking): cancel it,
            // or the one-Pending-per-application rule refuses the new slot and
            // the tick could ring the client unannounced on that stale time.
            Set<Id> hasFuture = new Set<Id>();
            Map<Id, List<AA_Call_Schedule__c>> stale = new Map<Id, List<AA_Call_Schedule__c>>();
            for (AA_Call_Schedule__c s : [
                SELECT Id, Application__c, Scheduled_At__c FROM AA_Call_Schedule__c
                 WHERE Application__c IN :appIds AND Status__c = 'Pending'
            ]) {
                if (s.Scheduled_At__c != null && s.Scheduled_At__c > now) {
                    hasFuture.add(s.Application__c);
                } else {
                    if (!stale.containsKey(s.Application__c)) stale.put(s.Application__c, new List<AA_Call_Schedule__c>());
                    stale.get(s.Application__c).add(s);
                }
            }

            List<Id> todo = new List<Id>();
            for (Id appId : appIds) {
                AA_Application__c app = apps.get(appId);
                if (app == null || app.Do_Not_Contact__c == true) continue;
                if (!FIRST_CALL_STAGES.contains(app.Stage__c)) continue; // moved on since
                if (hasFuture.contains(appId)) continue;
                todo.add(appId);
            }
            if (todo.isEmpty()) return;

            List<AA_Call_Schedule__c> cancels = new List<AA_Call_Schedule__c>();
            for (Id appId : todo) {
                if (!stale.containsKey(appId)) continue;
                for (AA_Call_Schedule__c s : stale.get(appId)) {
                    cancels.add(new AA_Call_Schedule__c(
                        Id = s.Id, Status__c = 'Cancelled', Cancelled_At__c = now,
                        Cancel_Reason__c = 'Superseded: bank details are in, Mary\'s first call was booked again'
                    ));
                }
            }
            Set<Id> cancelFailed = new Set<Id>();
            if (!cancels.isEmpty()) {
                Database.SaveResult[] res = Database.update(cancels, false);
                for (Integer i = 0; i < res.size(); i++) {
                    if (res[i].isSuccess()) continue;
                    System.debug(LoggingLevel.ERROR, 'AA_StageTransitionHelper: stale slot ' + cancels[i].Id
                        + ' not cancelled: ' + res[i].getErrors()[0].getMessage());
                    for (Id appId : todo) {
                        for (AA_Call_Schedule__c s : stale.containsKey(appId) ? stale.get(appId) : new List<AA_Call_Schedule__c>()) {
                            if (s.Id == cancels[i].Id) cancelFailed.add(appId);
                        }
                    }
                }
            }

            List<Id> leftover = new List<Id>();
            for (Integer i = 0; i < todo.size(); i++) {
                Id appId = todo[i];
                if (cancelFailed.contains(appId)) continue;
                // Bulk-safe: stop while there is headroom and hand the rest to
                // a follow-up job.
                if (Limits.getQueries() + QUERIES_PER_BOOKING > Limits.getLimitQueries()
                        || Limits.getDmlStatements() + 5 > Limits.getLimitDmlStatements()) {
                    for (Integer j = i; j < todo.size(); j++) leftover.add(todo[j]);
                    break;
                }
                book(appId, now);
            }
            if (!leftover.isEmpty() && !Test.isRunningTest()
                    && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new FirstCallBooker(leftover));
            }
        }

        /** createSchedule, rolling past bank holidays it refuses. Never throws. */
        private void book(Id appId, Datetime now) {
            for (Integer extra = 0; extra < 10; extra++) {
                Datetime slot = nextBusinessDaySlot(now, extra);
                try {
                    AA_CallScheduleService.createSchedule(appId, slot);
                    return;
                } catch (AuraHandledException e) {
                    String msg = e.getMessage();
                    if (msg != null && msg.startsWith(OUTSIDE_HOURS_PREFIX)) continue; // bank holiday: next day
                    System.debug(LoggingLevel.ERROR, 'AA_StageTransitionHelper: first call not booked for '
                        + appId + ': ' + msg);
                    return;
                }
            }
            System.debug(LoggingLevel.ERROR, 'AA_StageTransitionHelper: no bookable day found for ' + appId);
        }
    }
}