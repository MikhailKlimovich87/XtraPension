public class ApexToolkit {

    @AuraEnabled(cacheable=false)
    public static ResponseWrapper sendEnvelopeMethod(String applicationId) {
        ResponseWrapper wrapper = new ResponseWrapper();
        List<Application__c> applications =[
            SELECT
                First_Name__c,
                Second_Name__c,
                Email__c,
                Contact__c
            FROM Application__c
            WHERE Id = :applicationId];
        if (applications.isEmpty()) {
            wrapper.errorMessage = 'Did\'t find currnet application';
            wrapper.isSuccess = false;
            return wrapper;
        }
        Application__c currentApplication = applications[0];

        dfsle.EnvelopeIdTab testTab = new dfsle.EnvelopeIdTab();
        dfsle.Tab.Formatting formattingTest = new dfsle.Tab.Formatting('Arial', 'Red', 36, true, true, true, true, true);
        //formattingTest.withDataLabel('Test');
        testTab.withFormatting(formattingTest);
        testTab.withValue('Test');
        // Create an empty envelope.
        dfsle.Envelope myEnvelope = dfsle.EnvelopeService.getEmptyEnvelope(
            new dfsle.Entity(currentApplication.Id)
        );

        //use the Recipient.fromSource method to create the Recipient
        dfsle.Recipient myRecipient = dfsle.Recipient.fromSource(
            currentApplication.First_Name__c + ' ' + currentApplication.Second_Name__c, // Recipient name
            currentApplication.Email__c, // Recipient email
            null, //Optional phone number
            'Signer 1', //Role Name. Specify the exact role name from template
            new dfsle.Entity(currentApplication.Contact__c)); //source object for the Recipient

        //add Recipient to the Envelope
        myEnvelope = myEnvelope.withRecipients(new List<dfsle.Recipient> { myRecipient });

        List<dfsle__EnvelopeConfiguration__c> configurations = [
            SELECT
                Name,
                dfsle__DocuSignId__c
            FROM dfsle__EnvelopeConfiguration__c
        ];
        if (configurations.isEmpty()) {
            wrapper.errorMessage = 'Didn\'t find current envelop';
            wrapper.isSuccess = false;
            return wrapper;
        }
        dfsle__EnvelopeConfiguration__c envelopConfig = configurations[0];
        //myTemplateId contains the DocuSign Id of the DocuSign Template
        System.debug('envelopConfig.dfsle__DocuSignId__c === ' + envelopConfig.dfsle__DocuSignId__c);
        dfsle.UUID myTemplateId = dfsle.UUID.parse(envelopConfig.dfsle__DocuSignId__c);

        List<ContentDocumentLink> contentDocumentLinks = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersionId,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE (ContentDocument.Title LIKE '%64-8_ForSignature%' OR
                  ContentDocument.Title LIKE '%CF083_ForSignature%') AND 
                  (NOT ContentDocument.Title LIKE '%completed%') AND 
                  LinkedEntityId = :currentApplication.Id
        ];
        Set<Id> contVersionIds = new Set<Id>();
        if (!contentDocumentLinks.isEmpty()) {
            for (ContentDocumentLink link : contentDocumentLinks) {
                contVersionIds.add(link.ContentDocument.LatestPublishedVersionId);
            }
        } else {
            wrapper.errorMessage = 'Application don\'t have necessary files';
            wrapper.isSuccess = false;
            return wrapper;
        }
        System.debug('envelopConfig.Name === ' + envelopConfig.Name);
        //create a new document for the Envelope
        dfsle.Document templateDocument = dfsle.Document.fromTemplate(
            myTemplateId, // templateId in dfsle.UUID format
            envelopConfig.Name);
        //Create a list of documents (there will only be one)
        List < dfsle.Document > documents = dfsle.DocumentService.getDocuments(
            ContentVersion.getSObjectType(),
            contVersionIds);
        documents.add(templateDocument);
        myEnvelope = myEnvelope.withDocuments(documents);
        myEnvelope.withOptions(new dfsle.Envelope.Options(
            // Whether to populate auto-place tags for default roles
            true,
            new dfsle.Document.WriteBack(
                // Where to link the completed document(s)
                currentApplication.Id,
                // The completed document(s) file name format
                dfsle.Document.WRITE_BACK_NAME_ENVELOPE_STATUS_PDF,
                // Whether to combine all the documents into a single PDF
                false,
                // Whether to include the Certificate of Completion (CoC)
                false),
                // Envelope status event updates
                new Map<String, Map<String, Object>> {
                    // Set Opportunity.StageName to "Closed Won" upon completion
                    dfsle.Envelope.STATUS_COMPLETED => new Map<String, Object> {
                        'Application__c.Status__c' => 'Signed'
                    },
                    dfsle.Envelope.STATUS_SENT => new Map<String, Object> {
                        'Application__c.Status__c' => 'Sent for eSignature'
                    }
                },
                // Recipient status event updates
                new Map<String, Map<String, Object>>()));
        myEnvelope.withEmail(
            'UK State Pension - Application',
            'We got all your information, checked it and it is now ready for you to review and sign.\n\n' +
            'Then we will send it to HMRC immediately.\n\n' +
            '*** Please review and electronically sign by following the link above.'
        );

                // Send the envelope.
        dfsle.Notifications notifySigner = new dfsle.Notifications(
            true, // Indicates that the recipient should be reminded to sign
            1, // Number of days to wait before sending a reminder
            1, // Number of days between reminders
            true, // Whether or not the envelope expires and is voided
            60, // How many days before the envelope expires
            10, // Number of days before expiration to remind the recipient
            false // Placeholder for deprecated field
        );
        myEnvelope = myEnvelope.withNotifications(notifySigner);
        myEnvelope = dfsle.EnvelopeService.sendEnvelope(
            myEnvelope, // The envelope to send
            true); // Send now?
        wrapper.isSuccess = true;
        wrapper.envelop   = myEnvelope;
        return wrapper;
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
            WHERE (ContentDocument.Title LIKE '%64-8_ForSignature%' OR 
                  ContentDocument.Title LIKE '%CF083_ForSignature%') AND 
                  (NOT ContentDocument.Title LIKE '%completed%') AND 
                  LinkedEntityId = :applicationId
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