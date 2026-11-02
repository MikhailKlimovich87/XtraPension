trigger BasicTrigger on Basic__c (before insert, before update, after update) {
    BasicTriggerHandler handler = new BasicTriggerHandler(
        Trigger.new,
        Trigger.newMap,
        Trigger.oldMap
    );

    switch on Trigger.operationType {
        when BEFORE_INSERT {
            handler.distributeBetweenAgents();
        }
        when BEFORE_UPDATE {
            handler.blockEditsWhileOutForSignature();
        }
        when AFTER_UPDATE {
            handler.generatePdfFiles();
            handler.regeneratePackOnSourceChange();
        }
    }
}