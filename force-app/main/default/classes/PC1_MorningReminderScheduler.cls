/**
 * PC1_MorningReminderScheduler — Schedulable that fires the morning-of
 * "reminder that Mary will call you today" message for every application
 * that has a Pending PC1_Call_Schedule__c scheduled on the current UK
 * calendar day.
 *
 * ── DST strategy ─────────────────────────────────────────────────────────
 * Salesforce cron expressions are always UTC and have no notion of DST.
 * We want the job to run at 07:00 UK time year-round. UK toggles between
 * BST (UTC+1, summer) and GMT (UTC+0, winter), so 07:00 UK is either
 * 06:00 UTC (summer) or 07:00 UTC (winter).
 *
 * Instead of trying to re-schedule the job twice a year, we register TWO
 * cron entries — one at 06:00 UTC and one at 07:00 UTC — and have the
 * class itself gate on `PC1_UkTime.hourUk(now) == 7`. Only the invocation
 * that matches the current UK-local 07:00 does real work; the other
 * invocation short-circuits and returns.
 *
 * ── Idempotency ──────────────────────────────────────────────────────────
 * Multiple runs on the same day are safe: PC1_MessageDispatcher owns the
 * 24h dedup guard on (Template, Application) — this scheduler just re-
 * asks it to send, and the dispatcher logs a Skipped-Deduped row for the
 * repeats. That means a manual re-run for debugging is harmless.
 *
 * ── Governor safety ──────────────────────────────────────────────────────
 * Single bulk SOQL for the day's schedules; single call to the dispatcher
 * per application id. Volume ceiling is well below 50k rows on any
 * realistic day (PC1 dials a handful).
 *
 * ── Weekends / bank holidays ─────────────────────────────────────────────
 * PC1_CallScheduleService never places a Pending row on a non-business
 * day (PC1_BusinessDayHelper enforces this on write). So on a Saturday
 * or bank holiday the SOQL naturally returns zero rows and this class
 * does nothing — no special-casing needed here.
 */
public with sharing class PC1_MorningReminderScheduler implements Schedulable {

    /** Template key handed to PC1_MessageDispatcher. Owned by B3 spec. */
    @TestVisible
    private static final String TEMPLATE_KEY = 'Call_Reminder_Morning_Of';

    /** UK-local hour the reminder should fire at. */
    @TestVisible
    private static final Integer TARGET_UK_HOUR = 7;

    public void execute(SchedulableContext ctx) {
        run(Datetime.now());
    }

    /**
     * Extracted for the test harness so we can pass a specific `now` value.
     * Returns a summary line (also written to debug log) for observability.
     */
    @TestVisible
    public static String run(Datetime now) {
        // DST gate: two cron entries fire this class (06 & 07 UTC). Only
        // the one matching UK-local 07:00 continues; the other is a no-op.
        Integer ukHour = PC1_UkTime.hourUk(now);
        if (ukHour != TARGET_UK_HOUR) {
            String msg = 'PC1_MorningReminderScheduler: skipped (UK hour=' + ukHour + ', target=' + TARGET_UK_HOUR + ')';
            System.debug(LoggingLevel.INFO, msg);
            return msg;
        }

        Datetime[] bounds = PC1_UkTime.ukDayBoundsUtc(now);
        Datetime dayStart = bounds[0];
        Datetime dayEnd   = bounds[1];

        List<PC1_Call_Schedule__c> pending = [
            SELECT Id, Application__c
              FROM PC1_Call_Schedule__c
             WHERE Status__c = 'Pending'
               AND Scheduled_At__c >= :dayStart
               AND Scheduled_At__c <  :dayEnd
        ];

        // Dedup application ids in-Apex — an app could theoretically have
        // multiple Pending rows across the day (edit + cancel-and-recreate
        // trigger races). Dispatcher-level 24h dedup covers the rest.
        Set<Id> appIds = new Set<Id>();
        for (PC1_Call_Schedule__c row : pending) {
            if (row.Application__c != null) appIds.add(row.Application__c);
        }

        Integer dispatched = 0;
        Integer errored    = 0;
        Integer skipped    = pending.size() - appIds.size();

        // Audit R9-batch-D — was per-app dispatch(appId) → one enqueueJob
        // per app. At 51+ pending reminders the loop hit the 50-async cap
        // uncatchably. Now: bulk dispatch(Set<Id>) — the dispatcher self-
        // chunks (MAX_APPS_PER_EXECUTE with dynamic sizing) and only
        // enqueues once + self-chains for the remainder.
        if (testBypass) {
            for (Id appId : appIds) { dispatch(appId); dispatched++; }
        } else {
            try {
                Id jobId = PC1_MessageDispatcher.dispatch(appIds, TEMPLATE_KEY);
                dispatched = appIds.size();
                if (jobId == null && !appIds.isEmpty()) {
                    System.debug(LoggingLevel.WARN,
                        'PC1_MorningReminderScheduler: dispatch returned null (Batch/Future context or empty templates?) for ' + appIds.size() + ' apps');
                }
            } catch (Exception e) {
                errored = appIds.size();
                System.debug(LoggingLevel.ERROR,
                    'PC1_MorningReminderScheduler: bulk dispatch failed for ' + appIds.size() + ' apps — ' + e.getMessage());
            }
        }

        String summary = 'PC1_MorningReminderScheduler: dispatched=' + dispatched
                       + ' skipped(dedup)=' + skipped
                       + ' errored=' + errored
                       + ' (pending rows=' + pending.size() + ')';
        System.debug(LoggingLevel.INFO, summary);
        return summary;
    }

    /**
     * Test hook — when set, dispatch() records the call instead of
     * hitting PC1_MessageDispatcher. Lets PC1_MorningReminderSchedulerTest
     * exercise the query + DST gate + counting logic without coupling to
     * B3's dispatcher (which owns its own test coverage). Kept private
     * so production code can't accidentally toggle it.
     */
    @TestVisible
    private static Boolean testBypass = false;
    @TestVisible
    private static List<Id> testDispatched = new List<Id>();

    /**
     * Delegates to PC1_MessageDispatcher.dispatch(appId, TEMPLATE_KEY).
     * Wrapped so tests can bypass without needing the B3 class stubbed.
     */
    @TestVisible
    private static void dispatch(Id appId) {
        if (testBypass) {
            testDispatched.add(appId);
            return;
        }
        PC1_MessageDispatcher.dispatch(appId, TEMPLATE_KEY);
    }
}