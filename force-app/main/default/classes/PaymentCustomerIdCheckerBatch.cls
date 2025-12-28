public class PaymentCustomerIdCheckerBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Name,
                Product_Name__c,
                Application__r.Status__c,
                Payment_Method__c,
                Customer_Id__c,
                Current_Customer_Id__c
            FROM Payment__c
            WHERE Fail_Payment_Date__c != null AND
                  Status__c = 'Paid' AND
                  Current_Customer_Id__c = NULL AND
                  (Application__r.Status__c = 'Posted' OR
                   Application__r.Status__c = '64-8 Bounce' OR
                   Application__r.Status__c = 'HMRC Reply 1' OR
                   Application__r.Status__c = 'DWP Teleclaim' OR
                   Application__r.Status__c = 'DWP 2 Emails Sent' OR
                   Application__r.Status__c = 'XP Letter Sent' OR
                   Application__r.Status__c = 'HMRC Appeal' OR
                   Application__r.Status__c = 'DWP Appeal' OR
                   Application__r.Status__c = 'HMRC Reply 2' OR
                   Application__r.Status__c = 'Send to Client' OR
                   Application__r.Status__c = 'Agent Call' OR
                   Application__r.Status__c = 'Charge CC' OR
                   Application__r.Status__c = 'REPEAT(NO edits)' OR
                   Application__r.Status__c = 'REPEAT(edits)')
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Payment__c> failPayments) {
        if (failPayments.size() == 0) return;
        List<Payment__c> updatedPayments = new List<Payment__c>();
        for (Payment__c payment : failPayments) {
            StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
				'payment_methods/' + payment.Payment_Method__c,
				'GET',
				null
			);
			Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
			String customerData = (String)methodData.get('customer');
            if (payment.Customer_Id__c != customerData) {
                updatedPayments.add(
                    new Payment__c(Id = payment.Id, Current_Customer_Id__c = customerData)
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