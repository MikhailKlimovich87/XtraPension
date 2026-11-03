@IsTest
public class GocardlessPaymentBatchTest {

    private static final String MANDATE_ID   = 'MD-TEST';
    private static final String PAYMENT_ID   = 'PM-TEST';
    private static final String PRODUCT_NAME = 'Claim - Direct Debit';

    private static final String STATUS_SCHEDULE = 'Schedule';
    private static final String STATUS_PAID     = 'Paid';
    private static final String STATUS_FAILED   = 'Fail';

    private static final String MISSING_DATA_ERROR = 'Missing claim / mandate / amount.';

    private static final Decimal CHARGE_AMOUNT = 100.00;
    /** CHARGE_AMOUNT * 100 — GoCardless takes minor units. */
    private static final String EXPECTED_AMOUNT_SENT = '10000';
    private static final String EXPECTED_CURRENCY    = 'EUR';


    // ==================================================================
    // Test data
    // ==================================================================
    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);

        Contact contact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Basic__c chargeableClaim = BP_TestDataFactory.createBasic(contact.Id, false);
        chargeableClaim.Current_Address_Abroad__CountryCode__s = 'IE';
        chargeableClaim.GoCardless_Customer_Id__c     = 'CU-TEST';
        chargeableClaim.GoCardless_Bank_Account_Id__c = 'BA-TEST';
        chargeableClaim.GoCardless_Mandate_Id__c      = MANDATE_ID;
        insert chargeableClaim;

        // Same claimant, but the mandate was never set up — the batch must not
        // attempt a charge for this one.
        Basic__c claimWithoutMandate = BP_TestDataFactory.createBasic(contact.Id, false);
        claimWithoutMandate.Current_Address_Abroad__CountryCode__s = 'IE';
        insert claimWithoutMandate;

        insert new Product2(
            Name = PRODUCT_NAME,
            CurrencyIsoCode = EXPECTED_CURRENCY,
            IsActive = true
        );
    }


    // ==================================================================
    // Helpers
    // ==================================================================
    private static Basic__c chargeableClaim() {
        return [
            SELECT Id, CurrencyIsoCode, Name
            FROM Basic__c
            WHERE GoCardless_Mandate_Id__c = :MANDATE_ID
            LIMIT 1
        ];
    }

    private static Basic__c claimWithoutMandate() {
        return [
            SELECT Id
            FROM Basic__c
            WHERE GoCardless_Mandate_Id__c = null
            LIMIT 1
        ];
    }

    private static Product2 directDebitProduct() {
        return [
            SELECT Id
            FROM Product2
            WHERE Name = :PRODUCT_NAME
            LIMIT 1
        ];
    }

    /**
     * A scheduled direct-debit instalment, due today, built through the shared
     * factory so every other required field matches the rest of the suite.
     */
    private static Basic_Payment__c duePayment(Id claimId, Decimal amount) {
        Basic_Payment__c payment = BP_TestDataFactory.createBP_Payment(
            claimId, false, directDebitProduct()
        );
        payment.Amount__c       = amount;
        payment.Status__c       = STATUS_SCHEDULE;
        payment.Payment_Date__c = Date.today();
        payment.CurrencyIsoCode = EXPECTED_CURRENCY;
        insert payment;
        return payment;
    }

    private static Basic_Payment__c reload(Id paymentId) {
        return [
            SELECT Status__c, Error_Message__c, Transaction_Id__c, Amount__c
            FROM Basic_Payment__c
            WHERE Id = :paymentId
        ];
    }


    // ==================================================================
    // HTTP mock
    // ==================================================================
    private class GocardlessMock implements HttpCalloutMock {

        Integer callCount = 0;

        /** Status reported by GET /mandates/{id} — drives chargeability. */
        String mandateStatus = 'active';

        /** Status returned by POST /payments. */
        Integer paymentStatusCode = 201;

        // Captured request payload, asserted by the test after stopTest.
        String capturedAmount;
        String capturedCurrency;
        String capturedMandateId;
        String capturedReference;

        public HttpResponse respond(HttpRequest request) {
            callCount++;

            String endpoint = request.getEndpoint();
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (endpoint.endsWith('/mandates/' + MANDATE_ID)) {
                response.setStatusCode(200);
                response.setBody(
                    '{"mandates":{"id":"' + MANDATE_ID + '","status":"' + mandateStatus + '"}}'
                );
            } else if (endpoint.endsWith('/payments')) {
                capturePayment(request);
                response.setStatusCode(paymentStatusCode);
                response.setBody(
                    paymentStatusCode >= 200 && paymentStatusCode < 300
                        ? '{"payments":{"id":"' + PAYMENT_ID + '"}}'
                        : '{"error":{"type":"invalid_api_usage","message":"Payment rejected"}}'
                );
            } else {
                response.setStatusCode(404);
                response.setBody('{"error":{"message":"Unexpected endpoint: ' + endpoint + '"}}');
            }

            return response;
        }

        private void capturePayment(HttpRequest request) {
            Map<String, Object> root    = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            Map<String, Object> payment = (Map<String, Object>) root.get('payments');
            Map<String, Object> links   = (Map<String, Object>) payment.get('links');

            capturedAmount     = String.valueOf(payment.get('amount'));
            capturedCurrency   = (String) payment.get('currency');
            capturedReference  = (String) payment.get('reference');
            capturedMandateId  = (String) links.get('mandate');
        }
    }

    // ==================================================================
    // start()
    // ==================================================================

    /**
     * Rows on another day, and rows that were already charged, must stay out of
     * scope — the batch charges once and only on the due date.
     */
    @IsTest
    static void startOnlySelectsTodaysScheduledPayments() {
        Basic__c claim = chargeableClaim();
        Basic_Payment__c dueToday = duePayment(claim.Id, CHARGE_AMOUNT);

        Basic_Payment__c dueTomorrow = duePayment(claim.Id, CHARGE_AMOUNT);
        dueTomorrow.Payment_Date__c = Date.today().addDays(1);
        update dueTomorrow;

        Basic_Payment__c alreadyCharged = duePayment(claim.Id, CHARGE_AMOUNT);
        alreadyCharged.Status__c = STATUS_PAID;
        update alreadyCharged;

        Test.startTest();
        Database.QueryLocator locator = new GocardlessPaymentBatch().start(null);
        Test.stopTest();

        Set<Id> inScope = new Set<Id>();
        Database.QueryLocatorIterator rows = locator.iterator();
        while (rows.hasNext()) {
            inScope.add(((Basic_Payment__c) rows.next()).Id);
        }

        System.assertEquals(1, inScope.size(),
            'only the scheduled payment due today belongs in scope');
        System.assert(inScope.contains(dueToday.Id));
    }


    // ==================================================================
    // execute() — success
    // ==================================================================

    @IsTest
    static void chargesDuePaymentAndMarksItPaid() {
        Basic__c claim = chargeableClaim();
        Basic_Payment__c payment = duePayment(claim.Id, CHARGE_AMOUNT);

        GocardlessMock mock = new GocardlessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new GocardlessPaymentBatch(), 1);
        Test.stopTest();

        Basic_Payment__c charged = reload(payment.Id);
        System.assertEquals(null, charged.Error_Message__c);

        System.assertEquals(2, mock.callCount,
            'expected the mandate chargeability check, then POST /payments');
        System.assertEquals(EXPECTED_AMOUNT_SENT, mock.capturedAmount,
            'the claim amount must be converted to minor units before charging');
        System.assertEquals(EXPECTED_CURRENCY, mock.capturedCurrency);
        System.assertEquals(MANDATE_ID, mock.capturedMandateId);
        System.assert(String.isNotBlank(mock.capturedReference),
            'the claim name is sent as the payment reference');
    }

    @IsTest
    static void marksPaymentFailedWhenApiRejectsTheCharge() {
        Basic__c claim = chargeableClaim();
        Basic_Payment__c payment = duePayment(claim.Id, CHARGE_AMOUNT);

        GocardlessMock mock = new GocardlessMock();
        mock.paymentStatusCode = 422;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new GocardlessPaymentBatch(), 1);
        Test.stopTest();

        Basic_Payment__c failed = reload(payment.Id);
        System.assertEquals(STATUS_FAILED, failed.Status__c, 'a rejected charge must be recorded, not left in Schedule');
        System.assert(String.isNotBlank(failed.Error_Message__c), 'the failure reason must be stored');
        System.assertEquals(null, failed.Transaction_Id__c);
        System.assertEquals(2, mock.callCount);
    }


    /**
     * No mock registered: every callout throws, the API handler swallows it and
     * reports the mandate as unchargeable. The row must still end up 'Failed'
     * with a reason — a due payment may never be left silently in 'Schedule'.
     */
    @IsTest
    static void marksPaymentFailedWhenApiCannotBeReached() {
        Basic__c claim = chargeableClaim();
        Basic_Payment__c payment = duePayment(claim.Id, CHARGE_AMOUNT);

        Test.startTest();
        Database.executeBatch(new GocardlessPaymentBatch(), 1);
        Test.stopTest();

        Basic_Payment__c failed = reload(payment.Id);
        System.assertEquals(STATUS_FAILED, failed.Status__c);
        System.assert(String.isNotBlank(failed.Error_Message__c));
    }

    @IsTest
    static void marksPaymentFailedWhenTheClaimHasNoMandate() {
        Basic_Payment__c payment = duePayment(claimWithoutMandate().Id, CHARGE_AMOUNT);

        GocardlessMock mock = new GocardlessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new GocardlessPaymentBatch(), 1);
        Test.stopTest();

        Basic_Payment__c failed = reload(payment.Id);
        System.assertEquals(STATUS_FAILED, failed.Status__c);
        System.assertEquals(MISSING_DATA_ERROR, failed.Error_Message__c);
        System.assertEquals(0, mock.callCount, 'nothing may be charged without a mandate');
    }

    // ==================================================================
    // finish()
    // ==================================================================

    @IsTest
    static void finishCompletesWithoutError() {
        Test.startTest();
        new GocardlessPaymentBatch().finish(null);
        Test.stopTest();

        System.assertEquals(5, Limits.getDmlStatements(),
            'finish() is a no-op and must not touch the database');
    }

    @IsTest
    static void marksPaymentSubmittedWithApiPaymentId() {
    Basic__c claim = chargeableClaim();
    Basic_Payment__c payment = duePayment(claim.Id, CHARGE_AMOUNT);

    Test.setMock(HttpCalloutMock.class, new GocardlessMock());

    Test.startTest();
    Database.executeBatch(new GocardlessPaymentBatch(), 1);
    Test.stopTest();

    Basic_Payment__c submitted = [
        SELECT Status__c, Error_Message__c, GoCardless_Payment_Id__c
        FROM Basic_Payment__c
        WHERE Id = :payment.Id
    ];

    System.assertEquals('Submitted', submitted.Status__c,
        'a successful API call means the payment is in flight, not paid');
    System.assertEquals(PAYMENT_ID, submitted.GoCardless_Payment_Id__c,
        'the GoCardless payment id must be persisted for reconciliation');
    System.assertEquals(null, submitted.Error_Message__c,
        'a clean run must clear any prior error');
    }

    @IsTest
    static void processesMultiplePaymentsInOneScope() {
    Basic__c claim = chargeableClaim();
    Basic__c noMandate = claimWithoutMandate();

    Basic_Payment__c ok     = duePayment(claim.Id, CHARGE_AMOUNT);
    Basic_Payment__c bad    = duePayment(noMandate.Id, CHARGE_AMOUNT);
    Basic_Payment__c amount = duePayment(claim.Id, 0);   // fails validation

    Test.setMock(HttpCalloutMock.class, new GocardlessMock());

    Test.startTest();
    Database.executeBatch(new GocardlessPaymentBatch(), 200);
    Test.stopTest();

    Map<Id, Basic_Payment__c> byId = new Map<Id, Basic_Payment__c>([
        SELECT Status__c, Error_Message__c, GoCardless_Payment_Id__c
        FROM Basic_Payment__c
        WHERE Id IN :new Set<Id>{ ok.Id, bad.Id, amount.Id }
    ]);

    System.assertEquals('Submitted', byId.get(ok.Id).Status__c);
    System.assertEquals(PAYMENT_ID,  byId.get(ok.Id).GoCardless_Payment_Id__c);

    System.assertEquals(STATUS_FAILED, byId.get(bad.Id).Status__c);
    System.assertEquals(MISSING_DATA_ERROR, byId.get(bad.Id).Error_Message__c);

    System.assertEquals(STATUS_FAILED, byId.get(amount.Id).Status__c);
    System.assertEquals(MISSING_DATA_ERROR, byId.get(amount.Id).Error_Message__c);
    }

    @IsTest
    static void doesNotLogErrorsWhenAllUpdatesSucceed() {
    Basic__c claim = chargeableClaim();
    duePayment(claim.Id, CHARGE_AMOUNT);

    Test.setMock(HttpCalloutMock.class, new GocardlessMock());

    Test.startTest();
    Database.executeBatch(new GocardlessPaymentBatch(), 1);
    Test.stopTest();
    }
}