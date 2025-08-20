public class BuleRemoveBatch implements Database.Batchable<sObject>{
    public final String Query;

    public BuleRemoveBatch(String q) {
        Query=q;
    }

    public Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Application__c> apps) {
        List<ContentDocument> removeDocs = new List<ContentDocument>();
        Set<Id> notEmptyDocsApps = new Set<Id>();
        for(Application__c app : apps){
            if(app.ContentDocumentLinks.size() != 0) {
       	        notEmptyDocsApps.add(app.Id);
                for(ContentDocumentLink link : app.ContentDocumentLinks) {
                    removeDocs.add(
       			        new ContentDocument(Id = link.ContentDocumentId)
    		        );
                }
            }
            if(notEmptyDocsApps.size() > 200) break;
        }
        Database.delete(removeDocs, false);
   }

    public void finish(Database.BatchableContext bc){

    }
}