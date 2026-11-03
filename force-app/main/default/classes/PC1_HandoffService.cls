/**
 * PC1_HandoffService — @AuraEnabled Apex bridge for the pc1HandoffCard LWC.
 * Kept separate from the REST endpoint classes so LWC ↔ Apex traffic doesn't
 * confuse anyone looking at REST logs.
 */
public with sharing class PC1_HandoffService {

    @AuraEnabled(cacheable=true)
    public static PC1_Handoff__c getLatestOpenHandoff(Id applicationId) {
        List<PC1_Handoff__c> l = [
            SELECT Id, Escalation_Type__c, Reason__c, Last_Field_Id__c, Last_Field_Question__c,
                   Client_Verbatim__c, Attempted_Value__c, Next_Step_Suggestion__c, CreatedDate
            FROM PC1_Handoff__c
            WHERE Application__c = :applicationId AND Resolved__c = false
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return l.isEmpty() ? null : l[0];
    }

    @AuraEnabled
    public static void markResolved(Id handoffId) {
        update new PC1_Handoff__c(Id = handoffId, Resolved__c = true, Reviewed_At__c = Datetime.now(), Reviewed_By__c = UserInfo.getUserId());
    }

    @AuraEnabled(cacheable=true)
    public static PC1_Fill_Run__c getLatestFillRun(Id applicationId) {
        List<PC1_Fill_Run__c> l = [
            SELECT Id, Status__c, Current_Step__c, Total_Steps__c, Current_Page__c, Progress_Percent__c,
                   Duration_Min__c, Live_View_URL__c, Screenshot_URL__c, Error_Message__c,
                   Started_At__c, Finished_At__c
            FROM PC1_Fill_Run__c
            WHERE Application__c = :applicationId
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        return l.isEmpty() ? null : l[0];
    }

    /**
     * getFillRunPanelData — everything pc1FillRunPanel needs in one @wire.
     *
     * Returns:
     *   - latest PC1_Fill_Run__c (may be null if never filled)
     *   - PC1_Application__c.Stage__c + Declaration_Complete__c so the LWC can
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
        List<PC1_Application__c> apps = [
            SELECT Stage__c, Declaration_Complete__c
              FROM PC1_Application__c
             WHERE Id = :applicationId LIMIT 1
        ];
        if (!apps.isEmpty()) {
            r.stage = apps[0].Stage__c;
            r.declarationComplete = apps[0].Declaration_Complete__c;
        }
        List<PC1_Fill_Run__c> l = [
            SELECT Id, Status__c, Current_Step__c, Total_Steps__c, Current_Page__c, Progress_Percent__c,
                   Duration_Min__c, Live_View_URL__c, Screenshot_URL__c, Error_Message__c,
                   Started_At__c, Finished_At__c
              FROM PC1_Fill_Run__c
             WHERE Application__c = :applicationId
             ORDER BY CreatedDate DESC LIMIT 1
        ];
        r.fillRun = l.isEmpty() ? null : l[0];
        return r;
    }

    public class FillRunPanelData {
        @AuraEnabled public PC1_Fill_Run__c fillRun;
        @AuraEnabled public String stage;
        @AuraEnabled public Boolean declarationComplete;
    }
}