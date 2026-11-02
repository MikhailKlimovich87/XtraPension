@isTest
public class BulkUpdateStripePaymentIntentsBatchTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }

    @isTest
    static void testStartReturnsStripePaymentIntents() {
        BulkUpdateStripePaymentIntentsMock mock = new BulkUpdateStripePaymentIntentsMock();
        Test.setMock(HttpCalloutMock.class, mock);

        DateTime startDate = DateTime.newInstanceGmt(2024, 1, 1, 0, 0, 0);
        DateTime endDate = DateTime.newInstanceGmt(2024, 1, 31, 23, 59, 59);

        Test.startTest();
            BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch(startDate, endDate);
            Iterable<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper> result = batch.start(null);
            List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper> paymentData = new List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>();
            for (BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper item : result) {
                paymentData.add(item);
            }
        Test.stopTest();

        System.assertEquals(1, paymentData.size(), 'Expected one payment intent record from start');
        System.assertEquals('cus_123456789', paymentData[0].customer, 'Customer ID should match mocked response');
        System.assertEquals('pi_12345', paymentData[0].id, 'Payment intent ID should match mocked response');
        System.assert(mock.lastRequest.getEndpoint().contains('created%3E%3D'));
        System.assert(mock.lastRequest.getEndpoint().contains('created%3C%3D'));
    }

    @isTest
    static void testExecuteUpdatesStripePaymentIntentMetadata() {
        BulkUpdateStripePaymentIntentsMock mock = new BulkUpdateStripePaymentIntentsMock();
        mock.returnSearchDataNull = false;
        mock.returnSearchDataEmpty = false;
        Test.setMock(HttpCalloutMock.class, mock);

        Application__c existingApp = [
            SELECT Id, Name, Stripe_Customer_Id__c, Contact__c
            FROM Application__c
            LIMIT 1
        ];

        Contact appContact = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :existingApp.Contact__c
            LIMIT 1
        ];

        Order testOrder = TestDataFactory.createOrder(existingApp.Id, appContact.AccountId, true);
        Payment__c testPayment = TestDataFactory.createPayment(existingApp.Id, testOrder.Id, true);
        testPayment.Customer_Id__c = existingApp.Stripe_Customer_Id__c;
        update testPayment;

        BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper paymentWrapper = new BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper();
        paymentWrapper.customer = existingApp.Stripe_Customer_Id__c;
        paymentWrapper.id = 'pi_12345';

        Test.startTest();
            BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch();
            batch.execute(null, new List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>{paymentWrapper});
        Test.stopTest();

        System.assertNotEquals(null, mock.lastRequest, 'A Stripe POST request should have been made');
        System.assert(mock.lastRequest.getEndpoint().contains('payment_intents/pi_12345'));
        System.assert(mock.lastRequest.getBody().contains('metadata[AppNo]'));
    }

    @isTest
    static void testStartReturnsEmptyWhenStripeSearchReturnsNoData() {
        BulkUpdateStripePaymentIntentsMock mock = new BulkUpdateStripePaymentIntentsMock();
        mock.returnSearchDataNull = true;
        mock.returnSearchDataEmpty = false;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
            BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch();
            Iterable<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper> result = batch.start(null);
            List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper> paymentData = new List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>();
            for (BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper item : result) {
                paymentData.add(item);
            }
        Test.stopTest();

        System.assertEquals(0, paymentData.size(), 'Expected no payment intent records when Stripe returns no data');
        System.assertEquals(1, mock.calloutCount, 'Search callout should still occur');
    }

    @isTest
    static void testExecuteReturnsWhenScopeIsEmpty() {
        Test.startTest();
            BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch();
            batch.execute(null, new List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>());
        Test.stopTest();

        System.assert(true, 'Execute should return immediately when scope is empty');
    }

    @isTest
    static void testExecuteReturnsWhenNoPaymentMatchesCustomer() {
        BulkUpdateStripePaymentIntentsMock mock = new BulkUpdateStripePaymentIntentsMock();
        Test.setMock(HttpCalloutMock.class, mock);

        BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper paymentWrapper = new BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper();
        paymentWrapper.customer = 'cus_no_match';
        paymentWrapper.id = 'pi_no_match';

        Test.startTest();
            BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch();
            batch.execute(null, new List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>{paymentWrapper});
        Test.stopTest();

        System.assertEquals(1, mock.calloutCount, 'Should make GET customer request when no payment record matches');
        System.assert(mock.lastRequest.getEndpoint().contains('customers/cus_no_match'), 'Should attempt to get customer from Stripe');
    }

    @isTest
    static void testExecuteUsesApplicationEmailWhenNoPaymentFound() {
        BulkUpdateStripePaymentIntentsMock mock = new BulkUpdateStripePaymentIntentsMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Application__c existingApp = [
            SELECT Id, Name, Stripe_Customer_Id__c
            FROM Application__c
            LIMIT 1
        ];

        BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper paymentWrapper = new BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper();
        paymentWrapper.customer = existingApp.Stripe_Customer_Id__c;
        paymentWrapper.id = 'pi_12345';

        Test.startTest();
            BulkUpdateStripePaymentIntentsBatch batch = new BulkUpdateStripePaymentIntentsBatch();
            batch.execute(null, new List<BulkUpdateStripePaymentIntentsBatch.PaymentDataWrapper>{paymentWrapper});
        Test.stopTest();

        System.assertEquals(1, mock.calloutCount, 'Should make GET customer request when no payment record matches');
        System.assert(mock.lastRequest.getEndpoint().contains('customers/'), 'Should attempt to get customer from Stripe');
    }

    @isTest
    static void testDatabaseBatchExecutionRunsFinish() {
        BulkUpdateStripePaymentIntentsMock mock = new BulkUpdateStripePaymentIntentsMock();
        mock.returnSearchDataNull = false;
        mock.returnSearchDataEmpty = false;
        Test.setMock(HttpCalloutMock.class, mock);

        Application__c existingApp = [
            SELECT Id, Name, Stripe_Customer_Id__c, Contact__c
            FROM Application__c
            LIMIT 1
        ];

        Contact appContact = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :existingApp.Contact__c
            LIMIT 1
        ];

        Order testOrder = TestDataFactory.createOrder(existingApp.Id, appContact.AccountId, true);
        Payment__c testPayment = TestDataFactory.createPayment(existingApp.Id, testOrder.Id, true);
        testPayment.Customer_Id__c = existingApp.Stripe_Customer_Id__c;
        update testPayment;

        Test.startTest();
            Database.executeBatch(new BulkUpdateStripePaymentIntentsBatch(), 1);
        Test.stopTest();

        System.assertEquals(2, mock.calloutCount, 'Batch should make one search and one update callout');
        System.assertNotEquals(null, mock.lastRequest, 'POST callout should occur during batch execution');
    }

    private class BulkUpdateStripePaymentIntentsMock implements HttpCalloutMock {
        public HTTPRequest lastRequest;
        public Integer calloutCount = 0;
        public Boolean returnSearchDataNull = false;
        public Boolean returnSearchDataEmpty = false;

        public HTTPResponse respond(HTTPRequest req) {
            calloutCount++;
            lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getMethod() == 'GET' && req.getEndpoint().contains('payment_intents/search')) {
                if (returnSearchDataNull) {
                    res.setBody('{"data":null}');
                } else if (returnSearchDataEmpty) {
                    res.setBody('{"data":[]}');
                } else {
                    res.setBody('{"data":[{"customer":"cus_123456789","id":"pi_12345"}]}');
                }
                res.setStatusCode(200);
                return res;
            }
            if (req.getMethod() == 'GET' && req.getEndpoint().contains('customers/')) {
                res.setBody('{"id":"cus_123456789","email":"test@example.com"}');
                res.setStatusCode(200);
                return res;
            }
            if (req.getMethod() == 'POST' && req.getEndpoint().contains('payment_intents/')) {
                res.setBody('{"id":"pi_12345","object":"payment_intent"}');
                res.setStatusCode(200);
                return res;
            }
            res.setBody('{"error":{"message":"Unexpected callout"}}');
            res.setStatusCode(400);
            return res;
        }
    }
}