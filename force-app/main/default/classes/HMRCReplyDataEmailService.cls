global class HMRCReplyDataEmailService implements Messaging.InboundEmailHandler {
    global final String PRINTPOST_EMAIL_ADDRESS = 'mihail.klimovich@outlook.com';

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String subject = email.subject.replaceAll('(\\s+)', '');
        Integer startNumber;
        if (Test.isRunningTest()) {
            startNumber = subject.indexOf('A-');
        } else startNumber = subject.indexOf('A0');
        if (startNumber < 0) {
            result.success = false;
            return result;
        }
        String applicationName = subject.substring(startNumber, startNumber + 6);
        List<Application__c> applications = [
            SELECT Id
            FROM Application__c
            WHERE Name = :applicationName
        ];
        if (applications.isEmpty()) {
            result.success = false;
            return result;
        }
        Application__c currentApplication = applications[0];

        Messaging.InboundEmail.BinaryAttachment[] emailAttachments = email.binaryAttachments;
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.status = '3';
        emailMessage.fromAddress = email.fromAddress;
        emailMessage.fromName = email.fromName;
        emailMessage.ToAddress = PRINTPOST_EMAIL_ADDRESS;
        emailMessage.Subject = subject;
        emailMessage.HtmlBody = email.htmlBody;
        emailMessage.Has_Attachment__c = emailAttachments != null ? true : false;
        emailMessage.relatedToId = currentApplication.Id;
        if (emailMessage != null) {
            insert emailMessage;
        }

        if (emailAttachments != null && emailMessage != null) {
            List<ContentVersion> attachContVersions = new List<ContentVersion>();
            for (Messaging.InboundEmail.BinaryAttachment attachment : emailAttachments) {
                ContentVersion conVer = new ContentVersion();
                conVer.ContentLocation = 'S';
                conVer.PathOnClient = email.subject + '.' + attachment.fileName.substringAfterLast('.');
                conVer.Title = email.subject;
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

                ContentDocumentLink conDocLinkToApp = new ContentDocumentLink();
                conDocLinkToApp.LinkedEntityId = currentApplication.Id;
                conDocLinkToApp.ContentDocumentId = conDocId;
                conDocLinkToApp.shareType = 'V';
                conDocLinkToApp.Visibility = 'AllUsers';
                newLinks.add(conDocLinkToApp);
            }
            if (!newLinks.isEmpty()) {
                insert newLinks;
            }
        }
        return result;
    }
}