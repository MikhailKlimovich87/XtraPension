/**
 * Tests for AA_TwilioController. TwilioSF managed triggers will fire when
 * we insert a TwilioSF__Message__c row, but they run synchronously without a
 * live Twilio callout in test context (managed triggers auto-guard for
 * Test.isRunningTest()), so we just assert the row exists + is queued.
 *
 * 2026-10-02 (audit F69/F152): sendSMS_inserts_outbound_row had failed in the
 * org since the credential check sat ahead of the old Test.isRunningTest()
 * bypass: a non-SeeAllData test cannot see the org's XtraPension_Data__c row,
 * so sendSMS threw "Twilio Account SID/Token not configured" (line 148) and
 * every `sf-deploy-src --tests` run failed. Its From assertion was also stale
 * ('XtraPension' vs the UK long code). The tests now seed the custom setting
 * and drive the real HTTP path through an HttpCalloutMock.
 */
@IsTest
private class AA_TwilioControllerTest {

    private static final String UK_LONG_CODE = '+447476900311';

    // Twilio 201 Created, echoing what we sent (the real API does the same).
    private class TwilioOkMock implements HttpCalloutMock {
        public HttpRequest lastReq;
        public HttpResponse respond(HttpRequest req) {
            lastReq = req;
            HttpResponse r = new HttpResponse();
            r.setStatusCode(201);
            r.setHeader('Content-Type', 'application/json');
            r.setBody('{"sid":"SMtest00000000000000000000000000ab","status":"queued",'
                    + '"to":"+441234567890","from":"' + UK_LONG_CODE + '",'
                    + '"body":"Hello from AA SMS panel"}');
            return r;
        }
    }

