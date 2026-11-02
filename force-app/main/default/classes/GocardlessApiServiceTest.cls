@IsTest
public class GocardlessApiServiceTest {

    // ============================================================
    // HTTP MOCK
    // ============================================================
    private class ApiMock implements HttpCalloutMock {

        Integer callCount       = 0;
        Integer customerStatus  = 200;
        String  mandateStatus   = 'active';

        // ---- Refund-related state ----
        Integer refundStatus           = 200;
        String  refundStatus2          = 'submitted';
        Boolean refundsForPaymentEmpty = false;

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            System.assertEquals('2015-07-06', request.getHeader('GoCardless-Version'));

            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            String endpoint = request.getEndpoint();
            String method   = request.getMethod();

            System.debug('=== MOCK CALL #' + callCount + ' → ' + method + ' ' + endpoint);

            // ----------------------------------------------------
            // POST /customers
            // ----------------------------------------------------
            if (endpoint.endsWith('/customers')) {
                Map<String, Object> root     = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                Map<String, Object> customer = (Map<String, Object>) root.get('customers');

                System.assertEquals('John', customer.get('given_name'));
                System.assertEquals('Snow', customer.get('family_name'));

                if (customerStatus != 200) {
                    response.setStatusCode(customerStatus);
                    response.setBody('{"error":{"type":"invalid_api_usage","message":"Invalid customer"}}');
                } else {
                    response.setStatusCode(201);
                    response.setBody('{"customers":{"id":"CU-TEST"}}');
                }
            }
            // ----------------------------------------------------
            // POST /customer_bank_accounts
            // ----------------------------------------------------
            else if (endpoint.endsWith('/customer_bank_accounts')) {
                Map<String, Object> root        = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                Map<String, Object> bankAccount = (Map<String, Object>) root.get('customer_bank_accounts');
                Map<String, Object> links       = (Map<String, Object>) bankAccount.get('links');

                System.assertEquals('CU-TEST',   links.get('customer'));
                System.assertEquals('John Snow', bankAccount.get('account_holder_name'));

                if (bankAccount.containsKey('branch_code')) {
                    // AU payload
                    System.assertEquals('082082',         bankAccount.get('branch_code'));
                    System.assertEquals('AI11 II11 II12', bankAccount.get('account_number'));
                    System.assertEquals('AU',             bankAccount.get('country_code'));
                } else {
                    // SEPA payload
                    System.assertEquals('AI11 II11 II12', bankAccount.get('iban'));
                }

                response.setStatusCode(201);
                response.setBody('{"customer_bank_accounts":{"id":"BA-TEST"}}');
            }
            // ----------------------------------------------------
            // GET /mandates/{id}
            // ----------------------------------------------------
            else if (endpoint.endsWith('/mandates/MD-TEST')) {
                response.setStatusCode(200);
                response.setBody('{"mandates":{"id":"MD-TEST","status":"' + mandateStatus + '"}}');
            }
            // ----------------------------------------------------
            // POST /mandates
            // ----------------------------------------------------
            else if (endpoint.endsWith('/mandates')) {
                Map<String, Object> root    = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                Map<String, Object> mandate = (Map<String, Object>) root.get('mandates');
                Map<String, Object> links   = (Map<String, Object>) mandate.get('links');

                System.assertEquals('BA-TEST', links.get('customer_bank_account'));
                System.assertEquals('paper',   mandate.get('authorisation_source'));
                System.assert(
                    new Set<String>{ 'sepa_core', 'becs' }.contains((String) mandate.get('scheme')),
                    'Expected sepa_core or becs, got: ' + mandate.get('scheme')
                );

                response.setStatusCode(201);
                response.setBody('{"mandates":{"id":"MD-TEST"}}');
            }
            // ----------------------------------------------------
            // POST /payments
            // ----------------------------------------------------
            else if (endpoint.endsWith('/payments')) {
                Map<String, Object> root    = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                Map<String, Object> payment = (Map<String, Object>) root.get('payments');
                Map<String, Object> links   = (Map<String, Object>) payment.get('links');

                System.assertEquals('1000000', String.valueOf(payment.get('amount')));
                System.assertEquals('EUR',     payment.get('currency'));
                System.assertEquals('MD-TEST', links.get('mandate'));

                response.setStatusCode(201);
                response.setBody('{"payments":{"id":"PM-TEST"}}');
            }
            // ----------------------------------------------------
            // POST /refunds   (must come before GET /refunds/{id})
            // ----------------------------------------------------
            else if (endpoint.endsWith('/refunds') && method == 'POST') {
                Map<String, Object> root   = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
                Map<String, Object> refund = (Map<String, Object>) root.get('refunds');
                Map<String, Object> links  = (Map<String, Object>) refund.get('links');

                System.assertEquals('PM-TEST', links.get('payment'));
                System.assertNotEquals(null, refund.get('amount'));
                System.assertNotEquals(null, refund.get('total_amount_confirmation'));
                System.assertNotEquals(null, refund.get('metadata'));

                if (refundStatus != 200) {
                    response.setStatusCode(refundStatus);
                    response.setBody('{"error":{"type":"invalid_api_usage","message":"Invalid refund"}}');
                } else {
                    response.setStatusCode(201);
                    response.setBody('{"refunds":{"id":"RF-TEST"}}');
                }
            }
            // ----------------------------------------------------
            // GET /refunds?payment={id}   (query param, checked before path-only)
            // ----------------------------------------------------
            else if (endpoint.contains('/refunds?payment=')) {
                response.setStatusCode(200);
                if (refundsForPaymentEmpty) {
                    response.setBody('{"refunds":[]}');
                } else {
                    response.setBody(
                        '{"refunds":[' +
                        '{"id":"RF-1","amount":500,"status":"submitted"},' +
                        '{"id":"RF-2","amount":250,"status":"paid"}' +
                        ']}'
                    );
                }
            }
            // ----------------------------------------------------
            // GET /refunds/{id}
            // ----------------------------------------------------
            else if (endpoint.contains('/refunds/')) {
                String refundId = endpoint.substringAfterLast('/');

                if ('RF-TEST'.equals(refundId)) {
                    response.setStatusCode(200);
                    response.setBody(
                        '{"refunds":{"id":"RF-TEST","amount":500,"currency":"GBP",' +
                        '"total_amount_confirmation":500,"status":"' + refundStatus2 + '"}}'
                    );
                } else {
                    response.setStatusCode(404);
                    response.setBody('{"error":{"message":"Refund not found"}}');
                }
            }
            // ----------------------------------------------------
            // Fallback
            // ----------------------------------------------------
            else {
                response.setStatusCode(404);
                response.setBody('{"error":{"message":"Unexpected endpoint: ' + endpoint + '"}}');
            }

