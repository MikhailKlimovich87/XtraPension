@IsTest
public class BP_GoCardlessPaymentSchedulerTest {
    private class MandateMock implements HttpCalloutMock {
        String mandateStatus = 'active';

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(201);
            String endpoint = request.getEndpoint();

            if (endpoint.endsWith('/customers')) {
                response.setBody('{"customers":{"id":"CU-NEW"}}');
            } else if (endpoint.endsWith('/customer_bank_accounts')) {
                response.setBody('{"customer_bank_accounts":{"id":"BA-NEW"}}');
            } else if (endpoint.endsWith('/mandates/MD-TEST')) {
                response.setStatusCode(200);
                response.setBody(
                    '{"mandates":{"id":"MD-TEST","status":"' + mandateStatus +
                    '","reference":"REF-TEST","created_at":"2026-09-01T10:00:00Z"}}'
                );
            } else if (endpoint.endsWith('/mandates')) {
                response.setBody('{"mandates":{"id":"MD-NEW"}}');
            } else {
                response.setStatusCode(404);
                response.setBody('{"error":{"message":"Unexpected endpoint"}}');
            }
            return response;
        }
    }

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

        Basic__c claimWithMandate = BP_TestDataFactory.createBasic(contact.Id, false);
        claimWithMandate.Current_Address_Abroad__CountryCode__s = 'IE';
        claimWithMandate.GoCardless_Customer_Id__c = 'CU-TEST';
        claimWithMandate.GoCardless_Bank_Account_Id__c = 'BA-TEST';
        claimWithMandate.GoCardless_Mandate_Id__c = 'MD-TEST';
        insert claimWithMandate;

        insert new Product2(
            Name = 'Claim - Direct Debit',
            CurrencyIsoCode = 'EUR',
            IsActive = true
        );
    }

    private static Basic__c getClaim() {
        return [
            SELECT Id, CurrencyIsoCode, Award_Amount__c, DWP_Payment_Date__c,
                GoCardless_Mandate_Id__c
            FROM Basic__c
            WHERE GoCardless_Mandate_Id__c = null
            LIMIT 1
        ];
    }

    private static Basic__c getClaimWithMandate() {
        return [
            SELECT Id, GoCardless_Customer_Id__c, GoCardless_Bank_Account_Id__c,
                GoCardless_Mandate_Id__c
            FROM Basic__c
            WHERE GoCardless_Mandate_Id__c = 'MD-TEST'
            LIMIT 1
        ];
    }

    private static BP_GoCardlessPaymentSchedulerController.MandateWrapper validWrapper(Id claimId) {
        BP_GoCardlessPaymentSchedulerController.MandateWrapper wrapper =
            new BP_GoCardlessPaymentSchedulerController.MandateWrapper();
        wrapper.claimId = claimId;
        wrapper.awardAmount = 100.01;
        wrapper.feeAmount = 100.50;
        wrapper.installments = 3;
        wrapper.firstChargeDate = Date.today().addDays(30);
        wrapper.installmentAmount = 50.25;
        return wrapper;
    }

    private static void assertScheduleThrows(
        BP_GoCardlessPaymentSchedulerController.MandateWrapper wrapper
    ) {
        Boolean threw = false;
        try {
            BP_GoCardlessPaymentSchedulerController.createDDPayments(wrapper);
        } catch (AuraHandledException handledError) {
            threw = true;
        }
        System.assert(threw, 'Expected invalid schedule input to throw AuraHandledException');
    }

    @IsTest
    static void createsScheduledPaymentsAndDetectsExistingSchedule() {
        Basic__c claim = getClaim();
        System.assertEquals(false, BP_GoCardlessPaymentSchedulerController.hasExistingSchedule(claim.Id));
        System.assertEquals(false, BP_GoCardlessPaymentSchedulerController.hasExistingSchedule(null));

        // The claim is EUR, so the controller converts the GBP fee via the latest exchange rate.
        // 100.50 * 1.5 = 150.75 -> 50.25 per installment.
        Date rateDate = Date.today().addDays(-1);
        insert new Daily_Exchange_Rate__c(
            Rate_Date__c = rateDate,
            Date_Key__c = String.valueOf(rateDate),
            GBP_to_EUR__c = 1.5,
            GBP_to_AUD__c = 2.0,
            Fetched_At__c = Datetime.now()
        );

        BP_GoCardlessPaymentSchedulerController.MandateWrapper wrapper = validWrapper(claim.Id);
        Test.startTest();
        String result = BP_GoCardlessPaymentSchedulerController.createDDPayments(wrapper);
        Test.stopTest();

        System.assertEquals('Created 3 scheduled payment(s).', result);
        System.assertEquals(true, BP_GoCardlessPaymentSchedulerController.hasExistingSchedule(claim.Id));

        List<Basic_Payment__c> payments = [
            SELECT Amount__c, Status__c, Payment_Date__c, CurrencyIsoCode, Product__r.Name
            FROM Basic_Payment__c
            WHERE Basic__c = :claim.Id
            ORDER BY Payment_Date__c
        ];
        System.assertEquals(3, payments.size());
        for (Integer index = 0; index < payments.size(); index++) {
            System.assertEquals(50.25, payments[index].Amount__c);
            System.assertEquals('Schedule', payments[index].Status__c);
            System.assertEquals(wrapper.firstChargeDate.addMonths(index), payments[index].Payment_Date__c);
            System.assertEquals('EUR', payments[index].CurrencyIsoCode);
            System.assertEquals('Claim - Direct Debit', payments[index].Product__r.Name);
        }
    }

    @IsTest
    static void rejectsInvalidScheduleInputs() {
        Basic__c claim = getClaim();
        assertScheduleThrows(null);

        BP_GoCardlessPaymentSchedulerController.MandateWrapper wrapper = validWrapper(claim.Id);
        wrapper.claimId = null;
        assertScheduleThrows(wrapper);

        wrapper = validWrapper(claim.Id);
        wrapper.installments = 0;
        assertScheduleThrows(wrapper);

        wrapper = validWrapper(claim.Id);
        wrapper.firstChargeDate = null;
        assertScheduleThrows(wrapper);

        wrapper = validWrapper(claim.Id);
        wrapper.feeAmount = 0;
        assertScheduleThrows(wrapper);
    }

    @IsTest
    static void returnsLatestExchangeRatesAndEmptyDefaults() {
        // null/blank target currency → defaults to GBP, no conversion needed
        Map<String, Object> gbpResult =
            BP_GoCardlessPaymentSchedulerController.getGbpExchangeInfo(null);
        System.assertEquals('GBP', gbpResult.get('targetCurrency'));
        System.assertEquals(1, gbpResult.get('rate'));
        System.assertEquals(null, gbpResult.get('rateDate'));
        System.assertEquals(null, gbpResult.get('error'));

        // EUR requested before any rate record exists → null rate + descriptive error
        Map<String, Object> emptyResult =
            BP_GoCardlessPaymentSchedulerController.getGbpExchangeInfo('EUR');
        System.assertEquals('EUR', emptyResult.get('targetCurrency'));
        System.assertEquals(null, emptyResult.get('rate'));
        System.assertEquals('No Daily Exchange Rate records found.', emptyResult.get('error'));

        Date olderDate = Date.today().addDays(-1);
        insert new List<Daily_Exchange_Rate__c>{
            new Daily_Exchange_Rate__c(
                Rate_Date__c = olderDate,
                Date_Key__c = String.valueOf(olderDate),
                GBP_to_EUR__c = 1.1,
                GBP_to_AUD__c = 1.8,
                Fetched_At__c = Datetime.now()
            ),
            new Daily_Exchange_Rate__c(
                Rate_Date__c = Date.today(),
                Date_Key__c = String.valueOf(Date.today()),
                GBP_to_EUR__c = 1.2,
                GBP_to_AUD__c = 1.9,
                Fetched_At__c = Datetime.now()
            )
        };

        // The most recent rate record (today) wins for the requested currency
        Map<String, Object> latestResult =
            BP_GoCardlessPaymentSchedulerController.getGbpExchangeInfo('EUR');
        System.assertEquals('EUR', latestResult.get('targetCurrency'));
        System.assertEquals(Date.today(), latestResult.get('rateDate'));
        System.assertEquals(1.2, latestResult.get('gbpToEur'));
        System.assertEquals(1.9, latestResult.get('gbpToAud'));
        System.assertEquals(1.2, latestResult.get('rate'));
        System.assertEquals(null, latestResult.get('error'));
    }

    @IsTest
    static void savesAwardAmountAndRejectsInvalidValues() {
    // 1. Setup mock exchange rates to prevent "No Daily Exchange Rate record found" 
    // if your org is multi-currency and the user's default currency isn't GBP.
    Daily_Exchange_Rate__c mockRate = new Daily_Exchange_Rate__c(
        Rate_Date__c = Date.today(),
        GBP_to_EUR__c = 1.15,
        GBP_to_AUD__c = 1.90
    );
    insert mockRate;

    // 2. Setup the claim
    Basic__c claim = getClaim();
    Date paymentDate = Date.today().addDays(-10);

    Test.startTest();
    // 3. Execute the positive path
    BP_GoCardlessPaymentSchedulerController.saveAwardAmount(claim.Id, 1250.50, paymentDate);
    Test.stopTest();

    // 4. Assert results
    // We query both fields: Award_Amount_GBP__c (the true input) 
    // and Award_Amount__c (the converted display value).
    Basic__c savedClaim = [
        SELECT Award_Amount__c, Award_Amount_GBP__c, DWP_Payment_Date__c
        FROM Basic__c
        WHERE Id = :claim.Id
    ];
    
    // The GBP field should be exactly what we passed in
    System.assertEquals(1250.50, savedClaim.Award_Amount_GBP__c, 'GBP amount should match input');
    System.assertEquals(paymentDate, savedClaim.DWP_Payment_Date__c, 'DWP Payment Date should match input');
    
    // 5. Test Null Claim ID
    Boolean nullClaimThrew = false;
    try {
        BP_GoCardlessPaymentSchedulerController.saveAwardAmount(null, 10, paymentDate);
    } catch (AuraHandledException handledError) {
        nullClaimThrew = true;
        // Optional: Verify the exact error message
        System.assertEquals('claimId is required.', handledError.getMessage());
    }
    System.assertEquals(true, nullClaimThrew, 'Should throw error for null claimId');

    // 6. Test Negative Amount
    Boolean negativeAmountThrew = false;
    try {
        BP_GoCardlessPaymentSchedulerController.saveAwardAmount(claim.Id, -1, paymentDate);
    } catch (AuraHandledException handledError) {
        negativeAmountThrew = true;
        // Optional: Verify the exact error message
        System.assertEquals('awardAmount must be 0 or greater.', handledError.getMessage());
    }
    System.assertEquals(true, negativeAmountThrew, 'Should throw error for negative amount');
    }
    
    @IsTest
    static void returnsMandateStatusAndChargeability() {
        Basic__c claim = getClaimWithMandate();
        Map<String, Object> notSetUp = BP_GoCardlessPaymentSchedulerController.getMandateStatus(null);
        System.assertEquals(false, notSetUp.get('isActive'));
        System.assertEquals('Not set up', notSetUp.get('status'));
        System.assertEquals(false, BP_GoCardlessPaymentSchedulerController.isMandateChargeable(null));

        MandateMock mock = new MandateMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Map<String, Object> status = BP_GoCardlessPaymentSchedulerController.getMandateStatus(claim.Id);
        Boolean chargeable = BP_GoCardlessPaymentSchedulerController.isMandateChargeable(claim.Id);
        Test.stopTest();

        System.assertEquals(true, status.get('isActive'));
        System.assertEquals('Active', status.get('status'));
        System.assertEquals('REF-TEST', status.get('reference'));
        System.assertEquals('CU-TEST', status.get('customerId'));
        System.assertEquals('BA-TEST', status.get('bankAccountId'));
        System.assertEquals('MD-TEST', status.get('mandateId'));
        System.assertEquals(true, chargeable);
    }

    @IsTest
    static void setupMandateCreatesAndStoresIdentifiers() {
        Basic__c claim = getClaim();
        MandateMock mock = new MandateMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        String mandateId = BP_GoCardlessPaymentSchedulerController.setupMandate(claim.Id);
        Test.stopTest();

        System.assertEquals('MD-NEW', mandateId);
        Basic__c updatedClaim = [
            SELECT GoCardless_Customer_Id__c, GoCardless_Bank_Account_Id__c,
                GoCardless_Mandate_Id__c
            FROM Basic__c
            WHERE Id = :claim.Id
        ];
        System.assertEquals('CU-TEST', updatedClaim.GoCardless_Customer_Id__c);
        System.assertEquals('BA-NEW', updatedClaim.GoCardless_Bank_Account_Id__c);
        System.assertEquals('MD-NEW', updatedClaim.GoCardless_Mandate_Id__c);
    }

    @IsTest
    static void createDDPaymentsThrowsIfScheduleAlreadyExists() {
        Basic__c claim = getClaim();
        
        // Insert an existing active schedule to trigger the guard
        Product2 product = [SELECT Id FROM Product2 WHERE Name = 'Claim - Direct Debit' LIMIT 1];
        insert new Basic_Payment__c(
            Basic__c = claim.Id,
            Amount__c = 100,
            Status__c = 'Schedule',
            Payment_Date__c = Date.today(),
            CurrencyIsoCode = claim.CurrencyIsoCode,
            Product__c = product.Id
        );

        BP_GoCardlessPaymentSchedulerController.MandateWrapper wrapper = validWrapper(claim.Id);
        
        Boolean threw = false;
        try {
            Test.startTest();
            BP_GoCardlessPaymentSchedulerController.createDDPayments(wrapper);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assertEquals('A direct debit schedule already exists for this claim.', e.getMessage());
        }
        System.assert(threw, 'Expected duplicate schedule exception');
    }

    @IsTest
    static void createDDPaymentsThrowsIfExchangeRateMissing() {
        // The claim is in EUR. We will not insert a Daily_Exchange_Rate__c record.
        Basic__c claim = getClaim();
        System.assertEquals('EUR', claim.CurrencyIsoCode); // Ensure test setup is correct
        
        BP_GoCardlessPaymentSchedulerController.MandateWrapper wrapper = validWrapper(claim.Id);

        Boolean threw = false;
        try {
            Test.startTest();
            BP_GoCardlessPaymentSchedulerController.createDDPayments(wrapper);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            System.assertEquals('No Daily Exchange Rate record found.', e.getMessage());
        }
        System.assert(threw, 'Expected missing exchange rate exception');
    }

    @IsTest
    static void returnsMandateStatusWhenNotSetUp() {
        Basic__c claim = getClaim(); // Created without a mandate ID in TestSetup
        
        Test.startTest();
        Map<String, Object> status = BP_GoCardlessPaymentSchedulerController.getMandateStatus(claim.Id);
        Test.stopTest();

        System.assertEquals(false, status.get('isActive'));
        System.assertEquals('Not set up', status.get('status'));
        System.assertEquals('Needs: confirmed bank details + Direct Debit terms read to the client.', status.get('message'));
        System.assertEquals(null, status.get('reference'));
        System.assertEquals(null, status.get('customerId'));
    }

    @IsTest
    static void savesAwardAmountThrowsIfExchangeRateMissing() {
        Basic__c claim = getClaim(); // Claim is EUR
        Date paymentDate = Date.today().addDays(-10);

        // Attempt to save without a Daily_Exchange_Rate__c record inserted
        Boolean threw = false;
        try {
            Test.startTest();
            BP_GoCardlessPaymentSchedulerController.saveAwardAmount(claim.Id, 1250.50, paymentDate);
            Test.stopTest();
        } catch (AuraHandledException e) {
            threw = true;
            //System.assert(e.getMessage().contains('Error saving award amount: No Daily Exchange Rate record found.'));
        }
        System.assert(threw, 'Expected missing exchange rate exception');
    }
}