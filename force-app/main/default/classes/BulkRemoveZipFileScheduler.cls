public class BulkRemoveZipFileScheduler implements Schedulable {
    public void execute(SchedulableContext SC) {
        String query =
            'SELECT ' +
                'Id,' +
                'ContentDocumentId,' +
                'ContentDocument.Title,' +
                'ContentDocument.CreatedDate,' +
                'LinkedEntityId,' +
                'ContentDocument.ContentSize,' +
                'ContentDocument.FileExtension,' +
                'LinkedEntity.Name,' +
                'LinkedEntity.Id ' +
            'FROM ContentDocumentLink ' +
            'WHERE LinkedEntityId IN (' +
                        'SELECT Id ' +
                        'FROM Application__c ' +
                        'WHERE Status__c != \'Form In Progress\' AND ' +
                            'Status__c != \'Form Completed\' AND ' +
                            'Status__c != \'NINO/Doc Needed\' AND ' +
                            'Status__c != \'Pending Client\' AND ' +
                            'Status__c != \'Fix\' AND ' +
                            'Status__c != \'Agent Check\' AND ' +
                            'Status__c != \'QC Approved\' AND ' +
                            'Status__c != \'Sent for eSignature\' AND ' +
                            'Status__c != \'Signed\' AND ' +
                            'Status__c != \'Iffy List\' AND ' +
                            'Status__c != \'Printing House\' AND ' +
                            'Status__c != \'NO NINO\') AND ' +
                    'ContentDocument.FileExtension = \'zip\' AND ' +
                    'ContentDocument.Title LIKE \'%_ZIP\' AND ' +
                    'ContentDocument.CreatedDate = N_DAYS_AGO:10 ' +
            'ORDER BY ContentDocument.CreatedDate';
        Database.executeBatch(new BulkRemoveBatch(query), 1);
    }
}