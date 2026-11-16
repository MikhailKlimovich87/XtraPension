/**
 * PC1_SchedulerTickJob — Schedulable that POSTs /internal/scheduler-tick on
 * the Heroku worker every 5 minutes (via 12 stacked cron jobs, one per
 * 5-min offset). Without this, no scheduled Mary call ever dials.
 *
 * IMPORTANT: Salesforce forbids HTTP callouts from Schedulable Apex
 * directly ("Callout from scheduled Apex not supported"). The Schedulable
 * `execute` calls a `@future(callout=true)` method which does the real
 * callout in a separate async context — the only way to make outbound
 * HTTP work from a scheduled job.
 *
 * Idempotent: /internal/scheduler-tick guards against double-dial via the
 * "clear Next_Call_At__c BEFORE dial" pattern in scheduler.js.
 * Auth: PC1_Config__c.Heroku_Internal_Token__c (same as PC1_HerokuBridge).
 * Remote Site Setting PC1_Heroku_Autofill whitelists the Heroku base URL.
 */
public with sharing class PC1_SchedulerTickJob implements Schedulable {

    // Invocable = direct call from anonymous apex OR from a flow, both of
    // which DO allow callouts synchronously (unlike Schedulable). Keeps the
    // "fire once from console for smoke testing" ergonomic.
    @InvocableMethod(label='PC1 · Fire scheduler tick')
    public static List<String> fireOnce() {
        return new List<String>{ doTickSync() };
    }

    public void execute(SchedulableContext ctx) {
        // Cannot callout from here — hand off to @future.
        doTickAsync();
    }

    // ── Failure alerting (audit 2026-11-11 PC-APEX-12, port of AA F91) ──
    // The async path used to throw away Heroku's answer: a 401 (rotated
    // token), a 5xx, a timeout or a missing PC1_Config__c all "completed"
    // quietly while no Mary call was dialled, and the only trace was a
    // System.debug line. Now any non-2xx, callout exception or missing
    // config emails the ops address (PC1_Config__c.Admin_Alert_Email__c,
    // falling back to the job owner), like PC1_FormMonitorDeadmanScheduler.
    // De-duplication is stateless: only the tick whose @future runs in the
    // first 5 minutes of a UTC hour sends, so a persistent outage costs one
    // email per hour instead of twelve.

    /** Last failure seen by the async path (tests + debugging). */
    @TestVisible private static String lastFailure;
    /** Failure text of the alert last attempted, or null if none was due. */
    @TestVisible private static String lastAlertReason;
    /** Tests force the alert slot open/closed; null = real clock. */
    @TestVisible private static Boolean forceAlertSlot;

    @future(callout=true)
    private static void doTickAsync() {
        String failure = null;
        try {
            PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
            if (!isConfigured(cfg)) {
                failure = 'PC1_Config__c is missing Heroku_Base_Url__c or Heroku_Internal_Token__c, so the tick is not being sent.';
            } else {
                HttpResponse res = send(cfg);
                Integer code = res.getStatusCode();
                if (code < 200 || code > 299) {
                    String body = res.getBody() == null ? '' : res.getBody();
                    failure = 'Heroku answered HTTP ' + code + ': ' + body.abbreviate(300);
                }
            }
        } catch (Exception e) {
            failure = 'Callout failed: ' + e.getMessage();
        }
        if (failure != null) {
            System.debug(LoggingLevel.ERROR, 'PC1_SchedulerTickJob async failed: ' + failure);
            alertIfDue(failure);
        }
    }

    @TestVisible
    private static Boolean isAlertSlot(Datetime nowTs) {
        if (forceAlertSlot != null) return forceAlertSlot;
        return Integer.valueOf(nowTs.formatGmt('m')) < 5;
    }

    private static void alertIfDue(String failure) {
        lastFailure = failure;
        if (!isAlertSlot(Datetime.now())) return;
        lastAlertReason = failure;
        String to = resolveRecipient();
        if (String.isBlank(to)) {
            System.debug(LoggingLevel.ERROR, 'PC1_SchedulerTickJob: no alert recipient; failure NOT alerted: ' + failure);
            return;
        }
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ to });
        msg.setSubject('PC1 scheduler tick is failing: scheduled Mary calls are not being dialled');
        msg.setPlainTextBody(
            'The 5-minute PC1 scheduler tick (PC1_SchedulerTickJob -> POST /internal/scheduler-tick) failed at '
            + Datetime.now().formatGmt('yyyy-MM-dd HH:mm') + ' UTC.\n\n'
            + 'Failure: ' + failure + '\n\n'
            + 'While this lasts no scheduled Mary call is dialled and missed schedules are not re-planned. '
            + 'Check the Heroku app (pc1-autofill) is up, and that PC1_Config__c.Heroku_Base_Url__c / '
            + 'Heroku_Internal_Token__c match HEROKU_INTERNAL_TOKEN on Heroku. This alert repeats at most once '
            + 'an hour while the failure lasts.'
        );
        msg.setSaveAsActivity(false);
        try {
            Messaging.SendEmailResult[] rs = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
            if (rs != null && !rs.isEmpty() && !rs[0].isSuccess()) {
                String errs = '';
                for (Messaging.SendEmailError se : rs[0].getErrors()) errs += se.getStatusCode() + ':' + se.getMessage() + '; ';
                System.debug(LoggingLevel.ERROR, 'PC1_SchedulerTickJob: alert NOT delivered to ' + to + ': ' + errs);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PC1_SchedulerTickJob: sendEmail threw: ' + e.getMessage());
        }
    }

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

    private static Boolean isConfigured(PC1_Config__c cfg) {
        return cfg != null && String.isNotBlank(cfg.Heroku_Base_Url__c) && String.isNotBlank(cfg.Heroku_Internal_Token__c);
    }

    private static String doTickSync() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (!isConfigured(cfg)) {
            return 'skipped: PC1_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c';
        }
        HttpResponse res = send(cfg);
        return 'HTTP ' + res.getStatusCode() + ' — ' + res.getBody().abbreviate(200);
    }

    private static HttpResponse send(PC1_Config__c cfg) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Heroku_Base_Url__c.removeEnd('/') + '/internal/scheduler-tick');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Heroku-Token', cfg.Heroku_Internal_Token__c);
        req.setBody('{}');
        req.setTimeout(60000);
        return new Http().send(req);
    }
}