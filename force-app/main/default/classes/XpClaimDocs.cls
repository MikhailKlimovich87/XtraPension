/**
 * Builds a Claim's documents as a user who may change its files (10/11/2026).
 *
 * The devs' generators (BP_GeneratePdfFileController, BP_ClientSummaryPdfService, BP_PortalUtils) run "with sharing", and
 * the claim's files belong to XtraPension Admin, linked to the claim as Viewer. A Senior Agent can then create a new file
 * but not add a version to an existing one (INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY, probed in the org 10/11/2026),
 * so a regeneration or a Send to Validation started by an agent failed silently on any claim that already had documents.
 *
 * request(): a user with Modify All Data (the portal's XtraPension Admin, the admins) queues the job right away, as before;
 * anyone else publishes Claim_Docs_Request__e, whose trigger runs as XtraPension Admin (PlatformEventSubscriberConfig
 * ClaimDocsRequestConfig) and queues the same job there.
 */
public without sharing class XpClaimDocs {

    public static final String PACK = 'pack';             // BP_GeneratePdfFileControllerQueueable: full forms, Summary, DD, Stage 1
    public static final String REGENERATE = 'regenerate'; // BP_RegeneratePackQueueable: the whole pack again after a data change

    @TestVisible
    private static Boolean forceEvent = false;

    public static Boolean request(Id claimId, String job) {
        if (claimId == null) {
            return false;
        }
        if (!forceEvent && canChangeAnyFile()) {
            return enqueue(claimId, job);
        }
        Database.SaveResult res = EventBus.publish(new Claim_Docs_Request__e(Claim_Id__c = claimId, Job__c = job));
        if (!res.isSuccess()) {
            System.debug(LoggingLevel.ERROR, 'Claim_Docs_Request__e not published for ' + claimId + ': ' + res.getErrors());
        }
        return res.isSuccess();
    }

    // Claim_Docs_Request__e trigger (runs as XtraPension Admin): one job per claim and kind
    public static void handle(List<Claim_Docs_Request__e> events) {
        Set<String> done = new Set<String>();
        for (Claim_Docs_Request__e e : events) {
            if (String.isBlank(e.Claim_Id__c) || !done.add(e.Claim_Id__c + '|' + e.Job__c)) {
                continue;
            }
            enqueue(Id.valueOf(e.Claim_Id__c), e.Job__c);
        }
    }

    private static Boolean enqueue(Id claimId, String job) {
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return false;
        }
        if (job == PACK) {
            System.enqueueJob(new BP_GeneratePdfFileControllerQueueable(claimId));
        } else {
            System.enqueueJob(new BP_RegeneratePackQueueable(claimId));
        }
        return true;
    }

    // Modify All Data, from the profile or a permission set (the profile's own permission set is in PermissionSetAssignment)
    private static Boolean canChangeAnyFile() {
        return [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.PermissionsModifyAllData = true
        ] > 0;
    }
}