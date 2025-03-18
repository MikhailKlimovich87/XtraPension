trigger PaymentTrigger on Payment__c (after update, after insert) {
    switch on Trigger.operationType {
        when AFTER_UPDATE {
            PaymentTriggerHandler.sendEmailAfterChangeStatus(Trigger.newMap, Trigger.oldMap);
        }
        when AFTER_INSERT {
            PaymentTriggerHandler.sendEmailAfterCreatePaidPayment(Trigger.newMap);
        }
    }
}