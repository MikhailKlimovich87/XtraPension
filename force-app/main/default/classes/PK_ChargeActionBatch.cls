public with sharing class PK_ChargeActionBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    public final Map<String, String> CURRENCY_CODE_BY_PK_AMOUNT = new Map<String, String>{
        'EUR' => '12500',
        'CAD' => '20000',
        'AUD' => '20000',
        'NZD' => '20000',
        'ZAR' => '200000',
        'USD' => '15000'
    };    
    private final String PENSION_KEEPER_PRODUCT = 'Pension Keeper';
    private final String PK_ORG_WIDE_EMAIL_ADDRESS = 'keeper@xtrapension.com';
    private final String PK_REGISTRATION_EMAIL_TEMPLATE_NAME = 'Welcome Pension Keeper Template';
    
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
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
                Contact__c,
                Email__c
            FROM Application__c
            WHERE PK_Portal_User_Active__c = false AND 
                  PK_Registration_Date__c = TODAY
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Application__c> apps) {
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
            update currApp;
            sendPKRegistrationEmail(currApp);

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
		} else {
     		String errorMessage = requestResult.errorMessage;
			throw new RegistratePKCustomerException(errorMessage);
		}

    }


    public void finish(Database.BatchableContext BC) {
        //notification with errors
        //notification With success
    }

    public class RegistratePKCustomerException extends Exception {}

    public void sendPKRegistrationEmail(Application__c app) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :PK_ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> registrationEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :PK_REGISTRATION_EMAIL_TEMPLATE_NAME
        ];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (registrationEmailTemplate.size() > 0) {
            message.setTemplateID(registrationEmailTemplate[0].Id);
        }
        message.setWhatId(app.Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { app.Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }
}