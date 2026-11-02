/**
 * AA_FormMonitorDeadmanScheduler — dead-man for the DWP form-monitor (audit #63).
 *
 * AA_FormMonitorScheduler fires the daily walk (04:30 UTC) by callout to Heroku.
 * If that job is unscheduled/aborted, or the Heroku walk endpoint 401s/times out,
 * or the walker keeps crashing, the failure was only System.debug'd — nobody was
 * told. This SEPARATE scheduled job (run a few hours later) checks the freshness
 * of AA_Form_Snapshot__c directly in Salesforce and emails an alert if no walk of
 * any status has run within STALE_HOURS, or if walks are running but none has
 * succeeded within NO_SUCCESS_HOURS. See check() for why those are kept apart.
 *
 * Deliberately PURE Apex (SOQL + Messaging, no Heroku callout): the walk's own
 * failure modes include the SF→Heroku token/endpoint, so the dead-man must not
 * depend on them. setSaveAsActivity(false) → no EmailMessage record is created.
 *
 * Schedule (deploy-driven, matches AA_FormMonitorScheduler):
 *   System.schedule('AA Form Monitor Deadman', '0 0 12 * * ?',
 *                   new AA_FormMonitorDeadmanScheduler());
 */
public with sharing class AA_FormMonitorDeadmanScheduler implements Schedulable {

    @TestVisible private static Integer STALE_HOURS = 26;       // no walk RAN at all
    @TestVisible private static Integer NO_SUCCESS_HOURS = 72;  // walks ran, none succeeded

    /** Which alert the last check() raised: NO_RUN, NO_SUCCESS, or null. */
    @TestVisible private static String lastReason;

    public void execute(SchedulableContext ctx) { check(); }

    /**
     * Two DIFFERENT failures, told apart on purpose:
     *
     *  NO_RUN      — no walk of ANY status in STALE_HOURS. The pipeline itself is
     *                dead: the scheduled job is gone, or the SF→Heroku callout is
     *                401ing / timing out. Nothing else can report this, because
     *                the worker never ran. This is what the dead-man is for.
     *
     *  NO_SUCCESS  — walks ARE running but none has succeeded in NO_SUCCESS_HOURS.
     *                The walker is persistently failing.
     *
     * Until 2026-09-16 this only asked "any SUCCESS in 26h?", which folded the
     * second case into the first. A single transient DWP blip that morning made
     * one walk come back 'blocked'; the worker emailed its own walk-failed alert
     * straight away, and then this job fired a SECOND email about the same event
     * at 11:00 — telling the reader to check the scheduler and the endpoint, both
     * of which were healthy. A blocked or error run already alerts by itself, so a
     * short success gap is not the dead-man's business. The longer NO_SUCCESS
     * window stays as a backstop: if the walker keeps failing for days and its
     * own alerts are not arriving, this still speaks up.
     */
    @TestVisible
    public static Boolean check() {
        lastReason = null;
        Datetime lastRun     = newest(null);
        Datetime lastSuccess = newest('success');

        if (ageMinutes(lastRun) > ((Long) STALE_HOURS) * 60) {
            lastReason = 'NO_RUN';
            sendAlert(lastReason, lastRun, lastSuccess);
            return true;
        }
        if (ageMinutes(lastSuccess) > ((Long) NO_SUCCESS_HOURS) * 60) {
            lastReason = 'NO_SUCCESS';
            sendAlert(lastReason, lastRun, lastSuccess);
            return true;
        }
        return false;
    }

    /** Newest Captured_At__c, optionally for one status. Every row the worker
     *  writes carries Captured_At__c, error rows included. */
    private static Datetime newest(String status) {
        List<AA_Form_Snapshot__c> rows = (status == null)
            ? [SELECT Captured_At__c FROM AA_Form_Snapshot__c
                ORDER BY Captured_At__c DESC NULLS LAST LIMIT 1]
            : [SELECT Captured_At__c FROM AA_Form_Snapshot__c
                WHERE Status__c = :status
                ORDER BY Captured_At__c DESC NULLS LAST LIMIT 1];
        return rows.isEmpty() ? null : rows[0].Captured_At__c;
    }

    private static Long ageMinutes(Datetime t) {
        return (t == null)
            ? Long.valueOf('9223372036854775807')
            : (Datetime.now().getTime() - t.getTime()) / 60000;
    }

    private static String describe(Datetime t) {
        if (t == null) return 'NEVER';
        return (ageMinutes(t) / 60) + 'h ago (' + t.formatGmt('yyyy-MM-dd HH:mm') + ' UTC)';
    }

    private static void sendAlert(String reason, Datetime lastRun, Datetime lastSuccess) {
        String to = resolveRecipient();
        if (String.isBlank(to)) {
            System.debug(LoggingLevel.ERROR, 'AA_FormMonitorDeadmanScheduler: no recipient — ' + reason + ' NOT alerted');
            return;
        }
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ to });
        if (reason == 'NO_RUN') {
            msg.setSubject('AA form-monitor DEAD-MAN — no walk has run in ' + STALE_HOURS + 'h');
            msg.setHtmlBody(
                '<p>The DWP form-monitor has not run <b>at all</b> within ' + STALE_HOURS + 'h — not even a failed walk.</p>'
                + '<p>Last walk of any kind: <b>' + describe(lastRun) + '</b>.<br>'
                + 'Last successful walk: <b>' + describe(lastSuccess) + '</b>.</p>'
                + '<p>The walk pipeline itself is not firing, so the worker could not have alerted you. Check that the '
                + 'scheduled job <code>AA Form Monitor Daily</code> (class <code>AA_FormMonitorScheduler</code>) still exists '
                + 'under Setup → Scheduled Jobs, and that the Heroku walk endpoint <code>/internal/form-monitor/run</code> '
                + 'is reachable with the current <code>HEROKU_INTERNAL_TOKEN</code>.</p>'
            );
        } else {
            msg.setSubject('AA form-monitor DEAD-MAN — walks running, none successful in ' + NO_SUCCESS_HOURS + 'h');
            msg.setHtmlBody(
                '<p>DWP form-monitor walks <b>are</b> running, but none has succeeded within ' + NO_SUCCESS_HOURS + 'h.</p>'
                + '<p>Last walk of any kind: <b>' + describe(lastRun) + '</b>.<br>'
                + 'Last successful walk: <b>' + describe(lastSuccess) + '</b>.</p>'
                + '<p>The scheduler and the endpoint are working — the walker keeps failing. Each failed walk should '
                + 'already have sent its own "walk aborted" email; if you have not been receiving those, that alert path '
                + 'is broken too. Review the form-monitor dashboard for the failing persona and page.</p>'
            );
        }
        msg.setSaveAsActivity(false);       // no EmailMessage/Activity record
        msg.setTreatBodiesAsTemplate(false);
        try {
            // audit #12: allOrNone=false means a delivery failure is returned in the
            // result, NOT thrown — check it so the alerter-of-last-resort doesn't fail
            // silently (which is the exact thing this class exists to prevent).
            Messaging.SendEmailResult[] rs = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
            if (rs != null && !rs.isEmpty() && !rs[0].isSuccess()) {
                String errs = '';
                for (Messaging.SendEmailError se : rs[0].getErrors()) errs += se.getStatusCode() + ':' + se.getMessage() + '; ';
                System.debug(LoggingLevel.ERROR, 'AA_FormMonitorDeadmanScheduler: dead-man email NOT delivered to ' + to + ' — ' + errs);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AA_FormMonitorDeadmanScheduler: sendEmail threw — ' + e.getMessage());
        }
    }

    @TestVisible
    private static String resolveRecipient() {
        try {
            AA_Config__c cfg = AA_Config__c.getOrgDefaults();
            if (cfg != null) {
                Object v = cfg.get('Admin_Alert_Email__c');
                if (v != null && String.isNotBlank(String.valueOf(v))) return String.valueOf(v).trim();
            }
        } catch (Exception ignored) { /* field may not exist */ }
        try {
            return [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
        } catch (Exception ignored) { return null; }
    }
}