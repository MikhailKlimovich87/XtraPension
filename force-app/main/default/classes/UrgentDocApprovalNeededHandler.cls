public class UrgentDocApprovalNeededHandler {
    private static final OrgWideEmailAddress OWD {
        get {
            if (OWD == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    OWD = orgWideEmailAddresses[0];
                }
            }
            return OWD;
        }
        private set;
    }

    private static final EmailTemplate URGENT_DOC_APPROVAL_TEMPLATE {
        get {
            if (URGENT_DOC_APPROVAL_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, HtmlValue
                    FROM EmailTemplate
                    WHERE Name = 'Urgent Doc Approval Needed'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    URGENT_DOC_APPROVAL_TEMPLATE = emailTemplates[0];
                }
            }
        return URGENT_DOC_APPROVAL_TEMPLATE;
    }
        private set;
    }

    public static void sendUrgentDocApprovalEmail() {
        Date weekAgoDate = Date.today().addDays(-7);
        List<Application__c> notSignedApps = [
            SELECT
                Id,
                is_Sent_Urgent_Doc_Approval_Needed_Email__c,
                Contact__c,
                Email__c
            FROM Application__c
            WHERE Docusigned_Date__c <= :weekAgoDate AND
                (Date_Since_Contact__c <= :weekAgoDate OR
                Date_Since_Contact__c = NULL) AND
                Status__c = 'Sent for eSignature' AND
                is_Sent_Urgent_Doc_Approval_Needed_Email__c =false
            ];
        if(notSignedApps.size() == 0) return;
        List<Messaging.SingleEmailMessage> lstSingleEmailMessage = new List<Messaging.SingleEmailMessage>();
        for(Application__c app : notSignedApps) {
            lstSingleEmailMessage.add(createEmailMessageRecord(app));
            app.is_Sent_Urgent_Doc_Approval_Needed_Email__c = true;
        }
        if (lstSingleEmailMessage.size() != 0) {
            Messaging.SendEmailResult[] result = Messaging.sendEmail(lstSingleEmailMessage);
        }
        update notSignedApps;
    }

    private static Messaging.SingleEmailMessage createEmailMessageRecord(Application__c currApp) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currApp.Id);
        message.setTargetObjectId(currApp.Contact__c);
        if ( OWD != null ) {
            message.setOrgWideEmailAddressId(OWD.Id);
        }
        if (URGENT_DOC_APPROVAL_TEMPLATE != null) {
            message.setTemplateID(URGENT_DOC_APPROVAL_TEMPLATE.Id);
        }
        message.toAddresses = new String[] {currApp.Email__c};
        return message;
    }

}