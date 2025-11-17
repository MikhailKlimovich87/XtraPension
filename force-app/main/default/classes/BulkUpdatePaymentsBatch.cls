public class BulkUpdatePaymentsBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
    public final String Query;

    public BulkUpdatePaymentsBatch(String q) {
        Query = q;
    }

    public Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<Payment__c> payments) {
        List<Payment__c> updatedPayments = new List<Payment__c>();
        for(Payment__c payment : payments){
            Map<String, String> requestParams = new Map<String, String>();
            requestParams.put('metadata[AppNo]',payment.Application__r.Name);
	        StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
		        'payment_intents/' + payment.Payment_Intent__c,
		        'POST',
		        requestParams
	        );
            if (requestResult.isError != true) {
                updatedPayments.add(
                    new Payment__c(
                        Id = payment.Id,
                        isSyncAppData__c = true
                    )
                );
		    } else {
                updatedPayments.add(
                    new Payment__c(
                        Id = payment.Id,
                        Stripe_Error_Message__c = requestResult.errorMessage
                    )
                );
            }
        }
        if (updatedPayments.size() != 0) {
            Database.update(updatedPayments, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}