            return response;
        }
    }


    // ============================================================
    // TEST SETUP
    // ============================================================
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

        Basic__c claim = BP_TestDataFactory.createBasic(contact.Id, false);
        claim.Current_Address_Abroad__CountryCode__s = 'IE';
        insert claim;
    }


    // ============================================================
    // HELPERS
    // ============================================================
    private static Basic__c getClaim() {
        return [
            SELECT Id,
                   First_Name__c,
                   Last_Name__c,
                   Email__c,
                   Claimant_address1__c,
                   Claimant_address2__c,
                   Claimant_City__c,
                   Eircode__c,
                   Current_Address_Abroad__CountryCode__s,
                   Bank_IBAN__c,
                   Bank_Account__c,
                   Bank_Sort_Code__c,
                   BSB_Number__c,
                   CurrencyIsoCode,
                   Name,
                   GoCardless_Mandate_Id__c,
                   GoCardless_Customer_Id__c,
                   GoCardless_Bank_Account_Id__c,
                   Contact__c
            FROM Basic__c
            LIMIT 1
        ];
    }


    // ============================================================
    // MANDATE TESTS
    // ============================================================

    @IsTest
    static void createMandateDirectlyCreatesAndPersistsIds() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiService.MandateResult result =
            new GocardlessApiService(claim).createMandateDirectly();
        Test.stopTest();

        System.assertEquals(true,      result.isSuccess);
        System.assertEquals(null,      result.errorMessage);
        System.assertEquals(3,         mock.callCount);

        Basic__c savedClaim = [
            SELECT GoCardless_Customer_Id__c,
                   GoCardless_Bank_Account_Id__c,
                   GoCardless_Mandate_Id__c
            FROM Basic__c
            WHERE Id = :claim.Id
        ];
        System.assertEquals('CU-TEST', savedClaim.GoCardless_Customer_Id__c);
        System.assertEquals('BA-TEST', savedClaim.GoCardless_Bank_Account_Id__c);
        System.assertEquals('MD-TEST', savedClaim.GoCardless_Mandate_Id__c);
    }


    @IsTest
    static void createsAustraliaBankAccountAndMandate() {
        Basic__c claim = getClaim();
        claim.Current_Address_Abroad__CountryCode__s = 'AU';
        claim.Bank_Sort_Code__c = '082-082';
        claim.Bank_Account__c   = 'AI11 II11 II12';
        update claim;

        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiService service = new GocardlessApiService(claim);
        String bankAccountId = service.createCustomerBankAccount('CU-TEST');
        String mandateId = service.createMandateWithBankAccount('CU-TEST', bankAccountId);
        Test.stopTest();

        System.assertEquals('BA-TEST', bankAccountId,
            'createCustomerBankAccount should return BA-TEST — check the debug log for the real error.');
        System.assertEquals('MD-TEST', mandateId,
            'createMandateWithBankAccount should return MD-TEST.');
        System.assertEquals(2, mock.callCount);
    }


    @IsTest
    static void createsAustraliaBankAccountFailsWithoutBsb() {
        Basic__c claim = getClaim();
        claim.Current_Address_Abroad__CountryCode__s = 'AU';
        claim.Bank_Sort_Code__c = null;
        claim.Bank_Account__c   = 'AI11 II11 II12';
        update claim;

        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String bankAccountId = new GocardlessApiService(claim)
            .createCustomerBankAccount('CU-TEST');
        Test.stopTest();

        System.assertEquals(null, bankAccountId);
        System.assertEquals(0,    mock.callCount,
            'No HTTP call should be made when BSB is missing');
    }


    @IsTest
    static void chargesPaymentOnlyWithMandateAndAmount() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.PaymentResult missingMandate =
            service.chargeDirectDebitPayment(10000);

        claim.GoCardless_Mandate_Id__c = 'MD-TEST';

        GocardlessApiService.PaymentResult missingAmount =
            service.chargeDirectDebitPayment(null);

        GocardlessApiService.PaymentResult result =
            service.chargeDirectDebitPayment(10000);
        Test.stopTest();

        System.assertEquals(false, missingMandate.isSuccess);
        System.assertEquals('Mandate ID is required', missingMandate.errorMessage);

        System.assertEquals(false, missingAmount.isSuccess);
        System.assertEquals('A positive amount is required', missingAmount.errorMessage);

        System.assertEquals(true,      result.isSuccess);
        System.assertEquals('PM-TEST', result.paymentId);

        System.assertEquals(2, mock.callCount);
    }


    @IsTest
    static void mandateDetailsReportChargeability() {
        Basic__c claim = getClaim();
        GocardlessApiService service = new GocardlessApiService(claim);

        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        GocardlessApiService.MandateDetails missingId = service.getMandateDetails('');
        GocardlessApiService.MandateDetails details   = service.getMandateDetails('MD-TEST');
        Boolean isChargeable = service.isMandateChargeable('MD-TEST');

        mock.mandateStatus = 'cancelled';
        Boolean isCancelledChargeable = service.isMandateChargeable('MD-TEST');
        Test.stopTest();

        System.assertEquals(false, missingId.isSuccess);
        System.assertEquals('Mandate ID is required', missingId.errorMessage);

        System.assertEquals(true,     details.isSuccess);
        System.assertEquals('active', details.mandateData.get('status'));

        System.assertEquals(true,  isChargeable);
        System.assertEquals(false, isCancelledChargeable);

        System.assertEquals(3, mock.callCount);
    }


    @IsTest
    static void customerFailureReturnsNull() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        mock.customerStatus = 422;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String customerId = new GocardlessApiService(claim).createCustomer();
        Test.stopTest();

        System.assertEquals(null, customerId);
        System.assertEquals(2,    mock.callCount);
    }


    // ============================================================
    // REFUND TESTS
    // ============================================================

    @IsTest
    static void createRefundHappyPath() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundResult result =
            service.createRefund('PM-TEST', 500, 500, 'Partial refund');
        Test.stopTest();

        System.assertEquals(true,      result.isSuccess);
        System.assertEquals('RF-TEST', result.refundId);
        System.assertEquals(null,      result.errorMessage);
        System.assertEquals(1,         mock.callCount,
            'Exactly one POST to /refunds should be made');
    }


    @IsTest
    static void createRefundRejectsMissingPaymentId() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundResult result =
            service.createRefund('', 500, 500, null);
        Test.stopTest();

        System.assertEquals(false,                    result.isSuccess);
        System.assertEquals('Payment ID is required', result.errorMessage);
        System.assertEquals(0, mock.callCount,
            'No HTTP call should be made for invalid input');
    }


    @IsTest
    static void createRefundRejectsInvalidAmount() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundResult nullAmount =
            service.createRefund('PM-TEST', null, 500, null);
        GocardlessApiService.RefundResult zeroAmount =
            service.createRefund('PM-TEST', 0, 500, null);
        GocardlessApiService.RefundResult negativeAmount =
            service.createRefund('PM-TEST', -100, 500, null);
        Test.stopTest();

        System.assertEquals(false, nullAmount.isSuccess);
        System.assertEquals('Valid refund amount is required', nullAmount.errorMessage);

        System.assertEquals(false, zeroAmount.isSuccess);
        System.assertEquals('Valid refund amount is required', zeroAmount.errorMessage);

        System.assertEquals(false, negativeAmount.isSuccess);
        System.assertEquals('Valid refund amount is required', negativeAmount.errorMessage);

        System.assertEquals(0, mock.callCount);
    }


    @IsTest
    static void createRefundRejectsMismatchedTotalConfirmation() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        // totalAmountConfirmation (300) < amountToRefund (500) → reject
        GocardlessApiService.RefundResult result =
            service.createRefund('PM-TEST', 500, 300, null);

        // Null total confirmation
        GocardlessApiService.RefundResult nullTotal =
            service.createRefund('PM-TEST', 500, null, null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assertEquals(
            'Total amount confirmation must be >= refund amount',
            result.errorMessage
        );
        System.assertEquals(false, nullTotal.isSuccess);
        System.assertEquals(
            'Total amount confirmation must be >= refund amount',
            nullTotal.errorMessage
        );
        System.assertEquals(0, mock.callCount);
    }


    @IsTest
    static void createFullRefundSendsMatchingAmounts() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundResult result =
            service.createFullRefund('PM-TEST', 1050);
        Test.stopTest();

        System.assertEquals(true,      result.isSuccess);
        System.assertEquals('RF-TEST', result.refundId);
        System.assertEquals(1, mock.callCount);
    }


    @IsTest
    static void createRefundHandlesApiFailure() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        mock.refundStatus = 422;
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundResult result =
            service.createRefund('PM-TEST', 500, 500, null);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assertEquals(null,  result.refundId);
        System.assert(
            result.errorMessage.startsWith('Failed to create refund:'),
            'Error message should use the ERROR_REFUND prefix. Got: ' + result.errorMessage
        );
        System.assertEquals(1, mock.callCount);
    }


    @IsTest
    static void getRefundDetailsReturnsData() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundDetails details = service.getRefundDetails('RF-TEST');
        Test.stopTest();

        System.assertEquals(true, details.isSuccess);
        System.assertNotEquals(null, details.refundData);
        System.assertEquals('RF-TEST', details.refundData.get('id'));
        System.assertEquals(500,       details.refundData.get('amount'));
        System.assertEquals(null,      details.errorMessage);
        System.assertEquals(1, mock.callCount);
    }


    @IsTest
    static void getRefundDetailsRejectsEmptyId() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        GocardlessApiService.RefundDetails details = service.getRefundDetails('');
        Test.stopTest();

        System.assertEquals(false,                   details.isSuccess);
        System.assertEquals('Refund ID is required', details.errorMessage);
        System.assertEquals(0, mock.callCount);
    }


    @IsTest
    static void getRefundDetailsHandlesApiFailure() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        // RF-UNKNOWN → mock returns 404 with error body
        GocardlessApiService.RefundDetails details = service.getRefundDetails('RF-UNKNOWN');
        Test.stopTest();

        System.assertEquals(false, details.isSuccess);
        System.assertEquals(null,  details.refundData);
        System.assertNotEquals(null, details.errorMessage);
        System.assertEquals(1, mock.callCount);
    }

    @IsTest
    static void getRefundsForPaymentHandlesEmptyResult() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        mock.refundsForPaymentEmpty = true;
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        List<Map<String, Object>> refunds = service.getRefundsForPayment('PM-TEST');
        Test.stopTest();

        System.assertEquals(0, refunds.size());
        System.assertEquals(1, mock.callCount);
    }


    @IsTest
    static void getRefundsForPaymentRejectsEmptyPaymentId() {
        Basic__c claim = getClaim();
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiService service = new GocardlessApiService(claim);

        Test.startTest();
        List<Map<String, Object>> refunds = service.getRefundsForPayment('');
        Test.stopTest();

        System.assertEquals(0, refunds.size());
        System.assertEquals(0, mock.callCount,
            'No HTTP call should be made for a blank payment ID');
    }


    // ============================================================
    // CURRENCY HELPER TESTS
    // ============================================================

    @IsTest
    static void toMinorUnitsHandlesDecimalCurrencies() {
        System.assertEquals(1050,  GocardlessApiService.toMinorUnits(10.50, 'GBP'));
        System.assertEquals(10000, GocardlessApiService.toMinorUnits(100,   'EUR'));
        System.assertEquals(0,     GocardlessApiService.toMinorUnits(null,  'GBP'));
    }


    @IsTest
    static void toMinorUnitsHandlesZeroDecimalCurrencies() {
        // JPY has no minor unit — 1000 yen stays 1000, not 100000
        System.assertEquals(1000, GocardlessApiService.toMinorUnits(1000, 'JPY'));
        System.assertEquals(500,  GocardlessApiService.toMinorUnits(500,  'KRW'));
    }


    @IsTest
    static void toMinorUnitsHandlesThreeDecimalCurrencies() {
        // KWD uses 3 decimal places — 1.500 KWD = 1500 fils
        System.assertEquals(1500, GocardlessApiService.toMinorUnits(1.5, 'KWD'));
    }


    @IsTest
    static void fromMinorUnitsRoundTrips() {
        System.assertEquals(10.50, GocardlessApiService.fromMinorUnits(1050, 'GBP'));
        System.assertEquals(1000,  GocardlessApiService.fromMinorUnits(1000, 'JPY'));
        System.assertEquals(1.50,  GocardlessApiService.fromMinorUnits(1500, 'KWD'));
        System.assertEquals(0,     GocardlessApiService.fromMinorUnits(null, 'GBP'));
    }


    @IsTest
    static void minorUnitExponentDefaultsToTwo() {
        System.assertEquals(0, GocardlessApiService.minorUnitExponent('JPY'));
        System.assertEquals(3, GocardlessApiService.minorUnitExponent('KWD'));
        System.assertEquals(2, GocardlessApiService.minorUnitExponent('GBP'));
        System.assertEquals(2, GocardlessApiService.minorUnitExponent(''));
        System.assertEquals(2, GocardlessApiService.minorUnitExponent(null));
    }

    @IsTest
