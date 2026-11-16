/**
 * "Send to Validation" button on the Claim page (header, Form In Progress / Validation Call / Pending Client).
 *
 * Same rule as the long form's Summary button (BP_PortalUtils.settleAfterSubmit, 10/11/2026): nothing missing ->
 * Form completed and the documents are built; anything missing -> Pending Client, with the list in Missing_Info__c for
 * the validation agent. The long form saves itself every minute (the lists too, since 10/11/2026), so the sales agent
 * can finish here while the portal's Summary still blocks the send on empty fields.
 */
public with sharing class XpClaimSendToValidation {

    public static final Set<String> FROM_STAGES = new Set<String>{ 'Form In Progress', 'Validation Call', 'Pending Client' };

    public class State {
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String validationAgent;
        @AuraEnabled public Boolean allowed;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public Boolean complete;
        @AuraEnabled public List<String> missing;
        @AuraEnabled public String nextStatus;
    }

    @AuraEnabled
    public static State preview(Id claimId) {
        Basic__c b = BP_MissingInfo.load(claimId);
        Basic__c extra = [SELECT Validation_Agent__c FROM Basic__c WHERE Id = :claimId];
        State s = new State();
        s.name = b.Name;
        s.status = b.Status__c;
        s.validationAgent = extra.Validation_Agent__c;
        s.allowed = FROM_STAGES.contains(b.Status__c);
        s.blockedReason = s.allowed ? null
            : 'This claim is in "' + b.Status__c + '": it was sent to validation already.';
        s.missing = BP_MissingInfo.agentTexts(BP_MissingInfo.check(b));
        s.complete = s.missing.isEmpty();
        s.nextStatus = s.complete ? 'Form completed' : 'Pending Client';
        return s;
    }

    @AuraEnabled
    public static State send(Id claimId) {
        State before = preview(claimId);
        if (before.allowed != true) {
            throw new AuraHandledException(before.blockedReason);
        }
        String status;
        try {
            status = BP_PortalUtils.settleAfterSubmit(claimId);
        } catch (DmlException e) {
            throw new AuraHandledException(e.getDmlMessage(0));
        }
        // As XtraPension Admin when the agent cannot change the claim's files (XpClaimDocs)
        if (status == 'Form completed' && !Test.isRunningTest()) {
            XpClaimDocs.request(claimId, XpClaimDocs.PACK);
        }
        State after = preview(claimId);
        after.nextStatus = status;
        return after;
    }
}