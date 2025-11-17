public class PaymentTriggerHandler {
    public static final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
    public static final String EU_CLIENT_EMAIL_TEMPLATE_NAME = 'Client EU Receipt';
    public static final String NONE_EU_EMAIL_TEMPLATE_NAME = 'Client None EU Receipt';
    private static final XtraPension_Settings__mdt XP_SETTINGS {
        get {
            if (XP_SETTINGS == null) {
                List<XtraPension_Settings__mdt> setts = [
    				SELECT
                    	Admin_Email_Addresses__c,
                    	Admin_Fail_Reminder_Email_Addresses__c
    				FROM XtraPension_Settings__mdt
    				WHERE DeveloperName = 'Configuration'
                    LIMIT 1
                ];
                if (!setts.isEmpty()) {
                    XP_SETTINGS = setts[0];
                }
            }
            return XP_SETTINGS;
        }
        private set;
    }
    public static final String FAIL_PAYMENT_SMS_MESSAGE = 'Hi - We got an error when trying to charge your credit card. Please see our email (check spam folder). Thanks. XtraPension Ltd';
    public static final String ACCOUNT_ID = XtraPension_Data__c.getInstance().Twilio_Account__c;
    public static final String TOKEN_ID   = XtraPension_Data__c.getInstance().Twilio_Token__c;
    public static final String FROM_NAME = 'XtraPension';
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

    public static void sendEmailAfterChangeStatus(Map<Id, Payment__c> newPayments, Map<Id, Payment__c> oldPayments) {
        List<Payment__c> paidPayments = new List<Payment__c>();
        Map<Id, Payment__c> splitAppIdByPayment = new Map<Id, Payment__c>();
        Set<Id> failPaymentIds = new Set<Id>();
        for (Payment__c payment : newPayments.values()) {
            if (payment.Status__c == 'Paid' && payment.Status__c != oldPayments.get(payment.Id).Status__c) {
                paidPayments.add(payment);
            }
            if (payment.Status__c == 'Paid' && payment.Status__c != oldPayments.get(payment.Id).Status__c &&
                payment.Product_Name__c == 'Success' &&
                payment.CurrencyIsoCode == 'ZAR') {
                splitAppIdByPayment.put(payment.Application__c, payment);
            }
            if (payment.Status__c == 'Fail' && payment.Status__c != oldPayments.get(payment.Id).Status__c) {
                failPaymentIds.add(payment.Id);
            }
        }
        if (!paidPayments.isEmpty()) {
            sendReceipt(paidPayments);
            calculateCurrentTotalAmount(paidPayments);
        }
        if (!failPaymentIds.isEmpty()) {
            sendFailNotification(failPaymentIds);
        }
        if (splitAppIdByPayment.size() != 0) {
            scheduleSplitSuccessPayment(splitAppIdByPayment);
        }
    }

    public static void sendEmailAfterCreatePaidPayment(Map<Id, Payment__c> newPayments) {
        List<Payment__c> paidPayments = new List<Payment__c>();
        for (Payment__c payment : newPayments.values()) {
            if (payment.Status__c == 'Paid') {
                paidPayments.add(payment);
                sendRegistrationFeeDataToAdmin(payment);
                StripeApiService.updatePaymentCardData(payment.Id);
            }
        }
    }

    public static void sendReceipt(List<Payment__c> paidPayments) {
        Map<Id, Receipt__c> newReceipts = new Map<Id, Receipt__c>();
        for (Payment__c payment : paidPayments) {
            newReceipts.put(
                payment.Id,
                new Receipt__c(
                    Payment__c        = payment.Id,
                    Paid_Date__c      = payment.Payment_Date__c,
                    Payment_Method__c = payment.Card_Data__c,
                    Tax_EU__c         = payment.Tax_VAT__c,
                    Application__c    = payment.Application__c,
                    CurrencyIsoCode   = payment.CurrencyIsoCode
                )
            );
        }
        if (newReceipts.isEmpty()) {
            return;
        }
        insert newReceipts.values();
        List<Receipt__c> currentReceipts = [
            SELECT
                Id,
                Application_Contact__c,
                Contact_Email__c,
                Application__c,
                CurrencyIsoCode
            FROM Receipt__c
            WHERE Id IN :newReceipts.values()
        ];
        if (currentReceipts.isEmpty()) {
            return;
        }
        for (Receipt__c receipt : currentReceipts) {
            if(receipt.Id != null) {
                sendEmail(receipt);
            }
        }
    }

    public static void calculateCurrentTotalAmount(List<Payment__c> paidPayments) {
        if (paidPayments.size() == 0) return;
        Map<Id, Payment__c> paymentIdByPaidPayments = new Map<Id, Payment__c>(paidPayments);
        List<Application__c> updatedApps = new List<Application__c>();
        for (Payment__c payment : [
            SELECT Application__c,
                   Application__r.Amount__c,
                   Amount__c
            FROM Payment__c
            WHERE Id IN : paymentIdByPaidPayments.keySet()
        ]) {
            if (payment.Amount__c != null) {
                updatedApps.add(
                    new Application__c(
                        Id = payment.Application__c,
                        Amount__c = payment.Application__r.Amount__c == null ?
                                        payment.Amount__c :
                                        payment.Application__r.Amount__c + payment.Amount__c,
                        Last_Payment_Date__c = Date.today()
                    )
                );
            }
        }
        if(updatedApps.size() != 0) {
            Database.update(updatedApps, false);
        }
    }


    private static void scheduleSplitSuccessPayment(Map<Id, Payment__c> applicationIdBySuccessPayment) {
        if (applicationIdBySuccessPayment.size() == 0) return;
        List<Payment__c> updatedPayment = new List<Payment__c>();
        Date dateInMonth = Date.today().addMonths(1);
        for(Payment__c payment : [
            SELECT
                Id,
                Status__c,
                Application__c,
                Amount__c,
                CurrencyIsoCode
            FROM Payment__c
            WHERE Product_Name__c = 'Success' AND
                  Application__c IN :applicationIdBySuccessPayment.keySet() AND
                  Status__c = 'Draft'
        ]) {
            Payment__c paidPayment = applicationIdBySuccessPayment.get(payment.Application__c);

            if (paidPayment != null && paidPayment.Amount__c == payment.Amount__c) {
                updatedPayment.add(
                    new Payment__c(
                        Id = payment.Id,
                        Status__c = 'Schedule',
                        Payment_Date__c = dateInMonth
                    )
                );
            }
        }
        if (updatedPayment.size() != 0) {
            Database.update(updatedPayment, false);
        }
    }

    private static void sendEmail(Receipt__c currentReceipt) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        String templateName = EU_CLIENT_EMAIL_TEMPLATE_NAME;
        if (currentReceipt.CurrencyIsoCode != 'EUR') {
            templateName = NONE_EU_EMAIL_TEMPLATE_NAME;
        }
        List<EmailTemplate> receiptEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :templateName
        ];

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(currentReceipt.Application_Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (!receiptEmailTemplate.isEmpty()) {
            message.setTemplateID(receiptEmailTemplate[0].Id);
        }
        message.setWhatId(currentReceipt.Id);
        if ( owea.size() > 0 ) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { currentReceipt.Contact_Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);

        List<EmailMessage> relatedMessages = [
            SELECT
                HtmlBody,
                FromAddress,
                ToAddress,
                Subject
            FROM EmailMessage
            WHERE RelatedToId = :currentReceipt.Id
            ORDER BY CreatedDate DESC
        ];
        if (relatedMessages.isEmpty()) {
            return;
        }
        EmailMessage receiptMessage = relatedMessages[0];
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.status       = '3';
        emailMessage.relatedToId  = currentReceipt.Application__c;
        emailMessage.fromAddress  = receiptMessage.FromAddress;
        emailMessage.ToAddress    = receiptMessage.ToAddress;
        emailMessage.Subject      = receiptMessage.Subject;
        emailMessage.HtmlBody     = receiptMessage.HtmlBody;
        insert emailMessage;
    }

    public static void sendRegistrationFeeDataToAdmin(Payment__c payment) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<Application__c> applications = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Related_Contact_Phone__c,
                Email__c,
                Contact__c,
                Contact__r.MailingCountry,
                Current_Address_Abroad_Country__c,
                Install_from_Website__c,
                Agent_Making_Sale__c,
                Appeal_Application__c,
                Has_NINO_Now__c,
                CurrencyIsoCode
            FROM Application__c
            WHERE Id = :payment.Application__c
        ];
        if (applications.isEmpty()) {
            return;
        }
        Application__c currentApplication = applications[0];
        String htmlBody =
            '<div>Client email address ' + currentApplication.Email__c + '</div>' +
            '<div>Tel  '+ currentApplication.Related_Contact_Phone__c +'</div>';
        String noninoData = currentApplication.Has_NINO_Now__c == false ? 'NONINO - ' : '';
        String currencyData = currentApplication.CurrencyIsoCode == 'EUR' ?
                                '€ ' : currentApplication.CurrencyIsoCode == 'ZAR' ?
                                    currentApplication.CurrencyIsoCode + ' ' :
                                    currentApplication.CurrencyIsoCode + '$ ';
        String subject = CountryCodeHelper.getCountryNameByIsoCode(currentApplication.Contact__r.MailingCountry) + ' - ' +
                            currentApplication.Agent_Making_Sale__c + ' - ' + noninoData +
                            '(' + currentApplication.First_Name__c + ' ' +
                            currentApplication.Second_Name__c + ') - ' +
                            currencyData + payment.Amount__c + ' sale - ';
        if (currentApplication.Install_from_Website__c == true) {
            subject += 'Website';
        } else {
            subject += 'Phone';
        }
        if (currentApplication.Appeal_Application__c == true) {
            subject += ' - Class 3 Appeal';
        }

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currentApplication.Id);
        message.setSubject(subject);
        message.setHtmlBody(htmlBody);
        if ( owea.size() > 0 ) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.setToAddresses((List<String>)JSON.deserialize(XP_SETTINGS.Admin_Email_Addresses__c, List<String>.class));
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    public static void sendFailNotification(Set<Id> failPaymentIds) {
        if (failPaymentIds.size() == 0) return;
        List<Payment__c> failPayments = [
            SELECT
                Id,
                Application__c,
                Application__r.Email__c,
                Application__r.Name,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Error_Message__c,
                Application__r.Contact__c,
                Application__r.Related_Contact_Phone__c
            FROM Payment__c
            WHERE Id IN :failPaymentIds
        ];
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>();
        List<String> phones = new List<String>();
        for (Payment__c payment : failPayments) {
            Messaging.SingleEmailMessage singleErrorMessage = generateSingleEmailMessage(payment);
            singleErrorMessage.setTemplateId(PAYMENT_ERROR_TEMPLATE.Id);
            singleErrorMessage.setToAddresses(new String[] {payment.Application__r.Email__c});
            singleErrorMessage.setTargetObjectId(payment.Application__r.Contact__c);
            singleErrorMessage.setWhatId(payment.Id);
            messages.add(singleErrorMessage);

            Messaging.SingleEmailMessage singleAdminReminderMessage = generateSingleEmailMessage(payment);
            singleAdminReminderMessage.setPlainTextBody('Stripe Reason: ' + payment.Error_Message__c);
            singleAdminReminderMessage.setSubject('XP - CC FAILURE - ' + payment.Application__r.Name + ' - ' + payment.Application__r.First_Name__c + ' ' + payment.Application__r.Second_Name__c);
            singleAdminReminderMessage.setToAddresses((List<String>)JSON.deserialize(XP_SETTINGS.Admin_Fail_Reminder_Email_Addresses__c, List<String>.class));
            messages.add(singleAdminReminderMessage);

            phones.add(payment.Application__r.Related_Contact_Phone__c);
            if(phones.size() == 100) {
                sendMessage(phones, FAIL_PAYMENT_SMS_MESSAGE);
                phones = new List<String>();
            }
        }
        if(messages.size() != 0) {
            Messaging.sendEmail(messages);
        }
        if (phones.size() > 0) sendMessage(phones, FAIL_PAYMENT_SMS_MESSAGE);
    }

    public static void sendMessage(List<String> phoneData, String messageBody) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + ACCOUNT_ID + '/Messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        Blob headerValue = Blob.valueOf(ACCOUNT_ID + ':' + TOKEN_ID);
        String authorizationHeader = 'BASIC ' + EncodingUtil.base64Encode(headerValue);
        req.setHeader('Authorization', authorizationHeader);
        for (String phone : phoneData) {
            if(phone != null) {
                req.setBody('To=' + EncodingUtil.urlEncode(phone,'UTF-8') + '&From=' + FROM_NAME + '&Body=' + messageBody);
                try {
                    Http http = new Http();
                    //if (Test.isRunningTest()) return;
                    HTTPResponse res = http.send(req);
                    if(res.getStatusCode() == 201) System.debug('@@@Twilio Success' + phone);
                    else {
                        System.debug('@@@Twilio failed' + phone);
                        ErrorResponseWrapper erw =(ErrorResponseWrapper)json.deserialize(res.getBody(), ErrorResponseWrapper.class);
                        System.debug('@@@Twilio error' + erw.message);
                    }
                } catch(Exception ex){
                    System.debug('Error message = ' + ex.getMessage());
                }
            }
        }
    }

    public class ErrorResponseWrapper {
        String code;
        String message;
        String moreInfo;
        String status;
    }

    private static Messaging.SingleEmailMessage generateSingleEmailMessage(Payment__c payment) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(payment.Application__c);
        message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);

        return message;
    }
}