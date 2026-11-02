/**
 * PC1_MaryProgressCalculator — recomputes Mary_Progress_* on Application from
 * child PC1_Answer__c rows.
 *
 * Mary progress excludes declaration fields (decl, declname, decldate_*), which
 * only get filled at DWP submit time — they'd artificially depress Mary's
 * completion until then.
 *
 * Signature matches what Mary's tools will call: pass the Application Id and
 * we do all the aggregation + DML.
 */
public with sharing class PC1_MaryProgressCalculator {

    /** Fields that don't count toward Mary's collection progress. */
    private static final Set<String> DECLARATION_FIELDS = new Set<String>{
        'decl', 'declname', 'decldate_day', 'decldate_month', 'decldate_year'
    };

    // If you know the total Mary-collectable count from your form spec, put it
    // here — this class then computes the filled count. If total is 0 we
    // treat it as "not tracked" and skip the update (avoids divide-by-zero
    // false alarms while the schema is being wired up).
    private static final Integer DEFAULT_MARY_TOTAL = 70;

    public static void updateMaryProgress(Id appId) {
        Integer filled = 0;
        // NOTE: Value__c is a LongTextArea and can't be used in WHERE clauses.
        // Filter for non-null Value in-memory after the query.
        for (PC1_Answer__c a : [
            SELECT Field_Id__c, Value__c FROM PC1_Answer__c
            WHERE Application__c = :appId
        ]) {
            if (a.Value__c == null || a.Value__c == '') continue;
            if (!DECLARATION_FIELDS.contains(a.Field_Id__c)) filled++;
        }
        // Own only the Mary_Progress_* fields. Progress_Filled__c /
        // Progress_Total__c are the canonical flow-aware counters set by
        // PC1_FlowEngine via the Answer trigger — do NOT overwrite them here
        // with the naive 70-hardcoded number (that produced a flicker where
        // Mary tools reset the correct number until the trigger caught up).
        PC1_Application__c app = new PC1_Application__c(
            Id = appId,
            Mary_Progress_Filled__c = filled,
            Mary_Progress_Total__c = DEFAULT_MARY_TOTAL,
            Mary_Progress_Complete__c = (filled >= DEFAULT_MARY_TOTAL),
            Progress_Last_Updated__c = Datetime.now()
        );
        update app;
    }

    /**
     * Bulk variant — used by triggers to avoid governor-limit trouble when
     * many Answer rows are inserted at once (e.g. seed script inserting 100).
     */
    public static void updateMaryProgressBulk(Set<Id> appIds) {
        if (appIds.isEmpty()) return;
        Map<Id, Integer> filledByApp = new Map<Id, Integer>();
        for (Id appId : appIds) filledByApp.put(appId, 0);
        for (PC1_Answer__c a : [
            SELECT Application__c, Field_Id__c, Value__c FROM PC1_Answer__c
            WHERE Application__c IN :appIds
        ]) {
            if (a.Value__c == null || a.Value__c == '') continue;
            if (DECLARATION_FIELDS.contains(a.Field_Id__c)) continue;
            filledByApp.put(a.Application__c, filledByApp.get(a.Application__c) + 1);
        }
        List<PC1_Application__c> toUpdate = new List<PC1_Application__c>();
        for (Id appId : appIds) {
            Integer filled = filledByApp.get(appId);
            toUpdate.add(new PC1_Application__c(
                Id = appId,
                Mary_Progress_Filled__c = filled,
                Mary_Progress_Total__c = DEFAULT_MARY_TOTAL,
                Mary_Progress_Complete__c = (filled >= DEFAULT_MARY_TOTAL),
                Progress_Last_Updated__c = Datetime.now()
            ));
        }
        update toUpdate;
    }
}