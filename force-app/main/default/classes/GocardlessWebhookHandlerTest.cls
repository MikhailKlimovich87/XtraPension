@IsTest
private class GocardlessWebhookHandlerTest {

    private static final String TEST_SECRET = 'test_whsec_abcdef1234567890';

    @TestSetup
    static void setup() {
        insert new GoCardless_Integration__c(
            Name              = 'Test',
            Webhook_Secret__c = TEST_SECRET
        );
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------
    private static String signBody(String body) {
        Blob mac = Crypto.generateMac(
            'HmacSHA256',
            Blob.valueOf(body),
            Blob.valueOf(TEST_SECRET)
        );
        return EncodingUtil.convertToHex(mac).toLowerCase();
    }

    private static void primeRequest(String body, String signature) {
        RestRequest req = new RestRequest();
        req.httpMethod  = 'POST';
        req.requestBody = Blob.valueOf(body);
        req.addHeader('Content-Type', 'application/json');
        if (signature != null) {
            req.addHeader('webhook-signature', signature);
        }
        req.resourcePath = '/GoCardlessWebhookApi';

        RestResponse res = new RestResponse();
        RestContext.request  = req;
        RestContext.response = res;
    }

    // -----------------------------------------------------------------
    // Tests
    // -----------------------------------------------------------------
    @IsTest
    static void rejectsMissingSignature() {
        primeRequest('{"events":[]}', null);

        Test.startTest();
        GocardlessWebhookHandler.postRouter();
        Test.stopTest();

        System.assertEquals(498, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('Missing webhook-signature'),
            'Expected missing-signature error, got: ' + RestContext.response.responseBody.toString()
        );
    }

    @IsTest
    static void rejectsBadSignature() {
        primeRequest('{"events":[]}', 'deadbeef');

        Test.startTest();
        GocardlessWebhookHandler.postRouter();
        Test.stopTest();

        System.assertEquals(498, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('Invalid Webhook Signature'),
            'Expected invalid-signature error'
        );
    }

    @IsTest
    static void acceptsValidSignatureAndEnqueues() {
        String body      = '{"events":[{"id":"EV1","resource_type":"payments","action":"created"}]}';
        String signature = signBody(body);
        primeRequest(body, signature);

        Test.startTest();
        GocardlessWebhookHandler.postRouter();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(
            '{"status":"ok"}',
            RestContext.response.responseBody.toString()
        );
    }

    @IsTest
    static void updatesBasicPaymentStatusFromValidWebhook() {
        Account account = TestDataFactory.createAccount(true);
        Contact contact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Basic__c claim = BP_TestDataFactory.createBasic(contact.Id, true);
        Product2 product = new Product2(
            Name = 'Claim - Direct Debit',
            CurrencyIsoCode = 'EUR',
            IsActive = true
        );
        insert product;

        Basic_Payment__c payment = BP_TestDataFactory.createBP_Payment(claim.Id, false, product);
        payment.GoCardless_Payment_Id__c = 'GC-PAY-123';
        payment.Status__c = 'Schedule';
        insert payment;

        String body = '{"events":[{"id":"EV1","resource_type":"payments","action":"paid_out","created_at":"2026-10-07T12:00:00Z","links":{"payment":"GC-PAY-123"}}]}';
        String signature = signBody(body);
        primeRequest(body, signature);

        Test.startTest();
        GocardlessWebhookHandler.postRouter();
        Test.stopTest();

        Basic_Payment__c updatedPayment = [
            SELECT Status__c
            FROM Basic_Payment__c
            WHERE Id = :payment.Id
            LIMIT 1
        ];

        System.assertEquals('Paid', updatedPayment.Status__c);
        System.assertEquals(200, RestContext.response.statusCode);
    }

    @IsTest
    static void rejectsEmptyBody() {
        primeRequest('', 'abc');

        Test.startTest();
        GocardlessWebhookHandler.postRouter();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assert(
            RestContext.response.responseBody.toString().contains('Empty request body')
        );
    }

    @IsTest
    static void constantTimeEqualsHandlesNullsAndLengths() {
        System.assertEquals(false, GocardlessWebhookHandler.constantTimeEquals(null, 'a'));
        System.assertEquals(false, GocardlessWebhookHandler.constantTimeEquals('a', null));
        System.assertEquals(false, GocardlessWebhookHandler.constantTimeEquals('abc', 'abcd'));
        System.assertEquals(true,  GocardlessWebhookHandler.constantTimeEquals('abc', 'abc'));
        System.assertEquals(false, GocardlessWebhookHandler.constantTimeEquals('abc', 'abd'));
    }
}