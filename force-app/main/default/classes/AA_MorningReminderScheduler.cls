/**
 * AA_MorningReminderScheduler — Schedulable that fires the morning-of
 * "reminder that Mary will call you today" message for every application
 * that has a Pending AA_Call_Schedule__c scheduled on the current UK
 * calendar day.
 *
 * ── DST strategy ─────────────────────────────────────────────────────────
 * Salesforce cron expressions are evaluated in the timezone of the user who
 * scheduled the job. The two live jobs ("AA Morning Reminder 06:00 UTC" /
 * "07:00 UTC") are owned by a user on Europe/Dublin, so despite their names
 * they fire at 06:00 and 07:00 IRISH/UK local time (audit 2026-10-02 F161).
 * Whatever the owner's timezone, the class itself gates on
 * `AA_UkTime.hourUk(now) == 7`: only the invocation that lands on UK-local
 * 07:00 does real work, the other short-circuits. Registering two entries
 * an hour apart keeps that true across BST/GMT for a UTC-timezone owner too.
 *
 * ── Idempotency ──────────────────────────────────────────────────────────
 * Multiple runs on the same day are safe: AA_MessageDispatcher owns the
 * 24h dedup guard on (Template, Application) — this scheduler just re-
 * asks it to send, and the dispatcher logs a Skipped-Deduped row for the
 * repeats. That means a manual re-run for debugging is harmless.
 *
 * ── Governor safety ──────────────────────────────────────────────────────
 * Single bulk SOQL for the day's schedules and ONE bulk dispatcher call for
 * all of them (one Queueable). Until 2026-10-02 it enqueued one Queueable
 * per application, so a day with more than 50 calls hit the uncatchable
 * 50-enqueueJob limit and rolled back every reminder (audit F71).
 *
 * ── Who gets a reminder ──────────────────────────────────────────────────
 * Only applications Mary will actually dial today: Stage in the dialler's
 * set ('Awaiting First Call', 'Partial Data') and Do_Not_Contact__c = false,
 * mirroring src/webhooks/scheduler.js. A Pending row can outlive a stage
 * move (no trigger cancels it), and the client would otherwise be promised
 * a call that never comes, or a deceased/DNC client would be texted
 * (audit 2026-10-02 F70/F85).
 * A client who replied STOP (SMS_Opt_Out__c) is deliberately NOT filtered
 * here: Mary still calls them, and AA_MessageDispatcher skips the SMS and
 * logs it as an SMS opt-out, so the record shows why no reminder went
 * (owner decision 2026-10-02).
 *
 * ── Weekends / bank holidays ─────────────────────────────────────────────
 * AA_CallScheduleService places Pending rows on business days only; a slot
 * booked another way (e.g. at intake) can still land on a weekend, and is
 * then reminded like any other Pending row for today.
 */
public with sharing class AA_MorningReminderScheduler implements Schedulable {

    /** Template key handed to AA_MessageDispatcher. Owned by B3 spec. */
    @TestVisible
    private static final String TEMPLATE_KEY = 'Call_Reminder_Morning_Of';

    /** UK-local hour the reminder should fire at. */
    @TestVisible
    private static final Integer TARGET_UK_HOUR = 7;

    /** Stages the Heroku dialler calls (src/webhooks/scheduler.js). */
    @TestVisible
    private static final Set<String> DIALABLE_STAGES = new Set<String>{ 'Awaiting First Call', 'Partial Data' };

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
        Integer ukHour = AA_UkTime.hourUk(now);
        if (ukHour != TARGET_UK_HOUR) {
            String msg = 'AA_MorningReminderScheduler: skipped (UK hour=' + ukHour + ', target=' + TARGET_UK_HOUR + ')';
            System.debug(LoggingLevel.INFO, msg);
            return msg;
        }

        Datetime[] bounds = AA_UkTime.ukDayBoundsUtc(now);
        Datetime dayStart = bounds[0];
        Datetime dayEnd   = bounds[1];

        List<AA_Call_Schedule__c> pending = [
            SELECT Id, Application__c
              FROM AA_Call_Schedule__c
             WHERE Status__c = 'Pending'
               AND Scheduled_At__c >= :dayStart
               AND Scheduled_At__c <  :dayEnd
               AND Application__r.Do_Not_Contact__c = false
               AND Application__r.Stage__c IN :DIALABLE_STAGES
        ];

        // Dedup application ids in-Apex — an app could theoretically have
        // multiple Pending rows across the day (edit + cancel-and-recreate
        // trigger races). Dispatcher-level 24h dedup covers the rest.
        Set<Id> appIds = new Set<Id>();
        for (AA_Call_Schedule__c row : pending) {
            if (row.Application__c != null) appIds.add(row.Application__c);
        }

        Integer dispatched = 0;
        Integer errored    = 0;
        Integer skipped    = pending.size() - appIds.size();

        if (!appIds.isEmpty()) {
            try {
                dispatch(appIds);
                dispatched = appIds.size();
            } catch (Exception e) {
                errored = appIds.size();
                System.debug(LoggingLevel.ERROR,
                    'AA_MorningReminderScheduler: dispatch failed for ' + appIds.size() + ' apps — ' + e.getMessage());
            }
        }

        String summary = 'AA_MorningReminderScheduler: dispatched=' + dispatched
                       + ' skipped(dedup)=' + skipped
                       + ' errored=' + errored
                       + ' (pending rows=' + pending.size() + ')';
        System.debug(LoggingLevel.INFO, summary);
        return summary;
    }

    /**
     * Test hook — when set, dispatch() records the call instead of
     * hitting AA_MessageDispatcher. Lets AA_MorningReminderSchedulerTest
     * exercise the query + DST gate + counting logic without coupling to
     * B3's dispatcher (which owns its own test coverage). Kept private
     * so production code can't accidentally toggle it.
     */
    @TestVisible
    private static Boolean testBypass = false;
    @TestVisible
    private static List<Id> testDispatched = new List<Id>();

    /**
     * Delegates to AA_MessageDispatcher.dispatch(appIds, TEMPLATE_KEY): one
     * Queueable for the whole day, never one per application.
     * Wrapped so tests can bypass without needing the B3 class stubbed.
     */
    @TestVisible
    private static void dispatch(Set<Id> appIds) {
        if (testBypass) {
            testDispatched.addAll(appIds);
            testDispatchCalls++;
            return;
        }
        AA_MessageDispatcher.dispatch(appIds, TEMPLATE_KEY);
    }
    @TestVisible
    private static Integer testDispatchCalls = 0;
}