public class BulkUpdatePaymentsScheduler implements Schedulable {

    public void execute(SchedulableContext SC) {
        BulkUpdatePaymentsBatch batchPayment = new BulkUpdatePaymentsBatch(
            'SELECT Id, ' +
                   'Status__c, ' +
                   'isSyncAppData__c, ' +
                   'Product_Name__c, ' +
                   'Payment_Date__c, ' +
                   'Payment_Intent__c, ' +
                   'Application__r.Name ' +
            'FROM Payment__c ' +
            'WHERE Payment_Date__c = YESTERDAY AND ' +
                  'isSyncAppData__c = false AND ' +
                  '(Status__c = \'Paid\' OR ' +
                   'Status__c = \'Refund\' OR ' +
                   'Status__c = \'Fail\') AND ' +
                   'Payment_Intent__c != null ' +
            'ORDER BY Payment_Date__c'
        );
        Database.executeBatch(batchPayment, 1);
    }
}