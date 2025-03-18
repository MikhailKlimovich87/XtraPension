public class BlanketSMSScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        List<HMRC_SMS_Schedule_Date__c> blanketSMSScheduleDates = [
            SELECT Is_Send_Messages__c
            FROM HMRC_SMS_Schedule_Date__c
            WHERE Execute_Date__c = :(Date.today()) AND
                  Is_Send_Messages__c = false
        ];
        if (!blanketSMSScheduleDates.isEmpty()) {
            blanketSMSScheduleDates[0].Is_Send_Messages__c = true;
            update blanketSMSScheduleDates;
        }
    }
}