    // Twilio refusing the send (e.g. 21211 invalid To).
    private class TwilioRejectMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(400);
            r.setBody('{"code":21211,"message":"The To number is not valid."}');
            return r;
        }
    }

    // Hierarchy custom-setting data is invisible to non-SeeAllData tests, so
    // every send test must create its own org-default row.
    private static void seedTwilioCreds() {
        insert new XtraPension_Data__c(
            SetupOwnerId      = UserInfo.getOrganizationId(),
            Twilio_Account__c = 'ACtestaccount',
            Twilio_Token__c   = 'testtoken'
        );
    }

    // ─── helpers ────────────────────────────────────────────────────
    private static AA_Application__c makeApp(String phone) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Test',
            Last_Name__c  = 'SmsUser',
            Stage__c      = 'New',
            Phone__c      = phone
        );
        insert a;
        return a;
    }

    // ─── send: happy path ───────────────────────────────────────────
    @IsTest static void sendSMS_inserts_outbound_row() {
        seedTwilioCreds();
        AA_Application__c app = makeApp('+441234567890');
        TwilioOkMock mock = new TwilioOkMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Id msgId = AA_TwilioController.sendSMS(app.Id, 'Hello from AA SMS panel');
        Test.stopTest();

        // The request really went to Twilio's Messages API from the long code.
        System.assertNotEquals(null, mock.lastReq, 'sendSMS must call Twilio');
        System.assert(mock.lastReq.getEndpoint().endsWith('/Accounts/ACtestaccount/Messages.json'), mock.lastReq.getEndpoint());
        System.assert(mock.lastReq.getBody().contains('From=' + EncodingUtil.urlEncode(UK_LONG_CODE, 'UTF-8')), mock.lastReq.getBody());

        System.assertNotEquals(null, msgId, 'sendSMS should return an Id');
        TwilioSF__Message__c m = [
            SELECT Id, TwilioSF__Direction__c, TwilioSF__To_Number__c,
                   TwilioSF__From_Number__c, TwilioSF__Body__c,
                   TwilioSF__Status__c, TwilioSF__SF_Parent_Record_Id__c,
                   TwilioSF__Recipient_Name__c, TwilioSF__Message_SID__c
            FROM TwilioSF__Message__c
            WHERE Id = :msgId
        ];
        System.assertEquals('outbound-api', m.TwilioSF__Direction__c);
        System.assertEquals('+441234567890', m.TwilioSF__To_Number__c);
        System.assertEquals('Hello from AA SMS panel', m.TwilioSF__Body__c);
        System.assertEquals(String.valueOf(app.Id), m.TwilioSF__SF_Parent_Record_Id__c);
        System.assertEquals(UK_LONG_CODE, m.TwilioSF__From_Number__c,
            'AA sends from the UK long code (DEFAULT_FROM), not the legacy alphanumeric sender');
        System.assertEquals('queued', m.TwilioSF__Status__c, 'Status comes from the Twilio response');
        System.assertEquals('SMtest00000000000000000000000000ab', m.TwilioSF__Message_SID__c);
    }

    // ─── send: Twilio rejects → readable error, no mirror row ───────
    @IsTest static void sendSMS_twilio_rejection_throws_and_logs_nothing() {
        seedTwilioCreds();
        AA_Application__c app = makeApp('+441234567890');
        Test.setMock(HttpCalloutMock.class, new TwilioRejectMock());
        Boolean threw = false;
        Test.startTest();
        try {
            AA_TwilioController.sendSMS(app.Id, 'hello');
        } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'A Twilio 4xx must surface as an error to the panel');
        System.assertEquals(0, [SELECT COUNT() FROM TwilioSF__Message__c WHERE TwilioSF__SF_Parent_Record_Id__c = :String.valueOf(app.Id)],
            'No outbound row may be logged for a send Twilio refused');
    }

    // ─── send: credentials missing → clear error before any callout ─
    @IsTest static void sendSMS_without_credentials_throws() {
        AA_Application__c app = makeApp('+441234567890');
        Boolean threw = false;
        try {
            AA_TwilioController.sendSMS(app.Id, 'hello');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Missing XtraPension_Data__c credentials must throw');
    }

    // ─── send: Do Not Contact blocks the send (audit F54) ───────────
    @IsTest static void sendSMS_do_not_contact_blocks_before_callout() {
        seedTwilioCreds();
        AA_Application__c app = makeApp('+441234567890');
        app.Do_Not_Contact__c = true;
        update app;
        TwilioOkMock mock = new TwilioOkMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Boolean threw = false;
        Test.startTest();
        try {
            AA_TwilioController.sendSMS(app.Id, 'hello');
        } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'A Do Not Contact client must not be texted from the panel');
        System.assertEquals(null, mock.lastReq, 'Twilio must not be called for a Do Not Contact client');
    }

    // ─── send: a STOP reply blocks manual SMS (owner decision 2026-10-02) ─
    @IsTest static void sendSMS_sms_opt_out_blocks_before_callout() {
        seedTwilioCreds();
        AA_Application__c app = makeApp('+441234567890');
        app.SMS_Opt_Out__c = true;
        update app;
        TwilioOkMock mock = new TwilioOkMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Boolean threw = false;
        Test.startTest();
        try {
            AA_TwilioController.sendSMS(app.Id, 'hello');
        } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'A client who replied STOP must not be texted from the panel');
        System.assertEquals(null, mock.lastReq, 'Twilio must not be called after a STOP');
        System.assertEquals(0, [SELECT COUNT() FROM TwilioSF__Message__c WHERE TwilioSF__SF_Parent_Record_Id__c = :String.valueOf(app.Id)]);
    }

    // ─── send: blank body ───────────────────────────────────────────
    @IsTest static void sendSMS_blank_body_throws() {
        AA_Application__c app = makeApp('+441234567890');
        Boolean threw = false;
        try {
            AA_TwilioController.sendSMS(app.Id, '   ');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Blank body should throw');
    }

    // ─── send: no phone on file ─────────────────────────────────────
    @IsTest static void sendSMS_no_phone_throws() {
        AA_Application__c app = makeApp(null);
        Boolean threw = false;
        try {
            AA_TwilioController.sendSMS(app.Id, 'hello');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Missing phone should throw');
    }

    // ─── send: bogus record id ──────────────────────────────────────
    @IsTest static void sendSMS_bad_recordId_throws() {
        // Manufacture a plausible-looking AA_Application__c Id that doesn't
        // exist so the SOQL SingleRowException path is exercised.
        Id fakeId = AA_Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000000';
        Boolean threw = false;
        try {
            AA_TwilioController.sendSMS(fakeId, 'hi');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Bad recordId should throw');
    }

    // ─── read: mirrors sent row ─────────────────────────────────────
    @IsTest static void getThread_returns_row_by_parent_stamp() {
        AA_Application__c app = makeApp('+441234567890');
        // Insert a TwilioSF__Message__c directly, stamped with the parent id.
        TwilioSF__Message__c seed = new TwilioSF__Message__c(
            TwilioSF__From_Number__c        = 'XtraPension',
            TwilioSF__To_Number__c          = '+441234567890',
            TwilioSF__Body__c               = 'seeded outbound',
            TwilioSF__Direction__c          = 'outbound-api',
            TwilioSF__Status__c             = 'sent',
            TwilioSF__SF_Parent_Record_Id__c= String.valueOf(app.Id)
        );
        insert seed;

        // And an INBOUND row that only matches by phone (simulates historical data)
        TwilioSF__Message__c inbound = new TwilioSF__Message__c(
            TwilioSF__From_Number__c = '+441234567890',
            TwilioSF__To_Number__c   = 'XtraPension',
            TwilioSF__Body__c        = 'client reply',
            TwilioSF__Direction__c   = 'inbound',
            TwilioSF__Status__c      = 'received'
        );
        insert inbound;

        Test.startTest();
        AA_TwilioController.ThreadPayload out = AA_TwilioController.getThread(app.Id);
        Test.stopTest();

        System.assertEquals('+441234567890', out.appPhone);
        System.assert(out.messages.size() >= 2, 'Expected at least the 2 seeded rows');
        Boolean sawOut = false, sawIn = false;
        for (AA_TwilioController.MessageRow r : out.messages) {
            if (r.body == 'seeded outbound') { sawOut = true; System.assertEquals(true, r.isOutbound); }
            if (r.body == 'client reply')   { sawIn  = true; System.assertEquals(false, r.isOutbound); }
        }
        System.assert(sawOut, 'Outbound row should be visible via parent stamp');
        System.assert(sawIn,  'Inbound row should be visible via phone fallback');
    }

    // ─── read: no phone, no matches ─────────────────────────────────
    @IsTest static void getThread_empty_when_no_phone() {
        AA_Application__c app = makeApp(null);
        Test.startTest();
        AA_TwilioController.ThreadPayload out = AA_TwilioController.getThread(app.Id);
        Test.stopTest();
        System.assertEquals(null, out.appPhone);
        System.assertEquals(0, out.messages.size());
    }

    // ─── read: bad record id ────────────────────────────────────────
    @IsTest static void getThread_bad_recordId_throws() {
        Id fakeId = AA_Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000000';
        Boolean threw = false;
        try {
            AA_TwilioController.getThread(fakeId);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Bad recordId should throw');
    }
}