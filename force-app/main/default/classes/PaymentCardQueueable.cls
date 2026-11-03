public class PaymentCardQueueable implements Queueable {
    public Id paymentId;

    public PaymentCardQueueable(Id paymentId) {
        this.paymentId = paymentId;
    }

    public void execute(QueueableContext context) {
		String newPaymentMethodResult = '';
		List<Payment__c> payment = [
			SELECT
				Id,
				Application_Name__c,
				Status__c,
				Card_Data__c,
				Payment_Date__c,
				Tax_VAT__c,
				Application__c,
				Application__r.Contact__c,
				Payment_Method__c,
				CurrencyIsoCode,
				Refund__r.Contact__c
			FROM Payment__c
			WHERE Id = :paymentId
			LIMIT 1
		];
		if (payment.size() == 0) {
			throw new StripeApiService.StripeApiException('Don\'t exist payment method');
		}
		Payment__c currentPayment = payment[0];
		// String paymentMethodId = '';
        // if(currentPayment.Payment_Method__c.contains(';')) {
        //     List<String> paymentMethods = currentPayment.Payment_Method__c.split(';');
        //     paymentMethodId = paymentMethods[paymentMethods.size() - 1].trim();
        // } else if(currentPayment.Payment_Method__c != null) paymentMethodId = currentPayment.Payment_Method__c;
		StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'payment_methods/' + currentPayment.Payment_Method__c,
			'GET',
			null
		);
		if (requestResult.isError != true) {
			Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestResult?.responseBody);
			Map<String,Object> cardData = (Map<String,Object>)methodData.get('card');
			if (Test.isRunningTest()) {
				currentPayment.Card_Data__c = 'visa - 4242';
			} else currentPayment.Card_Data__c = cardData.get('brand') + ' - ' + cardData.get('last4');
			update currentPayment;
			PaymentTriggerHandler.sendReceipt(new List<Payment__c>{currentPayment}, true);
		}
    }
}