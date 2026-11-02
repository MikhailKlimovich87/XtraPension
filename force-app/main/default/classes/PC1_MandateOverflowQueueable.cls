/**
 * PC1_MandateOverflowQueueable — audit R6 meta-audit H13 helper.
 *
 * PC1_MandateAutoCreateTrigger caps at 40 direct enqueues to leave headroom
 * for other triggers (Apex synchronous transaction limit is 50). Overflow
 * used to be silently dropped — this Queueable picks up the remainder and
 * enqueues one PC1_GoCardlessMandateQueueable per app id, self-chaining
 * when the payload exceeds 45 rows.
 *
 * Chain rule: enqueue up to 45 per fire (buffer of 5 for the follow-up
 * chain enqueue + other framework overhead), stash the remainder in a
 * fresh instance and enqueue that.
 */
public with sharing class PC1_MandateOverflowQueueable
    implements Queueable, Database.AllowsCallouts {

    // Audit R7-H8 fix: from a Queueable context only ONE System.enqueueJob
    // is allowed per fire — the previous version tried to enqueue ONE
    // PC1_GoCardlessMandateQueueable per app in a loop, hitting the
    // uncatchable LimitException on the second call. Now: process ONE
    // app INLINE per fire (calling the same createMandateForApplication
    // as PC1_GoCardlessMandateQueueable), then self-chain the remainder
    // as the single allowed enqueue. Slower (1/fire vs N/fire) but
    // actually completes for arbitrary backlog.

    @TestVisible
    private List<Id> appIds;

    public PC1_MandateOverflowQueueable(List<Id> appIds) {
        this.appIds = (appIds == null) ? new List<Id>() : appIds;
    }

    public void execute(QueueableContext ctx) {
        if (appIds == null || appIds.isEmpty()) return;

        Id current = appIds[0];
        try {
            PC1_GoCardlessController.createMandateForApplication(current);
            System.debug(LoggingLevel.INFO,
                'PC1_MandateOverflowQueueable: created mandate for ' + current +
                ' (remaining backlog=' + (appIds.size() - 1) + ')');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'PC1_MandateOverflowQueueable: createMandate failed for ' + current +
                ' — ' + e.getMessage() + '. Continuing chain.');
        }

        // Self-chain the remainder — the ONE allowed enqueue per fire.
        if (appIds.size() > 1) {
            List<Id> remainder = new List<Id>();
            for (Integer i = 1; i < appIds.size(); i++) remainder.add(appIds[i]);
            try {
                System.enqueueJob(new PC1_MandateOverflowQueueable(remainder));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'PC1_MandateOverflowQueueable: self-chain enqueue failed — ' +
                    e.getMessage() + '. ' + remainder.size() + ' apps stranded.');
            }
        }
    }
}