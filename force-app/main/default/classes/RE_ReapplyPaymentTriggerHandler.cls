public class RE_ReapplyPaymentTriggerHandler {
    Map<Id, Reapply_Payment__c> newPayments;
    Map<Id, Reapply_Payment__c> oldPayments;
    public static final String EU_EMAIL_TEMPLATE_NAME = 'Client EU Receipt';
    public static final String AU_EMAIL_TEMPLATE_NAME = 'Client AU Receipt';
    public static final String NONE_EU_EMAIL_TEMPLATE_NAME = 'Client None EU Receipt';

    private final static OrgWideEmailAddress DEFAULT_ORG_WIDE_EMAIL_ADDRESS {
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

    private static final Map<String, Id> EMAIL_TEMPLATE_NAME_BY_ID {
        get {
            if (EMAIL_TEMPLATE_NAME_BY_ID == null) {
                EMAIL_TEMPLATE_NAME_BY_ID = new Map<String, Id>();
                for(EmailTemplate template : [
                    SELECT Id, Name
                    FROM EmailTemplate
                    WHERE Name = :EU_EMAIL_TEMPLATE_NAME OR
                          Name = :AU_EMAIL_TEMPLATE_NAME OR
                          Name = :NONE_EU_EMAIL_TEMPLATE_NAME
                ]) {
                    EMAIL_TEMPLATE_NAME_BY_ID.put(template.Name, template.Id);
                }
            }
        return EMAIL_TEMPLATE_NAME_BY_ID;
    }
        private set;
    }


    public RE_ReapplyPaymentTriggerHandler(Map<Id, Reapply_Payment__c> newMap, Map<Id, Reapply_Payment__c> oldMap) {
        this.newPayments = newMap;
        this.oldPayments = oldMap;
    }

    public void handleAfterInsert() {
        Set<Id> paymentsToProcess = new Set<Id>();

        for (Reapply_Payment__c payment : newPayments.values()) {
            if (payment.Status__c == 'Paid' &&
                payment.Payment_Date__c != null &&
                payment.Amount__c != null) {
                paymentsToProcess.add(payment.Id);
            }
        }

        if (!paymentsToProcess.isEmpty()) {
            processPayments(paymentsToProcess);
        }
    }

    private void processPayments(Set<Id> paymentIds) {
        List<Receipt__c> newReceipts = new List<Receipt__c>();
        for (Reapply_Payment__c payment : [
            SELECT 
                Id,
                Payment_Date__c,
                Card_Data__c,
                Tax__c,
                Reapply__r.Application__c,
                CurrencyIsoCode,
                Reapply__r.Application__r.Contact__c,
                Reapply__r.Application__r.Email__c
            FROM Reapply_Payment__c
            WHERE Id IN :paymentIds
        ]) {
            Receipt__c currReceipt = new Receipt__c(
                Reapply_Payment__c = payment.Id,
                Paid_Date__c      = payment.Payment_Date__c,
                Payment_Method__c = payment.Card_Data__c,
                Tax_EU__c         = payment.Tax__c,
                Application__c    = payment.Reapply__r.Application__c,
                CurrencyIsoCode   = payment.CurrencyIsoCode
            );
            if (payment.Reapply__r.Application__r.Contact__c != null) {
                currReceipt.Contact__c = payment.Reapply__r.Application__r.Contact__c;
            } 
            newReceipts.add(
               currReceipt
            );
        }
        if (!newReceipts.isEmpty()) {
            insert newReceipts;
            
            Set<Id> receiptIds = new Set<Id>();

            for (Receipt__c receipt : newReceipts) {
                receiptIds.add(receipt.Id);
            }
            sendEmail(receiptIds);
        }

    }

    @future(callout=true)
    private static void sendEmail(Set<Id> receiptIds) {
        if (receiptIds.isEmpty()) {
            return;
        }
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>();
        Map<Id, Id> receiptToPaymentMap = new Map<Id, Id>();
        for(Receipt__c currentReceipt : [
            SELECT 
                Id,
                Contact__c,
                CurrencyIsoCode,
                Contact_Email__c,
                Reapply_Payment__r.Reapply__c
            FROM Receipt__c
            WHERE Id IN :receiptIds
        ]) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(currentReceipt.Contact__c);
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);
            if(currentReceipt.CurrencyIsoCode == 'EUR') {
                message.setTemplateId(EMAIL_TEMPLATE_NAME_BY_ID.get(EU_EMAIL_TEMPLATE_NAME));
            } else if(currentReceipt.CurrencyIsoCode == 'AUD') {
                message.setTemplateId(EMAIL_TEMPLATE_NAME_BY_ID.get(AU_EMAIL_TEMPLATE_NAME));
            } else {
                message.setTemplateId(EMAIL_TEMPLATE_NAME_BY_ID.get(NONE_EU_EMAIL_TEMPLATE_NAME));
            }
            message.setWhatId(currentReceipt.Id);
            message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
            message.toAddresses = new String[] { currentReceipt.Contact_Email__c };

            messages.add(message);
            receiptToPaymentMap.put(currentReceipt.Id, currentReceipt.Reapply_Payment__r.Reapply__c);
            System.debug('currentReceipt.Reapply_Payment__r.Reapply__c' + currentReceipt.Reapply_Payment__r.Reapply__c);
        }
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);

        List<EmailMessage> emailMessagesToInsert = new List<EmailMessage>();
        for(EmailMessage message : [
            SELECT
                HtmlBody,
                FromAddress,
                ToAddress,
                Subject, 
                RelatedToId
            FROM EmailMessage
            WHERE RelatedToId IN :receiptToPaymentMap.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            System.debug('receiptToPaymentMap.get(message.Id) ==== ' + receiptToPaymentMap.get(message.RelatedToId));
            EmailMessage emailMessage = new EmailMessage();
            emailMessage.status       = '3';
            emailMessage.relatedToId  = receiptToPaymentMap.get(message.RelatedToId);
            emailMessage.fromAddress  = message.FromAddress;
            emailMessage.ToAddress    = message.ToAddress;
            emailMessage.Subject      = message.Subject;
            emailMessage.HtmlBody     = message.HtmlBody;
            emailMessagesToInsert.add(emailMessage);
        }
        System.debug('emailMessagesToInsert.size() ===== ' + emailMessagesToInsert.size());
        if (emailMessagesToInsert.size() > 0) {
            System.debug('IN IF');
            insert emailMessagesToInsert;
        }
    }

}