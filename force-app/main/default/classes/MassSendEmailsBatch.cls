public class MassSendEmailsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful{
    public final String endQuery;
    public final String TEMPALTE_NAME;
    public final String MESSAGE_BODY;
    public final String attachmentQueryData;

    public MassSendEmailsBatch(String q, String message, String template, String attachmentData) {
        endQuery = q;
        MESSAGE_BODY = message;
        TEMPALTE_NAME = template;
        attachmentQueryData = attachmentData;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT ' +
                'Id,' +
                'Name, ' +
                'Contact__c, ' +
                'Email__c, ' +
                'Related_Contact_Phone__c, ' +
                'Mass_Sms_Message_Send_Date__c, ' +
                'Current_Address_Abroad__CountryCode__s ' +
            'FROM Application__c ' + endQuery);
    }

    public void execute(Database.BatchableContext bc, List<Application__c> apps) {
        if (apps.size() == 0) {
            return;
        }
        Application__c currApp = apps[0];
        System.debug('Current app: ' + currApp);
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = 'clients@xtrapension.com'
        ];
        List<EmailTemplate> massEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :TEMPALTE_NAME
        ];
        System.debug('Mass email template: ' + massEmailTemplate);
        Application__c updatedApp;
        List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(currApp.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (massEmailTemplate.isEmpty()) {
            return;
        }
        message.setTemplateID(massEmailTemplate[0].Id);
        message.setWhatId(currApp.Id);
        message.setOrgWideEmailAddressId(owea.get(0).Id);
        message.toAddresses = new String[] { currApp.Email__c };
        if (String.isNotBlank(attachmentQueryData)) {
            String query = 
                'SELECT ' +
                    'ContentDocumentId,ContentDocument.Title,' +
                    'ContentDocument.LatestPublishedVersionId, ' +
                    'ContentDocument.LatestPublishedVersion.VersionData, ' +
                    'ContentDocument.LatestPublishedVersion.FileExtension ' +
                'FROM ContentDocumentLink  WHERE LinkedEntityId = \'' + currApp.Id + '\' AND ' + attachmentQueryData;
            List<ContentDocumentLink> contentDocumentLinks = Database.query(query);
            System.debug('Content document links: ' + contentDocumentLinks);
            if (contentDocumentLinks.size() > 0) {
                List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
                for (ContentDocumentLink cdl : contentDocumentLinks) {
                    Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                    efa.setFileName(cdl.ContentDocument.Title + '.' + cdl.ContentDocument.LatestPublishedVersion.FileExtension);
                    efa.setBody(cdl.ContentDocument.LatestPublishedVersion.VersionData);
                    attachments.add(efa);
                }
                message.setFileAttachments(attachments);
            }
        }
        emailMessages.add(message);
        Messaging.SendEmailResult[] results = Messaging.sendEmail(emailMessages);
        if(results[0].isSuccess()) {

            // Find created EmailMessage
            EmailMessage em = [
                SELECT Id
                FROM EmailMessage
                WHERE RelatedToId = :currApp.Id
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            // Link attachments to EmailMessage
            if (String.isNotBlank(attachmentQueryData)) {

            String query =
                'SELECT ContentDocumentId ' +
                'FROM ContentDocumentLink ' +
                'WHERE LinkedEntityId = \'' + currApp.Id + '\' AND ' + attachmentQueryData;

            List<ContentDocumentLink> originalLinks = Database.query(query);

            List<ContentDocumentLink> emailLinks = new List<ContentDocumentLink>();

            for(ContentDocumentLink cdl : originalLinks) {

                emailLinks.add(new ContentDocumentLink(
                    LinkedEntityId = em.Id,
                    ContentDocumentId = cdl.ContentDocumentId,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
            }

            if(!emailLinks.isEmpty()) {
                insert emailLinks;
            }
        }
        System.debug(currApp.Name + ' - send email successfully!');
        }
        System.debug('Email send results: ' + results);
        //if(results[0].isSuccess() == true) {
            //
            //updatedApp = new Application__c(Id = currApp.Id, Sent_Mass_Email_Message__c = true, Mass_Sms_Message_Send_Date__c = Date.today());
            //System.enqueueJob(new MassSendSmsQueueable(MESSAGE_BODY, currApp.Related_Contact_Phone__c, currApp.Current_Address_Abroad__CountryCode__s));
        //}
        //update updatedApp;
    }

    public void finish(Database.BatchableContext bc) {
    }
}