public class HMRCNotificationScheduleBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful  {
    public HMRC_SMS_Schedule_Date__c scheduleDate;
    private final String FROM_NAME = 'XtraPension';
    private final String TWILIO_FROM_NUMBER = '+19033076997';
    public Set<String> appNames = new Set<String>();
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

    public HMRCNotificationScheduleBatch(HMRC_SMS_Schedule_Date__c currScheduleDate) {
        this.scheduleDate = currScheduleDate;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        String limitQueryData = '';
        String extraQueryCondition = '';
        Set<String> processedApps;
        Date todayDate = Date.today();
        if (scheduleDate.Execute_Date__c == todayDate) {
            limitQueryData = 'LIMIT 3500';
        } else if (scheduleDate.Execute_Date__c == todayDate.addDays(-1) && scheduleDate.Processed_Application_Names__c != null) {
            processedApps = (Set<String>)JSON.deserialize(scheduleDate.Processed_Application_Names__c, Set<String>.class);
            appNames.addAll(processedApps);
            extraQueryCondition = 'AND Name NOT IN :processedApps ';
        }

        String query =
            'SELECT ' +
                'Id,' +
                'Name,' +
                'Email__c,' +
                'Related_Contact_Phone__c,' +
                'Current_Address_Abroad__CountryCode__s,' +
                'Contact__c,' +
                'First_Name__c ' +
            'FROM Application__c ' +
            'WHERE (Status__c = \'64-8 Bounce\' OR ' +
                  'Status__c = \'Posted\' OR ' +
                  'Status__c = \'DWP Teleclaim\' OR ' +
                  'Status__c = \'DWP 2 Emails Sent\') ' +
                  extraQueryCondition +
            'ORDER BY CreatedDate DESC ' +
            limitQueryData
        ;

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext BC, List<Application__c> currApps) {
        if (currApps.size() == 0) return;
        TwilioSmsHelper.SMSWrapper wrapper = new TwilioSmsHelper.SMSWrapper();
        wrapper.body = scheduleDate.SMS_message__c;
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>();
        for (Application__c app : currApps) {
            this.appNames.add(app.Name);
            wrapper.to = app.Related_Contact_Phone__c;
            wrapper.fromData = calculateFromData(app);
            TwilioSmsHelper smsHelper = new TwilioSmsHelper(app, wrapper);
            smsHelper.sendMessage();
            Messaging.SingleEmailMessage message = generateSingleEmailMessage(app);
            if (message != null) messages.add(message);
        }
        if (messages.size() != 0) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    public void finish(Database.BatchableContext BC) {
        if (this.appNames.size() > 0) {
            update new HMRC_SMS_Schedule_Date__c(
                Id = scheduleDate.Id,
                Processed_Application_Names__c =JSON.serializePretty(this.appNames)
            );
        }
    }

    private String calculateFromData(Application__c app) {
        return app.Current_Address_Abroad__CountryCode__s == 'AU' ||
               app.Current_Address_Abroad__CountryCode__s == 'NZ' ||
               app.Current_Address_Abroad__CountryCode__s == 'US' ||
               app.Current_Address_Abroad__CountryCode__s == 'ZA' ?
                    TWILIO_FROM_NUMBER :
                    FROM_NAME;
    }

    private Messaging.SingleEmailMessage generateSingleEmailMessage(Application__c app) {
        if (app == null) return null;

        Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
        emailMessage.setHtmlBody(scheduleDate.Email_Body__c.replace('{FNAME}', app.First_Name__c).replace('<p>','<P STYLE = "margin-top:0px; margin-bottom:0px;">'));
        emailMessage.setSubject(scheduleDate.Email_Subject__c);
        if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS != null) {
            emailMessage.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        }
        emailMessage.setSaveAsActivity(true);
        emailMessage.setTreatTargetObjectAsRecipient(false);
        emailMessage.setWhatId(app.Id);
        emailMessage.setTargetObjectId(app.Contact__c);
        emailMessage.setToAddresses(new String[] {app.Email__c});

        return emailMessage;
    }
}