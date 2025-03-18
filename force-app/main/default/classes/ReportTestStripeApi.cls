public class ReportTestStripeApi {
@future(callout=true)
	public static void getCustomerData(String customerId, String paymentMethodId, String applicationId) {
		StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'customers/' + customerId + '/payment_methods/' + paymentMethodId,
			'GET',
			null
		);
		if (requestResult.isError != true) {
			String customerData = requestResult?.responseBody;
            PaymentMethodWrapper dataWrapper    = (PaymentMethodWrapper) JSON.deserialize(customerData, PaymentMethodWrapper.class);
			if (dataWrapper == null) return;
			String streetData = dataWrapper?.billing_details?.address?.line1;
			if (String.isNotBlank(dataWrapper?.billing_details?.address?.line2)) {
				streetData += ', ' + dataWrapper?.billing_details?.address?.line2;
			}
			String stateName = '';
			if (dataWrapper?.billing_details?.address?.country == 'IE' &&
			dataWrapper?.billing_details.address?.state.contains('County')) {
				stateName = CountryCodeHelper.getStateCodeByStateName(
					dataWrapper?.billing_details?.address?.country,
					dataWrapper?.billing_details.address?.state.remove('County').trim());
			} else if(dataWrapper?.billing_details?.address?.country == 'AE') {
				stateName = CountryCodeHelper.getStateCodeByStateName(
					dataWrapper?.billing_details?.address?.country,
					dataWrapper?.billing_details.address?.state);
			} else stateName = dataWrapper?.billing_details.address?.state;
			update(
				new Application__c(
					Id = applicationId,
					Current_Address_Abroad__City__s = dataWrapper?.billing_details?.address?.city,
					Current_Address_Abroad__CountryCode__s = dataWrapper?.billing_details?.address?.country,
					Current_Address_Abroad__PostalCode__s = dataWrapper?.billing_details?.address?.postal_code,
					Current_Address_Abroad__StateCode__s = stateName,
					Current_Address_Abroad__Street__s = streetData,
					Current_Address_Abroad_Country__c     = CountryCodeHelper.getCountryNameByIsoCode(dataWrapper?.billing_details?.address?.country),
                    Current_Address_Abroad_State__c       = dataWrapper?.billing_details?.address?.country == 'IE' ?
																dataWrapper?.billing_details.address?.state :
                                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                    dataWrapper?.billing_details?.address?.country,
                                                                    dataWrapper?.billing_details.address?.state
                                                                )
				)
			);
        }
	}
	public class PaymentMethodWrapper {
		private BillingDataWrapper billing_details;
	}
    public class BillingDataWrapper {
		private AddessData address;
	}

	public class AddessData {
		private String city;
		private String country;
		private String line1;
		private String line2;
		private String postal_code;
		private String state;
	}
}