public class ApplicationService {

    public void executeStripePayment(List<Payment__c> payments) {
        List<Payment__c> updatePayment = new List<Payment__c>();
        for (Payment__c payment : payments) {
            Map<String, String> paymentIntentParams = new Map<String, String> {
                'currency'                                   => payment.CurrencyIsoCode,
                'confirm'                                    => 'true',
                'customer'                                   => payment?.Customer_Id__c,
                'payment_method'                             => payment?.Payment_Method__c,
                'amount'                                     => String.valueOf(Integer.valueOf(payment?.Amount__c * 100)),
                'description'                                => payment.Product__r.Name,
                'automatic_payment_methods[enabled]'         => 'true',
                'automatic_payment_methods[allow_redirects]' => 'never',
                'payment_method_options[card][moto]'         => 'true'
            };
            if(System.IsBatch() == false && System.isFuture() == false) {
                StripeApiService.createPaymentIntent(paymentIntentParams, payment.Id);
            } else {
                String paymentIntentenResult = StripeApiService.createPaymentIntentForBatch(paymentIntentParams, payment.Id);
                if (String.isNotBlank(paymentIntentenResult)) {
                    payment.Status__c = 'Paid';
                    payment.Payment_Date__c = Date.today();
                    updatePayment.add(payment);
                }
            }
        }
        update updatePayment;
    }
}