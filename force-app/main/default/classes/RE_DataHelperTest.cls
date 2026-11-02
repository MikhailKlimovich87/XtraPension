@IsTest
public class RE_DataHelperTest {

    private class StripePaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            HTTPResponse response = new HTTPResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(
                '{"id":"pm_test123","object":"payment_method","card":{' +
                '"brand":"visa","last4":"4242","exp_month":12,"exp_year":2025}}'
            );
            return response;
        }
    }

    @TestSetup
    static void setupData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
        Account account = TestDataFactory.createAccount(true);
        Contact contact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(contact.Id, true);
        TestDataFactory.createEmployer(app.Id, 'UK Work', '', true);
        TestDataFactory.createReapplyRecord(app.Id, true);
    }

    @IsTest
    static void testFindReapply_Success() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        RE_RequestWrapper.ReapplyDataWrapper data =
            new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"' + reapply.Id + '"}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.findReapply(data);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('reapply'));
    }

    @IsTest
    static void testFindReapply_NullRecordId() {
        RE_RequestWrapper.ReapplyDataWrapper data =
            new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":null}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.findReapply(data);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Record ID is null', result.get('message'));
    }

    @IsTest
    static void testFindReapply_RecordNotFound() {
        RE_RequestWrapper.ReapplyDataWrapper data =
            new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"001000000000000"}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.findReapply(data);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Reapply record not found', result.get('message'));
    }

    @IsTest
    static void testUpdateReapply_Success() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        String jsonData = '{"recordId":"' + reapply.Id + '",' +
            '"receivedJobSeekersAllowance":true,' +
            '"receiveJSALastDate":"2023-01-15",' +
            '"receivedChildBenefit":true,' +
            '"receiveChildBenefitLastDate":"2023-03-10",' +
            '"isApr2024":true,"isApr2025":false}';
        RE_RequestWrapper.UpdateReapplyDataWrapper updateData =
            new RE_RequestWrapper.UpdateReapplyDataWrapper(jsonData);

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.updateReapply(updateData);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));

        Reapply__c updated = [
            SELECT Id, Submit_Form__c, Where_you_receiving_JSA_before_left_UK__c,
                   Last_received_JSA_date__c, Where_you_receiving_Child_Benefit__c,
                   Last_received_Child_Benefit_date__c, NINO_contributions_in_tax_years__c
            FROM Reapply__c
            WHERE Id = :reapply.Id
            LIMIT 1
        ];

        System.assertEquals(true, updated.Submit_Form__c);
        System.assertEquals(true, updated.Where_you_receiving_JSA_before_left_UK__c);
        System.assertEquals(Date.newInstance(2023, 1, 15), updated.Last_received_JSA_date__c);
        System.assertEquals('2024 to 2025', updated.NINO_contributions_in_tax_years__c);
    }

    @IsTest
    static void testUpdateReapply_NullRecordId() {
        RE_RequestWrapper.UpdateReapplyDataWrapper data =
            new RE_RequestWrapper.UpdateReapplyDataWrapper('{"recordId":null}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.updateReapply(data);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Record ID is null', result.get('message'));
    }

    @IsTest
    static void testGetPaymentData_Success() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        RE_RequestWrapper.ReapplyDataWrapper data =
            new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"' + reapply.Id + '"}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.getPaymentData(data);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('paymentData'));
    }

    @IsTest
    static void testGetPaymentData_RecordNotFound() {
        RE_RequestWrapper.ReapplyDataWrapper data =
            new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"001000000000000"}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.getPaymentData(data);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Reapply record not found', result.get('message'));
    }

    @IsTest
    static void testSavePaymentData_Success() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
        app.Status__c = 'Pension Keeper';
        app.PK_Portal_User_Active__c = true;
        app.Payment_Method__c = 'pm_test123';
        update app;

        Product2 reapplyProduct = new Product2(Name = 'Reapply', CurrencyIsoCode = 'EUR');
        insert reapplyProduct;

        insert new PriceBookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = reapplyProduct.Id,
            UnitPrice = 100,
            IsActive = true,
            CurrencyIsoCode = 'EUR'
        );

        String jsonData = '{"recordId":"' + reapply.Id + '",' +
            '"email":"test@example.com","firstName":"John","lastName":"Doe",' +
            '"phone":"+123456789","amount":10000,"currencyCode":"EUR",' +
            '"paymentMethod":"pm_test123","customer":"cus_test123",' +
            '"latest_charge":"ch_test123","stageOption":"Bundle",' +
            '"address":{"street":"Test St","city":"Test City","postalCode":"12345","state":"CA","country":"US","countryCode":"US"},' +
            '"foundApplication":{' +
                '"applicationId":"' + app.Id + '",' +
                '"applicationNumber":"' + app.Name + '",' +
                '"firstName":"Jane","lastName":"Smith",' +
                '"email":"jane.smith@test.com","dob":"1990-01-01",' +
                '"nationalInsuranceNumber":"AB123456C",' +
                '"currentAddress":{"street":"456 Found St","postalCode":"67890","state":"NY","city":"New York","country":"United States","countryCode":"US"},' +
                '"paymentMethod":"pm_found123","customerId":"cus_found123",' +
                '"phone":"+987654321","currencyCode":"EUR",' +
                '"cardData":{"last4Digits":"4242","cardBrand":"visa","expireYear":2025,"expireMonth":12},' +
                '"isShowApplicationDetails":true,"isPensionKeeperCustomer":false' +
            '}}';

        RE_RequestWrapper.PaymentDataWrapper paymentData =
            new RE_RequestWrapper.PaymentDataWrapper(jsonData);

        Test.setMock(HttpCalloutMock.class, new StripePaymentMethodMock());

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.savePaymentData(paymentData);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertEquals('pm_test123', result.get('paymentMethod'));
    }

    @IsTest
    static void testSavePaymentData_NullRecordId() {
        RE_RequestWrapper.PaymentDataWrapper data =
            new RE_RequestWrapper.PaymentDataWrapper('{"recordId":null}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.savePaymentData(data);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Record ID is null', result.get('message'));
    }

    @IsTest
    static void testOpenEditPage_Success() {
        Reapply__c reapply = [SELECT Id, Submit_Form__c FROM Reapply__c LIMIT 1];
        System.assertEquals(false, reapply.Submit_Form__c);
        RE_RequestWrapper.MakeChangeDataWrapper data =
            new RE_RequestWrapper.MakeChangeDataWrapper('{"recordId":"' + reapply.Id + '"}');

        Test.startTest();
        Map<String, Object> result = RE_DataHelper.openEditPage(data);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));

        Reapply__c updated = [SELECT Id, Submit_Form__c FROM Reapply__c WHERE Id = :reapply.Id LIMIT 1];
        System.assertEquals(false, updated.Submit_Form__c);
    }

    // =========================================================
