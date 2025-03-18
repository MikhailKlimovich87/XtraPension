public class PayFailPaymentController {
    @AuraEnabled(cacheable='true')
    public static String chargePayment(String paymentId) {
        if (paymentId == null) {
            throw new FailPaymentException('Payment Id is null');
        }
        List<Payment__c> failPayment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c,
                CurrencyIsoCode
            FROM Payment__c
            WHERE Id = :paymentId AND
                  Status__c != 'Paid'
            LIMIT 1
        ];
        if (failPayment.isEmpty()) {
            throw new FailPaymentException('Don\'t exist Fail payment for application');
        }
        try {
            List<Payment__c> payments = new List<Payment__c>();
            ApplicationService service = new ApplicationService();
            service.executeStripePayment(failPayment);
            return failPayment[0].Id;
        } catch (Exception ex) {
            throw new FailPaymentException('You have error in dml operation: ' + ex.getMessage());
        }
    }

    public class FailPaymentException extends Exception {}
}