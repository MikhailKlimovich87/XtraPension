@isTest
public with sharing class PK_AnnualPaymentBatchTest {

    private static final String PRODUCT_NAME = 'Pension Keeper';

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    private static Boolean isMultiCurrency() {
        return Schema.getGlobalDescribe().containsKey('CurrencyType');
    }

    private static String defaultCurrency() {
        if (!isMultiCurrency()) return null;
        List<CurrencyType> corporate = [
            SELECT IsoCode
            FROM CurrencyType
            WHERE IsCorporate = true
            LIMIT 1
        ];
        return corporate.isEmpty() ? null : corporate[0].IsoCode;
    }

    // -------------------------------------------------------------------------
    // Test data
    // -------------------------------------------------------------------------
    @TestSetup
    static void makeData() {
        String currencyIso = defaultCurrency();

        // 1. Product
        Product2 product = new Product2(
            Name     = PRODUCT_NAME,
            IsActive = true
        );
        if (isMultiCurrency() && currencyIso != null) {
            product.CurrencyIsoCode = currencyIso;
        }
        insert product;

        // 1b. Verify name wasn't transformed by a trigger
        Product2 persistedProduct = [
            SELECT Id, Name
            FROM Product2
            WHERE Id = :product.Id
        ];
        System.assert(
            persistedProduct.Name == PRODUCT_NAME,
            'Product2 name was changed by a trigger. Inserted as "' + PRODUCT_NAME +
            '" but stored as "' + persistedProduct.Name + '".'
        );

        // 2. Standard price book — materialize it first
        Id pricebookId = Test.getStandardPricebookId();

        // CRITICAL: This DML makes the standard price book queryable in test context
        update new Pricebook2(Id = pricebookId, IsActive = true);

        Pricebook2 stdPb = [
            SELECT Id, Name, IsActive, IsStandard
            FROM Pricebook2
            WHERE Id = :pricebookId
        ];
        System.debug('=== Standard pricebook after update: ' + stdPb);
        System.assert(stdPb.IsStandard,
            'Standard price book has IsStandard = false after update. Org data issue.');

        // 3. PBE
        PriceBookEntry pbe = new PriceBookEntry(
            Pricebook2Id = pricebookId,
            Product2Id   = product.Id,
            UnitPrice    = 100000,
            IsActive     = true
        );
        if (isMultiCurrency() && currencyIso != null) {
            pbe.CurrencyIsoCode = currencyIso;
        }
        insert pbe;

        // 4. Sanity — PBE exists
        Integer pbeCount = [
            SELECT COUNT()
            FROM PriceBookEntry
            WHERE Product2Id = :product.Id
        ];
        System.assert(pbeCount > 0,
            'PBE not created. isMultiCurrency=' + isMultiCurrency() +
            ', currencyIso=' + currencyIso +
            ', pricebookId=' + pricebookId);

        // 4b. Sanity — batch filter matches
        Integer batchFilterCount = [
            SELECT COUNT()
            FROM PriceBookEntry
            WHERE Product2.Name = :PRODUCT_NAME
            AND Pricebook2.IsStandard = true
        ];
        System.debug('=== Batch filter match count = ' + batchFilterCount);
        System.assert(batchFilterCount > 0,
            'PBE exists but does NOT match batch filter. ' +
            'Product2.Name = "' + persistedProduct.Name + '"');

        // 5. Supporting config / data
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        System.assert(!contacts.isEmpty(), 'No Contact created');
        Id personContactId = contacts[0].Id;

        // 6. Application
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c                = 'Pension Keeper';
        testApplication.PK_Portal_User_Active__c = true;
        testApplication.PK_Auto_Renewal__c       = true;
        testApplication.PK_Registration_Date__c  = Date.today().addYears(-1);
        if (isMultiCurrency() && currencyIso != null) {
            testApplication.CurrencyIsoCode = currencyIso;
        }
        insert testApplication;

        // 7. Order + custom setting
        TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    // -------------------------------------------------------------------------
    // Happy path
    // -------------------------------------------------------------------------
    @isTest
    static void testBatchCreatesPayment() {
        Application__c app = [
            SELECT Id, CurrencyIsoCode, PK_Registration_Date__c
            FROM Application__c
            WHERE Status__c = 'Pension Keeper'
            LIMIT 1
        ];

        Integer pbeCount = [
            SELECT COUNT()
            FROM PriceBookEntry
            WHERE Product2.Name = :PRODUCT_NAME
            AND Pricebook2.IsStandard = true
        ];
        System.assert(pbeCount > 0,
            'Test precondition failed: PBE not visible. currency=' + app.CurrencyIsoCode +
            ', PRODUCT_NAME=' + PRODUCT_NAME);

        Date payDate   = Date.today().addDays(30);
        Integer amount = 500;

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, amount), 200);
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Id, Amount__c, Status__c, CurrencyIsoCode,
                   Application__c, Payment_Date__c,
                   Pension_Keeper_Annual_Payment__c, Customer_Id__c
            FROM Payment__c
            WHERE Application__c = :app.Id
        ];

        System.assertEquals(1, payments.size(),
            'Exactly one payment should be created. Found=' + payments.size() +
            ', regDate=' + app.PK_Registration_Date__c +
            ', currency=' + app.CurrencyIsoCode +
            ', pbeCount=' + pbeCount);

        Payment__c p = payments[0];
        System.assertEquals(amount, p.Amount__c, 'Amount mismatch');
        System.assertEquals('Schedule', p.Status__c, 'Status mismatch');
        System.assertEquals(app.CurrencyIsoCode, p.CurrencyIsoCode, 'Currency mismatch');
        System.assertEquals(payDate, p.Payment_Date__c, 'Payment date mismatch');
        System.assertEquals(true, p.Pension_Keeper_Annual_Payment__c, 'Annual flag mismatch');
    }

    // -------------------------------------------------------------------------
    // Idempotency
    // -------------------------------------------------------------------------
    @isTest
    static void testBatchIsIdempotent() {
        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        Integer paymentCount = [
            SELECT COUNT()
            FROM Payment__c
            WHERE Pension_Keeper_Annual_Payment__c = true
            AND Payment_Date__c = :payDate
        ];
        System.assertEquals(1, paymentCount,
            'Batch must not create duplicate payments for the same date');
    }

    // -------------------------------------------------------------------------
    // Empty scope
    // -------------------------------------------------------------------------
    @isTest
    static void testNoEligibleApplications() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        app.PK_Auto_Renewal__c = false;
        update app;

        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Payment__c],
            'No payments when no apps qualify');
    }

    // -------------------------------------------------------------------------
    // Missing PriceBookEntry
    // -------------------------------------------------------------------------
    @isTest
    static void testSkipsWhenNoPriceBookEntry() {
        delete [SELECT Id FROM PriceBookEntry WHERE Product2.Name = :PRODUCT_NAME];

        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Payment__c],
            'No payment without a matching PriceBookEntry');
    }

    // -------------------------------------------------------------------------
    // Null Payment_Method__c
    // -------------------------------------------------------------------------
    @isTest
    static void testNullPaymentMethodDoesNotThrow() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        app.Payment_Method__c = null;
        update app;

        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Payment_Method__c
            FROM Payment__c
            WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, payments.size(), 'One payment expected');
        System.assertEquals(null, payments[0].Payment_Method__c, 'Method should be null');
    }

    // -------------------------------------------------------------------------
    // Multi-value Payment_Method__c
    // -------------------------------------------------------------------------
    @isTest
    static void testUsesLastPaymentMethodSegment() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        app.Payment_Method__c = 'pm_old; pm_middle; pm_latest';
        update app;

        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Payment_Method__c
            FROM Payment__c
            WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, payments.size(), 'One payment expected');
        System.assertEquals('pm_latest', payments[0].Payment_Method__c, 'Last segment expected');
    }

    // -------------------------------------------------------------------------
    // Customer Id fallback
    // -------------------------------------------------------------------------
    @isTest
    static void testCustomerIdFallsBackToStripe() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        app.Current_Customer_Id__c = null;
        app.Stripe_Customer_Id__c  = 'cus_stripe123';
        update app;

        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Customer_Id__c
            FROM Payment__c
            WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, payments.size(), 'One payment expected');
        System.assertEquals('cus_stripe123', payments[0].Customer_Id__c, 'Stripe fallback expected');
    }

    // -------------------------------------------------------------------------
    // Most recent Order linkage
    // -------------------------------------------------------------------------
    @isTest
    static void testLinksToMostRecentOrder() {
        Application__c app = [
            SELECT Id, Contact__r.AccountId
            FROM Application__c
            LIMIT 1
        ];

        Order newerOrder = TestDataFactory.createOrder(app.Id, app.Contact__r.AccountId, true);

        Date payDate = Date.today().addDays(30);

        Test.startTest();
        Database.executeBatch(new PK_AnnualPaymentBatch(payDate, 500), 200);
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Order__c
            FROM Payment__c
            WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, payments.size(), 'One payment expected');
        System.assertEquals(newerOrder.Id, payments[0].Order__c, 'Most recent Order expected');
    }
}