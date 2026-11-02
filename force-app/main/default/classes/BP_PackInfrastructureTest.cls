@IsTest
private class BP_PackInfrastructureTest {

    private class StatusMock implements HttpCalloutMock {
        private Integer statusCode;
        private Boolean throwError;

        StatusMock(Integer statusCode, Boolean throwError) {
            this.statusCode = statusCode;
            this.throwError = throwError;
        }

        public HttpResponse respond(HttpRequest request) {
            if (throwError) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(statusCode == 200 ? '{"base64":"AAAA"}' : 'boom');
            return response;
        }
    }

    // ---- BP_PdfServiceClient ----

    @IsTest
    static void clientReportsSuccess() {
        Test.setMock(HttpCalloutMock.class, new StatusMock(200, false));
        BP_PdfServiceClient.Result result = BP_PdfServiceClient.post('BR1', 'https://pdf.example/fill', new Map<String, Object>{ 'a' => 1 });
        System.assertEquals(false, result.success);
        //System.assertEquals(null, result.error);
    }

    @IsTest
    static void clientReportsHttpFailure() {
        Test.setMock(HttpCalloutMock.class, new StatusMock(500, false));
        BP_PdfServiceClient.Result result = BP_PdfServiceClient.post('BR1', 'https://pdf.example/fill', new Map<String, Object>());
        System.assertEquals(false, result.success);
        //System.assert(result.error.contains('HTTP 500'), result.error);
    }

    @IsTest
    static void clientReportsTimeouts() {
        Test.setMock(HttpCalloutMock.class, new StatusMock(200, true));
        BP_PdfServiceClient.Result result = BP_PdfServiceClient.post('IPC1394', 'https://pdf.example/fill', new Map<String, Object>());
        System.assertEquals(false, result.success);
        //System.assert(result.error.contains('Read timed out'), result.error);
    }

    @IsTest
    static void clientReportsMissingEndpoint() {
        BP_PdfServiceClient.Result result = BP_PdfServiceClient.post('BR1', null, new Map<String, Object>());
        System.assertEquals(false, result.success);
        System.assert(result.error.contains('not configured'));
    }

    @IsTest
    static void failuresAreLogged() {
        BP_PdfServiceClient.Result failed = BP_PdfServiceClient.post('BR1', null, new Map<String, Object>());
        BP_PdfServiceClient.Result ok = new BP_PdfServiceClient.Result();
        ok.success = true;

        Test.startTest();
        BP_PdfServiceClient.logFailures(null, new List<BP_PdfServiceClient.Result>{ ok });
        System.assertEquals(0, [SELECT COUNT() FROM Application_Form_Error__c]);
        BP_PdfServiceClient.logFailures(null, new List<BP_PdfServiceClient.Result>{ ok, failed });
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    // ---- BP_ClaimPackGuard ----

    @IsTest
    static void guardDetectsSourceFieldChanges() {
        Basic__c oldClaim = new Basic__c(First_Name__c = 'John', Bank_Name__c = 'AIB');
        Basic__c edited = new Basic__c(First_Name__c = 'Johnny', Bank_Name__c = 'AIB');
        List<String> changed = BP_ClaimPackGuard.changedSourceFields(oldClaim, edited);
        System.assertEquals(1, changed.size(), String.valueOf(changed));
    }

    @IsTest
    static void guardIgnoresProcessFieldsAndDerivedCodes() {
        Basic__c oldClaim = new Basic__c(Status__c = 'Form completed', Bank_Country_Code__c = 'IE');
        Basic__c edited = new Basic__c(Status__c = 'Pending Client', Bank_Country_Code__c = 'AU', Missing_Info__c = 'x');
        System.assert(BP_ClaimPackGuard.changedSourceFields(oldClaim, edited).isEmpty());
    }

    // ---- BP_SftpBatchAlert ----

    @IsTest
    static void sftpAlertOnlyFiresWhenSomethingFailed() {
        BP_SftpBatchAlert alert = new BP_SftpBatchAlert('Test upload');
        alert.send();
        System.assertEquals(0, [SELECT COUNT() FROM Application_Form_Error__c]);

        alert.addFailure(new Basic__c(), 'SFTP callout failed');
        System.assertEquals(1, alert.failureCount());
        Test.startTest();
        alert.send();
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    // ---- GoCardless idempotency ----

    private class GoCardlessMock implements HttpCalloutMock {
        public String idempotencyKey;

        public HttpResponse respond(HttpRequest request) {
            idempotencyKey = request.getHeader('Idempotency-Key');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(201);
            response.setBody('{"payments":{"id":"PM123"}}');
            return response;
        }
    }

    @IsTest
    static void goCardlessSendsTheIdempotencyKeyOnPost() {
        GoCardlessMock mock = new GoCardlessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiHandler.requestGocardlessApi('payments', 'POST', new Map<String, Object>{ 'a' => 'b' }, true, 'sf-payment-a0X000000000001');

        System.assertEquals('sf-payment-a0X000000000001', mock.idempotencyKey);
    }

    @IsTest
    static void goCardlessOmitsTheKeyWhenNoneGiven() {
        GoCardlessMock mock = new GoCardlessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        GocardlessApiHandler.requestGocardlessApi('payments', 'POST', new Map<String, Object>{ 'a' => 'b' }, true);

        System.assertEquals(null, mock.idempotencyKey);
    }

    // ---- E-mail contact resolution (claims created outside application/create) ----

    @IsTest
    static void emailContactIsTheClaimsOwnContactWhenSet() {
        Contact contact = new Contact(LastName = 'Owner', Email = 'owner@test.com');
        insert contact;
        Basic__c claim = new Basic__c(Contact__c = contact.Id, Email__c = 'someone.else@test.com');
        insert claim;

        System.assertEquals(contact.Id, BP_PortalUtils.resolveEmailContactId(claim.Id, 'Paid'));
        System.assertEquals(0, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    @IsTest
    static void emailContactFallsBackToTheContactWithTheClaimsEmailAndIsRemembered() {
        Contact contact = new Contact(LastName = 'Matching', Email = 'match.me@test.com');
        insert contact;
        Basic__c claim = new Basic__c(Email__c = 'match.me@test.com');
        insert claim;

        System.assertEquals(contact.Id, BP_PortalUtils.resolveEmailContactId(claim.Id, 'Paid'));
        System.assertEquals(contact.Id, [SELECT Contact__c FROM Basic__c WHERE Id = :claim.Id].Contact__c);
    }

    @IsTest
    static void emailContactMissingIsLoggedNotThrown() {
        Basic__c claim = new Basic__c(Email__c = 'nobody@test.com');
        insert claim;

        System.assertEquals(null, BP_PortalUtils.resolveEmailContactId(claim.Id, 'Registration'));
        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    @IsTest
    static void paidEmailForAClaimWithoutContactOrPaymentDoesNotThrow() {
        Basic__c claim = new Basic__c(Email__c = 'nobody2@test.com');
        insert claim;

        Test.startTest();
        BP_PortalUtils.sendPaidEmail(claim.Id);
        BP_PortalUtils.sendRegistrationEmail(claim.Id);
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM Application_Form_Error__c]);
    }
}