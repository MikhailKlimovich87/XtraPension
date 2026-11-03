@isTest
public with sharing class BulkChargePaymentBatchTest {
    @TestSetup
    static void makeData(){
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Success'};
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c = 'Posted';
        insert testApplication;
        // create an order and payment for the application used in tests
        Order ord = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c pay = TestDataFactory.createPayment(testApplication.Id, ord.Id, true);
        // associate product and mark payment as failed so batch will pick it up
        pay.Product__c = newProducts[1].Id;
        pay.Status__c = 'Fail';
        update pay;
    }

    @IsTest
    static void testExecute_Success() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());

        Application__c app = [SELECT Id, First_Name__c, Email__c FROM Application__c LIMIT 1];
        Payment__c p = [SELECT Id, Customer_Id__c, Payment_Method__c, Amount__c FROM Payment__c WHERE Application__c = :app.Id LIMIT 1];

        Test.startTest();
        Database.executeBatch(new BulkChargePaymentBatch(), 1);
        Test.stopTest();

        Payment__c updated = [SELECT Id, Status__c, Payment_Intent__c, Source__c, Card_Data__c FROM Payment__c WHERE Id = :p.Id];
        System.assertEquals('Paid', updated.Status__c, 'Payment should be marked as Paid');
        System.assertNotEquals(null, updated.Payment_Intent__c, 'Payment_Intent should be set');
        //System.assertNotEquals(null, updated.Source__c, 'Source should be set');
        System.assertEquals('visa - 4242', updated.Card_Data__c, 'Card data should be set in tests');
    }

    @IsTest
    static void testExecute_Failure() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceErrorMock());

        Application__c app = [SELECT Id, First_Name__c, Email__c FROM Application__c LIMIT 1];
        Payment__c p = [SELECT Id, Customer_Id__c, Payment_Method__c, Amount__c FROM Payment__c WHERE Application__c = :app.Id LIMIT 1];

        Test.startTest();
        Database.executeBatch(new BulkChargePaymentBatch(), 1);
        Test.stopTest();

        Payment__c updated = [SELECT Id, Error_Message__c, Fail_Payment_Date__c, Status__c FROM Payment__c WHERE Id = :p.Id];
        System.assertEquals('Test error', updated.Error_Message__c, 'Error message should be set from the callout mock');
        System.assertNotEquals(null, updated.Fail_Payment_Date__c, 'Fail_Payment_Date should be set');
        System.assertEquals('Fail', updated.Status__c, 'Status should remain Fail');
    }
}