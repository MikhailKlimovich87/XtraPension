public with sharing class BP_DocuSignController {

    // Shared status strings (keep in sync with BasicTriggerHandler / picklist values)
    public static final String STATUS_SIGNED_WAITING_DOCS = 'Signed - Waiting Docs at WDM';
    public static final String STATUS_SENT_FOR_ESIG       = 'Sent for eSignature';

    // -------------------------------------------------------------------------
    // PUBLIC ENTRY POINT (kept for backward compat — Case B only, or Case A split by caller)
    // -------------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static ResponseWrapper sendEnvelopeMethod(String applicationId) {
        ResponseWrapper wrapper = new ResponseWrapper();

        List<Basic__c> apps = [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Contact__c, Status__c,
                   Bank_Account_Owner_Name__c, Bank_Account_Owner_Email__c
            FROM Basic__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        if (apps.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Claims not found.';
            return wrapper;
        }

        Basic__c app = apps[0];

        if (String.isBlank(app.Email__c)) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Claim must have a valid email address.';
            return wrapper;
        }

        String blocker = getSendBlocker(app);
        if (blocker != null) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = blocker;
            return wrapper;
        }

        Boolean hasBankOwner =
            String.isNotBlank(app.Bank_Account_Owner_Name__c) &&
            String.isNotBlank(app.Bank_Account_Owner_Email__c);

        // Case B: single envelope with both documents
        if (!hasBankOwner) {
            return sendCombinedEnvelope(applicationId);
        }

        // Case A: send only the Summary here.
        // The LWC will call sendMandateEnvelope(...) in a fresh transaction.
        ResponseWrapper result = sendSummaryEnvelope(applicationId);
        if (result.isSuccess) {
            result.needsSecondEnvelope = true;
        }
        return result;
    }

    // -------------------------------------------------------------------------
    // Case A – envelope 1: Summary to applicant (NO STATUS_SENT flip)
    // -------------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static ResponseWrapper sendSummaryEnvelope(String applicationId) {
        ResponseWrapper wrapper = new ResponseWrapper();

        List<Basic__c> apps = [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Contact__c
            FROM Basic__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Claims not found.';
            return wrapper;
        }
        Basic__c app = apps[0];

        Set<Id> summaryVersionIds = findVersionIdsByTitle(applicationId, 'Summary');
        if (summaryVersionIds.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'No Summary document found.';
            return wrapper;
        }

        List<dfsle.Document> summaryDocuments = dfsle.DocumentService.getDocuments(
            ContentVersion.getSObjectType(),
            summaryVersionIds
        );

        Id entityId = app.Contact__c != null ? app.Contact__c : app.Id;

        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(app.Id));

        dfsle.Recipient recipient = dfsle.Recipient.fromSource(
            app.First_Name__c + ' ' + app.Last_Name__c,
            app.Email__c,
            null,
            'Signer 1',
            new dfsle.Entity(entityId)
        );

        env = env.withDocuments(summaryDocuments);
        env = env.withRecipients(new List<dfsle.Recipient>{ recipient });

        env = env.withOptions(new dfsle.Envelope.Options(
            true,
            new dfsle.Document.WriteBack(
                app.Id,
                dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
                false,
                false
            ),
            // Case A: no status is written when this envelope completes. BP_DocuSignEnvelopes moves the claim to
            // "Signed - Waiting Docs at WDM" only after BOTH the Summary and the ddMandate envelopes are completed.
            new Map<String, Map<String, Object>>(),
            new Map<String, Map<String, Object>>()
        ));

        env = env.withEmail(
            'UK State Pension - Claim (Summary)',
            'Please review and electronically sign the Summary by following the link above.'
        );

        env = env.withNotifications(new dfsle.Notifications(true, 1, 7, true, 60, 10, false));

        env = dfsle.EnvelopeService.sendEnvelope(env, true);

        wrapper.isSuccess = true;
        wrapper.envelop = env;
        wrapper.additionalEnvelopes = new List<dfsle.Envelope>{ env };
        return wrapper;
    }

    // -------------------------------------------------------------------------
    // Case A – envelope 2: ddMandate to bank owner
    // Separate AuraEnabled method → separate transaction → callout is legal.
    // Flips the status to 'Sent for eSignature' on STATUS_SENT.
    // -------------------------------------------------------------------------
    @AuraEnabled(cacheable=false)
    public static ResponseWrapper sendMandateEnvelope(String applicationId) {
        ResponseWrapper wrapper = new ResponseWrapper();

        List<Basic__c> apps = [
            SELECT Id, First_Name__c, Last_Name__c, Contact__c,
                   Bank_Account_Owner_Name__c, Bank_Account_Owner_Email__c
            FROM Basic__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Claims not found.';
            return wrapper;
        }
        Basic__c app = apps[0];

        if (String.isBlank(app.Bank_Account_Owner_Name__c) ||
            String.isBlank(app.Bank_Account_Owner_Email__c)) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Bank account owner details are missing.';
            return wrapper;
        }

        Set<Id> mandateVersionIds = findVersionIdsByTitle(applicationId, 'ddMandate');
        if (mandateVersionIds.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'No ddMandate document found.';
            return wrapper;
        }
        if (BP_DocuSignEnvelopes.hasActiveDocument(BP_DocuSignEnvelopes.load(new Set<Id>{ app.Id }).get(app.Id), 'ddMandate')) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'A Direct Debit Mandate envelope has already been sent for this claim.';
            return wrapper;
        }

        List<dfsle.Document> mandateDocuments = dfsle.DocumentService.getDocuments(
            ContentVersion.getSObjectType(),
            mandateVersionIds
        );

        List<dfsle.Tab> tabs = new List<dfsle.Tab>();
        dfsle.TextTab customerTab = new dfsle.TextTab();
        customerTab.withDataLabel('Customer');
        customerTab.withValue(app.First_Name__c + ' ' + app.Last_Name__c);
        customerTab.withReadOnly(true);
        tabs.add(customerTab);

        Id entityId = app.Contact__c != null ? app.Contact__c : app.Id;

        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(app.Id));

        dfsle.Recipient bankOwnerRecipient = dfsle.Recipient.fromSource(
            app.Bank_Account_Owner_Name__c,
            app.Bank_Account_Owner_Email__c,
            null,
            'Signer 1',
            new dfsle.Entity(entityId)
        );
        bankOwnerRecipient = bankOwnerRecipient.withTabs(tabs);

        env = env.withDocuments(mandateDocuments);
        env = env.withRecipients(new List<dfsle.Recipient>{ bankOwnerRecipient });

        env = env.withOptions(new dfsle.Envelope.Options(
            true,
            new dfsle.Document.WriteBack(
                app.Id,
                dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
                false,
                false
            ),
            new Map<String, Map<String, Object>> {
                dfsle.Envelope.STATUS_SENT => new Map<String, Object> {
                    'Basic__c.Status__c' => STATUS_SENT_FOR_ESIG
                }
            },
            new Map<String, Map<String, Object>>()
        ));

        env = env.withEmail(
            'UK State Pension - Claim (Direct Debit Mandate)',
            'Please review and electronically sign the Direct Debit Mandate by following the link above.'
        );

        env = env.withNotifications(new dfsle.Notifications(true, 1, 7, true, 60, 10, false));

        env = dfsle.EnvelopeService.sendEnvelope(env, true);

        wrapper.isSuccess = true;
        wrapper.envelop = env;
        wrapper.additionalEnvelopes = new List<dfsle.Envelope>{ env };
        return wrapper;
    }

    // -------------------------------------------------------------------------
    // Case B – single envelope with both documents to applicant
    // -------------------------------------------------------------------------
    public static ResponseWrapper sendCombinedEnvelope(String applicationId) {
        ResponseWrapper wrapper = new ResponseWrapper();

        List<Basic__c> apps = [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Contact__c
            FROM Basic__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Claims not found.';
            return wrapper;
        }
        Basic__c app = apps[0];

        Set<Id> summaryVersionIds = findVersionIdsByTitle(applicationId, 'Summary');
        Set<Id> mandateVersionIds = findVersionIdsByTitle(applicationId, 'ddMandate');

        if (summaryVersionIds.isEmpty() || mandateVersionIds.isEmpty()) {
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Claim must have both a Summary and a ddMandate document.';
            return wrapper;
        }

        Set<Id> allIds = new Set<Id>();
        allIds.addAll(summaryVersionIds);
        allIds.addAll(mandateVersionIds);

        List<dfsle.Document> documents = dfsle.DocumentService.getDocuments(
            ContentVersion.getSObjectType(),
            allIds
        );

        List<dfsle.Tab> tabs = new List<dfsle.Tab>();
        dfsle.TextTab customerTab = new dfsle.TextTab();
        customerTab.withDataLabel('Customer');
        customerTab.withValue(app.First_Name__c + ' ' + app.Last_Name__c);
        customerTab.withReadOnly(true);
        tabs.add(customerTab);

        Id entityId = app.Contact__c != null ? app.Contact__c : app.Id;

        dfsle.Envelope env = dfsle.EnvelopeService.getEmptyEnvelope(new dfsle.Entity(app.Id));

        dfsle.Recipient recipient = dfsle.Recipient.fromSource(
            app.First_Name__c + ' ' + app.Last_Name__c,
            app.Email__c,
            null,
            'Signer 1',
            new dfsle.Entity(entityId)
        );
        recipient = recipient.withTabs(tabs);

        env = env.withDocuments(documents);
        env = env.withRecipients(new List<dfsle.Recipient>{ recipient });

        env = env.withOptions(new dfsle.Envelope.Options(
            true,
            new dfsle.Document.WriteBack(
                app.Id,
                dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
                false,
                false
            ),
            new Map<String, Map<String, Object>> {
                dfsle.Envelope.STATUS_COMPLETED => new Map<String, Object> {
                    'Basic__c.Status__c' => STATUS_SIGNED_WAITING_DOCS
                },
                dfsle.Envelope.STATUS_SENT => new Map<String, Object> {
                    'Basic__c.Status__c' => STATUS_SENT_FOR_ESIG
                }
            },
            new Map<String, Map<String, Object>>()
        ));

        env = env.withEmail(
            'UK State Pension - Claim',
            'Please review and electronically sign the documents by following the link above.'
        );

        env = env.withNotifications(new dfsle.Notifications(true, 1, 7, true, 60, 10, false));

        env = dfsle.EnvelopeService.sendEnvelope(env, true);

        wrapper.isSuccess = true;
        wrapper.envelop = env;
        wrapper.additionalEnvelopes = new List<dfsle.Envelope>{ env };
        return wrapper;
    }

    // -------------------------------------------------------------------------
    // HELPERS
    // -------------------------------------------------------------------------

    /**
     * Returns the reason a claim must not be sent for signature, or null when it can be sent:
     * already signed, still has missing info, or an envelope is already out for signature.
     */
    // Tests use minimal claims; production always enforces the missing-info check
    @TestVisible private static Boolean skipMissingInfoCheck = false;

    private static String getSendBlocker(Basic__c app) {
        if (app.Status__c == STATUS_SIGNED_WAITING_DOCS) {
            return 'This claim has already been signed.';
        }
        List<String> missingInfo = skipMissingInfoCheck ? new List<String>() : BP_PortalUtils.generateValidationEmail(app.Id);
        if (!missingInfo.isEmpty()) {
            return 'Cannot send for signature while information is missing: ' + String.join(missingInfo, '; ');
        }
        List<BP_DocuSignEnvelopes.EnvelopeInfo> envelopes = BP_DocuSignEnvelopes.load(new Set<Id>{ app.Id }).get(app.Id);
        if (BP_DocuSignEnvelopes.hasInFlightEnvelope(envelopes)) {
            return 'An envelope for this claim is already awaiting signature. Void it in DocuSign before sending a new one.';
        }
        return null;
    }

    /**
     * Returns the latest published version Ids of all ContentDocuments linked
     * to the given application whose Title contains the given fragment and
     * does NOT contain 'completed'.
     */
    private static Set<Id> findVersionIdsByTitle(Id applicationId, String titleFragment) {
        Set<Id> ids = new Set<Id>();
        for (ContentDocumentLink l : [
            SELECT ContentDocument.LatestPublishedVersionId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
              AND (NOT ContentDocument.Title LIKE '%completed%')
        ]) {
            String title = l.ContentDocument?.Title;
            if (String.isNotBlank(title) && title.containsIgnoreCase(titleFragment)) {
                ids.add(l.ContentDocument.LatestPublishedVersionId);
            }
        }
        return ids;
    }

    @AuraEnabled(cacheable=false)
    public static List<DocumentWrapper> getForSignatureDocuments(String applicationId) {
        List<DocumentWrapper> documents = new List<DocumentWrapper>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE (ContentDocument.Title LIKE '%Summary%' OR ContentDocument.Title LIKE '%ddMandate%')
              AND (NOT ContentDocument.Title LIKE '%completed%')
              AND LinkedEntityId = :applicationId
        ]) {
            documents.add(new DocumentWrapper(
                link.ContentDocumentId,
                link.ContentDocument.Title
            ));
        }
        return documents;
    }

    // -------------------------------------------------------------------------
    // WRAPPERS
    // -------------------------------------------------------------------------

    public class DocumentWrapper {
        @AuraEnabled public String docId;
        @AuraEnabled public String title;
        public DocumentWrapper() {}
        public DocumentWrapper(String id, String title) {
            this.docId = id;
            this.title = title;
        }
    }

    public class ResponseWrapper {
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String infoMessage;
        @AuraEnabled public dfsle.Envelope envelop;
        @AuraEnabled public List<dfsle.Envelope> additionalEnvelopes;
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public Boolean needsSecondEnvelope;  // signals LWC to call sendMandateEnvelope
    }
}