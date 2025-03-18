trigger TwilioMessageTrigger on TwilioSF__Message__c (after update) {
    for (TwilioSF__Message__c message : Trigger.new) {
        if (message.TwilioSF__Message_SID__c != Trigger.oldMap.get(message.Id).TwilioSF__Message_SID__c && Trigger.oldMap.get(message.Id).TwilioSF__Message_SID__c == null) {
            TwilioMessageTriggerHandler.getMessageData(message.TwilioSF__Message_SID__c, message.Id);
        }
    }
}