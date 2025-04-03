global class VoluntaryContributionEmailServiceHandler implements Messaging.InboundEmailHandler {
    private final static String AGENT_EMAIL_ADDRESS = 'grace@xtrapension.com';
    private final static String FROM_DWP_EMAIL_ADDRESS = 'IPC.REVIEWANDRECONTEAM@dwp.gov.uk';
    private static Messaging.SingleEmailMessage agentEmailMessage;

    private static final OrgWideEmailAddress DEFAULT_ORG_WIDE_EMAIL_ADDRESS {
        get {
            if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    DEFAULT_ORG_WIDE_EMAIL_ADDRESS = orgWideEmailAddresses[0];
                }
            }
            return DEFAULT_ORG_WIDE_EMAIL_ADDRESS;
        }
        private set;
    }

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String subject = email.subject;
        Messaging.InboundEmail.BinaryAttachment[] emailAttachments = email.binaryAttachments;
        Email_Message_Status__c newStatus = new Email_Message_Status__c();
        insert newStatus;
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.status = '3';
        emailMessage.fromAddress = email.fromAddress;
        emailMessage.fromName = email.fromName;
        emailMessage.ToAddress = email.toAddresses[0];
        emailMessage.Subject = String.isBlank(subject) ? 'Empty' : subject;
        emailMessage.HtmlBody = email.htmlBody;
        emailMessage.TextBody = email.plainTextBody;
        emailMessage.Has_Attachment__c = emailAttachments != null ? true : false;
        emailMessage.Email_Message_Status__c = newStatus.Id;
        emailMessage.NICS_JGBA_message__c = true;
        System.debug('body ==== ' + email.plainTextBody);

        String[] applicationEmails = new List<String>();
        if (email.fromAddress == 'IPC.REVIEWANDRECONTEAM@dwp.gov.uk') {
            applicationEmails.addAll(email.toAddresses);
        } else applicationEmails.add(email.fromAddress);

        if (applicationEmails.size() == 0) {
            result.success = false;
            return result;
        }
        List<Application__c> applications = [
            SELECT
                Id,
                Email__c,
                Name,
                First_Name__c,
                Second_Name__c
            FROM Application__c
            WHERE Email__c IN :applicationEmails
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            result.success = false;
            return result;
        }
        Application__c currentApplication = applications[0];
        emailMessage.relatedToId    = currentApplication.Id;
        emailMessage.Application__c = currentApplication.Id;
        agentEmailMessage = generateSingleEmailMessage(
            currentApplication.Name + ' - ' + currentApplication.First_Name__c + ' ' + currentApplication.Second_Name__c + ' - DWP E-mail Received',
            currentApplication.Id
        );

        if (emailMessage != null) {
            insert emailMessage;
        }
        if (emailAttachments != null && emailMessage != null) {
            List<ContentVersion> attachContVersions = new List<ContentVersion>();
            for (Messaging.InboundEmail.BinaryAttachment attachment : emailAttachments) {
                ContentVersion conVer = new ContentVersion();
                conVer.ContentLocation = 'S';
                conVer.PathOnClient = attachment.fileName;
                conVer.Title = attachment.fileName;
                conVer.VersionData = attachment.body;
                attachContVersions.add(conVer);
            }
            insert attachContVersions;
            Set<Id> contVersIds = new Set<Id>();
            for (ContentVersion version : attachContVersions) {
	            contVersIds.add(version.id);
            }
            List<ContentVersion> contVersAfterInsert = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :contVersIds
            ];
            Set<Id> contDocIds = new Set<Id>();
            for (ContentVersion version : contVersAfterInsert) {
                contDocIds.add(version.ContentDocumentId);
            }
            List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
            for (Id conDocId : contDocIds) {
                ContentDocumentLink conDocLink = new ContentDocumentLink();
                conDocLink.LinkedEntityId = emailMessage.Id;
                conDocLink.ContentDocumentId = conDocId;
                conDocLink.shareType = 'V';
                conDocLink.Visibility = 'AllUsers';
                newLinks.add(conDocLink);
            }
            if (!newLinks.isEmpty()) {
                insert newLinks;
            }
        }
        if (agentEmailMessage != null) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {agentEmailMessage};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
        result.success = true;
        return result;
    }

    private static Messaging.SingleEmailMessage generateSingleEmailMessage(
        String subject,
        Id appId
    ) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(appId);
        message.setSubject(subject);
        message.setPlainTextBody('');
        message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        message.setToAddresses(new String[] {AGENT_EMAIL_ADDRESS});

        return message;
    }
}