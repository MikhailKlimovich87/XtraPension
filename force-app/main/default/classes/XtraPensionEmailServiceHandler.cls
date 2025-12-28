global class XtraPensionEmailServiceHandler implements Messaging.InboundEmailHandler {
    global final String APPLICATION_ID_INDICATOR = 'AppID:';
    global final String TRACKING_NUMBER_INDICATOR = 'Tracking No:';
    global final String TRACKING_NUMBER_SEND_DATE_INDICATOR = 'Tracking No Rx\'d by Printer:';
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
    private final EmailTemplate CLIENT_APPEAL_TEMPLATE {
        get {
            if (CLIENT_APPEAL_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id
                    FROM EmailTemplate
                    WHERE DeveloperName = 'Appeal_tracking_number_receive_message'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    CLIENT_APPEAL_TEMPLATE = emailTemplates[0];
                }
            }
        return CLIENT_APPEAL_TEMPLATE;
    }
        private set;
    }

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String plainText= '';
        plainText = email.plainTextBody;
        Task[] newTask = new Task[0];
        List<String> linesEmailBody = plainText.split('\n');
        String applicationName = '';
        String trackingNo = '';
        String trackingNoSendDate = '';
        for (Integer i = 0; i < linesEmailBody.size(); i++) {
            if (linesEmailBody[i].contains(APPLICATION_ID_INDICATOR)) {
                applicationName = linesEmailBody[i];
            }
            if (linesEmailBody[i].contains(TRACKING_NUMBER_INDICATOR)) {
                trackingNo = linesEmailBody[i];
            }
            if (linesEmailBody[i].contains(TRACKING_NUMBER_SEND_DATE_INDICATOR)) {
                trackingNoSendDate = linesEmailBody[i];
            }
        }
        if (String.isBlank(applicationName)) {
            result.message = 'This message doesn\'t contain application Id';
            result.success = false;
            return result;
        } else {
            applicationName    = applicationName.substringAfter(APPLICATION_ID_INDICATOR).trim().replaceAll('(\\s+)', '');
            applicationName = applicationName.contains('A-00') ?
                                applicationName.replace('A-00', 'A0') :
                                applicationName;
            trackingNo         = trackingNo.substringAfter(TRACKING_NUMBER_INDICATOR).trim();
            trackingNoSendDate = trackingNoSendDate.substringAfter(TRACKING_NUMBER_SEND_DATE_INDICATOR).trim();
        }
        List<SObject> upsertObjects = new List<SObject>();
        if (email.subject.contains('APPEAL')) {
            List<HMRC_Appeal_Reply__c> relies = [
                SELECT
                    Id,
                    Application__c,
                    Application__r.Email__c,
                    Application__r.Contact__c,
                    Client_Attach_File_Ids__c
                FROM HMRC_Appeal_Reply__c
                WHERE Status__c = 'Sent to HMRC' AND
                      Application__r.Name = :applicationName
            ];
            if (relies.size() == 0) {
                result.message = 'Don\'t find application in SF';
                result.success = false;
                return result;
            }
            HMRC_Appeal_Reply__c currReply = relies[0];
            currReply.Sent_To_Client_Date__c = Date.today();
            currReply.Status__c = 'Sent to Client';
            currReply.Tracking_Number__c = trackingNo;
            update currReply;

            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);
            message.setTargetObjectId(currReply.Application__r.Contact__c);

            if(currReply.Client_Attach_File_Ids__c != null) {
                Set<String> processedApps = (Set<String>)JSON.deserialize(currReply.Client_Attach_File_Ids__c, Set<String>.class);
            }

            if (CLIENT_APPEAL_TEMPLATE != null) {
                message.setTemplateID(CLIENT_APPEAL_TEMPLATE.Id);
            }
            message.setWhatId(currReply.Id);
            if ( DEFAULT_ORG_WIDE_EMAIL_ADDRESS != null ) {
                message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
            }
            message.toAddresses = new String[] { currReply.Application__r.Email__c };
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] emailResults = Messaging.sendEmail(messages);

            result.success = true;
            return result;
        }
        try {
            List<Application__c> applications = [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Amount_PH_Responses__c,
                    Appeal_Application__c
                FROM Application__c
                WHERE Name = :applicationName /*AND Status__c != 'REPEAT(NO edits)'*/
            ];
            if (applications.isEmpty()) {
                result.message = 'Don\'t find application in SF';
                result.success = false;
                return result;
            }
            Application__c app = applications[0];
            Integer amount = Integer.valueOf(app.Amount_PH_Responses__c);

            app.Tracking_Number__c = trackingNo;
            if (amount == 0) app.Tracking_Number_Received_Date__c = DateTime.now();
            else if(amount == 1) app.Tracking_Number_Received_Date_2__c = DateTime.now();
            else if(amount == 2) app.Tracking_Number_Received_Date_3__c = DateTime.now();
            app.Tracking_No_Rx_d_by_XP__c = trackingNoSendDate;
            app.Amount_PH_Responses__c = amount == null ? 1 : ++amount;
            if (app.Appeal_Application__c == true) {
                app.Status__c = 'HMRC Appeal';
            } else app.Status__c = 'Posted';
            update app;
            EmailMessage emailMessage = new EmailMessage();
            emailMessage.status = '3';
            emailMessage.relatedToId = app.Id;
            emailMessage.Application__c = app.Id;
            emailMessage.fromAddress = email.fromAddress;
            emailMessage.fromName = email.fromName;
            emailMessage.Subject = email.subject;
            emailMessage.TextBody = plainText;
            upsertObjects.add(emailMessage);
            upsert upsertObjects;

        } catch (QueryException e) {
            System.debug('Query Issue: ' + e);
        }
        result.success = true;
        return result;
    }
}