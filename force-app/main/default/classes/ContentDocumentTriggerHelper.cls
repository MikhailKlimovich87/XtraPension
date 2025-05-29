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

    public static void changeLastUploadedDateField(List<ContentDocument> newDocs) {
        Set<Id> uploadedDocs = new Set<Id>();
        for (ContentDocument doc : newDocs) {
            if (doc.Title.contains('UPLOAD')) {
                uploadedDocs.add(doc.Id);
            }
        }
        if (uploadedDocs.isEmpty()) {
            return;
        }
        List<ContentDocumentLink> uploadContLinks = [
            SELECT
                LinkedEntityId,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :uploadedDocs
        ];
        if (uploadContLinks.isEmpty()) {
            return;
        }
        Map<Id, Application__c> updateApps = new Map<Id, Application__c>();
        for (ContentDocumentLink link : uploadContLinks) {
            Schema.SObjectType typeOfRecord = Id.valueOf(link.LinkedEntityId).getSobjectType();
            if(Schema.Application__c.SObjectType != typeOfRecord) {
                continue;
            }
            updateApps.put(
                link.LinkedEntityId,
                new Application__c (
                    Id       = link.LinkedEntityId,
                    Date_of_Last_Doc_Upload__c = Date.today()
                )
            );
        }
        if (!updateApps.isEmpty()) {
            update updateApps.values();
        }
    }
}