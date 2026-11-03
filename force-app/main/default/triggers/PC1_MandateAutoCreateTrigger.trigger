/**
 * PC1_MandateAutoCreateTrigger — after update: enqueues
 * PC1_GoCardlessMandateQueueable the moment a PC1_Application__c crosses
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
 * Global bypass: PC1_Config__c.Auto_Create_DD_Mandate__c defaults true; set
 * to false at org level to freeze the automation during maintenance without
 * disabling the trigger metadata.
 *
 * Eligibility helper: PC1_MandateEligibility.isEligible(app). Kept in a
 * dedicated class so tests can call it directly and so future axes
 * (Client_Refused_DD, expired mandates …) don't clutter the trigger.
 */
trigger PC1_MandateAutoCreateTrigger on PC1_Application__c (after insert, after update) {
    // Cheap early-out: check the global bypass once per trigger fire.
    PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
    Boolean autoEnabled = (cfg == null || cfg.Auto_Create_DD_Mandate__c == null)
        ? true
        : cfg.Auto_Create_DD_Mandate__c;
    if (!autoEnabled) return;

    // Governor cap: Apex allows at most 50 Queueable enqueues per transaction.
    // We're one Queueable per newly-eligible record — leave headroom for other
    // triggers on the same object (e.g. PC1_MessageDispatcher async fire).
    Integer maxEnqueue = 40;
    Integer enqueued = 0;
    // Audit R6 meta-audit H13 fix: overflow rows are now handed to a
    // chained Queueable instead of being silently dropped. Prior code
    // logged a debug WARN and moved on — because prevEligible=true on the
    // next update, the record NEVER got another shot at enqueue = no
    // mandate + no welcome pack + no fee, forever, until manually
    // triggered. Bulk data loads > 40 eligible rows lost every overflow.
    List<Id> overflowIds = new List<Id>();

    for (PC1_Application__c app : Trigger.new) {
        Boolean nowEligible  = PC1_MandateEligibility.isEligible(app);
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
            PC1_Application__c prev = Trigger.oldMap.get(app.Id);
            prevEligible = PC1_MandateEligibility.isEligible(prev);
        }
        if (!nowEligible || prevEligible) continue;

        if (enqueued >= maxEnqueue) {
            overflowIds.add(app.Id);
            continue;
        }
        System.enqueueJob(new PC1_GoCardlessMandateQueueable(app.Id));
        enqueued++;
    }
    // Overflow: enqueue ONE Queueable that iterates the remainder in its
    // own transaction (fresh 50-enqueue budget). Self-chains if needed.
    if (!overflowIds.isEmpty()) {
        System.enqueueJob(new PC1_MandateOverflowQueueable(overflowIds));
    }
}