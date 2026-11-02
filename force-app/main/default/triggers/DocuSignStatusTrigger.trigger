trigger DocuSignStatusTrigger on dfsle__EnvelopeStatus__c (after insert, after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        DocuSignStatusTriggerHelper.afterInsert(Trigger.new);
    }

    // Moves a claim to "Signed - Waiting Docs at WDM" only when both envelopes are completed
    // and returns it to the agent when an envelope is declined, voided or expired.
    // Must never break the DocuSign write-back, but a failure must not be silent either:
    // the claim would stay in "Sent for eSignature" with nobody knowing why.
    try {
        BP_DocuSignEnvelopes.process(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    } catch (Exception ex) {
        System.debug(LoggingLevel.ERROR, 'BP_DocuSignEnvelopes.process failed: ' + ex.getMessage());
        BP_DocuSignEnvelopes.logFailure(ex);
    }
}