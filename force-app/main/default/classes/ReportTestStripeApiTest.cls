@isTest
public with sharing class ReportTestStripeApiTest {
    @TestSetup
    static void makeData(){
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        Application__c application =  TestDataFactory.createApplication(personContactId, true);
    }


    @IsTest static void getCustomerDataTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        List<Application__c> testApps = [
            SELECT
                Id,
                Payment_Method__c,
                Stripe_Customer_Id__c,
                Current_Address_Abroad__Street__s,
                Current_Address_Abroad__PostalCode__s
            FROM Application__c
            LIMIT 1
        ];
        Application__c currentApplcation = testApps[0];
        Test.startTest();
        ReportTestStripeApi.getCustomerData(currentApplcation.Stripe_Customer_Id__c, currentApplcation.Payment_Method__c, currentApplcation.Id);
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                Payment_Method__c,
                Stripe_Customer_Id__c,
                Current_Address_Abroad__Street__s,
                Current_Address_Abroad__PostalCode__s
            FROM Application__c
            LIMIT 1
        ];
        Application__c currentApplcationAfterUpdate = testAppsAfterUpdate[0];
        Assert.areNotEqual(currentApplcation.Current_Address_Abroad__Street__s, currentApplcationAfterUpdate.Current_Address_Abroad__Street__s);
        Assert.areNotEqual(currentApplcation.Current_Address_Abroad__PostalCode__s, currentApplcationAfterUpdate.Current_Address_Abroad__PostalCode__s);
        Assert.areEqual('Line 1, Line 2', currentApplcationAfterUpdate.Current_Address_Abroad__Street__s);
        Assert.areEqual('QW7 AS2', currentApplcationAfterUpdate.Current_Address_Abroad__PostalCode__s);
    }

    public class PaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"billing_details": {' +
                        '"address":{ ' +
                            '"city" : "Dublin",' +
                            '"country" : "IE",' +
                            '"line1" : "Line 1",' +
                            '"line2" : "Line 2",' +
                            '"postal_code" : "QW7 AS2",' +
                            '"state" : "County Dublin"' +
                        '}' +
                    '}' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}