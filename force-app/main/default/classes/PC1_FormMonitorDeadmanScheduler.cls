/**
 * PC1_FormMonitorDeadmanScheduler — dead-man for the DWP form-monitor.
 *
 * PC1_FormMonitorScheduler fires the daily walk (04:30 UTC) by callout to Heroku.
 * If that job is unscheduled/aborted, or the Heroku walk endpoint 401s/times out,
 * or the walker keeps crashing before it can persist anything, the failure is only
 * System.debug'd — nobody is told, and "no email today" is indistinguishable from
 * "the form didn't change today". That is the worst failure mode a monitor has.
 *
 * This SEPARATE scheduled job (run a few hours after the walk) checks the
 * freshness of PC1_Form_Snapshot__c directly in Salesforce and emails an alert if
 * there has been no SUCCESSFUL walk within STALE_HOURS.
 *
 * Deliberately PURE Apex (SOQL + Messaging, no Heroku callout): the walk's own
 * failure modes include the SF→Heroku token and endpoint, so the dead-man must
 * not depend on either. setSaveAsActivity(false) → no EmailMessage record is
 * created (sandbox storage lesson from 2026-09-03).
 *
 * Schedule (deploy-driven, via scripts/schedule-form-monitor.cjs):
 *   System.schedule('PC1 Form Monitor Deadman', '0 0 12 * * ?',
 *                   new PC1_FormMonitorDeadmanScheduler());
 */
public with sharing class PC1_FormMonitorDeadmanScheduler implements Schedulable {

    @TestVisible private static Integer STALE_HOURS = 26;

    public void execute(SchedulableContext ctx) { check(); }

    // The worker writes one row per persona and then a single '__union__' row as
    // the LAST thing it does. Watching for that union row (rather than any
    // successful row) is what makes this a real dead-man: a sweep that dies
    // half-way -- a Heroku SIGTERM on deploy or dyno cycle lands squarely in the
    // ~20-minute walk window -- leaves early personas persisted and looks
    // perfectly healthy to a 'any success row' check, which is how a
    // half-finished sweep could pass unnoticed every single day.
    @TestVisible private static final String UNION_KEY = '__union__';

    @TestVisible
    public static Boolean check() {
        List<PC1_Form_Snapshot__c> latest = [
            SELECT Captured_At__c FROM PC1_Form_Snapshot__c
             WHERE Status__c = 'success'
               AND Persona_Key__c = :UNION_KEY
             ORDER BY Captured_At__c DESC
             LIMIT 1
        ];
        Datetime last = latest.isEmpty() ? null : latest[0].Captured_At__c;
        Long ageMin = (last == null)
            ? Long.valueOf('9223372036854775807')
            : (Datetime.now().getTime() - last.getTime()) / 60000;
        Boolean stale = ageMin > ((Long) STALE_HOURS) * 60;
        if (stale) sendAlert(last, ageMin);
        return stale;
    }

    private static void sendAlert(Datetime last, Long ageMin) {
        String to = resolveRecipient();
        if (String.isBlank(to)) {
            System.debug(LoggingLevel.ERROR, 'PC1_FormMonitorDeadmanScheduler: no recipient — stale walk NOT alerted');
            return;
        }
        String lastSeen = (last == null)
            ? 'NEVER'
            : (ageMin / 60) + 'h ago (' + last.formatGmt('yyyy-MM-dd HH:mm') + ' UTC)';
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ to });
        msg.setSubject('PC1 form-monitor DEAD-MAN — no COMPLETE walk in ' + STALE_HOURS + 'h');
        msg.setHtmlBody(
            '<p>The DWP form-monitor has not recorded a <b>complete</b> sweep within ' + STALE_HOURS + 'h.</p>'
            + '<p>Last complete sweep: <b>' + lastSeen + '</b>.</p>'
            + '<p>"Complete" means the <code>__union__</code> snapshot, which the worker writes only after '
            + 'every persona has finished. Individual persona rows may well exist for a sweep that then died '
            + 'part-way through — check the dashboard for a partial run.</p>'
            + '<p>Check that <code>PC1_FormMonitorScheduler</code> is still scheduled (Setup → Scheduled Jobs) and that '
            + 'the Heroku walk endpoint <code>/internal/form-monitor/run</code> is reachable.</p>'
        );
        msg.setSaveAsActivity(false);       // no EmailMessage/Activity record
        msg.setTreatBodiesAsTemplate(false);
        try {
            // allOrNone=false means a delivery failure is RETURNED in the result, not
            // thrown — check it, so the alerter-of-last-resort cannot fail silently
            // (which is the exact thing this class exists to prevent).
            Messaging.SendEmailResult[] rs = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
            if (rs != null && !rs.isEmpty() && !rs[0].isSuccess()) {
                String errs = '';
                for (Messaging.SendEmailError se : rs[0].getErrors()) errs += se.getStatusCode() + ':' + se.getMessage() + '; ';
                System.debug(LoggingLevel.ERROR, 'PC1_FormMonitorDeadmanScheduler: dead-man email NOT delivered to ' + to + ' — ' + errs);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PC1_FormMonitorDeadmanScheduler: sendEmail threw — ' + e.getMessage());
        }
    }

    @TestVisible
    private static String resolveRecipient() {
        try {
            PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
            if (cfg != null) {
                Object v = cfg.get('Admin_Alert_Email__c');
                if (v != null && String.isNotBlank(String.valueOf(v))) return String.valueOf(v).trim();
            }
        } catch (Exception ignored) { /* field may not exist in every org */ }
        try {
            return [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Email;
        } catch (Exception ignored) { return null; }
    }
}