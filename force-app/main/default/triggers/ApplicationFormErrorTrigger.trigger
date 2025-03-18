trigger ApplicationFormErrorTrigger on Application_Form_Error__c (after insert) {
    ApplicationFormErrorTriggerHandler handler = new ApplicationFormErrorTriggerHandler(Trigger.new);
    handler.sendErrorMessage();
}