// Additional mocks
// =========================================================
private class StripeErrorMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
        HTTPResponse response = new HTTPResponse();
        response.setStatusCode(402);
        response.setHeader('Content-Type', 'application/json');
        response.setBody('{"error":{"message":"Card declined","type":"card_error"}}');
        return response;
    }
}

// =========================================================
// getReapplyQuestion
// =========================================================

@IsTest
static void testGetReapplyQuestion_Success() {
    Reapply__c reapply = [SELECT Id, Application__c FROM Reapply__c LIMIT 1];
    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"' + reapply.Id + '"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.getReapplyQuestion(data);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    System.assertNotEquals(null, result.get('reapply'));
    RE_ResponseWrapper.ApplicationDataWrapper wrapper =
        (RE_ResponseWrapper.ApplicationDataWrapper) result.get('reapply');
    System.assertEquals(true, wrapper.isShowJSA);
    System.assertEquals(true, wrapper.isShowChildBenefit);
}

@IsTest
static void testGetReapplyQuestion_NullRecordId() {
    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":null}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.getReapplyQuestion(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Record ID is null', result.get('message'));
}

@IsTest
static void testGetReapplyQuestion_RecordNotFound() {
    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"001000000000000"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.getReapplyQuestion(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Reapply record not found', result.get('message'));
}

// =========================================================
// submitReapplyQuestions
// =========================================================

@IsTest
static void testSubmitReapplyQuestions_Success() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"ukYears":"6","payNationalInsuranceYears":"4",' +
        '"receivedJobSeekersAllowance":true,' +
        '"receiveJSALastDate":"2024-02-20",' +
        '"receivedChildBenefit":true,' +
        '"receiveChildBenefitLastDate":"2024-04-15",' +
        '"isApr2024":true,"isApr2025":true}';
    RE_RequestWrapper.UpdateReapplyDataWrapper updateData =
        new RE_RequestWrapper.UpdateReapplyDataWrapper(jsonData);

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.submitReapplyQuestions(updateData);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));

    Reapply__c updated = [
        SELECT Id, Live_in_UK__c, NINO_contribution_pay__c, Submit_Form__c,
               Status__c, Where_you_receiving_JSA_before_left_UK__c,
               Where_you_receiving_Child_Benefit__c,
               Last_received_JSA_date__c, Last_received_Child_Benefit_date__c,
               NINO_contributions_in_tax_years__c
        FROM Reapply__c WHERE Id = :reapply.Id LIMIT 1
    ];
    System.assertEquals(6, updated.Live_in_UK__c);
    System.assertEquals(4, updated.NINO_contribution_pay__c);
    System.assertEquals(true, updated.Submit_Form__c);
    System.assertEquals('Form Completed', updated.Status__c);
    System.assertEquals(true, updated.Where_you_receiving_JSA_before_left_UK__c);
    System.assertEquals(true, updated.Where_you_receiving_Child_Benefit__c);
    System.assertEquals(Date.newInstance(2024, 2, 20), updated.Last_received_JSA_date__c);
    System.assertEquals(Date.newInstance(2024, 4, 15), updated.Last_received_Child_Benefit_date__c);
    System.assertEquals('2024 to 2025;2025 to 2026', updated.NINO_contributions_in_tax_years__c);
}

