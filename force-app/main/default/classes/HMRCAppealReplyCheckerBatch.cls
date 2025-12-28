public class HMRCAppealReplyCheckerBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private final static String AGENT_ADDRESS = 'mihail.klimovich@outlook.com';
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

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Application__r.Name,
                Application__c
            FROM HMRC_Appeal_Reply__c
            WHERE Status__c = 'Sent to HMRC' AND
                  Sent_To_HMRC_Date__c = N_DAYS_AGO:5 AND
                  Sent_To_Client_Date__c = null
        ]);
    }

    public void execute(Database.BatchableContext BC, List<HMRC_Appeal_Reply__c> replies) {
        if (replies.size() == 0 ) return;
        HMRC_Appeal_Reply__c currReply = replies[0];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currReply.Application__c);
        message.setPlainTextBody('');
        message.setSubject(currReply.Application__r.Name + ' - HMRC REPLY - URGENT (REPLY NOT SENT)');
        if ( DEFAULT_ORG_WIDE_EMAIL_ADDRESS != null ) {
            message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id);
        }
        message.toAddresses = new List<String>{AGENT_ADDRESS};
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }

    public void finish(Database.BatchableContext BC) {
    }
}