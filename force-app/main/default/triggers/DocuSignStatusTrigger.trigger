trigger DocuSignStatusTrigger on dfsle__EnvelopeStatus__c (after insert, after update) {

    if (Trigger.isAfter && Trigger.isInsert) {
        DocuSignStatusTriggerHelper.afterInsert(Trigger.new);
    }
}