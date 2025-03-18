trigger EmployerTrigger on Employer__c (after update, before update, after insert, before insert) {
    EmployerTriggerHandler handler = new EmployerTriggerHandler(Trigger.oldMap, Trigger.newMap, Trigger.new);
    switch on Trigger.OperationType  {
        when BEFORE_UPDATE {
            handler.regenerateEmployerContryNameOrState();
        }
        when AFTER_UPDATE {
            handler.updateApplicationAfterUKEmployerStartDate();
        }
        when AFTER_INSERT {
            handler.checkEmployersAfterCreate();
        }
        when BEFORE_INSERT {
            handler.addCountryAndStateData();
        }
    }
}