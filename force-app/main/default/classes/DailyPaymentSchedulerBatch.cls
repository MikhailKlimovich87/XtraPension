public class DailyPaymentSchedulerBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
   public Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator([
            SELECT
                Name,
                Product__r.Name,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c,
                CurrencyIsoCode
            FROM Payment__c
            WHERE (Status__c = 'Schedule' AND
                  Payment_Date__c = TODAY) OR
                  (Status__c = 'Fail' AND
                  Repeated_Payment_Date_1__c = TODAY) OR
                  (Status__c = 'Fail' AND
                  Repeated_Payment_Date_2__c = TODAY) OR
                  (Status__c = 'Fail' AND
                  Repeated_Payment_Date_3__c = TODAY)
        ]);
   }

    public void execute(Database.BatchableContext bc, List<Payment__c> payments) {
        if (payments.size() == 0) {
            return;
        }
        ApplicationService service = new ApplicationService();
        service.executeStripePayment(payments);
    }

   public void finish(Database.BatchableContext bc){
   }
}