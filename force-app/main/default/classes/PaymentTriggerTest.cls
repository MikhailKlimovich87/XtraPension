@isTest
public class PaymentTriggerTest {
    @TestSetup
    static void makeData() {
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
        testPayment.Payment_Date__c = Date.today();
        insert testPayment;
    }

    @IsTest
    static void changePaymentStatusToPaidTest() {
        List<Payment__c> testPayment = [
            SELECT Status__c
            FROM Payment__c
        ];
        testPayment[0].Status__c = 'Paid';
        update testPayment;
    }

    @IsTest
    static void sendRegistrationFeeDataToAdminTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        List<Payment__c> testPayments = [
            SELECT
                Id,
                Status__c,
                Application__c,
                Amount__c
            FROM Payment__c
        ];
        Payment__c currentPayment = testPayments[0];
        currentPayment.Status__c = 'Paid';
        update currentPayment;
        Map<Id, Payment__c> newPayments = new Map<Id, Payment__c>();
        newPayments.put(currentPayment.Id, currentPayment);
        PaymentTriggerHandler.sendEmailAfterCreatePaidPayment(newPayments);
    }

    private class PaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id":"pm124512451", ' +
                    '"card":{' +
                        '"brand":"visa", ' +
                        '"last4":"4242"' +
                    '}' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}