// Runs as XtraPension Admin (PlatformEventSubscriberConfig ClaimDocsRequestConfig): builds the claim's documents for a
// user who cannot change its files (XpClaimDocs, 10/11/2026).
trigger ClaimDocsRequestTrigger on Claim_Docs_Request__e (after insert) {
    XpClaimDocs.handle(Trigger.new);
}