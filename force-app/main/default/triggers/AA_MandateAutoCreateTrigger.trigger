/**
 * AA_MandateAutoCreateTrigger — after update: enqueues
 * AA_GoCardlessMandateQueueable the moment a AA_Application__c crosses
 * the "eligible for auto-mandate" line.
 *
 * Eligibility (all three must be true NOW and were NOT all-true before):
 *   1. Bank_Verification_Status__c == 'Modulus Passed'
 *   2. DD_Terms_Read_By_Sales__c   == true
 *   3. DD_Mandate_Id__c            IS null
 *
 * The transition check keeps unrelated field updates on already-eligible
 * records from re-enqueueing (idempotency guardrail against the mandate
 * being created twice — the endpoint is also idempotent on sf_app_id, but
 * we still don't want a Queueable per unrelated save).
 *
 * Global bypass: AA_Config__c.Auto_Create_DD_Mandate__c defaults true; set
 * to false at org level to freeze the automation during maintenance without
 * disabling the trigger metadata.
 *
 * Eligibility helper: AA_MandateEligibility.isEligible(app). Kept in a
 * dedicated class so tests can call it directly and so future axes
 * (Client_Refused_DD, expired mandates …) don't clutter the trigger.
 */
trigger AA_MandateAutoCreateTrigger on AA_Application__c (after insert, after update) {
    // Cheap early-out: check the global bypass once per trigger fire.
    AA_Config__c cfg = AA_Config__c.getOrgDefaults();
    Boolean autoEnabled = (cfg == null || cfg.Auto_Create_DD_Mandate__c == null)
        ? true
        : cfg.Auto_Create_DD_Mandate__c;
    if (!autoEnabled) return;

    // Governor cap: Apex allows at most 50 Queueable enqueues per transaction.
    // We're one Queueable per newly-eligible record — leave headroom for other
    // triggers on the same object (e.g. AA_MessageDispatcher async fire).
    Integer maxEnqueue = 40;
    Integer enqueued = 0;

    for (AA_Application__c app : Trigger.new) {
        Boolean nowEligible  = AA_MandateEligibility.isEligible(app);
        // On INSERT (Trigger.oldMap is null), any newly-inserted app that is
        // already eligible (bank verified + DD terms read on the SAME insert
        // — the intake path) counts as "just became eligible" → enqueue.
        // On UPDATE, only fire when the record CROSSES the line — prevents
        // re-enqueueing when unrelated field updates land on an already-
        // eligible row (endpoint is idempotent on sf_app_id, but we still
        // don't want a Queueable per unrelated save).
        Boolean prevEligible;
        if (Trigger.isInsert) {
            prevEligible = false; // no prior state; treat as "not eligible before"
        } else {
            AA_Application__c prev = Trigger.oldMap.get(app.Id);
            prevEligible = AA_MandateEligibility.isEligible(prev);
        }
        if (!nowEligible || prevEligible) continue;

        if (enqueued >= maxEnqueue) {
            // Rare (bulk import scenario); log so ops can trigger manually.
            System.debug(LoggingLevel.WARN,
                'AA_MandateAutoCreateTrigger — enqueue cap hit; skipping ' + app.Id);
            continue;
        }
        System.enqueueJob(new AA_GoCardlessMandateQueueable(app.Id));
        enqueued++;
    }
}