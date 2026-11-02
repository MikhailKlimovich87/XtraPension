public class ChargePkActionController {
    public static final Map<String, String> CURRENCY_CODE_BY_PK_AMOUNT = new Map<String, String>{
        'EUR' => '12500',
        'CAD' => '20000',
        'AUD' => '20000',
        'NZD' => '20000',
        'ZAR' => '200000',
        'USD' => '15000'
    };    
    private static final String PENSION_KEEPER_PRODUCT = 'Pension Keeper';

    @AuraEnabled(cacheable=true)
    public static String getPensionKeeperBaseUrlAddress() {
        return Pension_Keeper_Settings__c.getInstance().Base_URL__c;
    }

    @AuraEnabled()
    public static String registratePkService(Id appId, String salesAgent) {
        if (String.isBlank(appId)) throw new RegistratePKCustomerException('Application Id is empty');
        List<Application__c> apps = [
            SELECT
                Id,
                CurrencyIsoCode,
                Stripe_Customer_Id__c,
                Payment_Method__c,
                Current_Customer_Id__c,
                PK_Portal_User_Active__c,
                PK_Registration_Date__c,
                Date_Of_Birth__c,
                Status__c,
                First_Name__c,
                Second_Name__c,
                National_Insurance_Number__c,
                Contact__c
            FROM Application__c
            WHERE Id = :appId
        ];
        if (apps.size() == 0) throw new RegistratePKCustomerException('Didn\'t find any app with currecnt appId');
        Application__c currApp = apps[0];
        if(currApp.PK_Portal_User_Active__c == true) throw new RegistratePKCustomerException('Currecnt applicaition has already registered');
        String paymentMethodId = '';
        if(currApp.Payment_Method__c.contains(';')) {
            List<String> paymentMethods = currApp.Payment_Method__c.split(';');
            paymentMethodId = paymentMethods[paymentMethods.size() - 1].trim();
        } else if(currApp.Payment_Method__c != null) paymentMethodId = currApp.Payment_Method__c;

        Map<String, String> requestParams = new Map<String, String> {
            'currency'                                   => currApp.CurrencyIsoCode,
            'confirm'                                    => 'true',
            'customer'                                   => String.isNotBlank(currApp.Current_Customer_Id__c) ? currApp.Current_Customer_Id__c : currApp.Stripe_Customer_Id__c,
            'payment_method'                             => paymentMethodId,
            'amount'                                     => CURRENCY_CODE_BY_PK_AMOUNT.get(currApp.CurrencyIsoCode),
            'description'                                => PENSION_KEEPER_PRODUCT,
            'automatic_payment_methods[enabled]'         => 'true',
            'automatic_payment_methods[allow_redirects]' => 'never',
            'payment_method_options[card][moto]'         => 'true'
        };
        StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'payment_intents',
			'POST',
			requestParams
		);
        String newPaymentIntentResult = '';
        if (requestResult.isError != true) {
			newPaymentIntentResult = requestResult.responseBody;
			Map<String,Object> intentData = (Map<String,Object>) JSON.deserializeUntyped(newPaymentIntentResult);
            Date pensionAge = PK_PortalUtils.calculatePensionDate(currApp.Date_Of_Birth__c);
            currApp.Status__c = 'Pension Keeper';
            currApp.PK_Portal_User_Active__c = true;
            currApp.PK_Portal_User_PW__c = PK_PortalAuthHelper.generatePassword(currApp);
            currApp.PK_Registration_Date__c = Date.today();
            currApp.PK_Date_Pension_Age_Reached__c = pensionAge;
            currApp.Pension_Age__c = pensionAge != null ? PK_PortalUtils.getYearsMonthsDaysBetween(currApp.Date_Of_Birth__c, pensionAge) : null;
            currApp.PK_Auto_Renewal__c = false;
            currApp.PK_Sale_Agent__c = String.isNotBlank(salesAgent) ? salesAgent : null;
            update currApp;
            ApplicationTriggerHandler.sendPKRegistrationEmail(currApp.Id);

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
                    WHERE Product2.Name = :PENSION_KEEPER_PRODUCT AND
                          CurrencyIsoCode = :currApp?.CurrencyIsoCode
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
            PriceBookEntry pkPrice = priceBookEntries[0];
            Order currentOrder;
            List<Order> existingOrders = [
                SELECT Id
                FROM Order
                WHERE Application__c = :currApp.Id
            ];
            if (existingOrders.size() > 0) {
                currentOrder = existingOrders[0];
            }
            if (currentOrder == null) {
                currentOrder = new Order(
                    Status          = 'Draft',
                    EffectiveDate   = Date.today(),
                    Pricebook2Id    = pkPrice.Pricebook2Id,
                    AccountId       = currApp.Contact__c,
                    Application__c  = currApp.Id,
                    CurrencyIsoCode = currApp?.CurrencyIsoCode
                );
                insert currentOrder;
            }

            List<Sobject> newSobjects = new List<Sobject>();
            newSobjects.add(
                new OrderItem(
                    Product2Id       = pkPrice.Product2Id,
		            OrderId          = currentOrder.Id,
		            PricebookEntryId = pkPrice.Id,
		            Quantity         = 1,
                    UnitPrice        = pkPrice.UnitPrice
		        )
            );
            newSobjects.add(
                new Payment__c (
                    Amount__c         = pkPrice.UnitPrice,
                    Product__c        = pkPrice.Product2Id,
                    Status__c         = 'Paid',
                    CurrencyIsoCode   = currApp?.CurrencyIsoCode,
                    Payment_Method__c = paymentMethodId,
                    Customer_Id__c    = String.isNotBlank(currApp.Current_Customer_Id__c) ? currApp.Current_Customer_Id__c : currApp.Stripe_Customer_Id__c,
                    Order__c          = currentOrder.Id,
                    Application__c    = currApp?.id,
                    Payment_Date__c   = Date.today(),
                    Payment_Intent__c = (String) intentData.get('id'),
                    Source__c         = (String) intentData.get('latest_charge')
                )
            );
            if (newSobjects != null) {
                insert newSobjects;
           }
            return currApp.Id;
		} else {
     		String errorMessage = requestResult.errorMessage;
			throw new RegistratePKCustomerException(errorMessage);
		}
        
    }

    public class RegistratePKCustomerException extends Exception {}
}