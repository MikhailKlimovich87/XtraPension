trigger ContentDocumentTrigger on ContentDocument (after insert, after update) {
    ContentDocumentTriggerHelper.changeLastUploadedDateField(Trigger.new);
    ContentDocumentTriggerHelper.saveNoteOnRelatedApplication(Trigger.new);
}