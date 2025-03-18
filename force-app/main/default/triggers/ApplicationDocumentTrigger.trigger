trigger ApplicationDocumentTrigger on Application_Document__c (after insert, after update) {
    ApplicationDocumentTriggerHandler handler = new ApplicationDocumentTriggerHandler(Trigger.newMap, Trigger.oldMap);
    switch on Trigger.operationType {
        when AFTER_INSERT {
            handler.updateRelatedApplicationDocumentsName();
        }
        when AFTER_UPDATE {
            handler.changedForSignatureAppDocument();
        }
    }
}