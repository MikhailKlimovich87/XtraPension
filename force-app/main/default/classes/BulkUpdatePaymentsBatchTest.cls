@isTest
public class BulkUpdatePaymentsBatchTest {
    @TestSetup
    static void setup(){
        TestDataFactory.createProductsWithPrices();
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
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c testPayment = TestDataFactory.createPayment(testApplication.Id, order.Id, false);
        testPayment.Status__c = 'Refund';
        insert testPayment;
    }

    @isTest
    static void createPaymentIntentTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Test.startTest();
        List<Payment__c> paymentsBeforeUpdate = [
            SELECT isSyncAppData__c
            FROM Payment__c
        ];
        Assert.areEqual(false, paymentsBeforeUpdate[0].isSyncAppData__c);
        BulkUpdatePaymentsBatch paymentBatch = new BulkUpdatePaymentsBatch(
            'SELECT Name, Application__r.Name, Status__c, Payment_Intent__c FROM Payment__c WHERE Status__c = \'Fail\' OR Status__c = \'Refund\' OR Status__c = \'Paid\' ORDER BY CreatedDate DESC'
        );
        Database.executeBatch(paymentBatch);

        Test.stopTest();

        List<Payment__c> paymentsAfterUpdate = [
            SELECT isSyncAppData__c
            FROM Payment__c
        ];
        Assert.areEqual(true, paymentsAfterUpdate[0].isSyncAppData__c);
    }
}