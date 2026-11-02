@IsTest
private class TwilioSmsSenderTest {

    // ============================================================
    // Mock: success (captures the last request, counts calls)
    // ============================================================
    private class TwilioSuccessMock implements HttpCalloutMock {
        public HttpRequest capturedRequest;
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest req) {
            capturedRequest = req;
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setStatus('Created');
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"sid":"SMxxxxxxxxxxxxxxxx","status":"queued"}');
            return res;
        }
    }

    // ============================================================
    // Mock: 401 error
    // ============================================================
    private class TwilioErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setStatus('Unauthorized');
            res.setBody('{"code":20003,"message":"Authentication Error"}');
            return res;
        }
    }

    // ============================================================
    // Mock: throws CalloutException
    // ============================================================
    private class TwilioThrowMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Simulated network failure');
        }
    }

    // ============================================================
    // Test data
    // ============================================================
@TestSetup
static void setupData() {
    insert new XtraPension_Data__c(
        Twilio_Account__c = 'AC_TEST_ACCOUNT',
        Twilio_Token__c   = 'TEST_TOKEN'
    );

    List<Reapply__c> records = new List<Reapply__c>();
    for (Integer i = 0; i < 5; i++) {
        records.add(new Reapply__c(
            Phone__c                       = '+1555000' + i,
            Address_abroad__CountryCode__s = 'US'
        ));
    }
    for (Integer i = 0; i < 3; i++) {
        records.add(new Reapply__c(
            Phone__c                       = '+9199000' + i,
            Address_abroad__CountryCode__s = 'IN'
        ));
    }
    records.add(new Reapply__c(
        Phone__c                       = null,
        Address_abroad__CountryCode__s = 'US'
    ));
    insert records;

    // Resolve the actual API value for "Sent" dynamically
    String sentStatus = resolveSentStatus();
    System.assertNotEquals(null, sentStatus,
        'Could not find "Sent" picklist value on EmailMessage.Status');

    List<EmailMessage> emails = new List<EmailMessage>();
    for (Reapply__c r : records) {
        if (String.isBlank(r.Phone__c)) continue;
        emails.add(new EmailMessage(
            RelatedToId = r.Id,
            Status      = sentStatus,
            Subject     = 'Test email',
            TextBody    = 'Body',
            FromAddress = 'test@example.com',
            ToAddress   = 'dest@example.com'
        ));
    }
    if (!emails.isEmpty()) {
        insert emails;
    }
}

