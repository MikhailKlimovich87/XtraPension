public with sharing class BP_PortalApplicationHelper {
	private static final String XTRAPENSION_LINK = XtraPension_Data__c.getInstance().BP_Form_Link__c;
	private static final String CLAIM_PRODUCT = 'Claim - Deposit';
	private static final Set<String> ALLOWED_CURRENCIES = new Set<String>{'EUR', 'USD', 'AUD', 'CAD', 'ZAR', 'NZD'};
	// Statuses in which the client or an agent may still edit the form through the portal
	private static final Set<String> EDITABLE_STATUSES = new Set<String>{'Form In Progress', 'Validation Call', 'Pending Client'};
	

	public static Map<String, Object> createApplication(BP_RequestWrappers.ApplicationCreateDataWrapper wrapper) {
		Map<String, Object> result = new Map<String, Object>();
		if (wrapper == null) {
			result.put('status', 'error');
			result.put('message', 'Application data is empty');
			return result;
		}
		Savepoint sp;
		try {
			if (String.isBlank(wrapper.id)) {
				result.put('status', 'error');
				result.put('message', 'Payment intent id is required');
				return result;
			}
			// Idempotency: a retried request for the same PaymentIntent returns the claim created the first time
			List<Basic__c> existingClaims = [
				SELECT Id FROM Basic__c WHERE Stripe_Transaction_Id__c = :wrapper.id LIMIT 1
			];
			if (!existingClaims.isEmpty()) {
				result.put('status', 'success');
				result.put('applicationId', String.valueOf(existingClaims[0].Id));
				result.put('duplicate', true);
				return result;
			}
			Map<String, Object> paymentError = verifyStripePayment(wrapper);
			if (paymentError != null) {
				return paymentError;
			}
			StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
			'payment_methods/' + wrapper?.paymentMethod,
			'GET',
			null
		    );
			String cardData = '';
			Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
			if(methodData.get('card') != null) {
				Map<String,Object> cardDataMap = (Map<String,Object>)methodData.get('card');
				if(cardDataMap.get('brand') != null && cardDataMap.get('last4')!= null){
					cardData = cardDataMap.get('brand') + ' - ' + cardDataMap.get('last4');
				}
			}
			String address1 = '';
			String address2 = '';
			if( wrapper?.address?.street!=null) {
				Integer i = wrapper?.address?.street.indexOf(',');
				address1 = (i >= 0) ? wrapper?.address?.street.substring(0, i) : wrapper?.address?.street;
				address2 = (i >= 0) ? wrapper?.address?.street.substring(i + 1) : '';
			}
			Account account = new Account();
			sp = Database.setSavepoint();
			String personContactId = '';
			String personAccountId = '';
			List<Account> accountList = [SELECT Id, PersonEmail FROM Account WHERE PersonEmail =: wrapper?.email];
			if(accountList.size()>0) {
				personAccountId = accountList[0].Id;
			} else {
				account = new Account(
					LastName                = wrapper?.name,
					PersonEmail             = wrapper?.email,
					PersonMobilePhone       = wrapper?.phone,
					PersonMailingCity       = wrapper.address?.city,
					PersonMailingCountry    = wrapper.address?.country,
					PersonMailingState      = wrapper.address?.state,
					PersonMailingPostalCode = wrapper.address?.postalCode,
					PersonMailingStreet     = wrapper.address?.street,
					Mailing_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.address?.country),
					Mailing_State__c        = wrapper?.address?.country == 'IE' ?
													wrapper?.address?.state :
													CountryCodeHelper.getCountryStateNameByIsoCode(
														wrapper?.address?.country,
														wrapper?.address?.state)
				);
				insert account;
				personAccountId = account.Id;
			}

			List<Contact> currentContact = [
				SELECT
					Id,
					AccountId
				FROM Contact
				WHERE AccountId = :personAccountId
				LIMIT 1
			];
			if (!currentContact.isEmpty()) {
				personContactId = currentContact[0].Id;
			}
			String currencyISO = '';
			String paidText = '';
			if(!ALLOWED_CURRENCIES.contains(wrapper?.currencyCode) || !isOrgCurrency(wrapper?.currencyCode)) {
				currencyISO = 'USD';
			} else {
				currencyISO = wrapper?.currencyCode;
			}
			if(String.isNotBlank(currencyISO) && wrapper?.amount != null) {
				String resultAmount = String.valueOf((wrapper?.amount / 100).setScale(2));
				resultAmount = resultAmount.replace('.', ',');
				paidText = BP_PortalUtils.getCurrencySymbol(currencyISO) + ' ' + resultAmount;
			}
			Basic__c basic = new Basic__c(
				Agent_Making_Sale__c = wrapper?.agent == null ? 'None' : wrapper?.agent,
				CurrencyIsoCode  = currencyISO,
				Contact__c = personContactId,
				Claimant_City__c = wrapper?.address?.city,
				Current_Address_Abroad_State__c = wrapper?.address?.state,
				Current_Address_Abroad_Country__c = wrapper?.address?.country,
				Current_Address_Abroad_Country_Name__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.address?.country),
				Current_Address_Abroad_State_Name__c = wrapper?.address?.country == 'IE' ?
													wrapper?.address?.state :
													CountryCodeHelper.getCountryStateNameByIsoCode(
														wrapper?.address?.country,
														wrapper?.address?.state),
				First_Name__c = wrapper?.firstName,
				Last_Name__c = wrapper?.lastName,
				Payment_Method__c = wrapper?.paymentMethod,
				Deposit_Payment_Date__c = Date.today(),
				Stripe_Customer_Id__c = wrapper?.customer,
				Stripe_Transaction_Id__c  = wrapper?.id,
				Email__c = wrapper?.email,
				Phone__c = wrapper?.phone,
				Claimant_address1__c = address1,
				Claimant_address2__c = address2,
				How_did_you_hear_about_us__c = wrapper?.howDidYouHearAboutUs,
				LatestCharge__c = wrapper?.latest_charge,
				Friend_Email__c = wrapper?.friendFamilyEmail,
				CC_Helper_on_All_Comms__c = String.isBlank(wrapper?.friendFamilyEmail) ? false : true,
				Deposit_Paid__c = paidText,
				Claimant_title__c = wrapper?.title,
				Friend_Last_Name__c = wrapper?.friendLastName,
				Friend_Phone__c = wrapper?.friendTel,
				Relationship__c = wrapper?.friendRelationship,
				Friend_First_Name__c = wrapper?.friendFirstName,
				Eircode__c = wrapper?.address?.postalCode,
				Eircode_Verified__c = true,
				Verification_Status__c = 'Verified',
				Address_Validated__c = true
			);
			insert basic;

			update new Basic__c(Id = basic.Id,
			Short_Agent_Link__c = XTRAPENSION_LINK.removeEnd('form/') + 'short-form/' + basic.id
			);
			result.putAll(createPayment(basic.Id, wrapper?.latest_charge, personAccountId, wrapper?.id, cardData));
			if (result.get('status') == 'error') {
				// Do not leave a claim without its payment record behind
				Database.rollback(sp);
				return result;
			}

			paidEmail(basic.Id);
			result.put('status', 'success');
			result.put('applicationId', String.valueOf(basic.Id));
		}catch (Exception e) {
			if (sp != null) {
				Database.rollback(sp);
			}
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
		}
		return result;
	}

	// A currency can only be stored if it is enabled in the org (e.g. NZD must be added in Company Information)
	private static Boolean isOrgCurrency(String isoCode) {
		for (Schema.PicklistEntry entry : Basic__c.CurrencyIsoCode.getDescribe().getPicklistValues()) {
			if (entry.getValue() == isoCode) {
				return true;
			}
		}
		return false;
	}

	// Confirms with Stripe that the PaymentIntent really succeeded and replaces the
	// browser-supplied amount, currency, customer and payment method with Stripe's values.
	private static Map<String, Object> verifyStripePayment(BP_RequestWrappers.ApplicationCreateDataWrapper wrapper) {
		Map<String, Object> error = new Map<String, Object>{ 'status' => 'error' };
		StripeApiHandler.StripeAPIResponseWrapper resp = StripeApiHandler.requestStripeApi(
			'payment_intents/' + EncodingUtil.urlEncode(wrapper.id, 'UTF-8'),
			'GET',
			null
		);
		if (resp == null || resp.isError == true || String.isBlank(resp.responseBody)) {
			error.put('message', 'Payment could not be verified' + (resp?.errorMessage != null ? ': ' + resp.errorMessage : ''));
			return error;
		}
		Map<String, Object> intent = (Map<String, Object>) JSON.deserializeUntyped(resp.responseBody);
		if (String.valueOf(intent.get('status')) != 'succeeded') {
			error.put('message', 'Payment has not been completed');
			return error;
		}

		Object paidRaw = intent.get('amount_received') != null ? intent.get('amount_received') : intent.get('amount');
		Decimal paid = paidRaw != null ? Decimal.valueOf(String.valueOf(paidRaw)) : null;
		if (paid != null && wrapper.amount != null && paid != wrapper.amount) {
			error.put('message', 'Payment amount does not match');
			return error;
		}
		String intentCurrency = intent.get('currency') != null ? String.valueOf(intent.get('currency')).toUpperCase() : null;
		if (intentCurrency != null && String.isNotBlank(wrapper.currencyCode) && wrapper.currencyCode.toUpperCase() != intentCurrency) {
			error.put('message', 'Payment currency does not match');
			return error;
		}
		String intentCustomer = intent.get('customer') instanceof String ? (String) intent.get('customer') : null;
		if (intentCustomer != null && String.isNotBlank(wrapper.customer) && wrapper.customer != intentCustomer) {
			error.put('message', 'Payment customer does not match');
			return error;
		}

		if (paid != null) {
			wrapper.amount = paid;
		}
		if (intentCurrency != null) {
			wrapper.currencyCode = intentCurrency;
		}
		if (intentCustomer != null) {
			wrapper.customer = intentCustomer;
		}
		if (intent.get('payment_method') instanceof String) {
			wrapper.paymentMethod = (String) intent.get('payment_method');
		}
		if (intent.get('latest_charge') instanceof String) {
			wrapper.latest_charge = (String) intent.get('latest_charge');
		}
		return null;
	}

	private static Map<String,Object> createPayment(Id appId, String source, Id acctId, String paymentIntentId, String cardData) {
		List<Sobject> newSobjects = new List<Sobject>();
		List<Basic__c> currApps = BP_PortalUtils.getApplication(appId);
		if (currApps.size() == 0) {
			Map<String, Object> result = new Map<String, Object>();
			result.put('status', 'error');
			result.put('message', 'Not found application');
			return result;
		}
		Basic__c app = currApps[0];
		List<PriceBookEntry> priceBookEntries = new List<PriceBookEntry>();
		Map<String, Object> result = new Map<String, Object>();
			if (!Test.isRunningTest()) {
				priceBookEntries = [
					SELECT
						Id,
						Product2Id,
						Product2.Name,
						Pricebook2Id,
						CurrencyIsoCode,
						Pricebook2.IsStandard,
						UnitPrice
					FROM PriceBookEntry
					WHERE Product2.Name = :CLAIM_PRODUCT
					AND CurrencyIsoCode = :app?.CurrencyIsoCode
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
				result.put('status', 'error');
				result.put('message', 'PriceBookEntries are empty');
				return result;
			}
			PriceBookEntry pkPrice = priceBookEntries[0];
		
			String paymentMethodId = '';
			if(app.Payment_Method__c != null && app.Payment_Method__c.contains(';')) {
				List<String> paymentMethods = app.Payment_Method__c.split(';');
				paymentMethodId = paymentMethods[paymentMethods.size() - 1].trim();
			} else if(app.Payment_Method__c != null) paymentMethodId = app.Payment_Method__c;
			newSobjects.add(
				new Basic_Payment__c (
					Amount__c         = pkPrice.UnitPrice,
					Product__c        = pkPrice.Product2Id,
					Status__c         = 'Paid',
					CurrencyIsoCode   = app?.CurrencyIsoCode,
					Payment_Method__c = paymentMethodId,
					Customer_Id__c    = app.Stripe_Customer_Id__c,
					Basic__c    = app?.id,
					Payment_Date__c   = Date.today(),
					Payment_Intent__c = paymentIntentId,
					Source__c         = source,
					Card_Data__c      = cardData
				)
			);
			if (newSobjects != null) {
				insert newSobjects;
		   }
		   return result;
	}

	public static Map<String, Object> getApplicationDetail(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
		Map<String, Object> result = new Map<String, Object>();
		try {
			if (wrapper == null || wrapper.applicationId == null) {
				result.put('status', 'error');
				result.put('message', 'Application Id is null');
				return result;
			}
			List<Basic__c> apps = BP_PortalUtils.getApplication(wrapper?.applicationId);
			if (apps.size() == 0) {
				result.put('status', 'error');
				result.put('message', 'Not found application');
			} else if (apps.size() > 0 && !EDITABLE_STATUSES.contains(apps[0].Status__c)) {
				result.put('status', 'error');
				result.put('message', 'The form has already been successfully submitted');
			} else {
				Basic__c currBasic = apps[0];
				result.put('status', 'success');
				result.put('applicationId', apps[0].Id);
				String currentStep ='';
				if(wrapper.isAgentForm) {
					currentStep = String.isBlank(apps[0].Agent_Form_Step__c) ? '' : apps[0].Agent_Form_Step__c;
				} else {
					currentStep = String.isBlank(apps[0].Step__c) ? '' : apps[0].Step__c;
				}
				
				result.put('currentStep', BP_PortalUtils.outputCurrentStep(currentStep));
				result.put('track', currBasic.Track__c);
				result.put(
					'application',
					new BP_ResponseWrappers.ApplicationDataWrapper(currBasic)
				);
				System.debug(result);
				
			}
			return result;
		} catch (Exception e) {
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
			return result;
		}
		
	}

	public static Map<String, Object> getApplicationFill(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
		Map<String, Object> result = new Map<String, Object>();
		try {
			if (wrapper == null || wrapper.applicationId == null) {
				result.put('status', 'error');
				result.put('message', 'Application Id is null');
				return result;
			}
			List<Basic__c> apps = BP_PortalUtils.getApplication(wrapper?.applicationId);
			if (apps.size() == 0) {
				result.put('status', 'error');
				result.put('message', 'Not found application');
			}  else {
				Basic__c currBasic = apps[0];
				result.put('status', 'success');
				result.put('applicationId', apps[0].Id);
				String currentStep = String.isBlank(apps[0].Step__c) ? '' : apps[0].Step__c;
				result.put('currentStep', BP_PortalUtils.outputCurrentStep(currentStep));
				result.put(
					'application',
					new BP_ResponseWrappers.ApplicationDataWrapper(currBasic)
				);
				if (result.get('status') != 'error') {
					result.put('status', 'success');
					result.put('applicationId', String.valueOf(currBasic.Id));
				}
			}
			return result;
		} catch (Exception e) {
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
			return result;
		}
	}

	public static Map<String, Object> getApplicationEnvelopeFill(BP_RequestWrappers.ShortApplicationDataWrapper wrapper) {
		Map<String, Object> result = new Map<String, Object>();
		try {
			if (wrapper == null || wrapper.applicationId == null) {
				result.put('status', 'error');
				result.put('message', 'Application Id is null');
				return result;
			}
			List<Basic__c> apps = BP_PortalUtils.getEnvApplication(wrapper?.applicationId);
			if (apps.size() == 0) {
				result.put('status', 'error');
				result.put('message', 'Not found application');
			} else if(apps[0].Is_envelope_created__c) {
				result.put('status', 'error');
				result.put('message', 'The form has already been successfully submitted');
			} else {
				Basic__c currBasic = apps[0];
				result.put('status', 'success');
				result.put('applicationId', apps[0].Id);
				String currentStep = String.isBlank(apps[0].Step__c) ? '' : apps[0].Step__c;
				result.put('currentStep', BP_PortalUtils.outputCurrentStep(currentStep));
				result.put(
					'application',
					new BP_ResponseWrappers.ShortApplicationDataWrapper(currBasic)
				);
			}
			return result;
		} catch (Exception e) {
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
			return result;
		}
	}

	public static Map<String, Object> updateApplicationDetailsEnvelope(BP_RequestWrappers.ShortApplicationDataWrapper wrapper) {
		Savepoint sp;
		Map<String, Object> result = new Map<String, Object>();
		try {
			if (wrapper == null || wrapper.applicationId == null) {
				result.put('status', 'error');
				result.put('message', 'Application Id is null');
				return result;
			}
			List<Basic__c> apps = BP_PortalUtils.getEnvApplication(wrapper?.applicationId);
			if (apps.size() == 0) {
				result.put('status', 'error');
				result.put('message', 'Not found application');
				return result;
			} if (apps[0].Is_envelope_created__c) {
				result.put('status', 'error');
				result.put('message', 'The form has already been successfully submitted');
				return result;
			}
			if(wrapper.isAutoSave) {
				BP_PortalUtils.autoSaveShort(wrapper);
				result.put('status', 'success');
				result.put('applicationId', wrapper?.applicationId);
				result.put(
					'application',
					new BP_ResponseWrappers.ShortApplicationDataWrapper(BP_PortalUtils.getEnvApplication(wrapper?.applicationId))
				);
				return result;
			} else {
				sp = Database.setSavepoint();
				BP_PortalUtils.deleteOldEnvelopeClaimantRelation(wrapper?.applicationId);
				Basic__c updatedApp = new Basic__c(
					Id = wrapper.applicationId,
					Personal_Details_Form_Link__c = XTRAPENSION_LINK + wrapper?.applicationId,
					Form_Agent_URL__c = XTRAPENSION_LINK.removeEnd('form/') + 'agent-form/' + wrapper?.applicationId,
					Step__c = 'Friend / Family for Communication',
					Agent_Form_Step__c = 'Friend / Family for Communication',
					Is_envelope_created__c = true,
					Track__c = wrapper?.application?.track,
					Claimant_title__c = wrapper?.application?.client?.title,
					First_Name__c = wrapper?.application?.client?.firstName,
					Claimant_Middle_Name__c = wrapper?.application?.client?.middleName,
					Last_Name__c = wrapper?.application?.client?.lastName,
					Claimant_maiden_Name__c = wrapper?.application?.client?.maidenName,
					Claimant_dob__c = wrapper?.application?.client?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.client?.dob) : null,
					Phone__c = wrapper?.application?.client?.tel,
					Email__c = wrapper?.application?.client?.email,
					Claimant_marital_Status__c = wrapper?.application?.client?.maritalStatus,
					Claimant_date_Of_Divorce__c = wrapper?.application?.client?.dateOfDivorce != null ? BP_PortalUtils.dateFromString(wrapper?.application?.client?.dateOfDivorce) : null,
					Current_Address_Abroad_Country__c =  wrapper?.application?.client?.country,
					Current_Address_Abroad_Country_Name__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.client?.country),
					PPS__c = wrapper?.application?.client?.pps,
					Friend_Email__c = wrapper?.application?.client?.helperEmail,
					CC_Helper_on_All_Comms__c = String.isNotBlank(wrapper?.application?.client?.helperEmail) ? true : false,
					Eircode__c =  wrapper?.application?.client?.postcode,
					Claimant_Address1__c =  wrapper?.application?.client?.address1,
					Claimant_Address2__c =  wrapper?.application?.client?.address2,
					Claimant_City__c =  wrapper?.application?.client?.city,
					Claimant_ever_Lived_UK__c = wrapper?.application?.client?.everLivedUK,
					Ever_Live_In_UK_approved__c = true,
					Claimant_lived_UK_to__c = wrapper?.application?.client?.dateLeftUK != null ? BP_PortalUtils.dateFromString(wrapper?.application?.client?.dateLeftUK) : null,
					Address_Validated__c = wrapper?.application?.client?.addressValidated  == null ? false : wrapper?.application?.client?.addressValidated,
					Verification_Status__c = wrapper?.application?.client?.verificationStatus  == null ? '' : wrapper?.application?.client?.verificationStatus,
					Was_Cleansed__c = wrapper?.application?.client?.wasCleansed  == null ? false : wrapper?.application?.client?.wasCleansed,
					Claimant_nationality__c = wrapper?.application?.client?.nationality,
					Approx_Years_in_UK__c = wrapper?.application?.client?.approxYearsInUK,
					Current_Address_Abroad_State_Name__c = wrapper?.application?.client?.stateName,
					Current_Address_Abroad_State__c = wrapper?.application?.client?.state
				
				);
				if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'A') {
					updatedApp.Claimant_nino__c = wrapper?.application?.trackA?.nino;
					updatedApp.Has_Nino__c = wrapper?.application?.trackA?.hasNino;
					updatedApp.Claimant_hasNino__c = wrapper?.application?.trackA?.hasNino == 'Yes' ? true : false;
					updatedApp.Claimant_State_Pension__c = wrapper?.application?.trackA?.isGettingUKStatePensionNow != null ? wrapper?.application?.trackA?.isGettingUKStatePensionNow :  false ;
				}
				if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'B') {
					updatedApp.Is_Partner_alive__c = String.isNotBlank(wrapper?.application?.trackB?.husbandAlive) && wrapper?.application?.trackB?.husbandAlive == 'Yes' ? true : false;
					updatedApp.Claimant_State_Pension__c = wrapper?.application?.trackB?.youGettinStatePensionNow!= null ?  wrapper?.application?.trackB?.youGettinStatePensionNow : false;
					updatedApp.Partner_State_Pension__c = wrapper?.application?.trackB?.husbandGettinStatePensionNow;
					updatedApp.Partner_First_Name__c = wrapper?.application?.trackB?.husbandFirstName;
					updatedApp.Partner_Other_Name__c = wrapper?.application?.trackB?.husbandOtherName;
					updatedApp.Partner_Surname__c = wrapper?.application?.trackB?.husbandSurname;
					updatedApp.Partner_DOB__c = wrapper?.application?.trackB?.husbandDob != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackB?.husbandDob) : null;
					updatedApp.Claimant_date_Of_Marriage__c = wrapper?.application?.trackB?.marriageDate != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackB?.marriageDate) : null;
					updatedApp.Partner_Left_UK__c = wrapper?.application?.trackB?.husbandLeftUk != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackB?.husbandLeftUk) : null;
					updatedApp.Partner_same_as_claimant__c = wrapper?.application?.trackB?.sameAddress;
					updatedApp.Partner_Country__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.trackB?.country);
					updatedApp.Partner_Country_Code__c = wrapper?.application?.trackB?.country;
					updatedApp.Partner_Postcode__c = wrapper?.application?.trackB?.postcode;
					updatedApp.Partner_Address1__c = wrapper?.application?.trackB?.address1;
					updatedApp.Partner_Address2__c = wrapper?.application?.trackB?.address2;
					updatedApp.Partner_City__c = wrapper?.application?.trackB?.city;
					updatedApp.Partner_Has_Nino_values__c = wrapper?.application?.trackB?.husbandHasNino;
					updatedApp.Partner_Has_Nino__c = String.isNotBlank(wrapper?.application?.trackB?.husbandHasNino) && wrapper?.application?.trackB?.husbandHasNino == 'Yes' ? true : false;
					updatedApp.Partner_Nino__c = wrapper?.application?.trackB?.husbandNino;
					updatedApp.Partner_Towns_Lived__c = wrapper?.application?.trackB?.country;
					updatedApp.Partner_Title__c = wrapper?.application?.trackB?.title;
					updatedApp.Partner_Address_Validated__c = wrapper?.application?.trackB?.addressValidated  == null ? false : wrapper?.application?.trackB?.addressValidated;
					updatedApp.Partner_Verification_Status__c = wrapper?.application?.trackB?.verificationStatus  == null ? '' : wrapper?.application?.trackB?.verificationStatus;
					updatedApp.Partner_Was_Cleansed__c = wrapper?.application?.trackB?.wasCleansed  == null ? false : wrapper?.application?.trackB?.wasCleansed;
					updatedApp.Partner_State_Name__c = wrapper?.application?.trackB?.stateName;
					updatedApp.Partner_State_Code__c = wrapper?.application?.trackB?.state;
					//updatedApp.Partner_Verified_Reference__c = wrapper?.application?.trackB?.verifiedReference  == null ? false : wrapper?.application?.trackB?.verifiedReference;
				   // updatedApp.Partner_Verification_Details__c = wrapper?.application?.trackB?.verificationDetails  == null ? false : wrapper?.application?.trackB?.verificationDetails;
				
				}
				if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'C') {
					updatedApp.Partner_DOB__c = wrapper?.application?.trackC?.wifeDob != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackC?.wifeDob) : null;
					updatedApp.Claimant_date_Of_Marriage__c = wrapper?.application?.trackC?.marriageDate != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackC?.marriageDate) : null;
					updatedApp.Partner_Left_UK__c = wrapper?.application?.trackC?.wifeLeftUK != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackC?.wifeLeftUK) : null;
					updatedApp.Partner_same_as_claimant__c = wrapper?.application?.trackC?.sameAddress;
					updatedApp.Partner_Country__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.trackC?.country);
					updatedApp.Partner_Country_Code__c = wrapper?.application?.trackC?.country;
					updatedApp.Partner_Postcode__c = wrapper?.application?.trackC?.postcode;
					updatedApp.Partner_Address1__c = wrapper?.application?.trackC?.address1;
					updatedApp.Partner_Address2__c = wrapper?.application?.trackC?.address2;
					updatedApp.Partner_City__c = wrapper?.application?.trackC?.city;
					updatedApp.Partner_Has_Nino_values__c = wrapper?.application?.trackC?.wifeHasNino;
					updatedApp.Partner_Has_Nino__c = String.isNotBlank(wrapper?.application?.trackC?.wifeHasNino) && wrapper?.application?.trackC?.wifeHasNino == 'Yes' ? true : false;
					updatedApp.Partner_Nino__c = wrapper?.application?.trackC?.wifeNino;
					updatedApp.Partner_Address_Validated__c = wrapper?.application?.trackC?.addressValidated  == null ? false : wrapper?.application?.trackC?.addressValidated;
					updatedApp.Partner_Verification_Status__c = wrapper?.application?.trackC?.verificationStatus  == null ? '' : wrapper?.application?.trackC?.verificationStatus;
					updatedApp.Partner_Was_Cleansed__c = wrapper?.application?.trackC?.wasCleansed  == null ? false : wrapper?.application?.trackC?.wasCleansed;
					updatedApp.Partner_State_Name__c = wrapper?.application?.trackC?.stateName;
					updatedApp.Partner_State_Code__c = wrapper?.application?.trackC?.state;
				   // updatedApp.Partner_Verified_Reference__c = wrapper?.application?.trackC?.verifiedReference  == null ? false : wrapper?.application?.trackC?.verifiedReference;
					//updatedApp.Partner_Verification_Details__c = wrapper?.application?.trackC?.verificationDetails  == null ? false : wrapper?.application?.trackC?.verificationDetails;
				}
				update updatedApp;
				if(!Test.isRunningTest()) {
					if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'A') {
						BP_PortalUtils.createNewClaimantRelationTrackA(wrapper);
					} else if (String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'B') {
						BP_PortalUtils.createNewClaimantRelationTrackB(wrapper);
					} else if (String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'C') {
						BP_PortalUtils.createNewClaimantRelationTrackC(wrapper);
					}
				}
				

				if(!Test.isRunningTest()) {
						System.enqueueJob(new BP_GenerateEnvelopeQueueable(wrapper?.applicationId));
				}
			}
			if (result.get('status') != 'error') {
				result.put('status', 'success');
				result.put('applicationId', String.valueOf(wrapper?.applicationId));
			}
			return result;
		} catch (Exception e) {
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
			System.debug(e.getMessage());
			if (sp != null) {
				Database.rollback(sp);
			}
			return result;
		}
	}

	public static Map<String, Object> updateApplicationDetails(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
		Map<String, Object> result = new Map<String, Object>();
		Savepoint sp;
		try {
			if (wrapper == null) {
				result.put('status', 'error');
				result.put('message', 'Input data is null');
				return result;
			}
			
			List<Basic__c> apps = BP_PortalUtils.getApplication(wrapper?.applicationId);
			if (apps.size() == 0) {
				result.put('status', 'error');
				result.put('message', 'Not found application');
				return result;
			} if(apps.size() > 0 && !EDITABLE_STATUSES.contains(apps[0].Status__c)) {
				result.put('status', 'error');
				result.put('message', 'The form has already been successfully submitted');
				return result;
			} if(wrapper.isAutoSave) {
				BP_PortalUtils.autoSave(wrapper);
				result.put('status', 'success');
				result.put('applicationId', wrapper?.applicationId);
				result.put(
					'application',
					new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(wrapper?.applicationId))
				);
				return result;
			} else  {
				Basic__c currApp = apps[0];
				sp = Database.setSavepoint();
				String nextStep = BP_PortalUtils.currentStep(apps[0].Step__c, wrapper?.currentStep);
				if(wrapper?.currentStep == 1) {
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Friend_First_Name__c = wrapper?.application?.contactCommunication?.firstName,
					Friend_Last_Name__c = wrapper?.application?.contactCommunication?.lastName,
					Friend_Phone__c = wrapper?.application?.contactCommunication?.tel,
					Friend_Email__c = wrapper?.application?.contactCommunication?.email,
					Relationship__c = wrapper?.application?.contactCommunication?.relationship,
					Validation_Agent__c = wrapper?.application?.agent
					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
				} else if (wrapper?.currentStep == 2) {
					String address1 = '';
					String address2 = '';
					if(String.isNotBlank(wrapper?.application?.claimant?.address1)) {
						address1 = wrapper?.application?.claimant?.address1;
					}
					if(String.isNotBlank(wrapper?.application?.claimant?.address2)) {
						address2 = wrapper?.application?.claimant?.address2;
					}
					BP_PortalUtils.deleteOldClaimantRelation(wrapper?.applicationId);
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Claimant_address1__c = wrapper?.application?.claimant?.address1,
					Claimant_address2__c = wrapper?.application?.claimant?.address2,
					Claimant_City__c = wrapper?.application?.claimant?.city,
					Current_Address_Abroad_Country__c = wrapper?.application?.claimant?.country,
					Current_Address_Abroad_Country_Name__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.claimant?.country),
					Claimant_date_Of_Bereavement__c = wrapper?.application?.claimant?.dateOfBereavement != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfBereavement) : null,
					Claimant_date_Of_Divorce__c = wrapper?.application?.claimant?.dateOfDivorce != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfDivorce) : null,
					Claimant_date_Of_Marriage__c = wrapper?.application?.claimant?.dateOfMarriage != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfMarriage) : null,
					Claimant_dob__c = wrapper?.application?.claimant?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dob) : null,
					Email__c = wrapper?.application?.claimant?.email,
					Claimant_ever_Lived_UK__c = wrapper?.application?.claimant?.everLivedUK,
					Claimant_Ever_Paid_Married_Woman_s_Stam__c = wrapper?.application?.claimant?.marriedWomansStamp,
					Claimant_Ever_Worked_UK__c = wrapper?.application?.claimant?.everWorkedUK,
					Ever_Work_UK_approved__c = true,
					Ever_Worked_UK_Use_Same_Dates__c = wrapper?.application?.claimant?.everWorkedUKuseSameDates,
					Claimant_has_Proof_Of_UK_Work__c = wrapper?.application?.claimant?.hasProofOfUKWork,
					Claimant_hasNino__c = wrapper?.application?.claimant?.hasNino,
					Claimant_lived_UK_From__c = wrapper?.application?.claimant?.livedUKFrom != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.livedUKFrom) : null,
					Claimant_lived_UK_to__c = wrapper?.application?.claimant?.livedUKTo != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.livedUKTo) : null,
					Claimant_maiden_Name__c = wrapper?.application?.claimant?.maidenName,
					Claimant_marital_Status__c = wrapper?.application?.claimant?.maritalStatus,
					Claimant_Minded_Kids__c = wrapper?.application?.claimant?.mindedKids,
					Claimant_nationality__c = wrapper?.application?.claimant?.nationality,
					Claimant_nino__c = wrapper?.application?.claimant?.nino,
					Claimant_other_names__c = wrapper?.application?.claimant?.otherNames,
					Phone__c = wrapper?.application?.claimant?.tel,
					Eircode__c = wrapper?.application?.claimant?.postcode,
					Claimant_self_Employed_UK__c = wrapper?.application?.claimant?.selfEmployedUK,
					Last_Name__c = wrapper?.application?.claimant?.surname,
					First_Name__c = wrapper?.application?.claimant?.firstName,
					Claimant_Middle_Name__c = wrapper?.application?.claimant?.middleName,
					Claimant_title__c = wrapper?.application?.claimant?.title,
					Claimant_worked_UK_From__c = wrapper?.application?.claimant?.workedUKFrom != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.workedUKFrom) : null,
					Claimant_worked_UK_To__c = wrapper?.application?.claimant?.workedUKTo != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.workedUKTo) : null,
					Address_Validated__c = wrapper?.application?.claimant?.addressValidated  == null ? false : wrapper?.application?.claimant?.addressValidated,
					Verification_Status__c = wrapper?.application?.claimant?.verificationStatus  == null ? '' : wrapper?.application?.claimant?.verificationStatus,
					Was_Cleansed__c = wrapper?.application?.claimant?.wasCleansed  == null ? false : wrapper?.application?.claimant?.wasCleansed,
					Approx_Years_in_UK__c = wrapper?.application?.claimant?.approxYearsInUK,
					Claimant_Ever_Lived_UK_Notes__c = wrapper?.application?.claimant?.everLivedUKNotes,
					Current_Address_Abroad_State_Name__c = wrapper?.application?.claimant?.stateName,
					Current_Address_Abroad_State__c = wrapper?.application?.claimant?.state
					//Verified_Reference__c = wrapper?.application?.claimant?.verifiedReference  == null ? false : wrapper?.application?.claimant?.verifiedReference,
					//Verification_Details__c = wrapper?.application?.claimant?.verificationDetails  == null ? false : wrapper?.application?.claimant?.verificationDetails
					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
					BP_PortalUtils.createNewClaimantRelation(wrapper);
				} else if (wrapper?.currentStep == 3) {
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Partner_Title__c = wrapper?.application?.partner?.title,
					Partner_Surname__c = wrapper?.application?.partner?.surname,
					Partner_Other_Name__c = wrapper?.application?.partner?.otherNames,
					Partner_DOB__c = wrapper?.application?.partner?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.partner?.dob) : null,
					Partner_Maiden_Name__c = wrapper?.application?.partner?.maidenName,
					Partner_Has_Nino__c = wrapper?.application?.partner?.hasNino,
					Partner_Nino__c = wrapper?.application?.partner?.nino,
					Partner_same_as_claimant__c = wrapper?.application?.partner?.saveAsClaimant,
					Partner_Country__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.partner?.country),
					Partner_Country_Code__c = wrapper?.application?.partner?.country,
					Partner_Postcode__c = wrapper?.application?.partner?.postcode,
					Partner_Address1__c = wrapper?.application?.partner?.address1,
					Partner_Address2__c = wrapper?.application?.partner?.address2,
					Partner_City__c = wrapper?.application?.partner?.city,
					Partner_Address_Validated__c = wrapper?.application?.partner?.addressValidated == null ? false : wrapper?.application?.partner?.addressValidated,
					Partner_Verification_Status__c = wrapper?.application?.partner?.verificationStatus == null ? '' :wrapper?.application?.partner?.verificationStatus,
					Partner_Was_Cleansed__c = wrapper?.application?.partner?.wasCleansed == null ? false : wrapper?.application?.partner?.wasCleansed,
					Partner_Ever_Lived_UK__c = wrapper?.application?.partner?.everLivedUK,
					Partner_Ever_Worked_UK__c = wrapper?.application?.partner?.everWorkedUK,
					Partner_Ever_Lived_UK_Notes__c = wrapper?.application?.partner?.everLivedUKNotes,
					Partner_First_Name__c = wrapper?.application?.partner?.firstName,
					Partner_Claiming_UK_Pension__c = wrapper?.application?.partner?.claimingUKPension,
					Partner_Reference_on_Any_DWP_Letters__c = wrapper?.application?.partner?.referenceOnAnyDWPLetters,
					Partner_State_Name__c = wrapper?.application?.partner?.stateName,
					Partner_State_Code__c = wrapper?.application?.partner?.state
					//Partner_Verified_Reference__c = wrapper?.application?.partner?.verifiedReference == null ? false : wrapper?.application?.partner?.verifiedReference,
				   //Partner_Verification_Details__c = wrapper?.application?.partner?.verificationDetails == null ? false : wrapper?.application?.partner?.verificationDetails
					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
				} else if (wrapper?.currentStep == 4) {
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Claimant_Graduated_Retirement_Benefit__c = wrapper?.application?.claimantBenefits?.graduatedRetirement,
					Claimant_Bereavement_Benefit__c = wrapper?.application?.claimantBenefits?.bereavement,
					Claimant_State_Pension__c = wrapper?.application?.claimantBenefits?.statePension!= null ?  wrapper?.application?.claimantBenefits?.statePension : false,
					Claimant_Widows_Benefit__c = wrapper?.application?.claimantBenefits?.widows,
					Claimant_is_Waiting_Uk_Benefits_text__c = wrapper?.application?.claimantBenefits?.isWaitingUkBenefitsText,
					Claimant_is_Waiting_Uk_Benefits__c = wrapper?.application?.claimantBenefits?.isWaitingUkBenefits
					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
				} else if (wrapper?.currentStep == 5) {
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Partner_Graduated_Retirement_Benefit__c = wrapper?.application?.partnerBenefits?.graduatedRetirement,
					Partner_Bereavement_Benefit__c = wrapper?.application?.partnerBenefits?.bereavement,
					Partner_State_Pension__c = wrapper?.application?.partnerBenefits?.statePension,
					Partner_Widows_Benefit__c = wrapper?.application?.partnerBenefits?.widows,
					Partner_is_Waiting_Uk_Benefits_text__c = wrapper?.application?.partnerBenefits?.isWaitingUkBenefitsText,
					Partner_is_Waiting_Uk_Benefits__c = wrapper?.application?.partnerBenefits?.isWaitingUkBenefits

					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
				} else if (wrapper?.currentStep == 6) {
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Pension_Claiming_from_Today__c = wrapper?.application?.pension?.claimingFromToday,
					Pension_Deferred_Pension__c = wrapper?.application?.pension?.deferredPension,
					Pension_Imprisoned_Since_Pension_Age__c = wrapper?.application?.pension?.imprisonedSincePensionAge,
					Pension_Start_Date__c = wrapper?.application?.pension?.startDate != null ? BP_PortalUtils.dateFromString(wrapper?.application?.pension?.startDate) : null,
					Pension_Work_After_Pension_Age__c = wrapper?.application?.pension?.workAfterPensionAge,
					Work_In_UK_during_2_years__c = wrapper?.application?.pension?.workInUKduring2years,
					Ever_Self_Employed_UK_after_1978__c = wrapper?.application?.pension?.everSelfEmployedUKafter1978,
					Ever_Pay_Reduced_UK_nino__c = wrapper?.application?.pension?.everPayReducedUKnino
					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
				} else if(wrapper?.currentStep == 7) {
					Basic__c updatedApp = new Basic__c(
						Id = wrapper?.applicationId,
						Is_Your_Partner_Currently_Get_Pension__c = wrapper.application?.benefits?.isYourPartnerCurrentlyGetPension!= null ? wrapper.application?.benefits?.isYourPartnerCurrentlyGetPension : false,
						isYourPartnerCurrentlyGetPensionText__c = String.isNotBlank(wrapper.application?.benefits?.isYourPartnerCurrentlyGetPensionText) ? wrapper.application?.benefits?.isYourPartnerCurrentlyGetPensionText : ''
	
					);
					if(wrapper?.isAgentForm) {
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
			
				} else if (wrapper?.currentStep == 8) {
					Basic__c updatedApp = new Basic__c(
					Id = wrapper?.applicationId,
					Bank_Account__c = wrapper?.application?.bank?.account,
					Bank_Account_Owner_Email__c = wrapper?.application?.bank?.accountOwnerEmail,
					Bank_Account_Owner_Name__c = wrapper?.application?.bank?.accountOwnerName,
					Bank_Account_Type__c = 'Current Account',
					Bank_IBAN__c = wrapper?.application?.bank?.iban,
					Bank_Name__c = wrapper?.application?.bank?.bankName,
					Bank_Sort_Code__c = wrapper?.application?.bank?.sortCode,
					Bank_Address__c = wrapper?.application?.bank?.address,
					Bank_City__c = wrapper?.application?.bank?.city,
					Bank_Country__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.bank?.country),
					Bank_Country_Code__c = wrapper?.application?.bank?.country,
					Bank_Post_Code__c = wrapper?.application?.bank?.postcode,
					Bank_BIC__c = wrapper?.application?.bank?.bic,
					Owns_This_Account__c = wrapper?.application?.bank?.ownsThisAccount,
					//Status__c = 'Form completed',
					Val_Form_Complete__c = String.isBlank(wrapper?.application?.agent ) ? false : true
					);
					if(wrapper?.isAgentForm) {
						String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
						updatedApp.Agent_Form_Step__c = nextStep;
					} else {
						updatedApp.Step__c = nextStep;
					}
					update updatedApp;
					validateFile(updatedApp.Id);
				} else if (wrapper?.currentStep == 9) {
					if(!Test.isRunningTest()) {

						BP_PortalUtils.reviewUpdate(apps, wrapper);
						//generateFile(apps[0].Id);
						if(!Test.isRunningTest()) {
							System.enqueueJob(
								new BP_GeneratePdfFileControllerQueueable(apps[0].Id)
							);
						}
					}
				}

				result.put('status', 'success');
				result.put('applicationId', currApp.Id);
				result.put('currentStep', BP_PortalUtils.outputCurrentStep(nextStep));
				result.put(
					'application',
					new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(wrapper?.applicationId))
				);
				return result;
			}

		} catch (Exception e) {
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
			System.debug( e.getMessage());
			if (sp != null) {
				Database.rollback(sp);
			}
		}
		return result;
	}

	public static Map<String, Object> validateBank(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
		Map<String, Object> result = new Map<String, Object>();
		 try {
			if (wrapper == null) {
				result.put('status', 'error');
				result.put('message', 'Input data is null');
				return result;
			}
				if (
				String.isBlank(wrapper.application?.bank?.sortCode)
				&& String.isBlank(wrapper.application?.bank?.bic)
				&& String.isBlank(wrapper.application?.bank?.iban)
				
			) {

				result.put('status', 'error');
				result.put('message', 'Sort code missing');
				return result;
			}
			if  (String.isBlank(wrapper.application?.bank?.account)
				&& String.isBlank(wrapper.application?.bank?.bic)
				&& String.isBlank(wrapper.application?.bank?.iban) && wrapper?.application?.claimant?.country != 'AU') {
				result.put('status', 'error');
				result.put('message', 'Account number missing');
				return result;
			}

			if(String.isBlank(wrapper.application?.bank?.bic) && String.isBlank(wrapper.application?.bank?.iban) && String.isBlank(wrapper.application?.bank?.sortCode) && (String.isBlank(wrapper.application?.bank?.account)) && wrapper?.application?.claimant?.country != 'AU') {
				result.put('status', 'error');
				result.put('message', 'BIC or IBAN missing');
				return result;
			}

			Map<String, String> inputs = new Map<String, String>{
				'accountNumber' => wrapper.application?.bank?.account,
				'BIC'  => wrapper.application?.bank?.bic,
				'IBAN'  => wrapper.application?.bank?.iban,
				'recordId'  => wrapper.applicationId,
				'sortCode' => wrapper.application?.bank?.sortCode

			};
			if(Test.isRunningTest()) {
				result.put('status', 'success');
			} else {
				if( wrapper?.application?.bank?.country == 'AU') {
					BP_CheckBank.BankAccountValidationResponseWrapper response = BP_CheckBank.validAUSCheck(inputs);
					if(response.Valid == 'Try manually') {
						result.put('status', 'error');
						result.put('message', 'BSB not found');
						return result;
					}
					result.put('status', 'success');
					result.put('response', response);
				} else {
					BP_CheckBank.BankAccountValidationResponseWrapper response = BP_CheckBank.validCheck(inputs);
					result.put('status', 'success');
					result.put('response', response);
				}
			}
			
			return result;

		} catch (Exception e) {
			result.put('status', 'error');
			result.put('message', e.getLineNumber() + '-' + e.getMessage());
		}
		return result;
	}


	@future (callout=true)
	public static void paidEmail(String basicId) {
		if(!Test.isRunningTest()){
			BP_PortalUtils.sendPaidEmail(basicId);
			BP_PortalUtils.sendRegistrationEmail(basicId);
			BP_PortalUtils.sendFriendEmail(basicId);
		}
	}

	@future (callout=true)
	public static void validateFile(String basicId) {
		List<String> missingFields = BP_PortalUtils.generateValidationEmail(basicId);
			if(missingFields.size()>0) {
				String missingField = '';
			if(missingFields.size()>0) {
				for(String item : missingFields) {
					missingField = missingField  + item +  '; ';
				}
				missingField = missingField.removeEnd('; ');
			}
			Basic__c updateStatusBase = new Basic__C(Id = basicId, Status__c = 'Validation Call', Missing_Info__c = missingField);
			update updateStatusBase;
			//BP_PortalUtils.sendValidationEmail(basicId,missingFields);

		} else {
			Basic__c updateStatusBase = new Basic__c( Id = basicId, Missing_Info__c = 'Form Fully Completed');
			update updateStatusBase;
		}
	}
}