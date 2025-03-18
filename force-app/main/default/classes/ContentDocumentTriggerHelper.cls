public class ContentDocumentTriggerHelper {

    public static void saveNoteOnRelatedApplication(List<ContentDocument> newDocs) {
        Set<Id> noteDocs = new Set<Id>();
        for (ContentDocument doc : newDocs) {
            if (doc.FileType == 'SNOTE') {
                noteDocs.add(doc.Id);
            }
        }
        if (noteDocs.isEmpty()) {
            return;
        }
        List<ContentDocumentLink> notesContLinks = [
            SELECT
                LinkedEntityId,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :noteDocs
        ];
        if (notesContLinks.isEmpty()) {
            return;
        }
        Map<Id, Application__c> updateApps = new Map<Id, Application__c>();
        for (ContentDocumentLink link : notesContLinks) {
            Schema.SObjectType typeOfRecord = Id.valueOf(link.LinkedEntityId).getSobjectType();
            if(Schema.Application__c.SObjectType != typeOfRecord) {
                continue;
            }
            updateApps.put(
                link.LinkedEntityId,
                new Application__c (
                    Id       = link.LinkedEntityId,
                    Notes__c = link.ContentDocument.LatestPublishedVersion.VersionData.toString()
                )
            );
        }
        if (!updateApps.isEmpty()) {
            update updateApps.values();
        }
    }
}