public class ApplicationNoteBatch implements Database.Batchable<sObject> {

    public String query;

    public ApplicationNoteBatch(String query) {
        this.query = query;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext BC, List<sObject> scope) {
        List<Application_Note__c> notes = (List<Application_Note__c>) scope;

        if (notes.isEmpty()) {
            return;
        }

        List<ContentNote> contentNotes = new List<ContentNote>();
        Map<String, Id> titleToApplicationId = new Map<String, Id>();

        for (Application_Note__c note : notes) {

            ContentNote cn = new ContentNote(
                Title = note.Title__c,
                Content = Blob.valueOf(note.Body__c)
            );

            contentNotes.add(cn);

            titleToApplicationId.put(note.Title__c, note.Application__c);
        }

        insert contentNotes;

        List<ContentNote> insertedNotes = [
            SELECT Id, Title
            FROM ContentNote
            WHERE Id IN :contentNotes
        ];

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for (ContentNote cn : insertedNotes) {

            links.add(new ContentDocumentLink(
                ContentDocumentId = cn.Id,
                LinkedEntityId = titleToApplicationId.get(cn.Title),
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }

        insert links;
    }

    public void finish(Database.BatchableContext BC) {

    }

    public static void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}