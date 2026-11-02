@isTest
public class PK_PortalBillingHelperTest {
    
    // Mock class to handle any HTTP callouts during testing
    private class BillingCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success": true}');
            res.setStatusCode(200);
            return res;
        }
    }

    private class CardCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type','application/json');
            res.setBody('{"card":{"last4":"1234","brand":"Visa","exp_year":2025,"exp_month":12}}');
            res.setStatusCode(200);
            return res;
        }
    }
    
    @TestSetup
    static void setup() {
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Success', 'Pension Keeper'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Order testOrder = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        List<Payment__c> testPayments = TestDataFactory.createRelatedPaymentToApplication(
            newProducts,
            testApplication,
            testOrder.Id,
            true
        );
    }
    
    @isTest
    static void testGetBillingInfoSuccess() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'billing@test.com';
        app.CurrencyIsoCode = 'GBP';
        update app;
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + app.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getBillingInfo(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('application'));
    }
    
    @isTest
    static void testGetBillingInfoNullId() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":null}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getBillingInfo(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Id is null', result.get('message'));
    }
    
    @isTest
    static void testGetBillingInfoNullWrapper() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getBillingInfo(null);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Id is null', result.get('message'));
    }
    
    @isTest
    static void testGetBillingInfoApplicationNotFound() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + UserInfo.getOrganizationId().substring(0,15) + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getBillingInfo(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }
    
    @isTest
    static void testGetReceiptSuccess() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Order ord = [SELECT Id FROM Order WHERE Application__c = :app.Id LIMIT 1];

        // use the factory to keep things consistent with other tests
        Payment__c pay = TestDataFactory.createPayment(app.Id, ord.Id, true);

        // insert a simple receipt record pointing back to the payment
        Receipt__c rec = new Receipt__c(
            Payment__c = pay.Id,
            Application__c = app.Id,
            Paid_Date__c = Date.today(),
            CurrencyIsoCode = pay.CurrencyIsoCode
        );
        insert rec;

        EmailMessage em = new EmailMessage(
            Status       = '3',
            RelatedToId  = rec.Id,
            Subject      = 'Unit Test Receipt',
            HtmlBody     = '<div>Receipt Content</div>'
        );
        insert em;

        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + pay.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getReceipt(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testGetReceiptNullId() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":null}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getReceipt(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Payment Id is null', result.get('message'));
    }
    
    @isTest
    static void testGetReceiptNullWrapper() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getReceipt(null);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Payment Id is null', result.get('message'));
    }
    
    @isTest
    static void testGetReceiptNotFound() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());
        
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Order ord = [SELECT Id FROM Order WHERE Application__c = :app.Id LIMIT 1];

        // use the factory to keep things consistent with other tests
        Payment__c pay = TestDataFactory.createPayment(app.Id, ord.Id, true);
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + pay.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getReceipt(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found receipt', result.get('message'));
    }
    
    @isTest
    static void testGetBillingInfoExceptionHandling() {
        Test.setMock(HttpCalloutMock.class, new BillingCalloutMock());        
        // Use invalid ID format to trigger exception
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"invalid"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalBillingHelper.getBillingInfo(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertNotEquals(null, result.get('message'));
    }
}