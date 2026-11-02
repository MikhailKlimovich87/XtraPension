/**
 * AA_FormMonitorScheduler — Schedulable Apex that triggers the daily DWP
 * form-monitor walk on Heroku.
 *
 * Fernando 2026-08-25: originally the form-monitor was supposed to be
 * triggered by Heroku Scheduler (a `curl` cron), but E2E audit found the
 * cron was never actually registered on the sandbox's Heroku Scheduler
 * addon — the form-monitor daily walk hadn't been firing. Adding it via
 * Heroku Scheduler requires the addon's web UI (no programmatic API),
 * which violates the "services self-sufficient, no manual Fernando
 * intervention" memory rule (feedback_services_self_sufficient).
 *
 * Solution: fire the daily walk from SF Schedulable Apex instead. This is
 * the same pattern AA_SchedulerTickJob + AA_MorningReminderScheduler +
 * AA_FeeInstallmentScheduler use — all deployment-driven, no Heroku
 * addon config to maintain.
 *
 * The walk itself is a Heroku Playwright job that takes 30–60s; we spawn
 * it fire-and-forget via `@future(callout=true)` so the Apex tx returns
 * fast and Salesforce doesn't hit the 120s callout ceiling.
 *
 * Cron: `0 30 4 * * ?` (daily 04:30 UTC). Registered via
 * `scripts/schedule-form-monitor.cjs` at deploy time.
 */
public with sharing class AA_FormMonitorScheduler implements Schedulable {

    @TestVisible private static final String BASE_URL = 'https://aa-autofill-14d501200453.herokuapp.com';
    private static final String PATH = '/internal/form-monitor/run';
    private static final Integer TIMEOUT_MS = 10000;   // Heroku returns 202 immediately

    public void execute(SchedulableContext ctx) {
        firePostAsync();
    }

    /**
     * Cross-transaction callout wrapper — needed because Schedulable can't
     * make callouts directly. Same pattern as AA_SchedulerTickJob.
     */
    @future(callout=true)
    public static void firePostAsync() {
        String token = getHerokuToken();
        if (String.isBlank(token)) {
            System.debug(LoggingLevel.ERROR, 'AA_FormMonitorScheduler: HEROKU_INTERNAL_TOKEN missing in AA_Config__c');
            return;
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + PATH);
        req.setMethod('POST');
        req.setHeader('X-Heroku-Token', token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody('{"source":"apex_scheduler"}');
        req.setTimeout(TIMEOUT_MS);
        try {
            HttpResponse resp = new Http().send(req);
            System.debug(LoggingLevel.INFO,
                'AA_FormMonitorScheduler: POST /internal/form-monitor/run → HTTP ' +
                resp.getStatusCode() + ' body=' + resp.getBody().left(200));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'AA_FormMonitorScheduler: callout failed — ' + e.getMessage());
        }
    }

    @TestVisible
    private static String getHerokuToken() {
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Heroku_Internal_Token__c))
            ? cfg.Heroku_Internal_Token__c.trim() : null;
    }
}