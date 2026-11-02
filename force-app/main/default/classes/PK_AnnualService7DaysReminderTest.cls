@isTest
public with sharing class PK_AnnualService7DaysReminderTest {

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
            Payment_Date__c = Date.today().addDays(7), // 7 days out for this batch
            Amount__c = 255,
            Payment_Method__c = 'pm_123'
        );
        insert payment;
    }

    @isTest
    static void testBatchSendsEmailAndUpdatesFlag() {
        Test.setMock(HttpCalloutMock.class, new MockStripeResponse());

        Test.startTest();
        Database.executeBatch(new PK_AnnualService7DaysReminder(), 10);
        Test.stopTest();

        // Verify by Subject to avoid framework dummy emails
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject'
        ];
        System.assertEquals(1, messages.size(), 'Exactly one email should be sent');

        List<Payment__c> payments = [SELECT Seven_Day_Reminder_Sent_Date__c FROM Payment__c];
        System.assertEquals(1, payments.size(), 'One payment expected');
        System.assertEquals(Date.today(), payments[0].Seven_Day_Reminder_Sent_Date__c, '7-Day Reminder Sent Date should be stamped');
    }

    @isTest
    static void testSendsEvenIf30DayReminderWasSent() {
        Test.setMock(HttpCalloutMock.class, new MockStripeResponse());

        // Pre-mark the 30-day reminder as sent
        Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
        p.Application_Reminder_Sent_Date__c = Date.today().addDays(-23); // Sent 23 days ago
        update p;

        Test.startTest();
        Database.executeBatch(new PK_AnnualService7DaysReminder(), 10);
        Test.stopTest();

        // Verify the 7-day email was STILL sent
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject'
        ];
        System.assertEquals(1, messages.size(), 'Email should be sent even if 30-day reminder was already sent');

        // Verify the 7-day flag was stamped
        Payment__c updatedPayment = [SELECT Seven_Day_Reminder_Sent_Date__c FROM Payment__c LIMIT 1];
        System.assertEquals(Date.today(), updatedPayment.Seven_Day_Reminder_Sent_Date__c, '7-Day Reminder Sent Date should be stamped');
    }

    @isTest
    static void testBatchIsIdempotent() {
        Test.setMock(HttpCalloutMock.class, new MockStripeResponse());

        // Pre-mark the 7-day payment as sent
        Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
        p.Seven_Day_Reminder_Sent_Date__c = Date.today();
        update p;

        Test.startTest();
        Database.executeBatch(new PK_AnnualService7DaysReminder(), 10);
        Test.stopTest();

        // Verify no NEW email was sent
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject'
        ];
        System.assertEquals(0, messages.size(), 'No email should be sent for an already processed payment');
    }

    @isTest
    static void testSkipsWhenRecordDoesNotMatchCriteria() {
        // Change date to 30 days out instead of 7
        Payment__c p = [SELECT Id FROM Payment__c LIMIT 1];
        p.Payment_Date__c = Date.today().addDays(30); 
        update p;

        Test.startTest();
        Database.executeBatch(new PK_AnnualService7DaysReminder(), 10);
        Test.stopTest();

        // Verify no email was sent
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject'
        ];
        System.assertEquals(0, messages.size(), 'Email should not be sent for records not matching criteria');
    }

    @isTest
    static void testHandlesStripeFailureGracefully() {
        Test.setMock(HttpCalloutMock.class, new MockStripeMissingCard());

        Test.startTest();
        Database.executeBatch(new PK_AnnualService7DaysReminder(), 10);
        Test.stopTest();

        // Verify email was still sent
        List<EmailMessage> messages = [
            SELECT Id, Subject 
            FROM EmailMessage 
            WHERE Subject = 'Test Subject'
        ];
        System.assertEquals(1, messages.size(), 'Email should be sent even if card data is missing');

        // Verify flag was updated
        Payment__c p = [SELECT Seven_Day_Reminder_Sent_Date__c FROM Payment__c LIMIT 1];
        System.assertEquals(Date.today(), p.Seven_Day_Reminder_Sent_Date__c, '7-Day Flag should be updated');
    }
}