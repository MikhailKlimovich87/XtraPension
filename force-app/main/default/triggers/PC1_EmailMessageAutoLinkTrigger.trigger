/**
 * After-insert hook on EmailMessage: if the row is related to a
 * PC1_Application__c AND we have a matching Contact by email address, add
 * an EmailMessageRelation row pointing at that Contact. That populates the
 * Activity Timeline avatar/name (which needs RelationId, not just
 * RelationAddress).
 *
 * Idempotent — the helper only inserts EMR rows whose (EmailMessageId,
 * RelationId, RelationType) triple doesn't already exist.
 */
trigger PC1_EmailMessageAutoLinkTrigger on EmailMessage (after insert) {
    PC1_EmailMessageAutoLinkHelper.linkContacts(Trigger.new);
}