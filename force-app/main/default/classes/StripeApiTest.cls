@isTest
public class StripeApiTest {
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
        TestDataFactory.createPayment(testApplication.Id, order.Id, true);
    }

    @IsTest
    static void createPaymentIntentTest(){
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Payment__c payment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c,
				Error_Message__c,
				Application__c
            FROM Payment__c
            LIMIT 1
        ];

        Map<String, String> paymentIntentParams = new Map<String, String> {
            'confirmation_method' => 'manual',
            'currency'            => 'eur',
            'confirm'             => 'true',
            'customer'            => payment?.Customer_Id__c,
            'payment_method'      => payment?.Payment_Method__c,
            'amount'              => String.valueOf(Integer.valueOf(payment?.Amount__c * 100))
            // 'description'         => 'Application',
            // 'receipt_email'       => payment.Application__r.Email__c
        };
        System.assertNotEquals(null, payment, 'Payment must be not null');
        System.assertEquals('Schedule', payment.Status__c, 'Payment status must be Schedule');
        Test.startTest();
        StripeApiService.createPaymentIntent(paymentIntentParams, payment.Id);
        Test.stopTest();
        Payment__c updatePayment = [
            SELECT
                Id,
                Status__c,
                Error_Message__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals(null, updatePayment.Error_Message__c, 'Payment Error Message must be null');
        System.assertEquals('Paid', updatePayment.Status__c, 'Payment status must be Schedule');
        System.assertNotEquals(payment.Status__c, updatePayment.Status__c, 'Payment status before and after update must be not equals');
    }

    @IsTest
    static void getPaymentIntentTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Map<String, String> paymentIntentParams = new Map<String, String> {
            'id' => 'pi_12Qasd45asdf'
        };
        Test.startTest();
        StripeApiHandler.StripeAPIResponseWrapper requestResult = StripeApiHandler.requestStripeApi(
			'payment_intents',
			'GET',
			paymentIntentParams
		);
        Test.stopTest();
        System.assertNotEquals(null, requestResult, 'Result must be not null');
        System.assertEquals(null, requestResult.errorMessage, 'Result error message must be null');
        System.assertEquals(null, requestResult.isError, 'Result isError checkbox must be  null');
        System.assertNotEquals(null, requestResult.responseBody, 'Result responseBody must be not null');
    }

    @IsTest
    static void errorResponseTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceErrorMock());
        Payment__c payment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertNotEquals(null, payment, 'Payment must be not null');
        System.assertEquals('Schedule', payment.Status__c, 'Payment status must be Schedule');
        Map<String, String> paymentIntentParams = new Map<String, String> {
            'confirmation_method' => 'manual',
            'currency'            => 'eur',
            'confirm'             => 'true',
            'customer'            => payment?.Customer_Id__c,
            'payment_method'      => payment?.Payment_Method__c,
            'amount'              => String.valueOf(Integer.valueOf(payment?.Amount__c * 100))
            // 'description'         => 'Application',
            // 'receipt_email'       => payment.Application__r.Email__c
        };
        Test.startTest();
        StripeApiService.createPaymentIntent(paymentIntentParams, payment.Id);
        Test.stopTest();
        Payment__c updatePayment = [
            SELECT
                Id,
                Status__c,
                Error_Message__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals('Fail', updatePayment.Status__c, 'Payment status must be Fail');
        System.assertNotEquals(payment.Status__c, updatePayment.Status__c, 'Payment status before and after update must be not equals');
    }

    @IsTest
    static void createPaymentIntentForBatchTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Payment__c payment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertNotEquals(null, payment, 'Payment must be not null');
        System.assertEquals('Schedule', payment.Status__c, 'Payment status must be Schedule');
        Map<String, String> paymentIntentParams = new Map<String, String> {
            'confirmation_method' => 'manual',
            'currency'            => 'eur',
            'confirm'             => 'true',
            'customer'            => payment?.Customer_Id__c,
            'payment_method'      => payment?.Payment_Method__c,
            'amount'              => String.valueOf(Integer.valueOf(payment?.Amount__c * 100))
            // 'description'         => 'Application',
            // 'receipt_email'       => payment.Application__r.Email__c
        };
        Test.startTest();
        StripeApiService.createPaymentIntentForBatch(paymentIntentParams, payment.Id);
        Test.stopTest();
        Payment__c updatePayment = [
            SELECT
                Id,
                Status__c,
                Error_Message__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals(null, updatePayment.Error_Message__c, 'Payment Error Message must be null');
        System.assertEquals('Paid', updatePayment.Status__c, 'Payment status must be Schedule');
        System.assertNotEquals(payment.Status__c, updatePayment.Status__c, 'Payment status before and after update must be not equals');
    }

    @IsTest
    static void createPaymentIntentForBatchCase2Test() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceErrorMock());
        Payment__c payment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertNotEquals(null, payment, 'Payment must be not null');
        System.assertEquals('Schedule', payment.Status__c, 'Payment status must be Schedule');
        Map<String, String> paymentIntentParams = new Map<String, String> {
            'confirmation_method' => 'manual',
            'currency'            => 'eur',
            'confirm'             => 'true',
            'customer'            => payment?.Customer_Id__c,
            'payment_method'      => payment?.Payment_Method__c,
            'amount'              => String.valueOf(Integer.valueOf(payment?.Amount__c * 100))
            // 'description'         => 'Application',
            // 'receipt_email'       => payment.Application__r.Email__c
        };
        Test.startTest();
        StripeApiService.createPaymentIntentForBatch(paymentIntentParams, payment.Id);
        Test.stopTest();
        Payment__c updatePayment = [
            SELECT
                Id,
                Status__c,
                Error_Message__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals('Test error' , updatePayment.Error_Message__c, 'Payment Error Message must be not null');
        System.assertEquals('Fail', updatePayment.Status__c, 'Payment status must be Fail');
        System.assertNotEquals(payment.Status__c, updatePayment.Status__c, 'Payment status before and after update must be not equals');

    }

    @IsTest
    static void updatePaymentCardDataTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentMethodMock());
        Payment__c payment = [
            SELECT
                Name,
                Product__r.Name,
                Status__c,
                Payment_Date__c,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c,
                Tax_VAT__c,
                Card_Data__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals(null, payment.Card_Data__c, 'Card Data field must be null');

        Test.startTest();
        StripeApiService.updatePaymentCardData(payment.Id);
        Test.stopTest();
        Payment__c updatePayment = [
            SELECT
                Id,
                Status__c,
                Error_Message__c,
                Card_Data__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertEquals('visa - 4242', updatePayment.Card_Data__c, 'Card Data field value don\'t match');
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