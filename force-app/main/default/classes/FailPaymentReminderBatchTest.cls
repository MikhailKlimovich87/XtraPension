@isTest
public with sharing class FailPaymentReminderBatchTest {
    @TestSetup
    static void makeData(){
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Email__c = 'john.snow@test.com';
        insert testApplication;
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c testPayment = TestDataFactory.createPayment(testApplication.Id, order.Id, false);
        testPayment.Status__c = 'Fail';
        testPayment.Repeated_Payment_Date_1__c  = Date.today();
        insert testPayment;
    }

    @IsTest
    static void executeFailPaymentReminderBatchTest(){
        Test.startTest();
            FailPaymentReminderBatch testReminder = new FailPaymentReminderBatch();
            DataBase.executeBatch(testReminder);
        Test.stopTest();
    }
}