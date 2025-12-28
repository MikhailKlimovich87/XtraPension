@RestResource(urlMapping='/StripeWebhookApi/*')
global class StripeWebhookHandler {

	private static final String XTRAPENSION_LINK = XtraPension_Data__c.getInstance().Form_Link__c;
    private static final List<String> ORDER_OF_PRODUCT_NAME = new List<String> {
        'Deposit', 'Application', 'Success'
    };
	private static final List<String> ORDER_OF_APPEAL_PRODUCT = new List<String> {
        'Deposit', 'Appeal Application', 'Appeal Success'
    };

	private static final String DESCRIPTION = 'Deposit MOTO';
	private static final String ACOUNT_RECORD_TYPE_NAME = 'Business_Account';
	private static final String PERSON_ACCOUNT_RECORD_TYPE_ID = XtraPension_Data__c.getInstance().Person_Account_Record_Type_Id__c;
	private static final String REFUND_INFO_TEMPLATE_NAME = 'Refund Info';
	private static final String OWD_NAME = 'clients@xtrapension.com';

	private static final Map<String, String> STATE_CODES {
        get {
            if (STATE_CODES == null) {
				STATE_CODES = new Map<String, String>();
				List<Schema.PicklistEntry> values = Application__c.Current_Address_Abroad__StateCode__s
  					.getDescribe()
  					.getPickListValues();
				for (Schema.PicklistEntry v : values) {
    				STATE_CODES.put(v.getValue(), v.getLabel());
				}
            }
            return STATE_CODES;
        }
        private set;
    }

	@HttpPost
    global static String invokeRestResponse() {
		RestRequest request = RestContext.request;
		Map<String, Object> eventData         = (Map<String, Object>) JSON.deserializeUntyped(request.requestBody.toString());
		System.debug('request.requestBody.toString()' );
		String typeData                       = (String) eventData.get('type');
		if (typeData == 'payment_intent.succeeded') {
			Map<String, Object> objectData        = (Map<String, Object>) eventData.get('data');
			Map<String, Object> paymentIntentData = (Map<String, Object>) objectData.get('object');
			PaymentIntentWrapper paymentIntent    = (PaymentIntentWrapper) JSON.deserialize(JSON.serialize(paymentIntentData), PaymentIntentWrapper.class);
			Integer amount                        = paymentIntent.amount/100;
			String descriptionData                = paymentIntent.description;
			String currencyCode                   = ((String) paymentIntentData.get('currency')).toUpperCase();
			String leadId = paymentIntent?.metadata?.leadId;
			if (descriptionData.equals(DESCRIPTION)) {
				String customerData = StripeApiService.getCustomerData(paymentIntent?.customer);
				if (customerData == 'Error') {
					return 'Didn\'t find customer';
				}
				String customerId = paymentIntent?.customer;
				List<Application__c> apps = [
					SELECT Id
					FROM Application__c
					WHERE Stripe_Customer_Id__c = :customerId
				];
				if (!apps.isEmpty()) {
					return 'Apps has allready exist';
				}
				try {
					Map<String, Object> customer = (Map<String, Object>) JSON.deserializeUntyped(customerData);
					Account account = new Account();
					String phoneDuplicateFinder = '%' + paymentIntent?.shipping?.phone?.substring(1, paymentIntent?.shipping?.phone?.length() - 4) + '%';
					String personContactId = '';
					account = new Account(
						LastName                = paymentIntent?.shipping?.name,
						PersonEmail             = (String) customer.get('email'),
						PersonMobilePhone       = paymentIntent?.shipping?.phone,
						PersonMailingCity       = paymentIntent?.shipping?.address?.city,
						PersonMailingCountry    = paymentIntent?.shipping?.address?.country,
						PersonMailingState      = paymentIntent?.shipping?.address?.state,
						PersonMailingPostalCode = paymentIntent?.shipping?.address?.postal_code,
						PersonMailingStreet     = paymentIntent?.shipping?.address?.line1,
						Mailing_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(paymentIntent?.shipping?.address?.country),
						Mailing_State__c        = paymentIntent?.shipping?.address?.country == 'IE' ?
													paymentIntent?.shipping?.address?.state :
													CountryCodeHelper.getCountryStateNameByIsoCode(
														paymentIntent?.shipping?.address?.country,
														paymentIntent?.shipping?.address?.state),
						Mailing_Line_2__c       = paymentIntent?.shipping?.address?.line2
					);
					if (!Test.isRunningTest()) {
						account.RecordTypeId = PERSON_ACCOUNT_RECORD_TYPE_ID;
					}
					insert account;
					List<Contact> currentContact = [
						SELECT
							Id,
							AccountId
						FROM Contact
						WHERE AccountId = :account.Id
						LIMIT 1
					];
					if (!currentContact.isEmpty()) {
						personContactId = currentContact[0].Id;
					}
					List<Agent__c> mainAgent = [
						SELECT
							Id,
							Name
						FROM Agent__c
					];
					Id agentId = mainAgent.size() == 0 ? null : mainAgent[0].Id;
					String fullName = paymentIntent?.shipping?.name.trim();
					String lastName = fullName.substringAfterLast(' ');
					String firstName = fullName.removeEnd(lastName).trim();
					String stateName = '';
					if (paymentIntent?.shipping?.address?.country == 'IE') {
						stateName = CountryCodeHelper.getStateCodeByStateName(
							paymentIntent?.shipping?.address?.country,
							paymentIntent?.shipping?.address?.state.remove('County').trim());
					} else if(paymentIntent?.shipping?.address?.country == 'AE' ||
				          	paymentIntent?.shipping?.address?.country == 'MY' ||
						  	paymentIntent?.shipping?.address?.country == 'ID') {
                    	stateName = CountryCodeHelper.getStateCodeByStateName(
                        	paymentIntent?.shipping?.address?.country,
                        	paymentIntent?.shipping?.address?.state);
                	} else stateName = paymentIntent?.shipping?.address?.state;
					String currentStateValue = STATE_CODES.get(stateName);
					if (String.isBlank(currentStateValue) && String.isNotBlank(stateName)) {
						stateName = '';
                    	Application_Form_Error__c errorData = new Application_Form_Error__c();
                    	errorData.Error_Body__c = firstName + ' ' + lastName + ' - ' + account.PersonEmail + '\n' + 'State Code doesn\'t exist on the org. Please check it and add';
                    	errorData.Error_Date__c = Date.today();
                    	insert errorData;
					}
					String streetData = paymentIntent?.shipping?.address?.line1;
					if (String.isNotBlank(paymentIntent?.shipping?.address?.line2)) {
                    	streetData += ', ' + paymentIntent?.shipping?.address?.line2;
                	}
					Application__c application = new Application__c(
						First_Name__c                         = firstName,
						Second_Name__c                        = lastName,
						Expiry_Date__c                        = Datetime.now().addYears(1),
						Package_Name__c                       = 'Standard',
						Payment_Method__c                     = paymentIntent?.payment_method,
						Stripe_Customer_Id__c                 = paymentIntent?.customer,
						Status__c                             = 'Form In Progress',
						Is_Payment_Completed__c               = true,
						Last_Payment_Date__c                  = Date.today(),
						Step__c                               = 'Personal Details',
						Stripe_Transaction_Id__c              = paymentIntent?.id,
						Contact__c                            = personContactId,
						Personal_Details_Form_Link__c         = XTRAPENSION_LINK + paymentIntent?.id,
						Amount__c                             = paymentIntent?.amount != null ?
																paymentIntent?.amount / 100 : 0,
						Last_UK_Home_Address__CountryCode__s  = 'GB',
						Related_Contact_Phone__c              = account.PersonMobilePhone,
						Email__c                              = account.PersonEmail,
						Live_In_The_EU__c                     = currencyCode == 'EUR' ? true : false,
						Agent__c                              = mainAgent.size() == 0 ? null : mainAgent[0].Id,
						Pay_Voluntary_Contribution_At__c      = 'Class 2',
						Install_from_Website__c               = false,
						How_Did_You_Hear_About_Us__c          = paymentIntent?.metadata?.howDidYouHearAboutUs,
						Agent_Making_Sale__c                  = paymentIntent?.metadata?.agent,
						Appeal_Application__c                 = paymentIntent?.metadata?.class3Appeal != null?
																	Boolean.valueOf(paymentIntent?.metadata?.class3Appeal) :
																	false,
						Freeform_RichText_Line1__c            = XtraPensionConstants.FREEFORM_CLASS2_FIELD_DEFAULT_VALUE,
						Freeform_RichText_Line5__c            = XtraPensionConstants.FREEFORM_FIELD_DEFAULT_VALUE,
						Current_Address_Abroad__City__s       = paymentIntent?.shipping?.address?.city,
                    	Current_Address_Abroad__Street__s     = streetData,
                    	Current_Address_Abroad__StateCode__s  = stateName,
                    	Current_Address_Abroad__CountryCode__s= paymentIntent?.shipping?.address?.country,
                    	Current_Address_Abroad__PostalCode__s = paymentIntent?.shipping?.address?.postal_code,
						Has_NINO_Now__c                       = paymentIntent?.metadata?.hasNINONow != null ?
																Boolean.valueOf(paymentIntent?.metadata?.hasNINONow) :
																false,
						CurrencyIsoCode                       = currencyCode,
                    	Current_Address_Abroad_Country__c     = CountryCodeHelper.getCountryNameByIsoCode(paymentIntent?.shipping?.address?.country),
                    	Current_Address_Abroad_State__c       = paymentIntent?.shipping?.address?.country == 'IE' ?
																	paymentIntent?.shipping?.address?.state :
																	CountryCodeHelper.getCountryStateNameByIsoCode(
																		paymentIntent?.shipping?.address?.country,
																		paymentIntent?.shipping?.address?.state
																	),
						Delay__c                              = paymentIntent?.metadata?.isDelay != null?
																	Boolean.valueOf(paymentIntent?.metadata?.isDelay) :
																	false,
						Split__c                              = paymentIntent?.metadata?.isSplit != null?
																	Boolean.valueOf(paymentIntent?.metadata?.isSplit) :
																	false,
						Delay_Date__c                         = !String.isBlank(paymentIntent?.metadata?.delayDate)?
																	Date.valueOf(paymentIntent?.metadata?.delayDate) :
																	null,
						Split_Date__c                         = paymentIntent?.metadata?.isSplit == 'true' &&
																paymentIntent?.shipping?.address?.country == 'ZA' ?
																	Date.today() :
																	null
					);
					insert application;
					List<PriceBookEntry> priceBookEntries = new List<PriceBookEntry>();
					if (!Test.isRunningTest()) {
						priceBookEntries = [
							SELECT
								Id,
								Product2Id,
								Product2.Name,
								Pricebook2Id,
								Pricebook2.IsStandard,
								UnitPrice
							FROM PriceBookEntry
							WHERE Pricebook2.IsStandard = true AND
                              	  CurrencyIsoCode = :currencyCode
							ORDER BY UnitPrice
						];
					} else {
						priceBookEntries = [
                        	SELECT
                            	Id,
                            	Product2Id,
                            	Product2.Name,
                            	Pricebook2Id,
                            	Pricebook2.IsStandard,
                            	UnitPrice
                        	FROM PriceBookEntry
						];
					}
					if (priceBookEntries.isEmpty()) {
						return 'Empty pricebook entry';
					}
					Map<String, PriceBookEntry> productNameByPricebookEntry = new Map<String, PriceBookEntry>();
					for (PriceBookEntry price : priceBookEntries) {
						productNameByPricebookEntry.put(price.Product2.Name, price);
					}
					Order newOrder = new Order(
						Status          = 'Draft',
						EffectiveDate   = Date.today(),
						Pricebook2Id    = priceBookEntries[0].Pricebook2Id,
						AccountId       = account.Id,
						Application__c  = application.Id,
						CurrencyIsoCode = currencyCode
					);
					insert newOrder;
               		List<Sobject> newSobjects = new List<Sobject>();
					List<String> paymentOrder = new List<String>();
					if (application.Appeal_Application__c == true) {
						paymentOrder.addAll(ORDER_OF_APPEAL_PRODUCT);
					} else paymentOrder.addAll(ORDER_OF_PRODUCT_NAME);
     				for (String productName : paymentOrder) {
						PriceBookEntry entry = productNameByPricebookEntry.get(productName);
						if (entry == null) continue;
						newSobjects.add(
					    	new OrderItem(
								Product2Id       = entry.Product2Id,
								OrderId          = newOrder.Id,
								PricebookEntryId = entry.Id,
						    	Quantity         = 1,
								UnitPrice        = entry.UnitPrice
							)
						);
						if (entry.Product2.Name == 'Application' &&
							application.Current_Address_Abroad__CountryCode__s == 'ZA' &&
							application.Split__c == true) {
							for (Integer i = 0; i < 5; i++) {
								newSobjects.add(
									new Payment__c (
					 					Amount__c         = entry.UnitPrice / 5,
										Product__c        = entry.Product2Id,
										Status__c         = 'Draft',
										Payment_Method__c = application.Payment_Method__c,
										Customer_Id__c    = application.Stripe_Customer_Id__c,
										Order__c          = newOrder.Id,
										Application__c    = application.Id,
										Payment_Intent__c = paymentIntent?.id,
										Source__c         = paymentIntent?.latest_charge,
										CurrencyIsoCode   = currencyCode
									)
								);
							}
						} else	if (entry.Product2.Name == 'Success' &&
							application.Current_Address_Abroad__CountryCode__s == 'ZA' &&
							application.Split__c == true) {
							for (Integer i = 0; i < 2; i++) {
								newSobjects.add(
									new Payment__c (
					 					Amount__c         = entry.UnitPrice / 2,
										Product__c        = entry.Product2Id,
										Status__c         = 'Draft',
										Payment_Method__c = application.Payment_Method__c,
										Customer_Id__c    = application.Stripe_Customer_Id__c,
										Order__c          = newOrder.Id,
										Application__c    = application.Id,
										Payment_Intent__c = paymentIntent?.id,
										Source__c         = paymentIntent?.latest_charge,
										CurrencyIsoCode   = currencyCode
									)
								);
							}
						} else {
							newSobjects.add(
								new Payment__c (
					 			    Amount__c         = entry.UnitPrice,
									Product__c        = entry.Product2Id,
									Status__c         = entry.Product2.Name == 'Deposit' ? 'Paid' : 'Draft',
									Payment_Method__c = application.Payment_Method__c,
									Customer_Id__c    = application.Stripe_Customer_Id__c,
									Order__c          = newOrder.Id,
									Application__c    = application.Id,
									Payment_Intent__c = paymentIntent?.id,
									Source__c         = paymentIntent?.latest_charge,
									CurrencyIsoCode   = currencyCode,
									Payment_Date__c   = entry.Product2.Name == 'Deposit' ? Date.today() : null
								)
							);
						}
					}

					if (newSobjects != null) {
						Database.insert(newSobjects, false);
    				}
					if (!String.isBlank(leadId)) {
	 					Database.upsert(
							new Lead(Id = leadId, Status = 'SALE', Application__c = application.Id),false);
					}
					return 'Success';
				}catch (Exception ex){
					Application_Form_Error__c errorData = new Application_Form_Error__c();
                	errorData.Error_Body__c = paymentIntent?.shipping?.name.trim() + ' - ' + '\n' + ex.getLineNumber() + '-' + ex.getMessage() + '\n' + ex.getStackTraceString();
                	errorData.Error_Date__c = Date.today();
					errorData.JSON_request__c = request.requestBody.toString();
                	insert errorData;
					return 'Error Payment';
				}
			} else return 'Not MOTO Payment';
		} else if (typeData == 'charge.refunded') {
			Map<String, Object> objectData        = (Map<String, Object>) eventData.get('data');
			Map<String, Object> paymentIntentData = (Map<String, Object>) objectData.get('object');
			String paymentIntentId = (String) paymentIntentData.get('payment_intent');
			String descriptionData = (String) paymentIntentData.get('description');
			String refundMethod = (String) paymentIntentData.get('payment_method');
			Integer capturedAmount = (Integer) paymentIntentData.get('amount_captured');
			Integer refundedAmount = (Integer) paymentIntentData.get('amount_refunded');
			if (descriptionData == DESCRIPTION) {
				descriptionData = 'Deposit';
			}
			List<Payment__c> payments = [
				SELECT
					Name,
					Product__c,
					Product__r.Name,
					Application__c,
					Application__r.Name,
					Application__r.Status__c,
					Application__r.Contact__c,
					Application__r.Email__c,
					Status__c,
					Amount__c,
					Tax_VAT__c
				FROM Payment__c
				WHERE Product_Name__c = :descriptionData AND
					  Payment_Intent__c = :paymentIntentId
				LIMIT 1
			];
			if (payments.isEmpty()) {
				return 'Don\'t found current payment';
			}
			Payment__c currentPayment = payments[0];
			OrgWideEmailAddress[] owea = [
				SELECT Id
				FROM OrgWideEmailAddress
				WHERE Address = :OWD_NAME
			];
			List<EmailTemplate> refundEmailTemplate = [
				SELECT
					Id
				FROM EmailTemplate
				WHERE Name = :REFUND_INFO_TEMPLATE_NAME
			];
			Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
			message.setTargetObjectId(currentPayment.Application__r.Contact__c);
			message.setUseSignature(false);
			message.setBccSender(false);
			message.setSaveAsActivity(true);
			message.setWhatId(currentPayment.Id);
			message.setTreatTargetObjectAsRecipient(false);
			if (!refundEmailTemplate.isEmpty()) {
				message.setTemplateID(refundEmailTemplate[0].Id);
			}
			if ( owea.size() > 0 ) {
				message.setOrgWideEmailAddressId(owea.get(0).Id);
			}
			message.toAddresses = new String[] { currentPayment.Application__r.Email__c };
			Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
			Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);

			if (capturedAmount != refundedAmount) {
				return 'Partial refund';
			}
			List<String> sentEnvelopes = new List<String>();
			for (dfsle__EnvelopeStatus__c status : [
				SELECT dfsle__Status__c, dfsle__DocuSignId__c
				FROM dfsle__EnvelopeStatus__c
				WHERE Application__c = :currentPayment.Application__c
			]) {
				if (status.dfsle__Status__c == 'Sent' || status.dfsle__Status__c == 'Delivered') {
					sentEnvelopes.add(status.dfsle__DocuSignId__c);
				}
			}
			if(sentEnvelopes.size() != 0) {
				ApexToolkit.voidEnvelope(sentEnvelopes);
			}
			List<Sobject> updatedData = new List<Sobject>();
			if (descriptionData == DESCRIPTION || descriptionData == 'Deposit') {
				Application__c currentApplication = new Application__c(
					Id = currentPayment.Application__c,
					Status__c = 'Deposit Refund'
				);
				updatedData.add(currentApplication);
			}
			Credit_Note__c relatedCreditNote = new Credit_Note__c(
				Refund_Date__c   = Date.today(),
				Refund_Method__c = refundMethod,
				Product__c       = currentPayment.Product__c,
				Amount__c        = currentPayment.Amount__c - currentPayment.Tax_VAT__c,
				Tax_EU__c        = currentPayment.Tax_VAT__c,
				Payment__c       = currentPayment.Id
			);
			updatedData.add(relatedCreditNote);
			currentPayment.Status__c   = 'Refund';
			currentPayment.Refunded__c = true;
			updatedData.add(currentPayment);
			if (!updatedData.isEmpty()) {
				upsert updatedData;
			}

			return 'End';
		}
		return 'Not charge.refunded or payment_intent.succeeded events';
	}


	private class PaymentIntentWrapper {
		private String id;
		private Integer amount;
		private String description;
		private ShippingDataWrapper shipping;
		private String customer;
		private String payment_method;
		private String latest_charge;
		private MetaDataInfo metadata;
	}

	private class ShippingDataWrapper {
		private String name;
		private String phone;
		private AddessData address;
	}

	private class AddessData {
		private String city;
		private String country;
		private String line1;
		private String line2;
		private String postal_code;
		private String state;
	}

	private class MetaDataInfo {
		private String howDidYouHearAboutUs;
		private String agent;
		private String leadId;
		private String class3Appeal;
		private String hasNINONow;
		private String isDelay;
		private String delayDate;
		private String isSplit;
	}
}