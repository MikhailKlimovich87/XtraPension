trigger ContentVersionTrigger on ContentVersion (after insert, after update) {
    ContentVersionTriggerHandler.linkFileToApplicationDocument(Trigger.new);
}