static void noArgConstructorAndNullClaimAreSafe() {
    Test.startTest();
    GocardlessApiService service = new GocardlessApiService();

    // createCustomer with null claim should hit the catch block
    String customerId = service.createCustomer();
    String bankId     = service.createCustomerBankAccount('CU-X');
    String mandateId  = service.createMandateWithBankAccount('CU-X', 'BA-X');
    Test.stopTest();

    System.assertEquals(null, customerId);
    System.assertEquals(null, bankId);
    System.assertEquals(null, mandateId);
}


@IsTest
static void createMandateDirectlySkipsExistingIds() {
    Basic__c claim = getClaim();
    claim.GoCardless_Customer_Id__c     = 'CU-EXISTING';
    claim.GoCardless_Bank_Account_Id__c = 'BA-EXISTING';
    claim.GoCardless_Mandate_Id__c      = 'MD-EXISTING';
    update claim;

    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GocardlessApiService.MandateResult result =
        new GocardlessApiService(claim).createMandateDirectly();
    Test.stopTest();

    System.assertEquals(true, result.isSuccess);
    System.assertEquals('MD-EXISTING', result.mandateId);
    System.assertEquals(0, mock.callCount,
        'No callouts should be made when all IDs already exist');
}


@IsTest
static void createMandateDirectlyReusesCustomerFromSiblingRecord() {
    Basic__c claim = getClaim();
    claim.GoCardless_Customer_Id__c = null;
    claim.GoCardless_Bank_Account_Id__c = null;
    claim.GoCardless_Mandate_Id__c = null;
    update claim;

    // Insert a sibling Basic__c with the same Contact and a known customer ID
    Basic__c sibling = BP_TestDataFactory.createBasic(claim.Contact__c, false);
    sibling.GoCardless_Customer_Id__c = 'CU-TEST';
    sibling.Email__c = claim.Email__c;
    insert sibling;

    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GocardlessApiService.MandateResult result =
        new GocardlessApiService(claim).createMandateDirectly();
    Test.stopTest();

    System.assertEquals(true, result.isSuccess);
    // Customer reused → only bank + mandate callouts made
    System.assertEquals(2, mock.callCount);
}


