@isTest
public class PayFailPaymentControllerTest {
    @TestSetup
    static void makeData(){
        List<Product2> testProducts = TestDataFactory.createProductsWithPrices();
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
        testPayment.Status__c  = 'Fail';
        testPayment.Product__c = testProducts[0].Id;
        insert testPayment;
    }

    @IsTest
    static void successChargePaymentTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Payment__c testPayment = [
            SELECT  Id
            FROM Payment__c
            LIMIT 1
        ];
        Test.startTest();
            String testResult = PayFailPaymentController.chargePayment(testPayment.Id);
        Test.stopTest();
        System.assertEquals(testPayment.Id, testResult);
    }

    @IsTest
    static void errorChargePaymentTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Payment__c testPayment = [
            SELECT  Id
            FROM Payment__c
            LIMIT 1
        ];
        delete testPayment;
        Test.startTest();
            try {
                PayFailPaymentController.chargePayment(testPayment.Id);
            } catch (Exception ex) {
                System.assertEquals('Don\'t exist Fail payment for application', ex.getMessage());
            }
        Test.stopTest();
    }

    private class PaymentServiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id":"pi_3hjNHGnBjgkjhg1FD", ' +
                    '"object":"payment_intent", ' +
                    '"amount":"10000",' +
                    '"payment_method":"pm_1245GFFuEghj4Gvbnjftg"' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }
}