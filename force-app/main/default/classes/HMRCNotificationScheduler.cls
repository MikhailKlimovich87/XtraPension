public class HMRCNotificationScheduler implements Schedulable {
    public void execute(SchedulableContext SC) {
        List<HMRC_SMS_Schedule_Date__c> scheduleDates = [
            SELECT
                Id,
                Email_Body__c,
                Email_Subject__c,
                SMS_message__c,
                Processed_Application_Names__c,
                Execute_Date__c
            FROM HMRC_SMS_Schedule_Date__c
            WHERE Execute_Date__c = TODAY OR Execute_Date__c = YESTERDAY
            LIMIT 1
        ];
        if (scheduleDates.size() == 0) return;
        HMRCNotificationScheduleBatch schedulerBatch = new HMRCNotificationScheduleBatch(scheduleDates[0]);
        Database.executeBatch(schedulerBatch, 1);
    }
}