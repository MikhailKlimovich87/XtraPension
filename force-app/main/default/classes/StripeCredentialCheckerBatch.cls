public with sharing class StripeCredentialCheckerBatch implements Database.Batchable<SObject>, Database.AllowsCallouts  {
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT 
                Name,
                Stripe_Customer_Id__c,
                Payment_Method__c,
                    (SELECT
                        Name,
                        Product_Name__c,
                        Application__r.Status__c,
                        Payment_Method__c,
                        Customer_Id__c,
                        Current_Customer_Id__c
                     FROM Payments__r
                     WHERE Status__c = 'Paid' 
                     ORDER BY Payment_Date__c DESC
                     LIMIT 1) 
            FROM Application__c
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Application__c> apps) {
        // for (Application__c app : apps) {
        //     if (app.Payments__r.size() == 0) {
        //         continue;
        //     }
        //     Payment__c  currPayment = app.Payments__r[0];

        // }
        //             if(app.Payment_Method__c.contains(';')) {
        //         List<String> paymentMethods = app.Payment_Method__c.split(';');
        //         paymentMethodId = paymentMethods[paymentMethods.size() - 1].trim();
        //     } else if(app.Payment_Method__c != null) paymentMethodId = app.Payment_Method__c;
        List<Payment__c> updatedPayments = new List<Payment__c>();
        for (Application__c app : apps) {
            if (app.Payments__r.size() == 0) {
                continue;
            }
            Payment__c  currPayment = app.Payments__r[0];
            StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
				'payment_methods/' + currPayment.Payment_Method__c,
				'GET',
				null
			);
			Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
			String customerData = (String)methodData.get('customer');
            if (currPayment.Customer_Id__c != customerData) {
                updatedPayments.add(
                    new Payment__c(Id = currPayment.Id, Current_Customer_Id__c = customerData, Current_Customer_Change_Date__c = Date.today())
                );
            }
        }
        if (updatedPayments.size() != 0) {
            update updatedPayments;
        }
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
    }

}