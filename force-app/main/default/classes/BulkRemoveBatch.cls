public class BulkRemoveBatch implements Database.Batchable<sObject> {
    public final String Query;

    public BulkRemoveBatch(String q) {
        Query = q;
    }

    public Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<ContentDocumentLink> links) {
        List<ContentDocument> removeDocs = new List<ContentDocument>();
        for(ContentDocumentLink link : links){
            removeDocs.add(
       			new ContentDocument(Id = link.ContentDocumentId)
    		);
        }
        Database.delete(removeDocs, false);
   }

    public void finish(Database.BatchableContext bc) {
    }
}