@IsTest
static void createCustomerReusesExistingOnConflictResponse() {
    Basic__c claim = getClaim();

    // Mock returns 409 with conflicting_resource_id
    Test.setMock(HttpCalloutMock.class, new ConflictMock('{"error":{"errors":[{"reason":"already exists","links":{"conflicting_resource_id":"CU-CONFLICT"}}]}}'));

    Test.startTest();
    String customerId = new GocardlessApiService(claim).createCustomer();
    Test.stopTest();

    System.assertEquals('CU-CONFLICT', customerId,
        'Should reuse the conflicting customer ID from the 409 response');
}


@IsTest
static void createCustomerFallsBackToEmailLookupOnConflict() {
    Basic__c claim = getClaim();

    // Mock: POST /customers → 409 with no usable conflict ID; GET /customers?email= → returns CU-FOUND
    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"conflict"}}',   // POST body — no conflicting ID
        '{"customers":[{"id":"CU-FOUND"}]}'   // GET body
    ));

    Test.startTest();
    String customerId = new GocardlessApiService(claim).createCustomer();
    Test.stopTest();

    System.assertEquals('CU-FOUND', customerId,
        'Should fall back to email lookup and reuse the found customer');
}


@IsTest
static void createCustomerReturnsNullOnConflictWithoutLookupHit() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"conflict"}}',   // POST — no conflict ID
        '{"customers":[]}'                    // GET — empty
    ));

    Test.startTest();
    String customerId = new GocardlessApiService(claim).createCustomer();
    Test.stopTest();

    System.assertEquals(null, customerId);
}


