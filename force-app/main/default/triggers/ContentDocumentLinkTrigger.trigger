trigger ContentDocumentLinkTrigger on ContentDocumentLink (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        ContentDocumentLinkTriggerHelper.afterInsert(Trigger.new);
    }
}