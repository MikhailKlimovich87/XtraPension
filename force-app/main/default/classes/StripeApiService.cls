public class StripeApiService {
	private static final User RECIPIENT_USER {
        get {
            if (RECIPIENT_USER == null) {
                List<User> users = [
            		SELECT
                		Id,
                		Email
                    FROM User
                    WHERE Email = 'ciara@xtrapension.com'
                    LIMIT 1
                ];
                if (!users.isEmpty()) {
                    RECIPIENT_USER = users[0];
                }
            }
            return RECIPIENT_USER;
        }
        private set;
    }
    private static final CustomNotificationType AGENT_NOTIFICATION {
        get {
            if (AGENT_NOTIFICATION == null) {
                List<CustomNotificationType> notificationType = [
                    SELECT
                        Id,
                        DeveloperName
                    FROM CustomNotificationType
                    WHERE DeveloperName = 'Doc_Agent_Notification'
                    LIMIT 1
                ];
                if (!notificationType.isEmpty()) {
                    AGENT_NOTIFICATION = notificationType[0];
                }
            }
            return AGENT_NOTIFICATION;
        }
        private set;
    }

	private static final OrgWideEmailAddress OWD {
        get {
            if (OWD == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    OWD = orgWideEmailAddresses[0];
                }
            }
            return OWD;
        }
        private set;
    }

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
				Application_Name__c,
				Application__r.Contact__c,
				Application__r.Email__c,
				Client_First_Name__c,
				Client_Second_Name__c,
				Product_Name__c,
				Payment_Intent__c,
				Source__c,
				Repeated_Payment_Date_1__c,
				Repeated_Payment_Date_2__c,
				Repeated_Payment_Date_3__c,
				Fail_Payment_Date__c
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
			if(currentPayment.Repeated_Payment_Date_3__c != null &&
			   currentPayment.Repeated_Payment_Date_3__c == Date.today() &&
			   currentPayment.Repeated_Payment_Date_2__c < Date.today() &&
			   currentPayment.Repeated_Payment_Date_1__c < Date.today()) {
			   sendFailNotification(currentPayment);
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
			if(currentPayment.Repeated_Payment_Date_3__c != null &&
			   currentPayment.Repeated_Payment_Date_3__c == Date.today() &&
			   currentPayment.Repeated_Payment_Date_2__c < Date.today() &&
			   currentPayment.Repeated_Payment_Date_1__c < Date.today()) {
				sendFailNotification(currentPayment);
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
			PaymentTriggerHandler.sendReceipt(new List<Payment__c>{currentPayment}, true);
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

	private static void sendFailNotification(Payment__c currPay) {
		if (currPay == null) return;
		String subject = '[URGENT] ' +  currPay.Application_Name__c + ' - ' + currPay.Client_First_Name__c + ' ' + currPay.Client_Second_Name__c + ' - ' + currPay.Product_Name__c + ' Fee - PAYMENT Failed (3x)';
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setTitle(subject);
        notification.setBody(currPay.Application_Name__c + ' - ' + currPay.Product_Name__c + ' Fee - PAYMENT Failed (3x)');
        notification.setNotificationTypeId(AGENT_NOTIFICATION.Id);
        notification.setTargetId(currPay.Application__c);
		if(RECIPIENT_USER == null) return;
        notification.send(new Set<String> {RECIPIENT_USER.Id});

		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currPay.Application__c);
        if ( OWD != null ) {
            message.setOrgWideEmailAddressId(OWD.Id);
        }
        message.setSubject(subject);
        message.setPlainTextBody('');
        message.toAddresses = new String[]{RECIPIENT_USER.Email};

        Messaging.SendEmailResult[] result = Messaging.sendEmail(
			new List<Messaging.SingleEmailMessage>{message}
		);
	}

    public class StripeApiException extends Exception{
	}
}