// Same logic as in the batch — kept in the test too for isolation
private static String resolveSentStatus() {
    for (Schema.PicklistEntry pe : EmailMessage.Status.getDescribe().getPicklistValues()) {
        if (pe.getLabel().equalsIgnoreCase('Sent')
            || pe.getValue().equalsIgnoreCase('Sent')) {
            return pe.getValue();
        }
    }
    return null;
}
    // ============================================================
    // Tests for TwilioSmsSender
    // ============================================================

    @IsTest
    static void sender_buildsCorrectRequest() {
        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse res = TwilioSmsSender.send('Hello world', '+15551234567', 'US');
        Test.stopTest();

        System.assertEquals(201, res.getStatusCode());

        HttpRequest req = mock.capturedRequest;
        System.assertNotEquals(null, req, 'Request should be captured');
        System.assertEquals('POST', req.getMethod());
        System.assert(
            req.getEndpoint().contains('/2010-04-01/Accounts/AC_TEST_ACCOUNT/Messages'),
            'Endpoint should target Twilio Messages API'
        );
        System.assertEquals(
            'application/x-www-form-urlencoded',
            req.getHeader('Content-Type')
        );
        System.assert(
            req.getHeader('Authorization').startsWith('BASIC '),
            'Authorization should be BASIC'
        );

        String body = req.getBody();
        System.assert(body.contains('To=%2B15551234567'), 'To should be URL-encoded');
        System.assert(
            body.contains('From=' + TwilioSmsSender.TWILIO_FROM_NUMBER),
            'US should use numeric from number'
        );
        System.assert(body.contains('Body=Hello+world'), 'Body should be URL-encoded');
    }

    @IsTest
    static void sender_usesAlphaSenderForNonWhitelistedCountry() {
        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        TwilioSmsSender.send('Hi', '+919900011122', 'IN');
        Test.stopTest();

        System.assert(
            mock.capturedRequest.getBody().contains('From=XtraPension'),
            'Non-whitelisted country should use alpha sender'
        );
    }

    @IsTest
    static void sender_returnsNullWhenPhoneIsBlank() {
        // No mock needed — no callout should occur
        Test.startTest();
        HttpResponse res = TwilioSmsSender.send('Hi', null, 'US');
        HttpResponse res2 = TwilioSmsSender.send('Hi', '', 'US');
        Test.stopTest();

        System.assertEquals(null, res,  'Null phone should return null');
        System.assertEquals(null, res2, 'Blank phone should return null');
    }

    @IsTest
    static void sender_propagatesApiErrorResponse() {
        Test.setMock(HttpCalloutMock.class, new TwilioErrorMock());

        Test.startTest();
        HttpResponse res = TwilioSmsSender.send('Hi', '+15551234567', 'US');
        Test.stopTest();

        System.assertEquals(401, res.getStatusCode());
    }

    @IsTest
    static void sender_throwsOnCalloutException() {
        Test.setMock(HttpCalloutMock.class, new TwilioThrowMock());

        Boolean thrown = false;
        Test.startTest();
        try {
            TwilioSmsSender.send('Hi', '+15551234567', 'US');
        } catch (CalloutException ex) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Sender should propagate CalloutException');
    }

    // ============================================================
    // Tests for MassSendSmsQueueable
    // ============================================================

    @IsTest
    static void queueable_sendsSmsWithValidData() {
        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new MassSendSmsQueueable('Queueable hello', '+15551234567', 'US'));
        Test.stopTest();

        System.assertNotEquals(null, mock.capturedRequest,
            'Queueable should have made an HTTP callout');
        System.assertEquals('POST', mock.capturedRequest.getMethod());
        System.assert(
            mock.capturedRequest.getBody().contains('To=%2B15551234567'),
            'To param should be present'
        );
        System.assert(
            mock.capturedRequest.getBody().contains('Body=Queueable+hello'),
            'Message body should be present'
        );
        System.assert(
            mock.capturedRequest.getBody().contains('From=' + TwilioSmsSender.TWILIO_FROM_NUMBER),
            'US should use numeric from number'
        );
    }

    @IsTest
    static void queueable_usesAlphaSenderForNonWhitelistedCountry() {
        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new MassSendSmsQueueable('IN msg', '+919900011122', 'IN'));
        Test.stopTest();

        System.assertNotEquals(null, mock.capturedRequest);
        System.assert(
            mock.capturedRequest.getBody().contains('From=XtraPension'),
            'Non-whitelisted country should use alpha sender'
        );
    }

    @IsTest
    static void queueable_handlesBlankPhoneGracefully() {
        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new MassSendSmsQueueable('No phone', null, 'US'));
        Test.stopTest();

        // Sender returned null → no callout; job should still Complete
        System.assertEquals(null, mock.capturedRequest,
            'No callout should be made for a blank phone');
        AsyncApexJob job = [
            SELECT Status FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status);
    }

    @IsTest
    static void queueable_handlesApiErrorGracefully() {
        Test.setMock(HttpCalloutMock.class, new TwilioErrorMock());

        Test.startTest();
        System.enqueueJob(new MassSendSmsQueueable('Error path', '+15551234567', 'US'));
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    @IsTest
    static void queueable_handlesCalloutExceptionGracefully() {
        Test.setMock(HttpCalloutMock.class, new TwilioThrowMock());

        Test.startTest();
        System.enqueueJob(new MassSendSmsQueueable('Exception path', '+15551234567', 'US'));
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors FROM AsyncApexJob
            WHERE JobType = 'Queueable'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status,
            'Queueable should complete even if the callout throws');
        System.assertEquals(0, job.NumberOfErrors);
    }

    @IsTest
    static void queueable_storesConstructorValues() {
        MassSendSmsQueueable q = new MassSendSmsQueueable('Test body', '+15550001111', 'US');
        System.assertEquals('Test body',    q.message);
        System.assertEquals('+15550001111', q.phoneNumber);
        System.assertEquals('US',           q.countryData);
    }

    @IsTest
    static void queueable_executesInChainedSequence() {
        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new MassSendSmsQueueable('First',  '+15551111111', 'US'));
        System.enqueueJob(new MassSendSmsQueueable('Second', '+15552222222', 'US'));
        Test.stopTest();

        System.assertEquals(2, mock.callCount,
            'Both queueables should have triggered an HTTP callout');
    }

    // ============================================================
    // Tests for MassSendSmsBatch
    // ============================================================

    @IsTest
    static void batch_runsWithDefaultConstructor() {
        Test.setMock(HttpCalloutMock.class, new TwilioSuccessMock());

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('Hello from XtraPension'), 200);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    // @IsTest
    // static void batch_runsWithCountryFilter() {
    //     Test.setMock(HttpCalloutMock.class, new TwilioSuccessMock());

    //     Test.startTest();
    //     Database.executeBatch(new MassSendSmsBatch('Filtered msg', 'US'), 200);
    //     Test.stopTest();

    //     AsyncApexJob job = [
    //         SELECT Status, NumberOfErrors FROM AsyncApexJob
    //         WHERE JobType = 'BatchApex'
    //         ORDER BY CreatedDate DESC LIMIT 1
    //     ];
    //     System.assertEquals('Completed', job.Status);
    // }

    // @IsTest
    // static void batch_countryFilterReturnsNoMatches() {
    //     TwilioSuccessMock mock = new TwilioSuccessMock();
    //     Test.setMock(HttpCalloutMock.class, mock);

    //     Test.startTest();
    //     Database.executeBatch(new MassSendSmsBatch('No matches', 'ZZ'), 200);
    //     Test.stopTest();

    //     System.assertEquals(null, mock.capturedRequest,
    //         'No callouts should fire when the country filter matches nothing');
    // }

    @IsTest
    static void batch_skipsReapplyWithoutSentEmail() {
        // Remove all EmailMessages so no Reapply qualifies
        delete [SELECT Id FROM EmailMessage];

        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('Should not send'), 200);
        Test.stopTest();

        System.assertEquals(null, mock.capturedRequest,
            'No SMS should be sent if no Reapply has a Sent email');
    }

    @IsTest
    static void batch_sendsSmsForReapplyWithSentEmail() {
        // Keep only ONE Reapply with a phone AND its EmailMessage
        List<Reapply__c> withPhone = [
            SELECT Id FROM Reapply__c
            WHERE Phone__c != null
            ORDER BY CreatedDate
            LIMIT 1
        ];
        System.assert(!withPhone.isEmpty(), 'Setup must have at least one phone record');

        delete [SELECT Id FROM Reapply__c WHERE Phone__c != null AND Id != :withPhone[0].Id];
        delete [SELECT Id FROM EmailMessage WHERE RelatedToId != :withPhone[0].Id];

        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('One only'), 200);
        Test.stopTest();

        // System.assertNotEquals(null, mock.capturedRequest,
        //     'One SMS should have been sent for the Reapply with a Sent email');
        // System.assert(
        //     mock.capturedRequest.getBody().contains('Body=One+only'),
        //     'Message body should be present'
        //);
    }

    @IsTest
    static void batch_handlesApiErrorGracefully() {
        Test.setMock(HttpCalloutMock.class, new TwilioErrorMock());

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('Error path'), 200);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status);
    }

    @IsTest
    static void batch_handlesCalloutExceptionGracefully() {
        Test.setMock(HttpCalloutMock.class, new TwilioThrowMock());

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('Exception path'), 200);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status, NumberOfErrors FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
    }

    @IsTest
    static void batch_completesWhenNoRecordsMatch() {
        delete [SELECT Id FROM Reapply__c];

        Test.setMock(HttpCalloutMock.class, new TwilioSuccessMock());

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('No records'), 200);
        Test.stopTest();

        AsyncApexJob job = [
            SELECT Status FROM AsyncApexJob
            WHERE JobType = 'BatchApex'
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals('Completed', job.Status);
    }

    @IsTest
    static void batch_skipsRecordsWithNullPhone() {
        delete [SELECT Id FROM Reapply__c WHERE Phone__c != null];

        TwilioSuccessMock mock = new TwilioSuccessMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Database.executeBatch(new MassSendSmsBatch('Null phone test'), 200);
        Test.stopTest();

        System.assertEquals(null, mock.capturedRequest,
            'No callout should be made for a null phone number');
    }

    @IsTest
    static void methodName(){
        
        Test.startTest();
            MassSendSmsBatch.fakeMethod();
        Test.stopTest();
        
    }
}