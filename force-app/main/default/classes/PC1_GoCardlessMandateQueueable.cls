/**
 * PC1_GoCardlessMandateQueueable — async wrapper around
 * PC1_GoCardlessController.createMandateForApplication.
 *
 * Fired from PC1_MandateAutoCreateTrigger when a PC1_Application__c crosses
 * the "bank verified + DD terms read + no existing mandate" line so we can
 * do the HTTP callout from the update-trigger context (Apex bans callouts in
 * synchronous trigger context).
 *
 * Failures are absorbed here — the LWC path re-throws AuraHandledException
 * because a live operator wants immediate feedback, but on the automated
 * trigger path the controller's persisted failure trail (Stage_Log +
 * DD_Mandate_Failure_Reason__c) is enough. Bubbling out of the Queueable
 * would leave a red row in the async job log with no way for the user to
 * retry beyond re-toggling the checkbox.
 */
public with sharing class PC1_GoCardlessMandateQueueable implements Queueable, Database.AllowsCallouts {
    private final Id applicationId;

    public PC1_GoCardlessMandateQueueable(Id applicationId) {
        this.applicationId = applicationId;
    }

    public void execute(QueueableContext ctx) {
        try {
            PC1_GoCardlessController.createMandateForApplication(this.applicationId);
        } catch (Exception e) {
            // Controller already stamped DD_Mandate_Failure_Reason__c + wrote
            // the Stage_Log. Log to system.debug so it shows in async job logs.
            System.debug(LoggingLevel.WARN,
                'PC1_GoCardlessMandateQueueable — mandate create failed for ' + this.applicationId + ': ' + e.getMessage());
        }
    }
}