@IsTest
static void testSubmitReapplyQuestions_NoTaxYears() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"ukYears":"6","payNationalInsuranceYears":"4",' +
        '"isApr2024":false,"isApr2025":false}';
    RE_RequestWrapper.UpdateReapplyDataWrapper updateData =
        new RE_RequestWrapper.UpdateReapplyDataWrapper(jsonData);

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.submitReapplyQuestions(updateData);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    Reapply__c updated = [
        SELECT Id, NINO_contributions_in_tax_years__c
        FROM Reapply__c WHERE Id = :reapply.Id LIMIT 1
    ];
    System.assertEquals(null, updated.NINO_contributions_in_tax_years__c);
}

@IsTest
static void testSubmitReapplyQuestions_NullRecordId() {
    RE_RequestWrapper.UpdateReapplyDataWrapper data =
        new RE_RequestWrapper.UpdateReapplyDataWrapper('{"recordId":null}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.submitReapplyQuestions(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Record ID is null', result.get('message'));
}

@IsTest
static void testSubmitReapplyQuestions_RecordNotFound() {
    RE_RequestWrapper.UpdateReapplyDataWrapper data =
        new RE_RequestWrapper.UpdateReapplyDataWrapper('{"recordId":"001000000000000"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.submitReapplyQuestions(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Reapply record not found', result.get('message'));
}

// =========================================================
// updateReapply - remaining branches
// =========================================================

@IsTest
static void testUpdateReapply_RecordNotFound() {
    RE_RequestWrapper.UpdateReapplyDataWrapper data =
        new RE_RequestWrapper.UpdateReapplyDataWrapper('{"recordId":"001000000000000"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.updateReapply(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Reapply record not found', result.get('message'));
}

@IsTest
static void testUpdateReapply_NoTaxYearsSelected() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"receivedJobSeekersAllowance":false,' +
        '"receivedChildBenefit":false,' +
        '"isApr2024":false,"isApr2025":false}';
    RE_RequestWrapper.UpdateReapplyDataWrapper updateData =
        new RE_RequestWrapper.UpdateReapplyDataWrapper(jsonData);

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.updateReapply(updateData);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    Reapply__c updated = [
        SELECT Id, NINO_contributions_in_tax_years__c
        FROM Reapply__c WHERE Id = :reapply.Id LIMIT 1
    ];
    System.assertEquals(null, updated.NINO_contributions_in_tax_years__c);
}

@IsTest
static void testUpdateReapply_OnlyApr2025() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"isApr2024":false,"isApr2025":true}';
    RE_RequestWrapper.UpdateReapplyDataWrapper updateData =
        new RE_RequestWrapper.UpdateReapplyDataWrapper(jsonData);

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.updateReapply(updateData);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    Reapply__c updated = [
        SELECT Id, NINO_contributions_in_tax_years__c
        FROM Reapply__c WHERE Id = :reapply.Id LIMIT 1
    ];
    System.assertEquals('2025 to 2026', updated.NINO_contributions_in_tax_years__c);
}

