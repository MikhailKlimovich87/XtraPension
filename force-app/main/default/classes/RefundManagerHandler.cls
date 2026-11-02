public class RefundManagerHandler {
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

    private static final List<String> ORDER_OF_PRODUCT_NAME = new List<String> {
        'Deposit', 'Application'
    };

    public static Map<String, Object> createRefund(RefundManager.RequestDataWrapper refundData) {
        Map<String, Object> result = new Map<String, Object>();
        if (refundData == null) {
            result.put('status', 'Error');
            result.put('message', 'Response data is empty');
            return result;
        }
        try {
            String phoneDuplicateFinder = '%' + refundData.phone.substring(1, refundData.phone.length() - 4) + '%';
            String personContactId = '';
            Account account = new Account(
                    //add logic check if only 1 word
                    //add line 2 from form
                    LastName                = refundData?.name,
                    PersonEmail             = refundData?.email,
                    PersonMobilePhone       = refundData?.phone,
                    PersonMailingCity       = refundData.address?.city,
                    PersonMailingCountry    = refundData.address?.country,
                    PersonMailingState      = refundData.address?.state,
                    PersonMailingPostalCode = refundData.address?.postal_code,
                    PersonMailingStreet     = refundData.address?.line1,
                    Mailing_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(refundData?.address?.country),
                    Mailing_State__c        = refundData?.address?.country == 'IE' ?
                                                refundData?.address?.state :
                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                    refundData?.address?.country,
                                                    refundData?.address?.state),
                    Mailing_Line_2__c       = refundData.address?.line2
                );
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
            String stateName = '';
            if (refundData?.address?.country == 'IE') {
                stateName = CountryCodeHelper.getStateCodeByStateName(
                                refundData?.address?.country,
                                refundData.address?.state.remove('County').trim());
            } else if(refundData?.address?.country == 'AE' ||
                       refundData?.address?.country == 'MY' ||
                       refundData?.address?.country == 'ID') {
                    stateName = CountryCodeHelper.getStateCodeByStateName(
                        refundData?.address?.country,
                        refundData.address?.state);
            } else stateName = refundData.address?.state;
            String currentStateValue = STATE_CODES.get(stateName);
            String streetData = refundData?.address?.line1;
            if (String.isNotBlank(refundData?.address?.line2)) {
                streetData += ', ' + refundData?.address?.line2;
            }
            Refund__c currRefund = new Refund__c(
                First_Name__c                          = refundData?.firstName,
                Last_Name__c                           = refundData?.lastName,
                Payment_Method__c                      = refundData?.paymentMethod,
                Stripe_Customer_Id__c                  = refundData?.customer,
                Stripe_Transaction_Id__c               = refundData?.id,
                Contact__c                             = personContactId,
                Phone__c                               = account.PersonMobilePhone,
                Email__c                               = account.PersonEmail,
                Agent_Making_Sale__c                   = refundData?.agent == null ? 'None' : refundData?.agent,
                Current_Address_Abroad__City__s        = refundData?.address?.city,
                Current_Address_Abroad__Street__s      = streetData,
                Current_Address_Abroad__StateCode__s   = stateName,
                Current_Address_Abroad__CountryCode__s = refundData?.address?.country,
                Current_Address_Abroad__PostalCode__s  = refundData?.address?.postal_code,
                Current_Address_Abroad_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(refundData?.address?.country),
                Current_Address_Abroad_State__c        = refundData?.address?.country == 'IE' ?
                                                                refundData.address?.state :
                                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                    refundData?.address?.country,
                                                                    refundData.address?.state
                                                                ),
                CurrencyIsoCode                        = refundData?.currencyCode
            );
            insert currRefund;
            List<PriceBookEntry> priceBookEntries = new List<PriceBookEntry>();
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
                    WHERE Pricebook2.IsStandard = true AND
                          CurrencyIsoCode = :currRefund?.CurrencyIsoCode
                ];
            } else {
                priceBookEntries = [
                    SELECT
                        Id,
                        Product2Id,
                        Product2.Name,
                        Pricebook2Id,
                        Pricebook2.IsStandard,
                        UnitPrice,
                        CurrencyIsoCode
                    FROM PriceBookEntry
                ];
            }
            if (priceBookEntries.isEmpty()) {
                result.put('status', 'Error');
                result.put('message', 'PriceBookEntries are empty');
                return result;
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
                    CurrencyIsoCode = 'GBP'
                );
                insert newOrder;
                List<SObject> newSobjects = new List<SObject>();
                for (String productName : ORDER_OF_PRODUCT_NAME) {
                    PriceBookEntry entry = productNameByPricebookEntry.get(productName);
                    newSobjects.add(
                        new OrderItem(
		                    Product2Id       = entry.Product2Id,
		                    OrderId          = newOrder.Id,
		                    PricebookEntryId = entry.Id,
		                    Quantity         = 1,
                            UnitPrice        = entry.UnitPrice
		                )
                    );
                    newSobjects.add(
                        new Payment__c (
                            Amount__c         = entry.UnitPrice,
                            Product__c        = entry.Product2Id,
                            Status__c         = entry.Product2.Name != 'Deposit' ? 'Draft' : 'Paid',
                            CurrencyIsoCode   = currRefund?.CurrencyIsoCode,
                            Payment_Method__c = currRefund?.Payment_Method__c,
                            Customer_Id__c    = currRefund?.Stripe_Customer_Id__c,
                            Order__c          = newOrder.Id,
                            Refund__c         = currRefund.Id,
                            Payment_Date__c   = entry.Product2.Name == 'Deposit' ? Date.today() : null,
                            Payment_Intent__c = entry.Product2.Name == 'Deposit' ? refundData?.id : null,
                            Source__c         = refundData?.latest_charge
                        )
                    );
                    }
                    if (newSobjects != null) {
                        insert newSobjects;
                    }
                Map<String, Id> productNameById = new Map<String, Id>();
                result.put('status', 'Success');

        } catch (Exception ex) {
            Application_Form_Error__c errorData = new Application_Form_Error__c();
                errorData.Error_Body__c = refundData?.name + ' - ' + refundData?.email + '\n' + ex.getLineNumber() + '-' + ex.getMessage();
                errorData.Error_Date__c = Date.today();
                insert errorData;
                result.put('status', 'Error');
                result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
        }
        return result;
    }
}