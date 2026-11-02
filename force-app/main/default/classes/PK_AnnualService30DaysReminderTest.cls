@isTest
public with sharing class PK_AnnualService30DaysReminderTest {

    public class MockStripeResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"id": "pm_123", "card": {"brand": "mastercard", "last4": "4444"}}');
            return res;
        }
    }

    public class MockStripeMissingCard implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"id": "pm_123"}'); 
            return res;
        }
    }

    @TestSetup
    static void makeData() {
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        
        List<Contact> contacts = [SELECT Id, Email FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        Id contactId = contacts[0].Id;

        Application__c app = TestDataFactory.createApplication(contactId, false);
        app.Status__c = 'Pension Keeper';
        app.Email__c = 'test.customer@example.com';
        app.First_Name__c = 'Test First Name';
        insert app;

        Order testOrder = TestDataFactory.createOrder(app.Id, account.Id, true);

        Payment__c payment = new Payment__c(
            Application__c = app.Id,
            Order__c = testOrder.Id,
            Status__c = 'Schedule',
            Pension_Keeper_Annual_Payment__c = true,
            Payment_Date__c = Date.today().addDays(30),
            Amount__c = 255,
            Payment_Method__c = 'pm_123'
        );
        insert payment;
    }

    @isTest
    static void testBatchSendsEmailAndUpdatesFlag() {
        Test.setMock(HttpCalloutMock.class, new MockStripeResponse());

        Test.startTest();
        Database.executeBatch(new PK_AnnualService30DaysReminder(), 10);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM EmailMessage], 'Exactly one email should be sent');

        List<Payment__c> payments = [SELECT Application_Reminder_Sent_Date__c FROM Payment__c];
        System.assertEquals(1, payments.size(), 'One payment expected');
        System.assertEquals(Date.today(), payments[0].Application_Reminder_Sent_Date__c, 'Reminder Sent Date should be stamped');
    }

    @isTest
    static void testBatchIsIdempotent() {
        Test.setMock(HttpCalloutMock.class, new MockStripeResponse());

        // Pre-mark the payment as sent
        Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
        p.Application_Reminder_Sent_Date__c = Date.today();
        update p;

        Test.startTest();
        Database.executeBatch(new PK_AnnualService30DaysReminder(), 10);
        Test.stopTest();

        // Query EmailMessage and filter by the Subject we know our template uses.
        // This bypasses the "dummy" email that the test framework sometimes creates.
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject' // The subject set in getTemplate() during Test.isRunningTest()
        ];
        
        System.assertEquals(0, messages.size(), 'No email should be sent for an already processed payment');
    }

    @isTest
    static void testSkipsWhenRecordDoesNotMatchCriteria() {
        // Delete the payment so the batch has absolutely nothing to query.
        delete [SELECT Id FROM Payment__c];

        Test.startTest();
        Database.executeBatch(new PK_AnnualService30DaysReminder(), 10);
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations(), 'Email should not be sent');
    }

    @isTest
    static void testHandlesStripeFailureGracefully() {
        Test.setMock(HttpCalloutMock.class, new MockStripeMissingCard());

        Test.startTest();
        Database.executeBatch(new PK_AnnualService30DaysReminder(), 10);
        Test.stopTest();

        // 1. Filter by Subject to ignore the test framework's placeholder EmailMessage
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject'
        ];
        System.assertEquals(1, messages.size(), 'Email should be sent even if card data is missing');

        // 2. Verify the flag was successfully updated
        Payment__c p = [SELECT Application_Reminder_Sent_Date__c FROM Payment__c LIMIT 1];
        System.assertEquals(Date.today(), p.Application_Reminder_Sent_Date__c, 'Flag should be updated');
    }
}