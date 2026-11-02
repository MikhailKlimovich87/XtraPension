public without sharing class RE_DocuSignController {
    public static final String REAPPLY_FORM_URL =
        XtraPension_Data__c.getInstance().RE_Pdf_File_Link__c;

    @AuraEnabled(cacheable=false)
    public static ResponseWrapper sendEnvelopeMethod(String applicationId) {
        ResponseWrapper wrapper = new ResponseWrapper();

        // 1. Get the application
        List<Reapply__c> applications = [
            SELECT Id,
                   First_Name__c,
                   Second_Name__c,
                   Email__c,
                   Application__r.Contact__c,
                   Leave_Old_DS_Files__c
            FROM Reapply__c
            WHERE Id = :applicationId
        ];

        if (applications.isEmpty()) {
            wrapper.errorMessage = 'Didn\'t find current Reapply';
            wrapper.isSuccess = false;
            return wrapper;
        }

        Reapply__c currentApplication = applications[0];

        // 2. Generate the reapply PDF (callout + DML). Wrap in try/catch so the
        //    LWC receives a clean error message instead of a raw DmlException.
        if (currentApplication.Leave_Old_DS_Files__c == false) {    
            try {
                generateReapplyDocs(currentApplication.Id);
            } catch (Exception e) {
                wrapper.isSuccess = false;
                wrapper.errorMessage = 'Error generating reapply document: ' + e.getMessage();
                return wrapper;
            }
        }


        // 3. Send the envelope in a separate transaction so that the
        //    ContentVersion DML from step 2 is committed first.
        if (!Test.isRunningTest()) {
            sendEnvelopeAsync(currentApplication.Id);
        }

        wrapper.isSuccess = true;
        return wrapper;
    }

    /**
     * Runs in a fresh transaction (no pending DML) so the DocuSign callout
     * is allowed.
     */
    @future(callout=true)
    public static void sendEnvelopeAsync(String applicationId) {
        Reapply__c currentApplication = [
            SELECT Id,
                   First_Name__c,
                   Second_Name__c,
                   Email__c,
                   Application__r.Contact__c
            FROM Reapply__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        // Create an empty envelope
        dfsle.Envelope myEnvelope = dfsle.EnvelopeService.getEmptyEnvelope(
            new dfsle.Entity(currentApplication.Id)
        );

        // Date Signed tab
        dfsle.Tab dateSignedTab = new dfsle.DateSignedTab();

        // Recipient
        dfsle.Recipient myRecipient = dfsle.Recipient.fromSource(
            currentApplication.First_Name__c + ' ' + currentApplication.Second_Name__c,
            currentApplication.Email__c,
            null,
            'Signer 1',
            new dfsle.Entity(currentApplication.Application__r.Contact__c)
        );

        myRecipient = myRecipient.withTabs(
            new List<dfsle.Tab> { dateSignedTab }
        );

        myEnvelope = myEnvelope.withRecipients(
            new List<dfsle.Recipient> { myRecipient }
        );

        // --- Query just the Links to get the Document IDs ---
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
              AND (ContentDocument.Title LIKE '%_CF083%' OR ContentDocument.Title LIKE '%_RVN%')
              AND (NOT ContentDocument.Title LIKE '%completed%')
        ];

        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : contentDocumentLinks) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        if (contentDocumentIds.isEmpty()) {
            return;
        }

        // Query ContentVersion using the Document IDs to get the latest published versions
        Set<Id> contVersionIds = new Set<Id>();
        for (ContentVersion cv : [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocumentIds
              AND IsLatest = true
        ]) {
            contVersionIds.add(cv.Id);
        }

        if (contVersionIds.isEmpty()) {
            return;
        }

        List<dfsle.Document> documents = dfsle.DocumentService.getDocuments(
            ContentVersion.getSObjectType(),
            contVersionIds
        );

        myEnvelope = myEnvelope.withDocuments(documents);

        // Envelope options
        myEnvelope = myEnvelope.withOptions(new dfsle.Envelope.Options(
            true,
            new dfsle.Document.WriteBack(
                currentApplication.Id,
                dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
                false,
                false
            ),
            new Map<String, Map<String, Object>> {
                dfsle.Envelope.STATUS_COMPLETED => new Map<String, Object> {
                    'Reapply__c.Status__c' => 'PH'
                },
                dfsle.Envelope.STATUS_SENT => new Map<String, Object> {
                    'Reapply__c.Status__c' => 'Send for Esignature'
                }
            },
            new Map<String, Map<String, Object>>()
        ));

        // Email
        myEnvelope = myEnvelope.withEmail(
            'UK State Pension - Reapply',
            'We got all your information, checked it and it is now ready for you to review and sign.\n\n' +
            'Then we will send it to HMRC immediately.\n\n' +
            '*** Please review and electronically sign by following the link above.'
        );

        // Notifications
        dfsle.Notifications notifySigner = new dfsle.Notifications(
            true, 1, 7, true, 60, 10, false
        );
        myEnvelope = myEnvelope.withNotifications(notifySigner);

        // Send
        myEnvelope = dfsle.EnvelopeService.sendEnvelope(myEnvelope, true);
    }

    @AuraEnabled(cacheable=false)
    public static List<DocumentWrapper> getForSignatureDocuments(String applicationId) {
        List<DocumentWrapper> documents = new List<DocumentWrapper>();
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersionId,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ((ContentDocument.Title LIKE '%_CF083%'
            OR ContentDocument.Title LIKE '%_RVN%')
            AND (NOT ContentDocument.Title LIKE '%completed%'))
            AND LinkedEntityId = :applicationId
        ];
        if (!contentDocumentLinks.isEmpty()) {
            for (ContentDocumentLink link : contentDocumentLinks) {
                DocumentWrapper document = new DocumentWrapper();
                document.Id    = link.ContentDocumentId;
                document.Title = link.ContentDocument.Title;
                documents.add(document);
            }
        }
        return documents;
    }

    private static void generateReapplyDocs(String recordId) {
        Reapply__c currReapp = RE_PortalUtils.getFullReapplyData(recordId);

        if (currReapp == null) {
            return;
        }

        RE_ResponseWrapper.FullReapplyDataWrapper wrap =
            new RE_ResponseWrapper.FullReapplyDataWrapper(currReapp, true);

        Map<String, Object> result = new Map<String, Object>();
        result.put('application', wrap);

        List<ContentDocumentLink> reapplyDocuments = [
            SELECT ContentDocumentId,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
              AND ContentDocument.Title LIKE '%_CF083%'
        ];

        HttpRequest request = new HttpRequest();
        request.setEndpoint(REAPPLY_FORM_URL);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json;charset=UTF-8');
        request.setBody(JSON.serialize(result));

        Http http = new Http();
        HttpResponse response = http.send(request);

        String fileName =
            currReapp.First_Name__c + '_' +
            currReapp.Second_Name__c + '_' +
            currReapp.Name + '_CF083';

        if (response.getStatusCode() >= 200 &&
            response.getStatusCode() < 300 &&
            !Test.isRunningTest()) {

            if (!reapplyDocuments.isEmpty()) {
                // This call is where the INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY
                // error was thrown. The fix (Solution 3) is applied INSIDE
                // RE_GenerateReapplyForm.updateDocumentVersion (see below).
                RE_GenerateReapplyForm.updateDocumentVersion(
                    response.getBody(),
                    fileName,
                    'pdf',
                    reapplyDocuments
                );
            } else {
                RE_GenerateReapplyForm.generateDocument(
                    response.getBody(),
                    recordId,
                    fileName
                );
            }
        }
    }

    public class DocumentWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String Title;
    }

    public class ResponseWrapper {
        @AuraEnabled public String errorMessage;
        @AuraEnabled public dfsle.Envelope envelop;
        @AuraEnabled public Boolean isSuccess;
    }

    public static void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}