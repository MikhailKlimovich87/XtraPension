/**
 * AA_LastContactUpdater — bulk-safe helper that mirrors the latest
 * AA_Call_Log__c contact onto its parent AA_Application__c's Last_Contact_*
 * fields.
 *
 * Called from AA_CallLogTrigger (after insert, after update). Also callable
 * from Node webhooks that create WhatsApp/Email/SMS rows in other objects —
 * those routes bypass Call Log entirely and call this helper via composite
 * REST + a small Apex REST wrapper (not implemented here; Node uses jsforce
 * .sobject().update directly for the WhatsApp path).
 *
 * Contract (2026-10-29 call-history audit):
 *   - Not a contact (never mirrored):
 *       Personalization_Only__c = true (a ring that never became a call)
 *       Status in_progress / queued / blank (still open; mirrored when closed)
 *       inbound call nobody at XtraPension answered (missed call, or the
 *       client left us a voicemail) — it used to show the extension that
 *       only rang as "Who"
 *   - Contact Type:
 *       outbound with Voicemail_Left__c          → 'V/Mail Left'
 *       completed / rescheduled                  → 'Phone Chat'
 *       outbound no_answer / failed              → 'No Answer'
 *     The voicemail rule comes before any Source check: a Mary call that
 *     reached voicemail used to show 'Phone Chat'. No answer is not a voicemail:
 *     only Mary's calls say whether one was left (Fernando, 30/10/2026, after
 *     Fiona saw the same mistake on the XtraPension Sales records).
 *   - Who: Rep_Name__c if set, else Source__c ('Mary' / 'Human')
 *   - Date: DATE(Started_At__c); At: Started_At__c
 *   - Latest-wins gate: a call older than Last_Contact_At__c is ignored. The
 *     SAME Started_At__c re-derives, so a row that is closed later (Mary's
 *     in_progress → no_answer) refreshes the card. Unchanged values are not
 *     re-written.
 *   - allOrNone=false (audit F83): a rejected Application update must not
 *     roll back the call-log insert that fired the trigger. While a Pending
 *     slot sat in the past, the Next_Call_At_In_Future validation rule
 *     rejected every Application update, so ElevenLabs/Nuacom call logs and
 *     the reaper's closes were lost with it.
 */
public with sharing class AA_LastContactUpdater {

    /** Entry point for the Call Log trigger. Bulk-safe. */
    public static void fromCallLogs(List<AA_Call_Log__c> newRows) {
        if (newRows == null || newRows.isEmpty()) return;

        // Collapse Trigger.new to (AppId → newest row that is a contact).
        Map<Id, AA_Call_Log__c> bestByApp = new Map<Id, AA_Call_Log__c>();
        for (AA_Call_Log__c cl : newRows) {
            if (cl.Application__c == null || cl.Started_At__c == null) continue;
            if (deriveType(cl) == null) continue;
            AA_Call_Log__c prev = bestByApp.get(cl.Application__c);
            if (prev == null || cl.Started_At__c > prev.Started_At__c) {
                bestByApp.put(cl.Application__c, cl);
            }
        }
        if (bestByApp.isEmpty()) return;

        Map<Id, AA_Application__c> apps = new Map<Id, AA_Application__c>([
            SELECT Id, Last_Contact_At__c, Last_Contact_Type__c, Last_Contact_Who__c
              FROM AA_Application__c WHERE Id IN :bestByApp.keySet()
        ]);

        List<AA_Application__c> toUpdate = new List<AA_Application__c>();
        for (Id appId : bestByApp.keySet()) {
            AA_Application__c app = apps.get(appId);
            if (app == null) continue;
            AA_Call_Log__c cl = bestByApp.get(appId);

            if (app.Last_Contact_At__c != null && app.Last_Contact_At__c > cl.Started_At__c) {
                continue; // older signal, ignore
            }

            String contactType = deriveType(cl);
            String who         = deriveWho(cl);
            if (app.Last_Contact_At__c == cl.Started_At__c
                && app.Last_Contact_Type__c == contactType
                && app.Last_Contact_Who__c == who) {
                continue; // nothing changed
            }

            toUpdate.add(new AA_Application__c(
                Id                    = appId,
                Last_Contact_Type__c  = contactType,
                Last_Contact_Who__c   = who,
                Last_Contact_Date__c  = cl.Started_At__c.date(),
                Last_Contact_At__c    = cl.Started_At__c
            ));
        }
        if (toUpdate.isEmpty()) return;
        Database.SaveResult[] results = Database.update(toUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                String errs = '';
                for (Database.Error err : results[i].getErrors()) errs += err.getMessage() + '; ';
                System.debug(LoggingLevel.WARN, 'AA_LastContactUpdater: Last Contact not mirrored for '
                    + toUpdate[i].Id + ': ' + errs);
            }
        }
    }

    /**
     * Contact type for one call, or null when the call is not a contact
     * (see the contract above).
     */
    @TestVisible
    private static String deriveType(AA_Call_Log__c cl) {
        if (cl == null || cl.Personalization_Only__c == true) return null;
        String status = cl.Status__c == null ? '' : cl.Status__c.trim().toLowerCase();
        String dir    = cl.Direction__c == null ? '' : cl.Direction__c.trim().toLowerCase();
        Boolean inbound = dir.startsWith('inbound');
        Boolean voicemail = cl.Voicemail_Left__c == true;

        if (status == '' || status == 'in_progress' || status == 'queued') return null;
        if (!inbound && voicemail) return 'V/Mail Left';
        if (status == 'completed' || status == 'rescheduled') {
            return (inbound && voicemail) ? null : 'Phone Chat';
        }
        if (!inbound && (status == 'no_answer' || status == 'failed')) return 'No Answer';
        return null; // inbound nobody answered
    }

    /**
     * Who = Rep_Name__c when set (the rep from Nuacom), else Source__c
     * ('Mary' for AI calls, 'Human' when Nuacom had no rep name).
     */
    @TestVisible
    private static String deriveWho(AA_Call_Log__c cl) {
        String src = cl.Source__c == null ? '' : cl.Source__c.trim();
        String rep = cl.Rep_Name__c == null ? '' : cl.Rep_Name__c.trim();
        // Last_Contact_Who__c is unrestricted (2026-08-01), so any name lands.
        if (String.isNotBlank(rep)) return rep;
        if (String.isNotBlank(src)) return src;
        return null;
    }
}