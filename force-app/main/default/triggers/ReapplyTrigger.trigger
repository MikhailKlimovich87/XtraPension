trigger ReapplyTrigger on Reapply__c (before insert, before update, after insert, after update) {
    ReapplyTriggerHandler handler = new ReapplyTriggerHandler(Trigger.newMap, Trigger.oldMap);
    switch on Trigger.operationType {
        when BEFORE_UPDATE {
            handler.beforeUpdateAction();
        }
        when AFTER_UPDATE {
            handler.afterUpdateAction();
        }
    }
}