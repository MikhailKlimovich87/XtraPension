global class ClientSupportEmailServiceHandler implements Messaging.InboundEmailHandler {
    global final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String subject = email.subject;
        if (email.fromAddress == 'dse@eumail.docusign.net' || email.fromAddress == 'clients@xtrapension.com') {
            result.success = false;
            return result;
        }
        Messaging.InboundEmail.BinaryAttachment[] emailAttachments = email.binaryAttachments;
        Email_Message_Status__c newStatus = new Email_Message_Status__c();
        insert newStatus;
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.status = '3';
        emailMessage.fromAddress = email.fromAddress;
        emailMessage.fromName = email.fromName;
        emailMessage.ToAddress = ORG_WIDE_EMAIL_ADDRESS;
        emailMessage.Subject = String.isBlank(subject) ? 'Empty' : subject;
        emailMessage.HtmlBody = email.htmlBody != null && email.htmlBody.length() >= 131072 ? email.htmlBody.substring(0, 131072) : email.htmlBody;
        emailMessage.TextBody = email.plainTextBody != null && email.plainTextBody.length() >= 131072 ? email.plainTextBody.substring(0, 131072) : email.plainTextBody;
        emailMessage.Has_Attachment__c = emailAttachments != null ? true : false;
        emailMessage.Email_Message_Status__c = newStatus.Id;

        if (email.fromAddress != null) {
            List<Application__c> applications = [
                SELECT
                    Id,
                    Email__c
                FROM Application__c
                WHERE Email__c = :email.fromAddress
                LIMIT 1
            ];
            if (!applications.isEmpty()) {
                Application__c currentApplication = applications[0];
                emailMessage.relatedToId    = currentApplication.Id;
                emailMessage.Application__c = currentApplication.Id;
            }
        }
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
        result.success = true;
        return result;
    }
}