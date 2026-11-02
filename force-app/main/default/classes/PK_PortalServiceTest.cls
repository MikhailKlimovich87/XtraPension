@isTest
private class PK_PortalServiceTest {
    private static RestRequest makeRequest(String uri, String body) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = 'POST';
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        return req;
    }

    private static Map<String, Object> executeService(String uri, String body) {
        RestContext.request = makeRequest(uri, body);
        RestContext.response = new RestResponse();

        Test.startTest();
        PK_PortalService.postRouter();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.responseBody, 'response body should not be null');
        String responseBody = RestContext.response.responseBody.toString();
        return (Map<String, Object>) JSON.deserializeUntyped(responseBody);
    }

    @TestSetup
    static void makeData() {
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Success'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
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
        Order testOrder = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        List<Payment__c> testPayments = TestDataFactory.createRelatedPaymentToApplication(
            newProducts,
            testApplication,
            testOrder.Id,
            true
        );
    }

    // simple mock that returns minimal card JSON; prevents real Stripe callout
    private class CardCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type','application/json');
            res.setBody('{"card":{"last4":"1234","brand":"Visa","exp_year":2025,"exp_month":12}}');
            res.setStatusCode(200);
            return res;
        }
    }

    @isTest
    static void testFindApplicationSuccess() {
        // register callout mock before exercising the service
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());

        List<Application__c> testApps = [
            SELECT
                Id,
                Name,
                Email__c,
                Contact__c
            FROM Application__c
        ];
        // give the application a known name so that we can look it up
        Application__c app = testApps[0];
        app.Email__c = 'test@example.com';
        update app;

        String body = JSON.serializePretty(new Map<String, Object>{
            'applicationNumber' => app.Name,
            'email'             => app.Email__c
        });

        Map<String, Object> result = executeService('/api/v3/find-application', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'), 'status should be success');
        Map<String, Object> foundApp = (Map<String, Object>) result.get('foundApplication');
        // CurrentApplicationDataWrapper uses the field applicationId for the Id
        System.assertEquals(app.Id, (String) foundApp.get('applicationId'), 'returned application Id should match');
    }

    @isTest
    static void testFindApplicationMissingInputs() {
        Map<String, Object> result = executeService('/api/v3/find-application', '{}');
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('error', result.get('status'));
        // the helper returns a specific message for null fields
        System.assert(result.get('message').toString().contains('null'), 'should indicate missing input');
    }

    @isTest
    static void testLoginSuccess() {
        List<Application__c> testApps = [
            SELECT
                Id,
                Name,
                Email__c,
                Contact__c
            FROM Application__c
        ];
        // give the application a known name so that we can look it up
        Application__c app = testApps[0];
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'SECRET';
        update app;

        String body = JSON.serializePretty(new Map<String, Object>{
            'applicationNumber' => app.Name,
            'password'          => 'SECRET',
            'ip'                => '127.0.0.1',
            'device'            => 'unit-test',
            'countryISO'        => 'GB',
            'browser'           => 'JUnit'
        });

        Map<String, Object> result = executeService('/api/v3/auth/login', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
        Map<String, Object> returnedApp = (Map<String, Object>) result.get('application');
        System.assertEquals(app.Id, (String) returnedApp.get('id'));
    }

    @isTest
    static void testLoginFailWrongPassword() {
        List<Application__c> testApps = [SELECT Id, Name FROM Application__c];
        Application__c app = testApps[0];
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'CORRECT_PASSWORD';
        update app;

        String body = JSON.serializePretty(new Map<String, Object>{
            'applicationNumber' => app.Name,
            'password'          => 'WRONG_PASSWORD',
            'ip'                => '127.0.0.1',
            'device'            => 'unit-test',
            'countryISO'        => 'GB',
            'browser'           => 'JUnit'
        });

        Map<String, Object> result = executeService('/api/v3/auth/login', body);
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Active Application not found', result.get('message'));
    }

    @isTest
    static void testForgotPasswordSuccess() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        
        List<Application__c> testApps = [SELECT Id, Name, Email__c FROM Application__c];
        Application__c app = testApps[0];
        app.PK_Portal_User_PW__c = 'SECRET';
        app.PK_Portal_User_Active__c = true;
        update app;

        String body = JSON.serializePretty(new Map<String, Object>{
            'applicationNumber' => app.Name,
            'email'             => app.Email__c
        });

        Map<String, Object> result = executeService('/api/v3/auth/forgot-password', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetDocuments() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'recordId' => app.Id,
            'docLimit' => '10'
        });

        Map<String, Object> result = executeService('/api/v3/documents/get-documents', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUploadDocument() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'recordId' => app.Id,
            'base64'   => 'VGVzdCBmbGll',
            'fileType' => 'pdf',
            'fileName' => 'test.pdf'
        });

        Map<String, Object> result = executeService('/api/v3/documents/upload-document', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testDeleteDocument() {
        ContentVersion cv = TestDataFactory.createTestContentVersion(true);
        
        String body = JSON.serializePretty(new Map<String, Object>{
            'documentId' => cv.Id
        });

        Map<String, Object> result = executeService('/api/v3/documents/delete-document', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testViewDocument() {
        ContentVersion cv = TestDataFactory.createTestContentVersion(true);

        String body = JSON.serializePretty(new Map<String, Object>{
            'documentId' => cv.Id
        });

        Map<String, Object> result = executeService('/api/v3/documents/view-document', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testCreateApplication() {
        // Stripe callouts occur during application creation; register mock
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());

        List<Product2> products = [SELECT Id FROM Product2 LIMIT 1];
        List<Account> accts = [SELECT Id, PersonContactId FROM Account];
        Account acct = accts[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'name'      => 'Jane Doe',
            'firstName' => 'Jane',
            'lastName'  => 'Doe',
            'email'     => 'jane.doe@example.com',
            'nino'      => 'AB1234567C',
            'phone'     => '01234567890',
            'address'   => new Map<String, Object>{
                'city'       => 'TestCity',
                'country'    => 'GB',
                'state'      => 'London',
                'postalCode' => '12345',
                'street'     => '1 Test St'
            }
        });

        Map<String, Object> result = executeService('/api/v3/create-application', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testApplicationDetails() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'commentsLimit' => 5
        });

        Map<String, Object> result = executeService('/api/v3/application/details', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetApplicationOverview() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/overview', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testCreateNotes() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id'      => app.Id,
            'subject' => 'Test Subject',
            'message' => 'Test message content'
        });

        Map<String, Object> result = executeService('/api/v3/application/create-notes', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    // @isTest
    // static void testGetFaq() {
    //     TestDataFactory.createFrequentlyAskedQuestions(5, true);
    //     Map<String, Object> result = executeService('/api/v3/application/faq', null);
    //     System.assertEquals(200, RestContext.response.statusCode);
    //     System.assertEquals('success', result.get('status'));
    // }

    @isTest
    static void testGetLatestComments() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        // create an email message linked to the application so the helper returns it
        EmailMessage comment = new EmailMessage(
            Subject      = 'Unit test comment',
            HtmlBody     = '<p>Latest comment body</p>',
            FromAddress  = 'test@sender.com',
            ToAddress    = 'client@recipient.com',
            RelatedToId  = app.Id,
            Pension_Keeper__c = true
        );
        insert comment;

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'commentsLimit' => 5
        });

        Map<String, Object> result = executeService('/api/v3/application/latest-comments', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
        List<Object> comments = (List<Object>) result.get('comments');
        System.assertEquals(1, comments.size(), 'should return the comment we inserted');
        Map<String, Object> returned = (Map<String, Object>) comments[0];
        System.assertEquals('Unit test comment', returned.get('subject'));
    }

    @isTest
    static void testTickEntitlementOption() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/tick-last-entitlement-option', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testInitCheckYourEntitlement() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/init-check-your-entitlement', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testSaveTaxYearAllocation() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'taxYearAllocation' => new List<Map<String, Object>>{
                new Map<String, Object>{'label' => '2020 to 2021', 'isChecked' => true}
            }
        });

        Map<String, Object> result = executeService('/api/v3/application/save-tax-year-allocation', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testSaveRequestCheck() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'amountPaid' => 100.00,
            'whenPaid' => Date.today()
        });

        Map<String, Object> result = executeService('/api/v3/application/save-request-check', body);
        System.assertEquals(null, result.get('message'));
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    // @isTest
    // static void testGetRequestCheck() {
    //     List<Application__c> testApps = [SELECT Id FROM Application__c];
    //     Application__c app = testApps[0];

    //     String body = JSON.serializePretty(new Map<String, Object>{
    //         'id' => app.Id
    //     });

    //     Map<String, Object> result = executeService('/api/v3/application/get-request-check', body);
    //     System.assertEquals(200, RestContext.response.statusCode);
    //     System.assertEquals('success', result.get('status'));
    // }

    @isTest
    static void testEditExtraYears() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'extraYears' => 5
        });

        Map<String, Object> result = executeService('/api/v3/application/edit-extra-years', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetReceipt() {
        // create a payment record and a linked receipt/email so that the helper
        // can return a non‑empty HTML body
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Order ord = [SELECT Id FROM Order WHERE Application__c = :app.Id LIMIT 1];

        // use the factory to keep things consistent with other tests
        Payment__c pay = TestDataFactory.createPayment(app.Id, ord.Id, true);

        // insert a simple receipt record pointing back to the payment
        Receipt__c rec = new Receipt__c(
            Payment__c = pay.Id,
            Application__c = app.Id,
            Paid_Date__c = Date.today(),
            CurrencyIsoCode = pay.CurrencyIsoCode
        );
        insert rec;

        // add an EmailMessage under the receipt with the expected HtmlBody
        EmailMessage em = new EmailMessage(
            Status       = '3',
            RelatedToId  = rec.Id,
            Subject      = 'Unit Test Receipt',
            HtmlBody     = '<div>Receipt Content</div>'
        );
        insert em;

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => pay.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/get-receipt', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
        System.assertEquals('<div>Receipt Content</div>', result.get('receipt'));
    }

    @isTest
    static void testGetBillingInfo() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/billing-info', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetPkApplication() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/get-pk-application', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testInvalidEndpointReturnsError() {
        Map<String, Object> result = executeService('/api/v3/nonexistent', null);
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals('error', result.get('status'));        
        System.assertEquals('Invalid endpoint', result.get('message'));
    }

    @isTest
    static void testCreatePkPayment() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'applicationId' => app.Id,
            'amount' => 100.00,
            'paymentMethod' => 'pm_123456789'
        });

        Map<String, Object> result = executeService('/api/v3/application/create-pk-payment', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUpdatePaymentMethodAfterRegistration() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];
        
        // Ensure application has all required fields populated
        app.First_Name__c = 'John';
        app.Second_Name__c = 'Doe';
        app.Related_Contact_Phone__c = '+1234567890';
        app.Email__c = 'john.doe@example.com';
        update app;

        String body = JSON.serializePretty(new Map<String, Object>{
            'applicationId' => app.Id,
            'id' => app.Id,
            'paymentMethod' => 'pm_987654321',
            'email' => 'john.doe@example.com',
            'phone' => '+1234567890',
            'firstName' => 'John',
            'lastName' => 'Doe'
        });

        Map<String, Object> result = executeService('/api/v3/application/update-payment-method-after-registration', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testUpdatePaymentMethodBillingPage() {
        Test.setMock(HttpCalloutMock.class, new CardCalloutMock());
        
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'paymentMethod' => 'pm_555666777'
        });

        Map<String, Object> result = executeService('/api/v3/application/update-payment-method-billing-page', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testApplicationDetailsUpdate() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        // wrapper expects an 'id' plus nested 'application' object
        String body = JSON.serializePretty(new Map<String, Object>{
            'id' => app.Id,
            'application' => new Map<String, Object>{
                'firstName' => 'Jane',
                'lastName' => 'Smith',
                'title' => 'Ms'
            }
        });

        Map<String, Object> result = executeService('/api/v3/application/details-update', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetLatestComment() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        // Create an email message to retrieve
        EmailMessage comment = new EmailMessage(
            Subject      = 'Test Latest Comment',
            HtmlBody     = '<p>Latest comment body</p>',
            FromAddress  = 'test@sender.com',
            ToAddress    = 'client@recipient.com',
            RelatedToId  = app.Id,
            Pension_Keeper__c = true
        );
        insert comment;

        String body = JSON.serializePretty(new Map<String, Object>{
            'commentId' => comment.Id
        });

        Map<String, Object> result = executeService('/api/v3/application/get-latest-comment', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }

    // @isTest
    // static void testGetAttachment() {
    //     // create a simple Attachment record linked to an application
    //     List<Application__c> testApps = [SELECT Id FROM Application__c];
    //     Application__c app = testApps[0];

    //     Attachment att = new Attachment(
    //         ParentId = app.Id,
    //         Name = 'test.txt',
    //         Body = Blob.valueOf('test content'),
    //         ContentType = 'text/plain'
    //     );
    //     insert att;

    //     String body = JSON.serializePretty(new Map<String, Object>{
    //         'attachmentId' => att.Id
    //     });

    //     Map<String, Object> result = executeService('/api/v3/documents/get-attachment', body);
    //     System.assertEquals(200, RestContext.response.statusCode);
    //     System.assertEquals('success', result.get('status'));
    // }

    @isTest
    static void testSavePkApplication() {
        List<Application__c> testApps = [SELECT Id FROM Application__c];
        Application__c app = testApps[0];

        String body = JSON.serializePretty(new Map<String, Object>{
            'application' => new Map<String, Object>{
                'id' => app.Id,
                'firstName' => 'John',
                'lastName' => 'Doe',
                'phone' => '123-456-7890',
                'email' => 'john.doe@example.com'
            },
            'document' => new Map<String, Object>{
                'recordId' => app.Id,
                'base64' => 'VGVzdCBmbGll',
                'fileType' => 'pdf',
                'fileName' => 'pk-app.pdf'
            }
        });

        Map<String, Object> result = executeService('/api/v3/application/save-pk-application', body);
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('success', result.get('status'));
    }
}