public without sharing class ApexToolkit {
    
    @AuraEnabled(cacheable=false)
    public static ResponseWrapper sendEnvelopeMethod(String applicationId) {
        
        ResponseWrapper wrapper = new ResponseWrapper();
        
        // 1. Get the application
        List<Application__c> applications = [
            SELECT Id,
                   First_Name__c,
                   Second_Name__c,
                   Email__c,
                   Contact__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        
        if (applications.isEmpty()) {
            wrapper.errorMessage = 'Didn\'t find current application';
            wrapper.isSuccess = false;
            return wrapper;
        }
        
        Application__c currentApplication = applications[0];
        
        // 2. Validate required recipient information
        if (currentApplication.Contact__c == null ||
        String.isBlank(currentApplication.Email__c)) {
            
            wrapper.errorMessage =
                'Application is missing Contact or Email information.';
            wrapper.isSuccess = false;
            return wrapper;
        }
        
        // 3. Check that required documents exist before queuing
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT ContentDocumentId,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :currentApplication.Id
            AND (
                ContentDocument.Title LIKE '%64-8_ForSignature%'
                OR ContentDocument.Title LIKE '%CF083_ForSignature%'
            )
            AND (NOT ContentDocument.Title LIKE '%completed%')
        ];
        
        if (contentDocumentLinks.isEmpty()) {
            wrapper.errorMessage =
                'Application doesn\'t have necessary files';
            wrapper.isSuccess = false;
            return wrapper;
        }
        
        // 4. Queue envelope sending in a separate transaction
        sendEnvelopeAsync(currentApplication.Id);
        
        wrapper.isSuccess = true;
        wrapper.errorMessage =
            'Envelope sending has been queued successfully.';
        
        return wrapper;
    }
    
    
    /**
     * Sends the DocuSign envelope in a separate transaction.
     * This avoids callout restrictions when the calling transaction
     * has already performed DML.
     */
    @future(callout=true)
    public static void sendEnvelopeAsync(String applicationId) {
        
        try {
            
            // 1. Get application
            Application__c currentApplication = [
                SELECT Id,
                       First_Name__c,
                       Second_Name__c,
                       Email__c,
                       Contact__c
                FROM Application__c
                WHERE Id = :applicationId
                LIMIT 1
            ];
            
            // 2. Create an empty envelope
            dfsle.Envelope myEnvelope =
                dfsle.EnvelopeService.getEmptyEnvelope(
                new dfsle.Entity(currentApplication.Id)
                );
            
            // 3. Create recipient
            dfsle.Recipient myRecipient = dfsle.Recipient.fromSource(
                currentApplication.First_Name__c + ' ' +
                currentApplication.Second_Name__c,
            currentApplication.Email__c,
            null,
            'Signer 1',
            new dfsle.Entity(currentApplication.Contact__c)
                );
            
            myEnvelope = myEnvelope.withRecipients(
            new List<dfsle.Recipient>{ myRecipient }
            );
            
            // 4. Get ContentDocument IDs
            List<ContentDocumentLink> contentDocumentLinks = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :currentApplication.Id
                AND (
                    ContentDocument.Title LIKE '%64-8_ForSignature%'
                    OR ContentDocument.Title LIKE '%CF083_ForSignature%'
                )
                AND (NOT ContentDocument.Title LIKE '%completed%')
            ];
            
            Set<Id> contentDocumentIds = new Set<Id>();
            
            for (ContentDocumentLink link : contentDocumentLinks) {
                contentDocumentIds.add(link.ContentDocumentId);
            }
            
            if (contentDocumentIds.isEmpty()) {
                throw new AuraHandledException(
                    'Application doesn\'t have necessary files.'
                    );
            }
            
            // 5. Get latest ContentVersion IDs
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
                throw new AuraHandledException(
                    'No latest document versions were found.'
                    );
            }
            
            // 6. Get DocuSign documents
            List<dfsle.Document> documents =
                dfsle.DocumentService.getDocuments(
                ContentVersion.getSObjectType(),
            contVersionIds
                );
            
            if (documents.isEmpty()) {
                throw new AuraHandledException(
                    'DocuSign could not retrieve the documents.'
                    );
            }
            
            // 7. Add documents to envelope
            myEnvelope = myEnvelope.withDocuments(documents);
            
            // 8. Set envelope options
            myEnvelope = myEnvelope.withOptions(
                new dfsle.Envelope.Options(
                true,
            new dfsle.Document.WriteBack(
                currentApplication.Id,
            dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
            false,
            false
                ),
            new Map<String, Map<String, Object>> {
                
                dfsle.Envelope.STATUS_COMPLETED =>
                new Map<String, Object> {
                    'Application__c.Status__c' => 'Signed'
                },
                
                dfsle.Envelope.STATUS_SENT =>
                new Map<String, Object> {
                    'Application__c.Status__c' =>
                        'Sent for eSignature'
                }
            },
            new Map<String, Map<String, Object>>()
                )
                );
            
            // 9. Set email subject and body
            myEnvelope = myEnvelope.withEmail(
                'UK State Pension - Application',
            'We got all your information, checked it and it is now ready for you to review and sign.\n\n' +
                'Then we will send it to HMRC immediately.\n\n' +
                '*** Please review and electronically sign by following the link above.'
                );
            
            // 10. Set notifications
            dfsle.Notifications notifySigner = new dfsle.Notifications(
                true,
            1,
            7,
            true,
            60,
            10,
            false
                );
            
            myEnvelope = myEnvelope.withNotifications(notifySigner);
            
            // 11. Send envelope
            myEnvelope = dfsle.EnvelopeService.sendEnvelope(
                myEnvelope,
            true
                );
            
            System.debug(
                LoggingLevel.INFO,
            'DocuSign envelope sent successfully: ' + myEnvelope
                );
            
        } catch (Exception e) {
            
            System.debug(
                LoggingLevel.ERROR,
            'DocuSign envelope sending failed. Application: ' +
                applicationId +
                '. Error: ' + e.getMessage() +
                '. Stack trace: ' + e.getStackTraceString()
                );
            
            throw e;
        }
    }
    
    
    @AuraEnabled(cacheable=false)
    public static List<DocumentWrapper> getForSignatureDocuments(
        String applicationId
    ) {
        
        List<DocumentWrapper> documents = new List<DocumentWrapper>();
        
        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.LatestPublishedVersionId,
                   LinkedEntityId
            FROM ContentDocumentLink
            WHERE (
                ContentDocument.Title LIKE '%64-8_ForSignature%'
                OR ContentDocument.Title LIKE '%CF083_ForSignature%'
            )
            AND (NOT ContentDocument.Title LIKE '%completed%')
            AND LinkedEntityId = :applicationId
        ];
        
        for (ContentDocumentLink link : contentDocumentLinks) {
            
            DocumentWrapper document = new DocumentWrapper();
            
            document.Id = link.ContentDocumentId;
            document.Title = link.ContentDocument.Title;
            
            documents.add(document);
        }
        
        return documents;
    }
    
    
    @future(callout=true)
    public static void voidEnvelope(List<String> envelopsIds) {
        
        if (envelopsIds == null || envelopsIds.isEmpty()) {
            return;
        }
        
        String reason = 'Deposit Refund';
        
        for (Integer i = 0;
        i < envelopsIds.size() && i < 100;
        i++) {
            
            try {
                
                dfsle.UUID docusignId =
                    dfsle.UUID.parse(envelopsIds[i]);
                
                dfsle.StatusService.voidEnvelope(
                    docusignId,
                reason
                    );
                
            } catch (Exception e) {
                
                System.debug(
                    LoggingLevel.ERROR,
                'Failed to void envelope ' +
                    envelopsIds[i] +
                    ': ' + e.getMessage()
                    );
            }
        }
    }
    
    
    public class DocumentWrapper {
        
        @AuraEnabled
        public String Id;
        
        @AuraEnabled
        public String Title;
    }
    
    
    public class ResponseWrapper {
        
        @AuraEnabled
        public String errorMessage;
        
        @AuraEnabled
        public dfsle.Envelope envelop;
        
        @AuraEnabled
        public Boolean isSuccess;
    }
}