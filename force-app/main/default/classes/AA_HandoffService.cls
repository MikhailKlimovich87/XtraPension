/**
 * AA_HandoffService — @AuraEnabled Apex bridge for the aaHandoffCard LWC.
 * Kept separate from the REST endpoint classes so LWC ↔ Apex traffic doesn't
 * confuse anyone looking at REST logs.
 */
public with sharing class AA_HandoffService {

    @AuraEnabled(cacheable=true)
    public static AA_Handoff__c getLatestOpenHandoff(Id applicationId) {
        List<AA_Handoff__c> l = [
            SELECT Id, Escalation_Type__c, Reason__c, Last_Field_Id__c, Last_Field_Question__c,
                   Client_Verbatim__c, Attempted_Value__c, Next_Step_Suggestion__c, CreatedDate
            FROM AA_Handoff__c
            WHERE Application__c = :applicationId AND Resolved__c = false
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return l.isEmpty() ? null : l[0];
    }

    @AuraEnabled
    public static void markResolved(Id handoffId) {
        update new AA_Handoff__c(Id = handoffId, Resolved__c = true, Reviewed_At__c = Datetime.now(), Reviewed_By__c = UserInfo.getUserId());
    }

    @AuraEnabled(cacheable=true)
    public static AA_Fill_Run__c getLatestFillRun(Id applicationId) {
        List<AA_Fill_Run__c> l = [
            SELECT Id, Status__c, Current_Step__c, Total_Steps__c, Current_Page__c, Progress_Percent__c,
                   Duration_Min__c, Live_View_URL__c, Screenshot_URL__c, Error_Message__c,
                   Started_At__c, Finished_At__c
            FROM AA_Fill_Run__c
            WHERE Application__c = :applicationId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return l.isEmpty() ? null : l[0];
    }

    /**
     * getFillRunPanelData — everything aaFillRunPanel needs in one @wire.
     *
     * Returns:
     *   - latest AA_Fill_Run__c (may be null if never filled)
     *   - AA_Application__c.Stage__c + Declaration_Complete__c so the LWC can
     *     decide whether to show a friendly "gate" message ("Fill will run
     *     once data is complete and declaration is signed") instead of the
     *     confusing technical failure of an attempt that was blocked by the
     *     engine's own missing-field check.
     *
     * Gate rationale: pre-Data-Complete fills fail with
     *   "No answer in the data for required question — (start): …"
     * which reads as a system error to Fernando/ops. Semantically it's a
     * precondition, not a failure — surface it as such.
     */
    @AuraEnabled(cacheable=true)
    public static FillRunPanelData getFillRunPanelData(Id applicationId) {
        FillRunPanelData r = new FillRunPanelData();
        List<AA_Application__c> apps = [
            SELECT Stage__c, Declaration_Complete__c
              FROM AA_Application__c
             WHERE Id = :applicationId LIMIT 1
        ];
        if (!apps.isEmpty()) {
            r.stage = apps[0].Stage__c;
            r.declarationComplete = apps[0].Declaration_Complete__c;
        }
        List<AA_Fill_Run__c> l = [
            SELECT Id, Status__c, Current_Step__c, Total_Steps__c, Current_Page__c, Progress_Percent__c,
                   Duration_Min__c, Live_View_URL__c, Screenshot_URL__c, Error_Message__c,
                   Started_At__c, Finished_At__c
              FROM AA_Fill_Run__c
             WHERE Application__c = :applicationId
             ORDER BY CreatedDate DESC LIMIT 1
        ];
        r.fillRun = l.isEmpty() ? null : l[0];
        return r;
    }

    public class FillRunPanelData {
        @AuraEnabled public AA_Fill_Run__c fillRun;
        @AuraEnabled public String stage;
        @AuraEnabled public Boolean declarationComplete;
    }

    // ─────────────────────── ops notifications ───────────────────────
    // Audit 2026-10-02 F75: escalations (Mary's flag_for_human, a stage move
    // to Needs Human) only posted a Chatter FeedItem, and nobody follows
    // AA_Application__c records (0 EntitySubscription rows), so a safeguarding
    // or distress report reached no one. These helpers also email the ops
    // mailbox, AA_Config__c.Admin_Alert_Email__c (the same recipient as
    // AA_AdminAlertREST). Best-effort by design: an email failure must never
    // roll back the handoff or the stage change that triggered it.

    /** Escalation types that put "URGENT" at the front of the subject. */
    @TestVisible
    private static final Set<String> URGENT_TYPES = new Set<String>{
        'safeguarding', 'distress', 'deceased', 'bereavement', 'complaint'
    };

    /** Last ops email built in this transaction (tests assert on it). */
    @TestVisible private static Messaging.SingleEmailMessage lastOpsEmail;

    /** Email one handoff digest per trigger batch. Never throws. */
    public static void notifyEscalations(List<AA_Handoff__c> handoffs) {
        try {
            if (handoffs == null || handoffs.isEmpty()) return;
            Set<Id> appIds = new Set<Id>();
            for (AA_Handoff__c h : handoffs) if (h.Application__c != null) appIds.add(h.Application__c);
            Map<Id, AA_Application__c> apps = new Map<Id, AA_Application__c>(
                [SELECT Id, Name, Full_Name__c, Phone__c FROM AA_Application__c WHERE Id IN :appIds]);
            Boolean urgent = false;
            List<String> lines = new List<String>();
            for (AA_Handoff__c h : handoffs) {
                String etype = String.isBlank(h.Escalation_Type__c) ? 'unknown' : h.Escalation_Type__c;
                if (URGENT_TYPES.contains(etype)) urgent = true;
                AA_Application__c a = apps.get(h.Application__c);
                lines.add(describeApp(a, h.Application__c)
                    + '\n  Escalation: ' + etype
                    + '\n  Reason: ' + (String.isBlank(h.Reason__c) ? '(none given)' : h.Reason__c)
                    + (String.isBlank(h.Next_Step_Suggestion__c) ? '' : '\n  Suggested next step: ' + h.Next_Step_Suggestion__c));
            }
            String subject = (urgent ? 'URGENT ' : '') + 'AA escalation: '
                + (handoffs.size() == 1
                    ? (String.isBlank(handoffs[0].Escalation_Type__c) ? 'unknown' : handoffs[0].Escalation_Type__c)
                      + ' on ' + nameOf(apps.get(handoffs[0].Application__c))
                    : handoffs.size() + ' new handoffs');
            emailOps(subject,
                'A client needs a human. Please review and resolve the handoff on the application.\n\n'
                + String.join(lines, '\n\n'));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AA_HandoffService.notifyEscalations failed: ' + e.getMessage());
        }
    }

    /** Email ops about apps moved to Needs Human without a fresh handoff. Never throws. */
    public static void notifyNeedsHuman(Set<Id> appIds) {
        try {
            if (appIds == null || appIds.isEmpty()) return;
            List<String> lines = new List<String>();
            for (AA_Application__c a : [SELECT Id, Name, Full_Name__c, Phone__c FROM AA_Application__c WHERE Id IN :appIds]) {
                lines.add(describeApp(a, a.Id));
            }
            emailOps('AA: ' + appIds.size() + ' application(s) moved to Needs Human',
                'These applications were moved to Needs Human without a new handoff record '
                + '(for example an operator move or the missed-call limit). Please review.\n\n'
                + String.join(lines, '\n\n'));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AA_HandoffService.notifyNeedsHuman failed: ' + e.getMessage());
        }
    }

    /**
     * Plain-text email to AA_Config__c.Admin_Alert_Email__c. Returns true when
     * Salesforce accepted it. Never throws. Also used by AA_MessageDispatcher
     * for client emails held back for a missing attachment.
     */
    public static Boolean emailOps(String subject, String body) {
        try {
            AA_Config__c cfg = AA_Config__c.getOrgDefaults();
            String to = (cfg == null || String.isBlank(cfg.Admin_Alert_Email__c)) ? null : cfg.Admin_Alert_Email__c.trim();
            if (String.isBlank(to)) {
                System.debug(LoggingLevel.WARN, 'AA_HandoffService.emailOps: Admin_Alert_Email__c not set; alert dropped: ' + subject);
                return false;
            }
            if (Limits.getEmailInvocations() >= Limits.getLimitEmailInvocations()) {
                System.debug(LoggingLevel.WARN, 'AA_HandoffService.emailOps: email invocation limit reached; alert dropped: ' + subject);
                return false;
            }
            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ to });
            msg.setSubject(subject == null ? 'AA alert' : subject.left(250));
            msg.setPlainTextBody(body == null ? '' : body.left(100000));
            msg.setSaveAsActivity(false);
            msg.setUseSignature(false);
            lastOpsEmail = msg;
            Messaging.SendEmailResult[] r = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
            if (!r[0].isSuccess()) {
                System.debug(LoggingLevel.WARN, 'AA_HandoffService.emailOps not accepted: ' + r[0].getErrors()[0].getMessage());
                return false;
            }
            return true;
        } catch (Exception e) {
            // e.g. deliverability set to "System email only" in a sandbox.
            System.debug(LoggingLevel.WARN, 'AA_HandoffService.emailOps failed: ' + e.getMessage());
            return false;
        }
    }

    private static String nameOf(AA_Application__c a) {
        return a == null ? '(unknown application)' : a.Name;
    }

    private static String describeApp(AA_Application__c a, Id appId) {
        String link = appId == null ? '' : URL.getOrgDomainUrl().toExternalForm() + '/' + appId;
        if (a == null) return '(application ' + appId + ') ' + link;
        return a.Name + ' ' + (String.isBlank(a.Full_Name__c) ? '' : a.Full_Name__c)
            + (String.isBlank(a.Phone__c) ? '' : ', ' + a.Phone__c)
            + '\n  ' + link;
    }
}