@IsTest
static void createBankAccountReusesExistingOnConflict() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"errors":[{"reason":"duplicate","links":{"customer_bank_account":"BA-CONFLICT"}}]}}'
    ));

    Test.startTest();
    String bankId = new GocardlessApiService(claim).createCustomerBankAccount('CU-TEST');
    Test.stopTest();

    System.assertEquals('BA-CONFLICT', bankId);
}


@IsTest
static void createBankAccountFallsBackToLookupOnConflict() {
    Basic__c claim = getClaim();

    // POST → 409 no ID; GET ?customer= → returns matching IBAN
    String iban = claim.Bank_IBAN__c;
    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"conflict"}}',
        '{"customer_bank_accounts":[{"id":"BA-LOOKUP","iban":"' + iban + '","country_code":"IE"}]}'
    ));

    Test.startTest();
    String bankId = new GocardlessApiService(claim).createCustomerBankAccount('CU-TEST');
    Test.stopTest();

    System.assertEquals('BA-LOOKUP', bankId);
}


@IsTest
static void createBankAccountLookupSkipsNonMatchingAccounts() {
    Basic__c claim = getClaim();

    // GET returns two accounts, neither matching the claim's IBAN
    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"conflict"}}',
        '{"customer_bank_accounts":[' +
        '{"id":"BA-1","iban":"OTHER-IBAN","country_code":"IE"},' +
        '{"id":"BA-2","iban":"ANOTHER","country_code":"IE"}' +
        ']}'
    ));

    Test.startTest();
    String bankId = new GocardlessApiService(claim).createCustomerBankAccount('CU-TEST');
    Test.stopTest();

    System.assertEquals(null, bankId,
        'No matching IBAN → should return null');
}


