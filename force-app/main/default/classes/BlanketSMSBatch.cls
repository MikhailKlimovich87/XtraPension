public class BlanketSMSBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    public String messgeInfo;

    public BlanketSMSBatch(String message) {
        this.messgeInfo = message;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Related_Contact_Phone__c
            FROM Application__c
            WHERE Status__c = 'Posted'
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Application__c> apps) {
        if (apps.size() > 0) {
            for (Application__c app : apps) {
                System.enqueueJob(new BlanketSMSQueueable(messgeInfo, app.Related_Contact_Phone__c));
            }
        }
    }

    public void finish(Database.BatchableContext BC) {
        //notification with errors
        //notification With success
    }


}