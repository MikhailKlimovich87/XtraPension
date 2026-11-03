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

    @future(callout=true)
    private static void doTickAsync() {
        try { doTickSync(); }
        catch (Exception e) { System.debug(LoggingLevel.ERROR, 'PC1_SchedulerTickJob async failed: ' + e.getMessage()); }
    }

    private static String doTickSync() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Heroku_Base_Url__c) || String.isBlank(cfg.Heroku_Internal_Token__c)) {
            return 'skipped: PC1_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c';
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(cfg.Heroku_Base_Url__c.removeEnd('/') + '/internal/scheduler-tick');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Heroku-Token', cfg.Heroku_Internal_Token__c);
        req.setBody('{}');
        req.setTimeout(60000);
        HttpResponse res = new Http().send(req);
        return 'HTTP ' + res.getStatusCode() + ' — ' + res.getBody().abbreviate(200);
    }
}