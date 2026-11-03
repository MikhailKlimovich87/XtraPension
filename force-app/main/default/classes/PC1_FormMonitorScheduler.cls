/**
 * PC1_FormMonitorScheduler — Schedulable Apex that triggers the daily DWP
 * form-monitor walk on Heroku.
 *
 * Fernando 2026-08-25: the walk was supposed to be triggered by a Heroku
 * Scheduler `curl` cron. An E2E audit concluded that cron had never been
 * registered, so this Apex job was added to fire the walk instead.
 *
 * CORRECTION 2026-09-09: that conclusion was WRONG. The Heroku Scheduler job
 * does exist and still runs — PC1_Form_Snapshot__c shows two complete sweeps
 * every day (~03:31 UTC from here, ~04:32 UTC from Heroku), and has since at
 * least 2026-09-06. That is double the traffic against the live DWP service,
 * and worse: the second sweep diffs against the first, so anything the first
 * sweep failed to email can never be re-flagged by the second.
 *
 * RESOLVED 2026-09-10: this Apex job was UNSCHEDULED and the Heroku Scheduler
 * job (daily 04:30 UTC) is now the single trigger. The class stays deployed and
 * working — only the CronTrigger was aborted — so ownership can be flipped back
 * at any time with:
 *     node scripts/schedule-form-monitor.cjs --with-walk
 * after deleting the Heroku job first. NEVER arm both: that is the duplicate
 * sweep this resolved. See docs/pc1-workflow-manual.md §14.3.
 *
 * KNOWN TRADE-OFF: Heroku Scheduler is manual web-UI config with no API, so a
 * sandbox refresh or app rebuild loses it silently and the walk simply stops.
 * The 12:00 UTC dead-man is what catches that — it alerts if no complete sweep
 * lands within 26h, which is exactly this failure.
 *
 * TIMEZONE: Salesforce evaluates a cron expression in the SCHEDULING USER's
 * timezone, NOT UTC. This org's admin is Europe/Dublin, so `0 30 4 * * ?`
 * fires at 03:30 UTC during BST and shifts to 04:30 UTC on 2026-10-25 — the
 * same minute as the Heroku job, which is exactly why the lock exists.
 *
 * Firing from Apex rather than Heroku Scheduler is still the right default:
 * the Scheduler add-on has no programmatic API, so it can only be configured
 * by hand in a web UI, which violates the "services self-sufficient, no manual
 * Fernando intervention" rule. This is the same deployment-driven pattern as
 * PC1_SchedulerTickJob / PC1_MorningReminderScheduler / PC1_FeeInstallmentScheduler.
 *
 * A full 11-persona sweep takes ~20 minutes, far past the 120s Apex callout
 * ceiling, so the POST is fire-and-forget via `@future(callout=true)`: Heroku
 * returns 202 immediately and the walk continues in a detached worker.
 *
 * Cron: `0 30 4 * * ?` — see the TIMEZONE note above; this is NOT 04:30 UTC
 * year-round. Registered via `scripts/schedule-form-monitor.cjs` at deploy time.
 */
public with sharing class PC1_FormMonitorScheduler implements Schedulable {

    @TestVisible private static final String BASE_URL = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com';
    private static final String PATH = '/internal/form-monitor/run';
    private static final Integer TIMEOUT_MS = 10000;   // Heroku returns 202 immediately

    public void execute(SchedulableContext ctx) {
        firePostAsync();
    }

    /**
     * Cross-transaction callout wrapper — needed because Schedulable can't
     * make callouts directly. Same pattern as PC1_SchedulerTickJob.
     */
    @future(callout=true)
    public static void firePostAsync() {
        String token = getHerokuToken();
        if (String.isBlank(token)) {
            System.debug(LoggingLevel.ERROR, 'PC1_FormMonitorScheduler: HEROKU_INTERNAL_TOKEN missing in PC1_Config__c');
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
                'PC1_FormMonitorScheduler: POST /internal/form-monitor/run → HTTP ' +
                resp.getStatusCode() + ' body=' + resp.getBody().left(200));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_FormMonitorScheduler: callout failed — ' + e.getMessage());
        }
    }

    @TestVisible
    private static String getHerokuToken() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Heroku_Internal_Token__c))
            ? cfg.Heroku_Internal_Token__c.trim() : null;
    }
}