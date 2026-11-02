/**
 * AA_WelcomePackWatchdog — hourly Schedulable that makes sure a client's
 * welcome email is never silently lost (audit 2026-10-02 F73).
 *
 * Re-sends held emails (Apex only, no callout). AA_MessageDispatcher holds
 * an email whose per-application PDF is missing (log Status__c =
 * 'Skipped-Missing-Attachment'), holds the SMS of the same event with it and
 * emails ops once. This job looks at the held Email logs of the last
 * LOOKBACK_DAYS days and, for every app+event whose email has still never
 * been Sent and whose files are now all present
 * (AA_MessageDispatcher.appsWithAttachmentsReady), calls
 * AA_MessageDispatcher.dispatchHeldResend, which sends the email and the held
 * SMS and never repeats a part that already went. While the file is still
 * missing it does nothing (no extra logs, no repeat alert).
 *
 * The Heroku mandate-PDF retry (POST /internal/gocardless/retry-pending-
 * mandate-pdfs, which uploads a mandate PDF whose download failed and stamps
 * DD_Mandate_Id__c, firing the normal Intake_Created welcome) is NOT called
 * from here any more (wave 3, 2026-10-02). Its one caller is the Heroku
 * scheduler tick (src/webhooks/scheduler.js, "mandate-PDF watchdog", every
 * 15 minutes, off switch MANDATE_PDF_WATCHDOG=0), which AA_SchedulerTickJob
 * drives every 5 minutes. Wave 2 had added a second, hourly POST here; the
 * two runs could overlap and upload the same mandate PDF and re-render the
 * same welcome pack twice. With one caller there is also no callout in this
 * class, so fireOnce() can no longer hit "uncommitted work pending" after the
 * re-send enqueues its job (wave-2 review finding).
 *
 * Schedule (once, as the integration / admin user; minute 20 keeps it clear
 * of the 5-minute scheduler ticks):
 *   System.schedule('AA Welcome Pack Watchdog', '0 20 * * * ?', new AA_WelcomePackWatchdog());
 */
public with sharing class AA_WelcomePackWatchdog implements Schedulable {

    @TestVisible private static final Integer LOOKBACK_DAYS = 7;
    // The re-send loads every PDF of every app into one Queueable's heap
    // (12 MB async, three PDFs of ~130 KB each per app), so cap each run; the
    // rest go in the next hourly run.
    @TestVisible private static final Integer MAX_APPS_PER_EVENT = 10;

    public void execute(SchedulableContext ctx) {
        resendHeld();
    }

    /** Console / Flow smoke test: the same re-send, synchronously. */
    @InvocableMethod(label='AA · Run welcome pack watchdog')
    public static List<String> fireOnce() {
        Map<String, Set<Id>> resent = resendHeld();
        Integer n = 0;
        for (Set<Id> s : resent.values()) n += s.size();
        return new List<String>{ 'resent ' + n + ' held event(s)' };
    }

    /** Re-dispatches every ready held event. Returns event -> app ids sent for. */
    @TestVisible
    private static Map<String, Set<Id>> resendHeld() {
        Datetime since = Datetime.now().addDays(-LOOKBACK_DAYS);
        Map<String, Set<Id>> heldByEvent = new Map<String, Set<Id>>();
        Set<Id> allApps = new Set<Id>();
        for (AA_Message_Send_Log__c l : [
                SELECT Application__c, Template__r.Trigger_Event__c
                  FROM AA_Message_Send_Log__c
                 WHERE Status__c = 'Skipped-Missing-Attachment'
                   AND Channel__c = 'Email'
                   AND Sent_At__c >= :since
                   AND Application__c != null
                   AND Template__r.Active__c = true
                 ORDER BY Sent_At__c DESC
                 LIMIT 2000]) {
            String ev = l.Template__r.Trigger_Event__c;
            if (String.isBlank(ev)) continue;
            if (!heldByEvent.containsKey(ev)) heldByEvent.put(ev, new Set<Id>());
            heldByEvent.get(ev).add(l.Application__c);
            allApps.add(l.Application__c);
        }
        Map<String, Set<Id>> out = new Map<String, Set<Id>>();
        if (heldByEvent.isEmpty()) return out;

        // An email of that event that went out later (an earlier re-send, a
        // manual send) closes the case: re-dispatching would only write
        // Skipped-Deduped rows every hour.
        for (AA_Message_Send_Log__c s : [
                SELECT Application__c, Template__r.Trigger_Event__c
                  FROM AA_Message_Send_Log__c
                 WHERE Status__c = 'Sent'
                   AND Channel__c = 'Email'
                   AND Application__c IN :allApps
                   AND Template__r.Trigger_Event__c IN :heldByEvent.keySet()]) {
            Set<Id> held = heldByEvent.get(s.Template__r.Trigger_Event__c);
            if (held != null) held.remove(s.Application__c);
        }

        for (String ev : heldByEvent.keySet()) {
            Set<Id> held = heldByEvent.get(ev);
            if (held.isEmpty()) continue;
            Set<Id> ready = AA_MessageDispatcher.appsWithAttachmentsReady(held, ev);
            if (ready.isEmpty()) continue;
            Set<Id> batch = new Set<Id>();
            for (Id appId : ready) {
                if (batch.size() >= MAX_APPS_PER_EVENT) break;
                batch.add(appId);
            }
            if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) break;
            AA_MessageDispatcher.dispatchHeldResend(batch, ev);
            out.put(ev, batch);
        }
        return out;
    }
}