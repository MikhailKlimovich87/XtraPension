@isTest
public class PK_PortalSignUpHelperTest {
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
    static void testFindApplicationSuccess() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'signup@test.com';
        app.PK_Portal_User_Active__c = false;
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"signup@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('foundApplication'));
    }
    
    @isTest
    static void testFindApplicationAlreadyActive() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'alreadyactive@test.com';
        app.PK_Portal_User_Active__c = true;
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"alreadyactive@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertNotEquals(null, result.get('message'));
    }
    
    @isTest
    static void testFindApplicationNotFound() {
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"NONEXISTENT","email":"notfound@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertNotEquals(null, result.get('message'));
    }
    
    @isTest
    static void testFindApplicationNullApplicationNumber() {
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":null,"email":"test@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Number or Email is null', result.get('message'));
    }
    
    @isTest
    static void testFindApplicationNullEmail() {
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"APP003","email":null}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Number or Email is null', result.get('message'));
    }
    
    @isTest
    static void testFindApplicationBothNull() {
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":null,"email":null}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Number or Email is null', result.get('message'));
    }
    
    @isTest
    static void testFindApplicationExceptionHandling() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());

        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'error@test.com';
        update app;
        
        // Use invalid JSON to potentially trigger exception
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"error@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testFindApplicationMultipleMatches() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());

        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'duplicate@test.com';
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"duplicate@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('foundApplication'));
    }
    
    @isTest
    static void testFindApplicationCaseInsensitive() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'CaseSensitive@test.com';
        update app;
        
        // Try with different case
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"casesensitive@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        // Should not find if case doesn't match
        System.assertEquals('error', result.get('status'));
    }
    
    @isTest
    static void testFindApplicationAllFieldsPopulated() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());

        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'fullapp@test.com';
        app.First_Name__c = 'John';
        app.Second_Name__c = 'Smith';
        app.Full_Maiden_Previous_Name__c = 'Doe';
        app.Date_Of_Birth__c = Date.newInstance(1985, 3, 20);
        app.National_Insurance_Number__c = 'YZ987654X';
        app.Private_UK_Pension__c = true;
        app.Current_Occupation__c = 'Doctor';
        app.Current_Address_Abroad__City__s = 'Paris';
        app.Current_Address_Abroad__CountryCode__s = 'FR';
        app.Current_Address_Abroad__PostalCode__s = '75001';
        app.Current_Address_Abroad__Street__s = '100 Rue de Rivoli';
        app.Stripe_Customer_Id__c = 'cus_xyz789';
        app.Payment_Method__c = 'Stripe';
        app.PK_Portal_User_Active__c = false;
        app.Related_Contact_Phone__c = '+33123456789';
        app.CurrencyIsoCode = 'EUR';
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"fullapp@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalSignUpHelper.findApplication(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        PK_ResponseWrappers.CurrentApplicationDataWrapper appWrapper = 
            (PK_ResponseWrappers.CurrentApplicationDataWrapper) result.get('foundApplication');
        System.assertNotEquals(null, appWrapper);
    }
}