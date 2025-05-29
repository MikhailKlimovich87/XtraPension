public class FailPaymentReminderBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
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

    private static final EmailTemplate PAYMENT_ERROR_TEMPLATE {
        get {
            if (PAYMENT_ERROR_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, Subject, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = 'Payment_error_message'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    PAYMENT_ERROR_TEMPLATE = emailTemplates[0];
                }
            }
        return PAYMENT_ERROR_TEMPLATE;
    }
        private set;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Id,
                Application__r.Related_Contact_Phone__c,
                Application__r.Contact__c,
                Application__r.First_Name__c,
                Application__r.Email__c,
                Application__c
            FROM Payment__c
            WHERE (Repeated_Payment_Date_1__c  = TODAY OR
                   Repeated_Payment_Date_2__c = TODAY OR
                   Repeated_Payment_Date_3__c = TODAY)  AND
                   Status__c = 'Fail'
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Payment__c> payments) {
        if (payments.size() == 0) return;
        Payment__c failPayment = payments[0];
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>{generateSingleEmailMessage(failPayment)};
        if(messages.size() != 0) Messaging.sendEmail(messages);

        List<String> phones = new List<String>{failPayment.Application__r.Related_Contact_Phone__c};
        if (phones.size() != 0) {
            PaymentTriggerHandler.sendMessage(
                phones,
                'Hi ' + failPayment.Application__r.First_Name__c + ', We got an error when trying to charge your credit card. Please see our email (check spam folder). Thanks. XtraPension Ltd'
            );
        }
    }


    public void finish(Database.BatchableContext BC) {
    }

    private static Messaging.SingleEmailMessage generateSingleEmailMessage(Payment__c payment) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(payment.Application__c);
        message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        message.setTemplateId(PAYMENT_ERROR_TEMPLATE.Id);
        message.setToAddresses(new String[] {payment.Application__r.Email__c});
        message.setTargetObjectId(payment.Application__r.Contact__c);
        message.setWhatId(payment.Id);

        return message;
    }
}