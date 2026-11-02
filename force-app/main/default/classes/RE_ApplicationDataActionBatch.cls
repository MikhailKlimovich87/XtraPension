public class RE_ApplicationDataActionBatch  implements Database.Batchable<SObject> {
    public String extrCondition;
    public RE_ApplicationDataActionBatch(String cond) {
        this.extrCondition = cond;
    }
    public RE_ApplicationDataActionBatch() {
        this.extrCondition = '';
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        String query = 
            'SELECT Id, Name, ' +
            '(SELECT Id FROM Reapplies__r) ' + 
            'FROM Application__c ';
        if (String.isNotBlank(extrCondition)) query += ' WHERE ' + extrCondition;
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext context, List<Application__c> scope) {
        if (scope.size() == 0) {
            return;
        }
        for (Application__c app : scope) {
            if (app.Reapplies__r.size() == 0) {
                RE_ApplicationDataAction.createRelatedReapply(app.Id);
            }
        }
    }


    public void finish(Database.BatchableContext context) {}
}