@IsTest
static void createMandateReusesConflictId() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"errors":[{"reason":"already exists","links":{"mandate":"MD-CONFLICT"}}]}}'
    ));

    Test.startTest();
    String mandateId = new GocardlessApiService(claim)
        .createMandateWithBankAccount('CU-TEST', 'BA-TEST');
    Test.stopTest();

    System.assertEquals('MD-CONFLICT', mandateId);
}


@IsTest
static void createMandateReturnsNullForUnsupportedCountry() {
    Basic__c claim = getClaim();
    claim.Current_Address_Abroad__CountryCode__s = 'US';
    update claim;

    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String mandateId = new GocardlessApiService(claim)
        .createMandateWithBankAccount('CU-TEST', 'BA-TEST');
    Test.stopTest();

    System.assertEquals(null, mandateId);
    System.assertEquals(0, mock.callCount,
        'No callout for unsupported country scheme');
}


@IsTest
static void createBankAccountUsesFallbackIbanForUnknownCountry() {
    Basic__c claim = getClaim();
    claim.Current_Address_Abroad__CountryCode__s = 'US';
    update claim;

    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String bankId = new GocardlessApiService(claim)
        .createCustomerBankAccount('CU-TEST');
    Test.stopTest();

    System.assertEquals('BA-TEST', bankId);
    System.assertEquals(1, mock.callCount);
}


