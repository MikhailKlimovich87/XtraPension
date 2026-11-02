/**
 * After-insert hook on EmailMessage: if the row is related to a
 * AA_Application__c AND we have a matching Contact by email address, add
 * an EmailMessageRelation row pointing at that Contact. That populates the
 * Activity Timeline avatar/name (which needs RelationId, not just
 * RelationAddress).
 *
 * Idempotent — the helper only inserts EMR rows whose (EmailMessageId,
 * RelationId, RelationType) triple doesn't already exist.
 */
trigger AA_EmailMessageAutoLinkTrigger on EmailMessage (after insert) {
    AA_EmailMessageAutoLinkHelper.linkContacts(Trigger.new);
}