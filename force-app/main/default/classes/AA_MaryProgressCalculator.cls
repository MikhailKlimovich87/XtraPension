/**
 * AA_MaryProgressCalculator — RETIRED (audit 2026-10-02 F44/F177).
 *
 * It used to write Mary_Progress_Filled__c / Mary_Progress_Total__c by counting
 * every non-empty, non-declaration answer against a hard-coded total of 70
 * (live AA00058 showed 79/70). Nothing read those counters, and its plain
 * `update` could fail an answer save on any Application validation rule. The
 * real, flow-aware counters are Progress_* (AA_FlowEngine via
 * AA_AnswerTrigger); Mary_Progress_Complete__c is owned by mark-complete.
 *
 * Every caller has been removed. The methods are kept as no-ops only so the
 * class compiles without the retired fields until it is deleted from the org
 * with a destructive change (then delete this file too).
 */
public with sharing class AA_MaryProgressCalculator {

    /** No-op. Retired; see class header. */
    public static void updateMaryProgress(Id appId) {
        return;
    }

    /** No-op. Retired; see class header. */
    public static void updateMaryProgressBulk(Set<Id> appIds) {
        return;
    }
}