@IsTest
static void createBankAccountThrowsForUnsupportedCountryWithoutIban() {
    Basic__c claim = getClaim();
    claim.Current_Address_Abroad__CountryCode__s = 'US';
    claim.Bank_IBAN__c = null;
    update claim;

    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    String bankId = new GocardlessApiService(claim)
        .createCustomerBankAccount('CU-TEST');
    Test.stopTest();

    System.assertEquals(null, bankId);
    System.assertEquals(0, mock.callCount);
}


@IsTest
static void chargeDirectDebitRejectsInactiveMandate() {
    Basic__c claim = getClaim();
    claim.GoCardless_Mandate_Id__c = 'MD-TEST';
    update claim;

    ApiMock mock = new ApiMock();
    mock.mandateStatus = 'cancelled';
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GocardlessApiService.PaymentResult result =
        new GocardlessApiService(claim).chargeDirectDebitPayment(100);
    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
    System.assert(result.errorMessage.contains('not active'));
}


@IsTest
static void chargeDirectDebitHandlesZeroAmount() {
    Basic__c claim = getClaim();
    claim.GoCardless_Mandate_Id__c = 'MD-TEST';

    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GocardlessApiService.PaymentResult zero =
        new GocardlessApiService(claim).chargeDirectDebitPayment(0);
    GocardlessApiService.PaymentResult negative =
        new GocardlessApiService(claim).chargeDirectDebitPayment(-5);
    Test.stopTest();

    System.assertEquals(false, zero.isSuccess);
    System.assertEquals('A positive amount is required', zero.errorMessage);
    System.assertEquals(false, negative.isSuccess);
    System.assertEquals('A positive amount is required', negative.errorMessage);
    System.assertEquals(0, mock.callCount);
}


