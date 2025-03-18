trigger HMRC_SMS_ScheduleDateTrigger on HMRC_SMS_Schedule_Date__c (after update) {
    HMRC_SMS_Schedule_Date__c currentRecord = (Trigger.new)[0];
    HMRC_SMS_Schedule_Date__c oldRedord     = (Trigger.oldMap).get(currentRecord.Id);
    if (currentRecord.Is_Send_Messages__c != oldRedord.Is_Send_Messages__c && currentRecord.Is_Send_Messages__c == true) {
        List<String> phones = new List<String>();
        String messageBody = currentRecord.SMS_message__c;
        if(messageBody == null) return;
        for (Application__c app : [SELECT Related_Contact_Phone__c
                                   FROM Application__c
                                   WHERE Status__c = 'Posted']) {
            phones.add(app.Related_Contact_Phone__c);
            if(phones.size() == 100) {
                HMRC_SMS_ScheduleDateTriggerHandler.sendMessage(phones, messageBody);
                phones = new List<String>();
            }
        }
        if (phones.size() > 0) HMRC_SMS_ScheduleDateTriggerHandler.sendMessage(phones, messageBody);
    }
}