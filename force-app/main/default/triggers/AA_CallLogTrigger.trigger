/**
 * AA_CallLogTrigger — mirror the newest call onto the parent Application's
 * Last_Contact_* fields. Runs after insert + after update so any late-
 * arriving webhook (Nuacom poll bumping Ended_At__c, ElevenLabs post-call
 * closing an in_progress row) also refreshes the card. AA_LastContactUpdater
 * enforces the latest-wins gate so out-of-order events don't regress the
 * displayed values.
 */
trigger AA_CallLogTrigger on AA_Call_Log__c (after insert, after update) {
    AA_LastContactUpdater.fromCallLogs(Trigger.new);
}