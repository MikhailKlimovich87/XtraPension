/**
 * Reads the DocuSign envelopes of a claim and keeps the claim status in step with them.
 *
 * Case A (bank account owner differs from the applicant) uses two envelopes: the Summary for the
 * applicant and the ddMandate for the bank account owner. The claim must only move to
 * "Signed - Waiting Docs at WDM" once BOTH are completed, so the envelopes no longer write that
 * status themselves; DocuSignStatusTrigger calls process() on every envelope status change.
 */
public without sharing class BP_DocuSignEnvelopes {

    public static final String STATUS_SENT_FOR_ESIG = 'Sent for eSignature';
    public static final String STATUS_SIGNED_WAITING_DOCS = 'Signed - Waiting Docs at WDM';
    public static final String STATUS_PENDING_CLIENT = 'Pending Client';
    public static final String STATUS_FORM_COMPLETED = 'Form completed';

    public static final String ENVELOPE_COMPLETED = 'Completed';
    public static final Set<String> ENVELOPE_IN_FLIGHT = new Set<String>{ 'Created', 'Sent', 'Delivered' };
    public static final Set<String> ENVELOPE_FAILED = new Set<String>{ 'Declined', 'Voided', 'Expired' };

    private static final String SUMMARY_FRAGMENT = 'Summary';
    private static final String MANDATE_FRAGMENT = 'ddMandate';

    @TestVisible
    private static Boolean forceFailureForTest = false;

    public class EnvelopeInfo {
        public String docuSignId;
        public String status;
        public List<String> documentNames = new List<String>();

        public Boolean hasDocument(String fragment) {
            for (String name : documentNames) {
                if (String.isNotBlank(name) && name.containsIgnoreCase(fragment)) {
                    return true;
                }
            }
            return false;
        }
    }

    public static Map<Id, List<EnvelopeInfo>> load(Set<Id> claimIds) {
        Map<Id, List<EnvelopeInfo>> result = new Map<Id, List<EnvelopeInfo>>();
        Set<String> claimIdStrings = new Set<String>();
        for (Id claimId : claimIds) {
            result.put(claimId, new List<EnvelopeInfo>());
            claimIdStrings.add(String.valueOf(claimId));
        }

        Map<String, EnvelopeInfo> infoByDocuSignId = new Map<String, EnvelopeInfo>();
        for (dfsle__EnvelopeStatus__c status : [
            SELECT dfsle__DocuSignId__c, dfsle__Status__c, dfsle__SourceId__c
            FROM dfsle__EnvelopeStatus__c
            WHERE dfsle__SourceId__c IN :claimIdStrings
        ]) {
            EnvelopeInfo info = new EnvelopeInfo();
            info.docuSignId = status.dfsle__DocuSignId__c;
            info.status = status.dfsle__Status__c;
            infoByDocuSignId.put(info.docuSignId, info);
            result.get((Id) status.dfsle__SourceId__c).add(info);
        }

        if (!infoByDocuSignId.isEmpty()) {
            for (dfsle__Envelope__c envelope : [
                SELECT dfsle__DocuSignId__c, (SELECT dfsle__FullName__c FROM dfsle__Documents__r)
                FROM dfsle__Envelope__c
                WHERE dfsle__DocuSignId__c IN :infoByDocuSignId.keySet()
            ]) {
                EnvelopeInfo info = infoByDocuSignId.get(envelope.dfsle__DocuSignId__c);
                for (dfsle__Document__c document : envelope.dfsle__Documents__r) {
                    info.documentNames.add(document.dfsle__FullName__c);
                }
            }
        }
        return result;
    }

    public static Boolean hasInFlightEnvelope(List<EnvelopeInfo> envelopes) {
        for (EnvelopeInfo info : envelopes) {
            if (ENVELOPE_IN_FLIGHT.contains(info.status)) {
                return true;
            }
        }
        return false;
    }

    // True when an envelope that is still open or already signed carries the document
    public static Boolean hasActiveDocument(List<EnvelopeInfo> envelopes, String fragment) {
        for (EnvelopeInfo info : envelopes) {
            if ((ENVELOPE_IN_FLIGHT.contains(info.status) || info.status == ENVELOPE_COMPLETED) && info.hasDocument(fragment)) {
                return true;
            }
        }
        return false;
    }

    public static Boolean isSigned(List<EnvelopeInfo> envelopes, String fragment) {
        for (EnvelopeInfo info : envelopes) {
            if (info.status == ENVELOPE_COMPLETED && info.hasDocument(fragment)) {
                return true;
            }
        }
        return false;
    }

    public static Boolean summaryAndMandateSigned(List<EnvelopeInfo> envelopes) {
        return isSigned(envelopes, SUMMARY_FRAGMENT) && isSigned(envelopes, MANDATE_FRAGMENT);
    }

    /**
     * Returns the status the claim should move to, or null to leave it alone.
     * Only claims that are waiting on the signature (or were returned to the agent) are touched, so a late
     * envelope event can never pull a claim back from a later stage.
     */
    public static String decideStatus(String currentStatus, Boolean bothSigned, Boolean failedEnvelopeEvent) {
        if (bothSigned) {
            if (currentStatus == STATUS_SENT_FOR_ESIG || currentStatus == STATUS_FORM_COMPLETED || currentStatus == STATUS_PENDING_CLIENT) {
                return STATUS_SIGNED_WAITING_DOCS;
            }
            return null;
        }
        if (failedEnvelopeEvent && currentStatus == STATUS_SENT_FOR_ESIG) {
            return STATUS_PENDING_CLIENT;
        }
        return null;
    }

    public static void logFailure(Exception ex) {
        try {
            insert new Application_Form_Error__c(
                Error_Body__c = 'DocuSign status could not be applied to the claim\n' + ex.getMessage() + '\n' + ex.getStackTraceString(),
                Error_Date__c = Date.today()
            );
        } catch (Exception ignored) {
            System.debug(LoggingLevel.ERROR, 'DocuSign failure could not be logged: ' + ignored.getMessage());
        }
    }

    public static void process(List<dfsle__EnvelopeStatus__c> statuses, Map<Id, dfsle__EnvelopeStatus__c> oldStatuses) {
        if (forceFailureForTest) {
            throw new DmlException('Forced failure for test coverage of DocuSignStatusTrigger catch block');
        }
        Set<Id> claimIds = new Set<Id>();
        Set<Id> claimsWithFailedEnvelope = new Set<Id>();
        for (dfsle__EnvelopeStatus__c status : statuses) {
            if (String.isBlank(status.dfsle__SourceId__c)) {
                continue;
            }
            Id sourceId;
            try {
                sourceId = Id.valueOf(status.dfsle__SourceId__c);
            } catch (Exception ex) {
                continue;
            }
            if (sourceId.getSobjectType() != Basic__c.SObjectType) {
                continue;
            }
            dfsle__EnvelopeStatus__c old = oldStatuses == null ? null : oldStatuses.get(status.Id);
            if (old != null && old.dfsle__Status__c == status.dfsle__Status__c) {
                continue;
            }
            claimIds.add(sourceId);
            if (ENVELOPE_FAILED.contains(status.dfsle__Status__c)) {
                claimsWithFailedEnvelope.add(sourceId);
            }
        }
        if (claimIds.isEmpty()) {
            return;
        }

        Map<Id, List<EnvelopeInfo>> envelopesByClaim = load(claimIds);
        List<Basic__c> toUpdate = new List<Basic__c>();
        for (Basic__c claim : [SELECT Id, Status__c FROM Basic__c WHERE Id IN :claimIds]) {
            String newStatus = decideStatus(
                claim.Status__c,
                summaryAndMandateSigned(envelopesByClaim.get(claim.Id)),
                claimsWithFailedEnvelope.contains(claim.Id)
            );
            if (newStatus != null && newStatus != claim.Status__c) {
                toUpdate.add(new Basic__c(Id = claim.Id, Status__c = newStatus));
            }
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}