global class SchedulePaymentBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    global String query =
        'SELECT ' +
            'Order__c, ' +
            'Product__c, ' +
            'Payment_Date__c, ' +
            'Status__c, ' +
            'Payment_Method__c, ' +
            'Customer_Id__c, ' +
            'Application__r.Email__c, ' +
            'CurrencyIsoCode, ' +
            'Tax_VAT__c ' +
        'FROM Payment__c ' +
        'WHERE Status__c = \'Schedule\' AND ' +
            '(Payment_Date__c = TODAY OR ' +
            'Payment_Date__c = YESTERDAY)';

    global Database.QueryLocator start(Database.BatchableContext BC) {
        Date todayDate = Date.today();
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext BC, List<Payment__c> payments) {
        ApplicationService service = new ApplicationService();
        service.executeStripePayment(payments);
    }

    global void finish(Database.BatchableContext BC){}
}