trigger HMRC_SMS_ScheduleDateTrigger on HMRC_SMS_Schedule_Date__c (after update) {
    HMRC_SMS_Schedule_Date__c currentRecord = (Trigger.new)[0];
    HMRC_SMS_Schedule_Date__c oldRedord     = (Trigger.oldMap).get(currentRecord.Id);
    if (currentRecord.Is_Send_Messages__c != oldRedord.Is_Send_Messages__c && currentRecord.Is_Send_Messages__c == true) {
        List<HMRC_SMS_ScheduleDateTriggerHandler.ClientInfo> phones = new List<HMRC_SMS_ScheduleDateTriggerHandler.ClientInfo>();
        String messageBody = currentRecord.SMS_message__c;
        if(messageBody == null) return;
        for (Application__c app : [SELECT
                                        Related_Contact_Phone__c,
                                        Current_Address_Abroad__CountryCode__s
                                   FROM Application__c
                                   WHERE Status__c = 'Posted' OR
                                         Status__c = '64-8 Bounce'
                                   ORDER BY CreatedDate DESC
                                   LIMIT 5000]) {
            HMRC_SMS_ScheduleDateTriggerHandler.ClientInfo info = new HMRC_SMS_ScheduleDateTriggerHandler.ClientInfo();
            info.phone = app.Related_Contact_Phone__c;
            info.countryCode = app.Current_Address_Abroad__CountryCode__s;
            phones.add(info);
            if(phones.size() == 100) {
                HMRC_SMS_ScheduleDateTriggerHandler.sendMessage(JSON.serialize(phones), messageBody);
                phones = new List<HMRC_SMS_ScheduleDateTriggerHandler.ClientInfo>();
            }
        }
        if (phones.size() > 0) HMRC_SMS_ScheduleDateTriggerHandler.sendMessage(JSON.serialize(phones), messageBody);
    }
}