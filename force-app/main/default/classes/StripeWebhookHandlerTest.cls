@isTest
public class StripeWebhookHandlerTest {
    @TestSetup
    static void makeData(){
        //List<Product2> testProducts = TestDataFactory.createProductsWithPrices();
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Monthly Updates', 'Success'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        // Pricebook2 standardPricebook = new Pricebook2(
	    //     Id = pricebookId,
	    //     IsActive = true
        // );
        // update standardPricebook;
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
        TestDataFactory.createXtraPensionDataCustomSetting(true);
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
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c testPayment = TestDataFactory.createPayment(testApplication.Id, order.Id, false);
        Id depositProductId;
        for (Product2 product : newProducts) {
            if (product.Name == 'Deposit') {
                depositProductId = product.Id;
                break;
            }
        }
        testPayment.Product__c = depositProductId;
        insert testPayment;
    }

    @IsTest static void invokeRestResponseTest() {
        Test.setMock(HttpCalloutMock.class, new CustomerDataMock());
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/StripeWebhookApi';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(
            '{ '+
                '"id": "evt_12457185",' +
                '"type": "payment_intent.succeeded",' +
                '"data": {' +
                    '"object": {'+
                        '"amount": 10000,' +
                        '"description": "Deposit MOTO",' +
                        '"customer": "cus_9874054",' +
                        '"payment_method": "pm_784151245941124",' +
                        '"id":"pi_87541124578415",' +
                        '"currency":"EUR",' +
                        '"shipping": {' +
                            '"address": {' +
                                '"city": "Galway",' +
                                '"country": "US",' +
                                '"line1": "73 West Street",' +
                                '"postal_code": "04075",' +
                                '"state": "ID"' +
                            '},' +
                            '"name": "Ugerd Lane",' +
                            '"phone": "+375297926917"' +
                        '}' +
                    '}' +
                '}' +
            '}');
        RestContext.request = request;
        RestContext.response= response;
        List<Application__c> testApplicationsBeforeRequest = [
            SELECT Id
            FROM Application__c
        ];
        System.assertEquals(1, testApplicationsBeforeRequest.size());
        Test.startTest();
            StripeWebhookHandler.invokeRestResponse();
        Test.stopTest();
        List<Application__c> testApplicationsAfterRequest = [
            SELECT
                Id,
                First_Name__c,
                Second_Name__c,
                Payment_Method__c,
                Stripe_Customer_Id__c,
                Stripe_Transaction_Id__c,
                Email__c,
                Related_Contact_Phone__c
            FROM Application__c
        ];
        System.assertEquals(2, testApplicationsAfterRequest.size());
        Application__c currentApplication = testApplicationsAfterRequest[1];
        System.assertEquals('Ugerd', currentApplication.First_Name__c);
        System.assertEquals('Lane', currentApplication.Second_Name__c);
        System.assertEquals('pm_784151245941124', currentApplication.Payment_Method__c);
        System.assertEquals('pi_87541124578415', currentApplication.Stripe_Transaction_Id__c);
        System.assertEquals('cus_9874054', currentApplication.Stripe_Customer_Id__c);
    }

    @IsTest
    static void invokeRestResponseTestCase2() {
        Test.setMock(HttpCalloutMock.class, new CustomerDataMock());
        RestRequest request = new RestRequest();
        RestResponse response = new RestResponse();
        request.requestURI = '/StripeWebhookApi';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(
            '{ '+
                '"id": "evt_12457185",' +
                '"type": "charge.refunded",' +
                '"data": {' +
                    '"object": {'+
                        '"description": "Deposit MOTO",' +
                        '"customer": "cus_9874054",' +
                        '"payment_method": "pm_784151245941124",' +
                        '"amount_captured": 10000,' +
                        '"amount_refunded": 10000,' +
                        '"payment_intent":"pi_87541124578415"' +
                        '}' +
                    '}' +
                '}' +
            '}');
        RestContext.request = request;
        RestContext.response= response;
        Payment__c testPaymentBeforeUpdate = [
            SELECT Status__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertNotEquals('Refund', testPaymentBeforeUpdate.Status__c);
        Test.startTest();
        StripeWebhookHandler.invokeRestResponse();
        Test.stopTest();
        Payment__c testPaymentAfterUpdate = [
            SELECT Status__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals('Refund', testPaymentAfterUpdate.Status__c);
    }

    private class CustomerDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id":"cus_9874054", ' +
                    '"email":"john.snow@gmail.com"' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}