/**
 * AA_ProgressRecomputeBatch: recompute the stored "what is missing" figures
 * (Progress_Filled__c, Progress_Total__c, Progress_Missing_Sections__c,
 * Progress_Last_Updated__c) of every open application.
 *
 * Why (audit 2026-11-11 AA-APEX-9): those figures are only recomputed when an
 * AA_Answer__c row of the application changes (AA_AnswerTrigger). After a
 * deploy of the aaFlowConfig static resource or of AA_FlowEngine, every
 * application nobody has touched since still shows the list computed by the
 * old flow. On 2026-11-11 all 11 applications carried figures from 08/10,
 * older than the flow of 22/10 and the engine of 29/10.
 *
 * Run it once after each such deploy, as an administrator (anonymous Apex):
 *
 *     Database.executeBatch(new AA_ProgressRecomputeBatch(), 20);
 *
 * It calls AA_ProgressCalculator.recompute, the same entry point the answer
 * trigger uses, so it writes nothing the next answer save would not write. It
 * makes no callout and sends no message. Closed cases are left as they are.
 */
public with sharing class AA_ProgressRecomputeBatch implements Database.Batchable<SObject> {

    @TestVisible private static final Set<String> CLOSED_STAGES = new Set<String>{
        'Closed - Paid', 'Closed - Refused', 'Closed - Fee Failed'
    };

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM AA_Application__c WHERE Stage__c NOT IN :CLOSED_STAGES
        ]);
    }

    public void execute(Database.BatchableContext bc, List<AA_Application__c> scope) {
        Set<Id> appIds = new Set<Id>();
        for (AA_Application__c a : scope) appIds.add(a.Id);
        Map<Id, String> notWritten = AA_ProgressCalculator.recompute(appIds);
        for (Id appId : notWritten.keySet()) {
            System.debug(LoggingLevel.ERROR, 'AA_ProgressRecomputeBatch: ' + appId + ' not updated: ' + notWritten.get(appId));
        }
    }

    public void finish(Database.BatchableContext bc) {}
}