trigger ContentDocumentTrigger on ContentDocument (after insert, after update) {
    ContentDocumentTriggerHelper.saveNoteOnRelatedApplication(Trigger.new);
}