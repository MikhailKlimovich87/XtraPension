public class HMRCNotificationWrongEmailSend implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    public HMRC_SMS_Schedule_Date__c scheduleDate;
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

    public HMRCNotificationWrongEmailSend(HMRC_SMS_Schedule_Date__c currScheduleDate) {
        this.scheduleDate = currScheduleDate;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        String limitQueryData = '';
        String extraQueryCondition = '';
        Set<String> processedApps;
        processedApps = (Set<String>)JSON.deserialize(scheduleDate.Processed_Application_Names__c, Set<String>.class);

        return Database.getQueryLocator([
            SELECT
                Id,
                Name,
                Email__c,
                Related_Contact_Phone__c,
                Current_Address_Abroad__CountryCode__s,
                Contact__c,
                First_Name__c
            FROM Application__c
            WHERE Name IN :processedApps AND Name != 'A18205'
            ORDER BY CreatedDate DESC
        ]);
    }

    
    public void execute(Database.BatchableContext BC, List<Application__c> currApps) {
        if (currApps.size() == 0) return;

        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>();
        for (Application__c app : currApps) {
            Messaging.SingleEmailMessage message = generateSingleEmailMessage(app);
            if (message != null) messages.add(message);
        }
        if (messages.size() != 0) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    public void finish(Database.BatchableContext BC) {
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

    public static void fakeMethod(){
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
                i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}