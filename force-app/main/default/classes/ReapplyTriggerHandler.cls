public with sharing class ReapplyTriggerHandler {
    public Map<Id, Reapply__c> newReapply;
    public Map<Id, Reapply__c> oldReapply;
    public static final String REAPPLY_POSITION_URL = XtraPension_Data__c.getInstance().RE_Correct_Date_Position__c;

    public ReapplyTriggerHandler(Map<Id, Reapply__c> newReapply, Map<Id, Reapply__c> oldReapply) {
        this.newReapply = newReapply;
        this.oldReapply = oldReapply;
    }

    public void afterUpdateAction() {
        for (Reapply__c app : newReapply.values()) {
            if (app.Status__c == 'PH' && app.Status__c != oldReapply.get(app.Id).Status__c) {
                generateReadyDocAsync(app.Id);
            }
            if (app.Status__c == 'Form In Progress' && oldReapply.get(app.Id).Status__c == 'Pre Sale') {
                generateWelcomeEmail(app.Id);
            }
            if (app.Status__c == 'Send for Esignature' && oldReapply.get(app.Id).Status__c == 'Pending Client') {
                generateDocuSignEmailAfterSent(app.Id);
            }
        }
    }

    public void beforeUpdateAction() {
        for (Reapply__c newRec : newReapply.values()) {
            Reapply__c oldRec = oldReapply.get(newRec.Id);

            if (newRec.Status__c != oldRec.Status__c) {
                Datetime nowTime = System.now();
                Id currentUserId = UserInfo.getUserId();

                switch on newRec.Status__c {
                    when 'Form Completed' {
                        newRec.Form_Completed_Date__c = nowTime;
                        newRec.Form_Completed_User__c = currentUserId;
                    }
                    when 'Pending Client' {
                        newRec.Pending_Client_Date__c = nowTime;
                        newRec.Pending_Client_User__c = currentUserId;
                    }
                    when 'Send for Esignature' {
                        newRec.Esignature_Date__c = nowTime;
                        newRec.Esignature_User__c = currentUserId;
                    }
                    when 'PH' {
                        newRec.PH_Date__c = nowTime;
                        newRec.PH_User__c = currentUserId;
                    }
                    when 'Posted' {
                        newRec.Posted_Date__c = nowTime;
                        newRec.Posted_User__c = currentUserId;
                    }
                    when 'HMRC Reply 1' {
                        newRec.HMRC_Reply_1_Date__c = nowTime;
                        newRec.HMRC_Reply_1_User__c = currentUserId;
                    }
                    when 'Pending Info' {
                        newRec.Pending_Info_Date__c = nowTime;
                        newRec.Pending_Info_User__c = currentUserId;
                    }
                    when 'HMRC Appeal' {
                        newRec.HMRC_Appeal_Date__c = nowTime;
                        newRec.HMRC_Appeal_User__c = currentUserId;
                    }
                    when 'HMRC Reply 2' {
                        newRec.HMRC_Reply_2_Date__c = nowTime;
                        newRec.HMRC_Reply_2_User__c = currentUserId;
                    }
                    when 'Send to Client' {
                        newRec.Send_to_Client_Date__c = nowTime;
                        newRec.Send_to_Client_User__c = currentUserId;
                    }
                    when 'Agent Call' {
                        newRec.Agent_Call_Date__c = nowTime;
                        newRec.Agent_Call_User__c = currentUserId;
                    }
                    when 'Closed' {
                        newRec.Closed_Date__c = nowTime;
                        newRec.Closed_User__c = currentUserId;
                    }
                    when 'REPEAT(NO edits)' {
                        newRec.Repeat_No_Edits_Date__c = nowTime;
                        newRec.Repeat_No_Edits_User__c = currentUserId;
                    }
                    when 'REPEAT(edits)' {
                        newRec.Repeat_Edits_Date__c = nowTime;
                        newRec.Repeat_Edits_User__c = currentUserId;
                    }
                    when 'Deposit Refund' {
                        newRec.Deposit_Refund_Date__c = nowTime;
                        newRec.Deposit_Refund_User__c = currentUserId;
                    }
                }
            }
        }
    }

    public static void generateDocuSignEmailAfterSent(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';

        List<Reapply__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name,
                Email__c,
                Application__r.Contact__c
            FROM Reapply__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.size() == 0) return;

        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> docuSignEmailTemplate = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :'REAPPLY_Email_DocuSign_is_sent'
        ];

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(apps[0].Application__r.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (docuSignEmailTemplate.size() > 0) {
            message.setTemplateID(docuSignEmailTemplate[0].Id);
        }
        message.setToAddresses(new String[] {
            apps[0].Email__c
        });
        message.setWhatId(apps[0].Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        if (!Test.isRunningTest()) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    public static void generateWelcomeEmail(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';

        List<Reapply__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name,
                Email__c,
                Application__r.Contact__c
            FROM Reapply__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.size() == 0) return;

        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> welcomeEmailTemplate = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :'REAPPLY_Welcome_Email'
        ];

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(apps[0].Application__r.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (welcomeEmailTemplate.size() > 0) {
            message.setTemplateID(welcomeEmailTemplate[0].Id);
        }
        message.setToAddresses(new String[] {
            apps[0].Email__c
        });
        message.setWhatId(apps[0].Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        if (!Test.isRunningTest()) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    @future(callout=true)
    public static void generateReadyDocAsync(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        List<Reapply__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name
            FROM Reapply__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (apps.size() == 0) return;
        Reapply__c currentApplication = apps[0];

        update new Reapply__c(
            Id = applicationId,
            FTP_Reapply_Full_Form_Created_Send_Date__c = null,
            FTP_Reapply2_Full_Form_Created_Send_Date__c = null,
            Reapply_Full_Form_ZIP_for_UPLOAD__c = true
        );
    }

    public class RequestWrapper {
        public Integer pageNumber;
        public Integer x;
        public Integer y;
        public String base64;
    }
}