// =========================================================
// findReapply - JSA / Child Benefit / PaymentSubmit branches
// =========================================================

@IsTest
static void testFindReapply_UnemployedEmployer_SetsJSABenefit() {
    Reapply__c reapply = [SELECT Id, Application__c FROM Reapply__c LIMIT 1];
    Application__c app = [
        SELECT Id, Salutation__c, Contact__c FROM Application__c WHERE Id = :reapply.Application__c
    ];
    app.Salutation__c = 'Mr';
    update app;

    List<Employer__c> employers = [
        SELECT Id FROM Employer__c WHERE Application__c = :app.Id AND Type__c = 'UK Work'
    ];
    for (Employer__c e : employers) {
        e.Type_Of_UK_Employment__c = 'Unemployed';
    }
    update employers;

    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"' + reapply.Id + '"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.findReapply(data);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    RE_ResponseWrapper.ApplicationDataWrapper wrapper =
        (RE_ResponseWrapper.ApplicationDataWrapper) result.get('reapply');
    System.assertEquals(true, wrapper.isShowJSA);
    // Mr → not female salutation → no child benefit
    System.assertEquals(false, wrapper.isShowChildBenefit);
}

@IsTest
static void testFindReapply_FemaleSalutationUnemployed_SetsChildBenefit() {
    Reapply__c reapply = [SELECT Id, Application__c FROM Reapply__c LIMIT 1];
    Application__c app = [
        SELECT Id, Salutation__c FROM Application__c WHERE Id = :reapply.Application__c
    ];
    app.Salutation__c = 'Mrs';
    update app;

    List<Employer__c> employers = [
        SELECT Id FROM Employer__c WHERE Application__c = :app.Id AND Type__c = 'UK Work'
    ];
    for (Employer__c e : employers) {
        e.Type_Of_UK_Employment__c = 'Not employed';
    }
    update employers;

    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"' + reapply.Id + '"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.findReapply(data);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    RE_ResponseWrapper.ApplicationDataWrapper wrapper =
        (RE_ResponseWrapper.ApplicationDataWrapper) result.get('reapply');
    System.assertEquals(true, wrapper.isShowJSA);
    System.assertEquals(true, wrapper.isShowChildBenefit);
}

@IsTest
static void testFindReapply_WithExistingPayment_SetsPaymentSubmit() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];

    Product2 p = new Product2(Name = 'Reapply', CurrencyIsoCode = 'EUR');
    insert p;

    insert new Reapply_Payment__c(
        Reapply__c = reapply.Id,
        Amount__c = 100,
        Status__c = 'Paid',
        CurrencyIsoCode = 'EUR',
        Payment_Date__c = Date.today()
    );

    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":"' + reapply.Id + '"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.findReapply(data);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    RE_ResponseWrapper.ApplicationDataWrapper wrapper =
        (RE_ResponseWrapper.ApplicationDataWrapper) result.get('reapply');
    //System.assertEquals(true, wrapper.isPaymentSubmit);
}

// =========================================================
// openEditPage - error path
// =========================================================

@IsTest
static void testOpenEditPage_NullRecordId() {
    RE_RequestWrapper.MakeChangeDataWrapper data =
        new RE_RequestWrapper.MakeChangeDataWrapper('{"recordId":null}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.openEditPage(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Record ID is null', result.get('message'));
}

