/**
 * PC1_CallLogTrigger — mirror the newest call onto the parent Application's
 * Last_Contact_* fields. Runs after insert + after update so any late-
 * arriving webhook (Nuacom poll bumping Ended_At__c, ElevenLabs post-call
 * closing an in_progress row) also refreshes the card. PC1_LastContactUpdater
 * enforces the latest-wins gate so out-of-order events don't regress the
 * displayed values.
 */
trigger PC1_CallLogTrigger on PC1_Call_Log__c (after insert, after update) {
    PC1_LastContactUpdater.fromCallLogs(Trigger.new);
}