/**
 * PC1_StageTransitionHelper — stamps Stage_Changed_At and writes a
 * PC1_Stage_Log__c audit row every time Stage__c changes.
 *
 * State-machine guardrail removed 2026-07-30 per Fernando: he needs to be
 * able to move Applications through any stage he wants without being
 * blocked by a validation rule. The audit trail below still records every
 * transition so we can reconstruct history + spot unusual patterns; only
 * the "Illegal Stage transition" hard block is gone.
 */
public with sharing class PC1_StageTransitionHelper {

    /** Optional note for the NEXT transition logged in this transaction —
     *  set by callers that change the stage on purpose (record-page Stage
     *  button) so their note lands on the single audit row instead of a
     *  second, duplicate row. Cleared after use. */
    public static String pendingNote;

    public static void handleTransitions(List<PC1_Application__c> newList, Map<Id, PC1_Application__c> oldMap) {
        List<PC1_Stage_Log__c> logs = new List<PC1_Stage_Log__c>();
        Set<Id> submittedIds = new Set<Id>();
        Datetime now = Datetime.now();
        Id userId = UserInfo.getUserId();

        for (PC1_Application__c app : newList) {
            PC1_Application__c prev = oldMap.get(app.Id);
            if (app.Stage__c == prev.Stage__c) continue;

            app.Stage_Changed_At__c = now;
            logs.add(new PC1_Stage_Log__c(
                Application__c = app.Id,
                From_Stage__c  = prev.Stage__c,
                To_Stage__c    = app.Stage__c,
                Actor__c       = 'human',
                Note__c        = String.isBlank(pendingNote) ? null : pendingNote.left(255),
                Changed_At__c  = now,
                Changed_By__c  = userId
            ));

            // Message dispatcher hook — fire the "Application Submitted to DWP"
            // template pack when an app transitions INTO Submitted. Only with
            // a DWP reference on the record (the autofill writes it in the same
            // update): a manual move without one used to email the client a
            // submission notice for a claim nobody had confirmed was filed.
            if ('Submitted'.equalsIgnoreCase(app.Stage__c) && String.isNotBlank(app.DWP_Reference__c)) {
                submittedIds.add(app.Id);
            }
        }
        pendingNote = null;

        // Once per application: moving out of Submitted and back in (a
        // correction) must not send the client a second notice.
        if (!submittedIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Application__c a FROM PC1_Stage_Log__c
                 WHERE Application__c IN :submittedIds AND To_Stage__c = 'Submitted'
                 GROUP BY Application__c
            ]) {
                submittedIds.remove((Id) ar.get('a'));
            }
        }
        if (!logs.isEmpty()) insert logs;
        if (!submittedIds.isEmpty()) {
            PC1_MessageDispatcher.dispatch(submittedIds, 'Application_Submitted_DWP');
        }
    }
}