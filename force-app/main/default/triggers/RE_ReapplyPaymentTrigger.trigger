trigger RE_ReapplyPaymentTrigger on Reapply_Payment__c (after insert, after update) {
    RE_ReapplyPaymentTriggerHandler handler = new RE_ReapplyPaymentTriggerHandler(
        Trigger.newMap,
        Trigger.oldMap
    );
    switch on Trigger.operationType {
        when AFTER_INSERT {
            handler.handleAfterInsert();
        }
        when AFTER_UPDATE {
        }
    }

}