global class XtraPensionHMRCReplyService implements Messaging.InboundEmailHandler {
    global final Map<String, String> hmrcResultByTemplateName = new Map<String, String>{
        'APPROVED Basic'    => 'HMRC Approve Result Basic Package Reply',
        'APPROVED Standard' => 'HMRC Approve Result Standard Package Reply',
        'APPROVED Premier'  => 'HMRC Approve Result Premier Package Reply',
        'APPROVED Freebie'  => 'HMRC Approve Result Standard Package Reply',
        'REJECT'            => 'HMRC Reject Result Reply'
    };
    global final String APPROVE_EMAIL_TEMPLATE_NAME = 'HMRC Success Result Reply';
    global final String REJECT_EMAIL_TEMPLATE_NAME  = 'HMRC Reject Result Reply';
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {

        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String subject = email.subject.replaceAll('(\\s+)', '');
        String nationalInsuranceNumber = '';
        String documentName = 'HMRC Assessment';
        Application__c currentApplication = new Application__c();
        if (subject.contains('APPROVED')) {
            nationalInsuranceNumber = subject.substringBefore('-APPROVED');
            documentName += ' - APPROVED';
            currentApplication.HMRC_Reply_Status__c = 'APPROVED';
        } else if (subject.contains('UNKNOWN')) {
            nationalInsuranceNumber = subject.substringBefore('-UNKNOWN');
            documentName += ' - UNKNOWN';
            currentApplication.HMRC_Reply_Status__c = 'UNKNOWN';
        } else if (subject.contains('REJECT')) {
            nationalInsuranceNumber = subject.substringBefore('-REJECT');
            documentName += ' - REJECT';
            currentApplication.HMRC_Reply_Status__c = 'REJECT';
        }
        List<Application__c> applications = [
            SELECT
                National_Insurance_Number__c,
                Status__c,
                Contact__c,
                Email__c,
                Package_Name__c
            FROM Application__c
            WHERE National_Insurance_Number__c = :nationalInsuranceNumber
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            result.success = false;
            return result;
        }
        currentApplication.Id = applications[0].Id;
        currentApplication.Status__c = 'HMRC Reply';

        if (email?.binaryAttachments.size() == 0 ) {
            result.success = false;
            return result;
        }
        Blob attachmentBody = email?.binaryAttachments[0]?.body;
        ContentVersion conVer = new ContentVersion();
        conVer.ContentLocation = 'S';
        conVer.PathOnClient = documentName + '.' + email?.binaryAttachments[0].fileName.substringAfterLast('.');
        conVer.Title = documentName;
        conVer.VersionData = attachmentBody;
        insert conVer;

        List<ContentVersion> currentContentVersions = [
            SELECT
                ContentDocumentId,
                ContentSize
            FROM ContentVersion
            WHERE Id =:conVer.Id];
        if (currentContentVersions == null) {
            result.success = false;
            return result;
        }
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = applications[0].Id;
        conDocLink.ContentDocumentId = currentContentVersions[0].ContentDocumentId;
        conDocLink.shareType = 'V';
        insert conDocLink;

        Application_Document__c assessment = new Application_Document__c(
            Application__c = currentApplication.Id,
            File_Name__c   = documentName,
            File_Size__c   = currentContentVersions[0].ContentSize,
            Large_File__c  = Integer.valueOf(currentContentVersions[0].ContentSize) > 6000000 ? true : false,
            Status__c      = 'New',
            Type__c        = 'HMRC Assessment'
        );
        insert assessment;

        ContentDocumentLink conDocLinkAppDocum = new ContentDocumentLink(
            ContentDocumentId = currentContentVersions[0].ContentDocumentId,
            LinkedEntityId    = assessment.Id
        );
        insert conDocLinkAppDocum;

        EmailMessage emailMessage = new EmailMessage();
        emailMessage.status = '3';
        emailMessage.relatedToId = currentApplication.Id;
        emailMessage.fromAddress = email.fromAddress;
        emailMessage.fromName = email.fromName;
        emailMessage.Subject = email.subject;
        insert emailMessage;

        ContentDocumentLink conDocLinkEmailMessage = new ContentDocumentLink(
            ContentDocumentId = currentContentVersions[0].ContentDocumentId,
            LinkedEntityId    = emailMessage.Id
        );
        List<SObject> sobjectForDML = new List<SObject>();
        sobjectForDML.add(conDocLinkEmailMessage);
        sobjectForDML.add(currentApplication);
        upsert sobjectForDML;

        String emailTemplateName = '';
        switch on currentApplication.HMRC_Reply_Status__c {
            when  'APPROVED'{
                emailTemplateName = currentApplication.HMRC_Reply_Status__c + ' ' + applications[0].Package_Name__c;
            }
            when 'REJECT' {
                emailTemplateName = currentApplication.HMRC_Reply_Status__c;
            }
            when 'UNKNOWN' {
                result.success = true;
                return result;
            }
        }
        List<EmailTemplate> emailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :hmrcResultByTemplateName.get(emailTemplateName)
        ];
        if (emailTemplate.isEmpty()) {
            result.success = false;
            return result;
        }
        try {
            sendHMRCReplyResult(applications[0], emailTemplate[0].Id, conVer.Id);
        } catch (Exception ex) {
            System.debug('Exception === ' + ex.getMessage());
            result.success = false;
            return result;
        }
        result.success = true;
        return result;
    }

    private static void sendHMRCReplyResult(Application__c currentApplication, Id templateId, Id contentVersionId) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(currentApplication.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setEntityAttachments(new List<String>{contentVersionId});
        message.setTemplateID(templateId);
        message.setWhatId(currentApplication.Id);
        if ( owea.size() > 0 ) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { currentApplication.Email__c};
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }
}