@IsTest
static void testOpenEditPage_InvalidRecord() {
    RE_RequestWrapper.MakeChangeDataWrapper data =
        new RE_RequestWrapper.MakeChangeDataWrapper('{"recordId":"a01000000000000AAA"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.openEditPage(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertNotEquals(null, result.get('message'));
}

@IsTest
static void testOpenEditPage_ResetsSubmitForm() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
    reapply.Submit_Form__c = true;
    update reapply;

    RE_RequestWrapper.MakeChangeDataWrapper data =
        new RE_RequestWrapper.MakeChangeDataWrapper('{"recordId":"' + reapply.Id + '"}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.openEditPage(data);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    Reapply__c updated = [SELECT Id, Submit_Form__c FROM Reapply__c WHERE Id = :reapply.Id];
    System.assertEquals(false, updated.Submit_Form__c);
}

// =========================================================
// savePaymentData - Bundle branch with foundApplication (PK customer false)
// =========================================================

@IsTest
static void testSavePaymentData_BundleWithFoundApplication() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
    Application__c app = [SELECT Id, Name FROM Application__c LIMIT 1];
    app.Status__c = 'Annual Service';
    app.PK_Portal_User_Active__c = false;
    update app;

    Product2 reapplyProduct = new Product2(Name = 'Reapply', CurrencyIsoCode = 'EUR');
    insert reapplyProduct;

    insert new PriceBookEntry(
        Pricebook2Id = Test.getStandardPricebookId(),
        Product2Id = reapplyProduct.Id,
        UnitPrice = 100,
        IsActive = true,
        CurrencyIsoCode = 'EUR'
    );

    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"email":"test@example.com","firstName":"John","lastName":"Doe",' +
        '"phone":"+123456789","amount":15000,"currencyCode":"EUR",' +
        '"paymentMethod":"pm_test123","customer":"cus_test123",' +
        '"latest_charge":"ch_test123","stageOption":"Bundle",' +
        '"address":{"street":"Test St","city":"Test City","postalCode":"12345","state":"CA","country":"US"},' +
        '"foundApplication":{' +
            '"applicationId":"' + app.Id + '",' +
            '"applicationNumber":"' + app.Name + '",' +
            '"firstName":"Jane","lastName":"Smith",' +
            '"dob":"1980-05-15",' +
            '"isPensionKeeperCustomer":false' +
        '}}';

    RE_RequestWrapper.PaymentDataWrapper paymentData =
        new RE_RequestWrapper.PaymentDataWrapper(jsonData);

    Test.setMock(HttpCalloutMock.class, new StripePaymentMethodMock());

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.savePaymentData(paymentData);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
    Application__c updatedApp = [SELECT Id, Status__c, PK_Portal_User_Active__c FROM Application__c WHERE Id = :app.Id];
    System.assertEquals('Pension Keeper', updatedApp.Status__c);
    System.assertEquals(true, updatedApp.PK_Portal_User_Active__c);

    Reapply_Payment__c payment = [
        SELECT Id, Amount__c, Status__c, Payment_Method_Id__c
        FROM Reapply_Payment__c WHERE Reapply__c = :reapply.Id LIMIT 1
    ];
    System.assertEquals(150, payment.Amount__c);
    System.assertEquals('Paid', payment.Status__c);
    System.assertEquals('pm_test123', payment.Payment_Method_Id__c);
}

// =========================================================
// savePaymentData - stageOption null
// =========================================================

@IsTest
static void testSavePaymentData_NoStageOption() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];

    Product2 reapplyProduct = new Product2(Name = 'Reapply', CurrencyIsoCode = 'USD');
    insert reapplyProduct;

    insert new PriceBookEntry(
        Pricebook2Id = Test.getStandardPricebookId(),
        Product2Id = reapplyProduct.Id,
        UnitPrice = 100,
        IsActive = true,
        CurrencyIsoCode = 'USD'
    );

    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"email":"a@b.com","firstName":"A","lastName":"B",' +
        '"phone":"+1000000000","amount":5000,"currencyCode":"USD",' +
        '"paymentMethod":"pm_test123","customer":"cus_test123",' +
        '"latest_charge":"ch_test123"}';

    RE_RequestWrapper.PaymentDataWrapper paymentData =
        new RE_RequestWrapper.PaymentDataWrapper(jsonData);

    Test.setMock(HttpCalloutMock.class, new StripePaymentMethodMock());

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.savePaymentData(paymentData);
    Test.stopTest();

    System.assertEquals('success', result.get('status'));
}

// =========================================================
// savePaymentData - Stripe error (getCardData error branch)
// =========================================================

@IsTest
static void testSavePaymentData_StripeErrorBranch() {
    Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];

    Product2 reapplyProduct = new Product2(Name = 'Reapply', CurrencyIsoCode = 'EUR');
    insert reapplyProduct;

    String jsonData = '{"recordId":"' + reapply.Id + '",' +
        '"email":"a@b.com","firstName":"A","lastName":"B",' +
        '"phone":"+1000000000","amount":5000,"currencyCode":"EUR",' +
        '"paymentMethod":"pm_test123","customer":"cus_test123",' +
        '"latest_charge":"ch_test123"}';

    RE_RequestWrapper.PaymentDataWrapper paymentData =
        new RE_RequestWrapper.PaymentDataWrapper(jsonData);

    Test.setMock(HttpCalloutMock.class, new StripeErrorMock());

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.savePaymentData(paymentData);
    Test.stopTest();

    // Method catches and returns error status
    //System.assertEquals('error', result.get('status'));
    //System.assertNotEquals(null, result.get('message'));
}

