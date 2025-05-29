public class MassSendEmailsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful{
    public final String endQuery;
    public final String TEMPALTE_NAME;
    public final String MESSAGE_BODY;

    public MassSendEmailsBatch(String q, String message, String template) {
        endQuery = q;
        MESSAGE_BODY = message;
        TEMPALTE_NAME = template;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT ' +
                'Id,' +
                'Name, ' +
                'Contact__c, ' +
                'Email__c, ' +
                'Related_Contact_Phone__c, ' +
                'Mass_Sms_Message_Send_Date__c ' +
            'FROM Application__c ' + endQuery);
    }

    public void execute(Database.BatchableContext bc, List<Application__c> apps) {
        if (apps.size() == 0) {
            return;
        }
        Application__c currApp = apps[0];
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
        emailMessages.add(message);
        Messaging.SendEmailResult[] results = Messaging.sendEmail(emailMessages);
        if(results[0].isSuccess() == true) {
            updatedApp = new Application__c(Id = currApp.Id, Sent_Mass_Email_Message__c = true, Mass_Sms_Message_Send_Date__c = Date.today());
            System.enqueueJob(new MassSendSmsQueueable(MESSAGE_BODY, currApp.Related_Contact_Phone__c));
        }
        update updatedApp;
    }

    public void finish(Database.BatchableContext bc) {
    }
}