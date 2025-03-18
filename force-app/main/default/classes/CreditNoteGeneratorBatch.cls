public with sharing class CreditNoteGeneratorBatch implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts{
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Payment__c
            FROM Credit_Note__c
            WHERE Is_Generated_PDF__c = false
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Credit_Note__c> creditNotes) {
        if (!creditNotes.isEmpty()) {
            for (Credit_Note__c note : creditNotes) {
                CreditNoteHelper.generateCreditNotePdf(note.Payment__c);
            }
        }
    }

    public void finish(Database.BatchableContext BC) {
        //notification with errors
        //notification With success
    }
}