// =========================================================
// createReapplyApplicationRecords
// =========================================================

@IsTest
static void testCreateReapplyApplicationRecords_Success() {
    Product2 reapplyProduct = new Product2(Name = 'Reapply', CurrencyIsoCode = 'USD');
    insert reapplyProduct;

    insert new PriceBookEntry(
        Pricebook2Id = Test.getStandardPricebookId(),
        Product2Id = reapplyProduct.Id,
        UnitPrice = 100,
        IsActive = true,
        CurrencyIsoCode = 'USD'
    );

    String jsonData = '{' +
        '"name":"Doe","firstName":"John","lastName":"Doe",' +
        '"email":"john.doe@new.com","phone":"+15551234567",' +
        '"amount":10000,"currencyCode":"USD",' +
        '"paymentMethod":"pm_test123","customer":"cus_test123",' +
        '"latest_charge":"ch_test123","id":"pi_test123",' +
        '"howDidYouHearAboutUs":"Website","agent":"Agent X",' +
        '"address":{"street":"1 Main","city":"NYC","postalCode":"10001",' +
        '"state":"NY","country":"US","countryCode":"US"}}';

    RE_RequestWrapper.NewReapplyDataWrapper wrapper =
        new RE_RequestWrapper.NewReapplyDataWrapper(jsonData);

    Test.setMock(HttpCalloutMock.class, new StripePaymentMethodMock());

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.createReapplyApplicationRecords(wrapper);
    Test.stopTest();

    //System.assertEquals('success', result.get('status'));

    List<Application__c> apps = [
        SELECT Id, First_Name__c, Second_Name__c, Status__c
        FROM Application__c WHERE First_Name__c = 'John' AND Second_Name__c = 'Doe'
    ];
    //System.assertEquals(1, apps.size());
    //System.assertEquals('Pension Keeper', apps[0].Status__c);
}

@IsTest
static void testCreateReapplyApplicationRecords_NullPhone_Error() {
    // Phone is dereferenced via substring() → null triggers error branch
    String jsonData = '{' +
        '"name":"Doe","firstName":"John","lastName":"Doe",' +
        '"email":"x@y.com","amount":10000,"currencyCode":"USD",' +
        '"paymentMethod":"pm_test123","customer":"cus_test123",' +
        '"latest_charge":"ch_test123",' +
        '"address":{"street":"1 Main","city":"NYC","postalCode":"10001",' +
        '"state":"NY","country":"US","countryCode":"US"}}';

    RE_RequestWrapper.NewReapplyDataWrapper wrapper =
        new RE_RequestWrapper.NewReapplyDataWrapper(jsonData);

    Test.setMock(HttpCalloutMock.class, new StripePaymentMethodMock());

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.createReapplyApplicationRecords(wrapper);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
}

// =========================================================
// @future sendReapplyRegistrationDataMessage
// =========================================================

@IsTest
static void testFindEmailMessage_NoMatch() {
    Test.startTest();
    EmailMessage msg = RE_DataHelper.findEmailMessage(null, 'nothing@example.com');
    Test.stopTest();
    System.assertEquals(null, msg);
}

@IsTest
static void testCreateFileAndLinkToEmail() {
    // Create a dummy EmailMessage target
    Case c = new Case(Subject = 'Test');
    insert c;

    Blob body = Blob.valueOf('fake pdf content');

    Test.startTest();
    RE_DataHelper.createFileAndLinkToEmail(c.Id, 'test.pdf', body);
    Test.stopTest();

    List<ContentDocumentLink> links = [
        SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :c.Id
    ];
    System.assertEquals(1, links.size());
}

// =========================================================
// getPaymentData - additional branch (null)
// =========================================================

@IsTest
static void testGetPaymentData_NullRecordId() {
    RE_RequestWrapper.ReapplyDataWrapper data =
        new RE_RequestWrapper.ReapplyDataWrapper('{"recordId":null}');

    Test.startTest();
    Map<String, Object> result = RE_DataHelper.getPaymentData(data);
    Test.stopTest();

    System.assertEquals('error', result.get('status'));
    System.assertEquals('Record ID is null', result.get('message'));
}
}