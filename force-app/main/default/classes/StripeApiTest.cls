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
    static void createPaymentIntentTestcase2() {
        Test.setMock(HttpCalloutMock.class, new FailPaymentMock());
        List<Payment__c> payment = [
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
        Payment__c testPayment = payment[0];
        testPayment.Repeated_Payment_Date_1__c = Date.today().addDays(-8);
        testPayment.Repeated_Payment_Date_2__c = Date.today().addDays(-4);
        testPayment.Repeated_Payment_Date_3__c = Date.today();
        update testPayment;

        Map<String, String> paymentIntentParams = new Map<String, String> {
            'confirmation_method' => 'manual',
            'currency'            => 'eur',
            'confirm'             => 'true',
            'customer'            => testPayment?.Customer_Id__c,
            'payment_method'      => testPayment?.Payment_Method__c,
            'amount'              => String.valueOf(Integer.valueOf(testPayment?.Amount__c * 100))
        };
        System.assertNotEquals(null, testPayment, 'Payment must be not null');
        System.assertEquals('Schedule', testPayment.Status__c, 'Payment status must be Schedule');
        Test.startTest();
        StripeApiService.createPaymentIntent(paymentIntentParams, testPayment.Id);
        Test.stopTest();
        Payment__c updatePayment = [
            SELECT
                Id,
                Status__c,
                Error_Message__c
            FROM Payment__c
            LIMIT 1
        ];
        System.assertNotEquals(null, updatePayment.Error_Message__c, 'Payment Error Message mustn\'t be null');
        System.assertEquals('Fail', updatePayment.Status__c, 'Payment status must be Fail');
        System.assertNotEquals(testPayment.Status__c, updatePayment.Status__c, 'Payment status before and after update must be not equals');
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
    static void getCustomerDataTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());

        Test.startTest();
        String customerData = StripeApiService.getCustomerData('cus_test');
        Test.stopTest();

        System.assert(customerData.contains('"payment_method"'));
    }

    @IsTest
    static void getCustomerDataErrorTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceErrorMock());

        Test.startTest();
        String customerData = StripeApiService.getCustomerData('cus_test');
        Test.stopTest();

        System.assertEquals('Error', customerData);
    }

    @IsTest
    static void createPaymentIntentForMissingPaymentTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());

        Test.startTest();
        try {
            StripeApiService.createPaymentIntentForBatch(new Map<String, String>(), null);
            System.assert(false, 'A missing payment should throw an exception');
        } catch (StripeApiService.StripeApiException error) {
            System.assertEquals('Don\'t exist payment method', error.getMessage());
        }
        Test.stopTest();
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
    static void createPaymentIntentForBatchHandlesMissingCardDataTest() {
        Test.setMock(HttpCalloutMock.class, new MissingCardDataMock());
        Payment__c payment = [SELECT Id, Customer_Id__c, Payment_Method__c FROM Payment__c LIMIT 1];

        Test.startTest();
        StripeApiService.createPaymentIntentForBatch(
            new Map<String, String>{
                'customer' => payment.Customer_Id__c,
                'payment_method' => payment.Payment_Method__c
            },
            payment.Id
        );
        Test.stopTest();

        Payment__c updatedPayment = [
            SELECT Status__c, Payment_Intent__c, Card_Data__c
            FROM Payment__c
            WHERE Id = :payment.Id
        ];
        System.assertEquals('Paid', updatedPayment.Status__c);
        System.assertEquals('pi_missing_card_test', updatedPayment.Payment_Intent__c);
        System.assertEquals(null, updatedPayment.Card_Data__c);
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
    static void createPaymentIntentForBatchPreservesRetryDatesTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceErrorMock());
        Payment__c payment = [
            SELECT Id, Customer_Id__c, Payment_Method__c, Repeated_Payment_Date_1__c,
                Repeated_Payment_Date_2__c, Repeated_Payment_Date_3__c
            FROM Payment__c
            LIMIT 1
        ];
        payment.Repeated_Payment_Date_1__c = Date.today().addDays(-8);
        payment.Repeated_Payment_Date_2__c = Date.today().addDays(-4);
        payment.Repeated_Payment_Date_3__c = Date.today();
        update payment;

        Test.startTest();
        StripeApiService.createPaymentIntentForBatch(
            new Map<String, String>{
                'customer' => payment.Customer_Id__c,
                'payment_method' => payment.Payment_Method__c
            },
            payment.Id
        );
        Test.stopTest();

        Payment__c updatedPayment = [
            SELECT Repeated_Payment_Date_1__c, Repeated_Payment_Date_2__c, Repeated_Payment_Date_3__c
            FROM Payment__c
            WHERE Id = :payment.Id
        ];
        System.assertEquals(Date.today().addDays(-8), updatedPayment.Repeated_Payment_Date_1__c);
        System.assertEquals(Date.today().addDays(-4), updatedPayment.Repeated_Payment_Date_2__c);
        System.assertEquals(Date.today(), updatedPayment.Repeated_Payment_Date_3__c);
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

    @IsTest
    static void updatePaymentCardDataErrorTest() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceErrorMock());
        Payment__c payment = [SELECT Id FROM Payment__c LIMIT 1];

        Test.startTest();
        StripeApiService.updatePaymentCardData(payment.Id);
        Test.stopTest();

        Payment__c unchangedPayment = [
            SELECT Card_Data__c
            FROM Payment__c
            WHERE Id = :payment.Id
        ];
        System.assertEquals(null, unchangedPayment.Card_Data__c);
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

    private class MissingCardDataMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/payment_methods/')) {
                response.setBody('{"id":"pm_test","type":"link"}');
            } else {
                response.setBody(
                    '{"id":"pi_missing_card_test","latest_charge":"ch_missing_card_test","payment_method":"pm_test"}'
                );
            }
            response.setStatusCode(200);
            return response;
        }
    }

    private class FailPaymentMock implements HttpCalloutMock{
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"error":{' +
                        '"message":"Your card has insufficient funds."' +
                    '}' +
                '}');
            res.setStatusCode(400);
            return res;
        }
    }
}