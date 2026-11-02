/**
 * PC1_ProgressCalculator — recomputes Progress_Filled__c / Progress_Total__c
 * (and the new Progress_Missing_Sections__c JSON) on PC1_Application__c from
 * its child PC1_Answer__c rows.
 *
 * Phase 2 rewrite: hardcoded TOTAL=67 is gone. All the real work lives in
 * PC1_FlowEngine — this class is now a thin trigger-facing shim that keeps
 * the existing entry-point signature (recompute(Set<Id>)) so PC1_AnswerTrigger
 * needs no change.
 *
 * Filled = fields whose answer is non-empty for the branch this application
 *          is actually walking, including Source__c='default' policy pre-fills
 *          (per Phase 1 Q2). Declaration fields (decl/declname/decldate) never
 *          count (per Phase 1 Q3).
 * Total  = the number of fields the walker will ask on this branch — 48 on the
 *          happy single-adult path, 30-something on early stages, more when a
 *          partner or shares expand the flow.
 */
public with sharing class PC1_ProgressCalculator {

    /** Recompute progress for a set of Application Ids. Bulk-safe. */
    public static void recompute(Set<Id> appIds) {
        if (appIds == null || appIds.isEmpty()) return;
        PC1_FlowEngine.recomputeAndUpdate(appIds);
    }
}