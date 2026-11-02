public class BulkChargePaymentBatch implements Database.Batchable<sObject>, Database.AllowsCallouts {
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

	public Database.QueryLocator start(Database.BatchableContext bc) {
		return Database.getQueryLocator([
			SELECT
				Name,
				Application__c,
				Application__r.Name,
				Application__r.Status__c,
				Application__r.First_Name__c,
				Application__r.Second_Name__c,
				Application__r.Email__c,
				Application_Name__c,
				Status__c,
				CurrencyIsoCode,
				Customer_Id__c,
				Payment_Method__c,
				Amount__c,
				Product__r.Name,
				Payment_Info_Link__c,
				Payment_Link__c
			FROM Payment__c
			WHERE (Product_Name__c = 'Application' OR
				   Product_Name__c = 'Appeal Application') AND
				   Status__c = 'Fail' AND
				  (Application__r.Status__c = 'Posted' OR
				   Application__r.Status__c = '64-8 Bounce' OR
				   Application__r.Status__c = 'HMRC Reply 1' OR
				   Application__r.Status__c = 'DWP Teleclaim' OR
				   Application__r.Status__c = 'DWP 2 Emails Sent' OR
				   Application__r.Status__c = 'XP Letter Sent' OR
				   Application__r.Status__c = 'HMRC Appeal' OR
				   Application__r.Status__c = 'DWP Appeal' OR
				   Application__r.Status__c = 'HMRC Reply 2' OR
				   Application__r.Status__c = 'Send to Client')
			ORDER BY Application__r.Name DESC
			LIMIT 1
		]);
	}

	public void execute(Database.BatchableContext bc, List<Payment__c> payments) {
		if(payments.size() == 0) return;
		Payment__c payment = payments[0];

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
		String newPaymentIntentResult = '';
		StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'payment_intents',
			'POST',
			paymentIntentParams
		);
		if (requestResult.isError != true) {
			newPaymentIntentResult = requestResult.responseBody;
			Map<String,Object> intentData = (Map<String,Object>) JSON.deserializeUntyped(newPaymentIntentResult);
			if (Test.isRunningTest()) {
				payment.Card_Data__c = 'visa - 4242';
			} else {
				StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
					'payment_methods/' + intentData.get('payment_method'),
					'GET',
					null
				);
				Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
				Map<String,Object> cardData = (Map<String,Object>)methodData.get('card');
				payment.Card_Data__c = cardData.get('brand') + ' - ' + cardData.get('last4');
			}
			payment.Status__c = 'Paid';
			payment.Payment_Date__c   = Date.today();
			payment.Payment_Intent__c = (String) intentData.get('id');
			payment.Source__c         = (String) intentData.get('latest_charge');
			update payment;
		} else {
	 		String errorMessage = requestResult.errorMessage;
			payment.Error_Message__c = errorMessage;

			payment.Fail_Payment_Date__c = Datetime.now();

			update payment;
			sendFailNotification(payment);
		}
   }

	public void finish(Database.BatchableContext bc) {
	}

	private static void sendFailNotification(Payment__c currPay) {
		if (currPay == null) return;
		String htmlBody =
				'<html style=\'overflow-y: hidden;\'>'+
					'<head>' +
						'<style type=\'text/css\'>'+
							'* {' +
								'margin: 0px;' +
								'padding: 0px;' +
								'box-sizing: border-box;' +
								'text-decoration: none;' +
							'}' +
							'.link-data {' +
								'color: #1aa2b0;' +
								'text-decoration: underline' +
							'}' +
						'</style>' +
					'</head>' +
					'<body>' +
						'<div> Hi ' + currPay.Application__r.First_Name__c + '</div>' +
						'<br />' +
						'<div> Please pay the outstanding payment now via this link: </div>' +
						'<div>' +
							'<a href=\'' + currPay.Payment_Link__c + '\' class=\'link-data\'>' + currPay.Payment_Link__c + '</a>' +
						'</div>' +
						'<br />' +
						'<div> Our fees remain unchanged and are outlined here: </div>' +
						'<div>' +
							'<a href=\'' + currPay.Payment_Info_Link__c + '\' class=\'link-data\'>' + currPay.Payment_Info_Link__c + '</a>' +
						'</div>' +
						'<br/>' +
						'<div>Best wishes</div>' +
						'<div>Client Support</div>' +
						'<br/>' +
						'<div>XtraPension Ltd</div>' +
						'<div>Galway, Ireland</div>' +
						'<br/>' +
						'<div>M-F: 8-6pm. Sat: 9-3pm</div>' +
						'<div><a href=\'https://xtrapension.com\' class=\'link-data\'>https://xtrapension.com</a></div>' +
					'</body>' +
				'</html>';
		String subject = currPay.Application_Name__c + ' - ' + currPay.Application__r.First_Name__c + ' ' + currPay.Application__r.Second_Name__c + ' - Outstanding Payment';

		Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
		message.setUseSignature(false);
		message.setSaveAsActivity(true);
		message.setTreatTargetObjectAsRecipient(false);
		message.setWhatId(currPay.Application__c);
		if ( OWD != null ) {
			message.setOrgWideEmailAddressId(OWD.Id);
		}
		message.setSubject(subject);
		message.setHtmlBody(htmlBody);
		message.toAddresses = new String[]{currPay.Application__r.Email__c};

		Messaging.SendEmailResult[] result = Messaging.sendEmail(
			new List<Messaging.SingleEmailMessage>{message}
		);
	}
}