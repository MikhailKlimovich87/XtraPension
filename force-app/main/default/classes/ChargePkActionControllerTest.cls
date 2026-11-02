@isTest
public class ChargePkActionControllerTest {
    
    /**
     * Mock class for successful Stripe API responses
     */
    private class StripeSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id": "pi_test123456789", ' +
                    '"object": "payment_intent", ' +
                    '"amount": 12500, ' +
                    '"currency": "eur", ' +
                    '"status": "succeeded", ' +
                    '"latest_charge": "ch_test987654321"' +
                '}'
            );
            res.setStatusCode(200);
            return res;
        }
    }
    
    /**
     * Mock class for failed Stripe API responses
     */
    private class StripeFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"error": {' +
                        '"message": "Payment failed - insufficient funds", ' +
                        '"type": "card_error"' +
                    '}' +
                '}'
            );
            res.setStatusCode(402);
            return res;
        }
    }
    
    /**
     * Setup method to create test data
     */
    @TestSetup
    static void setupTestData() {
        // Create products with Pension Keeper product
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Monthly Updates', 'Success', 'Pension Keeper'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        
        // Create pricebook entries
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry pbe = new PriceBookEntry();
            pbe.Pricebook2Id = pricebookId;
            pbe.Product2Id = product.Id;
            pbe.UnitPrice = counter;
            pbe.IsActive = true;
            pbe.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(pbe);
            counter += 10000;
        }
        insert testPriceBookEntries;
        
        // Create test country
        TestDataFactory.createTestCountry(true);
    }
    
    /**
     * Test PK service registration with existing order
     */
    @isTest
    static void testRegistratePkService_Success_ExistingOrder() {
        Test.setMock(HttpCalloutMock.class, new StripeSuccessMock());
        
        Account account = TestDataFactory.createAccount(true);
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        
        Application__c testApp = TestDataFactory.createApplication(contacts[0].Id, false);
        testApp.CurrencyIsoCode = 'EUR';
        testApp.Payment_Method__c = 'pm_testmethod123';
        testApp.Current_Customer_Id__c = 'cus_testcustomer123';
        testApp.Date_Of_Birth__c = Date.valueOf('1970-05-15');
        testApp.PK_Portal_User_Active__c = false;
        insert testApp;
        
        // Create existing order
        Order existingOrder = TestDataFactory.createOrder(testApp.Id, account.Id, true);
        
        Test.startTest();
        String result = ChargePkActionController.registratePkService(testApp.Id, null);
        Test.stopTest();
        
        // Verify no new order was created
        List<Order> orders = [SELECT Id FROM Order WHERE Application__c = :testApp.Id];
        Assert.areEqual(1, orders.size(), 'Should reuse existing order');
        Assert.areEqual(existingOrder.Id, orders[0].Id, 'Should use the existing order');
        
        // Verify order item and payment were still created
        List<OrderItem> orderItems = [SELECT Id FROM OrderItem WHERE OrderId = :existingOrder.Id];
        Assert.areEqual(1, orderItems.size(), 'Order item should be created');
        
        List<Payment__c> payments = [SELECT Id FROM Payment__c WHERE Application__c = :testApp.Id];
        Assert.areEqual(1, payments.size(), 'Payment should be created');
    }
    
    /**
     * Test error handling - blank application ID
     */
    @isTest
    static void testRegistratePkService_Error_BlankAppId() {
        Test.startTest();
        try {
            ChargePkActionController.registratePkService(null, null);
            Assert.fail('Should throw exception for blank app Id');
        } catch (ChargePkActionController.RegistratePKCustomerException e) {
            Assert.isTrue(e.getMessage().contains('Application Id is empty'), 'Should have correct error message');
        }
        Test.stopTest();
    }
    
    /**
     * Test error handling - application already registered
     */
    @isTest
    static void testRegistratePkService_Error_AlreadyRegistered() {
        Account account = TestDataFactory.createAccount(true);
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        
        Application__c testApp = TestDataFactory.createApplication(contacts[0].Id, false);
        testApp.PK_Portal_User_Active__c = true; // Already registered
        testApp.Date_Of_Birth__c = Date.valueOf('1970-05-15');
        insert testApp;
        
        Test.startTest();
        try {
            ChargePkActionController.registratePkService(testApp.Id, null);
            Assert.fail('Should throw exception for already registered app');
        } catch (ChargePkActionController.RegistratePKCustomerException e) {
            Assert.isTrue(e.getMessage().contains('has already registered'), 'Should have correct error message');
        }
        Test.stopTest();
    }
    
    /**
     * Test currency code constant map
     */
    @isTest
    static void testCurrencyCodeMap() {
        // Verify all expected currencies are in the map
        Assert.areEqual('12500', ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.get('EUR'), 'EUR amount should be 12500');
        Assert.areEqual('20000', ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.get('CAD'), 'CAD amount should be 20000');
        Assert.areEqual('20000', ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.get('AUD'), 'AUD amount should be 20000');
        Assert.areEqual('20000', ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.get('NZD'), 'NZD amount should be 20000');
        Assert.areEqual('200000', ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.get('ZAR'), 'ZAR amount should be 200000');
        Assert.areEqual('15000', ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.get('USD'), 'USD amount should be 15000');
        Assert.areEqual(6, ChargePkActionController.CURRENCY_CODE_BY_PK_AMOUNT.size(), 'Should have 6 currency mappings');
    }
   
}