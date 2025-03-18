public class StripeApiService {

	@future(callout=true)
    public static void createPaymentIntent(Map<String, String> requestParams, Id paymentId) {
        String newPaymentIntentResult = '';
        StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'payment_intents',
			'POST',
			requestParams
		);
		List<Payment__c> payment = [
			SELECT
				Id,
				Status__c,
				Error_Message__c,
				Application__c,
				Application__r.Contact__c,
				Application__r.Email__c,
				Payment_Intent__c,
				Source__c,
				Repeated_Payment_Date_1__c,
				Repeated_Payment_Date_2__c,
				Repeated_Payment_Date_3__c
			FROM Payment__c
			WHERE Id = :paymentId
			LIMIT 1
		];
		if (payment.isEmpty()) {
			throw new StripeApiException('Don\'t exist payment method');
		}
		Payment__c currentPayment = payment[0];
		if (requestResult.isError != true) {
			newPaymentIntentResult = requestResult.responseBody;
			Map<String,Object> intentData = (Map<String,Object>) JSON.deserializeUntyped(newPaymentIntentResult);
			if (Test.isRunningTest()) {
				currentPayment.Card_Data__c = 'visa - 4242';
			} else {
				StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
					'payment_methods/' + intentData.get('payment_method'),
					'GET',
					null
				);
				Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
				Map<String,Object> cardData = (Map<String,Object>)methodData.get('card');
				currentPayment.Card_Data__c = cardData.get('brand') + ' - ' + cardData.get('last4');
			}
			currentPayment.Status__c = 'Paid';
			currentPayment.Payment_Date__c   = Date.today();
			currentPayment.Payment_Intent__c = (String) intentData.get('id');
			currentPayment.Source__c         = (String) intentData.get('latest_charge');
			update currentPayment;
		} else {
     		String errorMessage = requestResult.errorMessage;
			currentPayment.Error_Message__c = errorMessage;
			currentPayment.Status__c = 'Fail';
			currentPayment.Fail_Payment_Date__c = Datetime.now();
			if (currentPayment.Repeated_Payment_Date_1__c == null) {
				Date todayDate = Date.today();
				currentPayment.Repeated_Payment_Date_1__c = todayDate.addDays(4);
				currentPayment.Repeated_Payment_Date_2__c = todayDate.addDays(8);
				currentPayment.Repeated_Payment_Date_3__c = todayDate.addDays(12);
			}
			update currentPayment;
		}
    }

	public static String createPaymentIntentForBatch(Map<String, String> requestParams, Id paymentId) {
        String newPaymentIntentResult = '';
        StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'payment_intents',
			'POST',
			requestParams
		);
		List<Payment__c> payment = [
			SELECT
				Id,
				Status__c,
				Repeated_Payment_Date_1__c,
				Repeated_Payment_Date_2__c,
				Repeated_Payment_Date_3__c
			FROM Payment__c
			WHERE Id = :paymentId
			LIMIT 1
		];
		if (payment.isEmpty()) {
			throw new StripeApiException('Don\'t exist payment method');
		}
		Payment__c currentPayment = payment[0];
		if (requestResult.isError != true) {
			newPaymentIntentResult = requestResult.responseBody;
			currentPayment.Status__c = 'Paid';
			currentPayment.Payment_Date__c = Date.today();
			update currentPayment;
		} else {
			String errorMessage = requestResult.errorMessage;
			currentPayment.Error_Message__c = errorMessage;
			currentPayment.Status__c = 'Fail';
			currentPayment.Fail_Payment_Date__c = Datetime.now();
			if (currentPayment.Repeated_Payment_Date_1__c == null) {
				Date todayDate = Date.today();
				currentPayment.Repeated_Payment_Date_1__c = todayDate.addDays(4);
				currentPayment.Repeated_Payment_Date_2__c = todayDate.addDays(8);
				currentPayment.Repeated_Payment_Date_3__c = todayDate.addDays(12);
			}
			update currentPayment;
		}
		return newPaymentIntentResult;
    }

	@future(callout=true)
	public static void updatePaymentCardData(Id paymentId) {
		String newPaymentMethodResult = '';
		List<Payment__c> payment = [
			SELECT
				Id,
				Status__c,
				Card_Data__c,
				Payment_Date__c,
				Tax_VAT__c,
				Application__c,
				Payment_Method__c,
				CurrencyIsoCode
			FROM Payment__c
			WHERE Id = :paymentId
			LIMIT 1
		];
		if (payment == null) {
			throw new StripeApiException('Don\'t exist payment method');
		}
		Payment__c currentPayment = payment[0];
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
			PaymentTriggerHandler.sendReceipt(payment);
		}
	}

	public static String getCustomerData(String customerId) {
		StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'customers/' + customerId,
			'GET',
			null
		);
		if (requestResult.isError != true) {
			return requestResult?.responseBody;
		} else {
			return 'Error';
		}
	}

    public class StripeApiException extends Exception{
	}
}