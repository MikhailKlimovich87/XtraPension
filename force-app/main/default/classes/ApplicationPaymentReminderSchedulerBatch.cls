public class ApplicationPaymentReminderSchedulerBatch implements Database.Batchable<SObject>, Database.AllowsCallouts{
    public final String FROM_NAME = 'XtraPension';
    public final String TWILIO_FROM_NUMBER = '+19033076997';
    public final String MESSAGE_BODY = 'Please note that XtraPension\'s UK State Pension application fee ({!AmountData}) will be charged to the card you gave us tmrw. https://xpen.uk/fees - Thanks';
    private final EmailTemplate REMINDER_TEMPLATE {
        get {
            if (REMINDER_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id
                    FROM EmailTemplate
                    WHERE DeveloperName = 'Application_Payment_Reminder'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    REMINDER_TEMPLATE = emailTemplates[0];
                }
            }
        return REMINDER_TEMPLATE;
    }
        private set;
    }

    private final OrgWideEmailAddress DEFAULT_ORG_WIDE_EMAIL_ADDRESS {
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

    public final XtraPension_Data__c XTRAPENSION_DATA {
        get {
            if (XTRAPENSION_DATA == null) {
                XTRAPENSION_DATA = XtraPension_Data__c.getInstance();
            }
            return XTRAPENSION_DATA;
        }
        private set;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Id,
                Amount__c,
                CurrencyIsoCode,
                Application__c,
                Application__r.Email__c,
                Application__r.Contact__c,
                Application__r.Current_Address_Abroad__CountryCode__s,
                Application_Name__c,
                Application__r.Related_Contact_Phone__c
            FROM Payment__c
            WHERE Status__c = 'Schedule' AND
                  Product_Name__c = 'Application' AND
                  Payment_Date__c = TOMORROW AND
                  Application_Reminder_Sent_Date__c = NULL
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Payment__c> schedulePayments) {
        if (schedulePayments.size() > 0) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>();
            List<Payment__c> updatePayment = new List<Payment__c>();
            for (Payment__c payment : schedulePayments) {
                Messaging.SingleEmailMessage message = generateSingleEmailMessage(
                    payment.Id,
                    payment.Application__r.Contact__c,
                    payment.Application__r.Email__c
                );
                if (message != null) messages.add(message);
                String fromValue = payment.Application__r.Current_Address_Abroad__CountryCode__s == 'AU' ||
                                   payment.Application__r.Current_Address_Abroad__CountryCode__s == 'NZ' ||
                                   payment.Application__r.Current_Address_Abroad__CountryCode__s == 'US' ||
                                   payment.Application__r.Current_Address_Abroad__CountryCode__s == 'ZA' ?
                                        TWILIO_FROM_NUMBER :
                                        FROM_NAME;
                sendSMS(
                    payment.Application__r.Related_Contact_Phone__c,
                    fromValue,
                    MESSAGE_BODY.replace('{!AmountData}', payment.CurrencyIsoCode + ' ' + payment.Amount__c)
                );
                updatePayment.add(
                    new Payment__c (
                        Id = payment.Id,
                        Application_Reminder_Sent_Date__c = Date.today()
                    )
                );
            }
            if (messages.size() != 0) {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
            }
            if (updatePayment.size() != 0) {
                Database.update(updatePayment, false);
            }
        }
    }

    public void finish(Database.BatchableContext BC) {
    }

    private Messaging.SingleEmailMessage generateSingleEmailMessage(
        Id paymentId,
        Id contactId,
        String toAddress
    ) {
        if (paymentId == null || toAddress == null) return null;

        Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
        emailMessage.setTemplateId(REMINDER_TEMPLATE.Id);
        emailMessage.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        emailMessage.setSaveAsActivity(true);
        emailMessage.setTreatTargetObjectAsRecipient(false);
        emailMessage.setWhatId(paymentId);
        emailMessage.setTargetObjectId(contactId);
        emailMessage.setToAddresses(new String[] {toAddress});

        return emailMessage;
    }

    private void sendSMS(
        String phoneNumber,
        String fromData,
        String messageData
    ) {
        if (phoneNumber == null || fromData == null || messageData == null) return;
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + XTRAPENSION_DATA.Twilio_Account__c + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(XTRAPENSION_DATA.Twilio_Account__c + ':' + XTRAPENSION_DATA.Twilio_Token__c);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        req.setBody('To=' + EncodingUtil.urlEncode(phoneNumber,'UTF-8') + '&From=' + fromData + '&Body=' + messageData);
        try {
            Http http = new Http();
            HTTPResponse res = http.send(req);
            if(res.getStatusCode() != 201) {
                ErrorResponseWrapper erw =(ErrorResponseWrapper)json.deserialize(res.getBody(), ErrorResponseWrapper.class);
            }
        } catch(Exception ex) {
            System.debug('Error message = ' + ex.getMessage());
        }
    }

    public class ErrorResponseWrapper{
        String code;
        String message;
        String moreInfo;
        String status;
    }
}