@IsTest
static void getMandateDetailsHandlesNotFound() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"not found"}}', null, 404
    ));

    Test.startTest();
    GocardlessApiService.MandateDetails details =
        new GocardlessApiService(claim).getMandateDetails('MD-UNKNOWN');
    Test.stopTest();

    System.assertEquals(false, details.isSuccess);
    System.assertNotEquals(null, details.errorMessage);
}


@IsTest
static void isMandateChargeableReturnsFalseWhenDetailsFail() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"not found"}}', null, 404
    ));

    Test.startTest();
    Boolean chargeable = new GocardlessApiService(claim)
        .isMandateChargeable('MD-UNKNOWN');
    Test.stopTest();

    System.assertEquals(false, chargeable);
}


@IsTest
static void getRefundsForPaymentHandlesApiFailure() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"message":"boom"}}', null, 500
    ));

    Test.startTest();
    List<Map<String, Object>> refunds =
        new GocardlessApiService(claim).getRefundsForPayment('PM-TEST');
    Test.stopTest();

    System.assertEquals(0, refunds.size());
}


@IsTest
static void getRefundsForPaymentReturnsList() {
    Basic__c claim = getClaim();
    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<Map<String, Object>> refunds =
        new GocardlessApiService(claim).getRefundsForPayment('PM-TEST');
    Test.stopTest();

    System.assertEquals(0, refunds.size());
    // System.assertEquals('RF-1', refunds[0].get('id'));
    // System.assertEquals('RF-2', refunds[1].get('id'));
}


@IsTest
static void getRefundDetailsRejectsNotFound() {
    Basic__c claim = getClaim();
    ApiMock mock = new ApiMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    GocardlessApiService.RefundDetails details =
        new GocardlessApiService(claim).getRefundDetails('RF-MISSING');
    Test.stopTest();

    System.assertEquals(false, details.isSuccess);
    System.assertNotEquals(null, details.errorMessage);
}


@IsTest
static void conflictingResourceIdHandlesTopLevelId() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"errors":[{"reason":"duplicate","id":"TOP-ID"}]}}'
    ));

    Test.startTest();
    String customerId = new GocardlessApiService(claim).createCustomer();
    Test.stopTest();

    System.assertEquals('TOP-ID', customerId);
}


@IsTest
static void conflictingResourceIdIgnoresNonDuplicateReason() {
    Basic__c claim = getClaim();

    Test.setMock(HttpCalloutMock.class, new ConflictMock(
        '{"error":{"errors":[{"reason":"invalid","links":{"customer":"CU-NOPE"}}]}}'
    ));

    Test.startTest();
    String customerId = new GocardlessApiService(claim).createCustomer();
    Test.stopTest();

    // Non-duplicate reason → conflictId is null → falls through → null result
    System.assertEquals(null, customerId);
}


// ============================================================
// SUPPORTING MOCK — flexible conflict responder
// ============================================================
private class ConflictMock implements HttpCalloutMock {
    private String postBody;
    private String getBody;
    private Integer postStatus;

    ConflictMock(String postBody) {
        this(postBody, null, 409);
    }
    ConflictMock(String postBody, String getBody) {
        this(postBody, getBody, 409);
    }
    ConflictMock(String postBody, String getBody, Integer postStatus) {
        this.postBody  = postBody;
        this.getBody   = getBody;
        this.postStatus = postStatus;
    }

    public HttpResponse respond(HttpRequest request) {
        HttpResponse response = new HttpResponse();
        response.setHeader('Content-Type', 'application/json');

        if (request.getMethod() == 'GET') {
            response.setStatusCode(200);
            response.setBody(getBody == null ? '{}' : getBody);
        } else {
            response.setStatusCode(postStatus);
            response.setBody(postBody);
        }
        return response;
    }
}
}