trigger ApplicationTrigger on Application__c (before insert,after insert, after update) {
    ApplicationTriggerHandler handler = new ApplicationTriggerHandler(Trigger.newMap, Trigger.oldMap);
    switch on Trigger.operationType {
        when BEFORE_INSERT {
            handler.autoAssignToAgent(Trigger.new);
        }
        when AFTER_UPDATE {
            handler.generatePdfFiles();
        }
        when AFTER_INSERT {
            handler.autopopulateRequiredFields();
            handler.sendRegistrationDataMessage();
        }
    }
}