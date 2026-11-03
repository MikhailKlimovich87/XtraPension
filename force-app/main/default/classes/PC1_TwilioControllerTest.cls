/**
 * Tests for PC1_TwilioController. TwilioSF managed triggers will fire when
 * we insert a TwilioSF__Message__c row, but they run synchronously without a
 * live Twilio callout in test context (managed triggers auto-guard for
 * Test.isRunningTest()), so we just assert the row exists + is queued.
 */
@IsTest
private class PC1_TwilioControllerTest {

    // ─── helpers ────────────────────────────────────────────────────
    private static PC1_Application__c makeApp(String phone) {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Test',
            Last_Name__c  = 'SmsUser',
            Stage__c      = 'New',
            Phone__c      = phone
        );
        insert a;
        return a;
    }

    private class TwilioMock implements HttpCalloutMock {
        Integer status;
        TwilioMock(Integer status) { this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(status == 201
                ? '{"sid":"SM123","status":"queued","to":"+441234567890","from":"' + PC1_TwilioController.DEFAULT_FROM
                  + '","body":"Hello from PC1 SMS panel"}'
                : '{"message":"The To number is not a valid phone number."}');
            return r;
        }
    }

    private static void seedTwilioCreds() {
        insert new XtraPension_Data__c(
            SetupOwnerId      = UserInfo.getOrganizationId(),
            Twilio_Account__c = 'ACtestaccount',
            Twilio_Token__c   = 'testtoken'
        );
    }

    // ─── send: happy path ───────────────────────────────────────────
    @IsTest static void sendSMS_inserts_outbound_row() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp('+441234567890');
        Test.setMock(HttpCalloutMock.class, new TwilioMock(201));
        Test.startTest();
        Id msgId = PC1_TwilioController.sendSMS(app.Id, 'Hello from PC1 SMS panel');
        Test.stopTest();

        System.assertNotEquals(null, msgId, 'sendSMS should return an Id');
        TwilioSF__Message__c m = [
            SELECT Id, TwilioSF__Direction__c, TwilioSF__To_Number__c,
                   TwilioSF__From_Number__c, TwilioSF__Body__c,
                   TwilioSF__Status__c, TwilioSF__SF_Parent_Record_Id__c,
                   TwilioSF__Recipient_Name__c
            FROM TwilioSF__Message__c
            WHERE Id = :msgId
        ];
        System.assertEquals('outbound-api', m.TwilioSF__Direction__c);
        System.assertEquals('+441234567890', m.TwilioSF__To_Number__c);
        System.assertEquals('Hello from PC1 SMS panel', m.TwilioSF__Body__c);
        System.assertEquals(String.valueOf(app.Id), m.TwilioSF__SF_Parent_Record_Id__c);
        System.assertEquals(PC1_TwilioController.DEFAULT_FROM, m.TwilioSF__From_Number__c);  // UK long code since the alphanumeric sender was dropped
        System.assert(String.isNotBlank(m.TwilioSF__Status__c), 'Status should be set');
    }

    // ─── send: sandbox gate ─────────────────────────────────────────
    @IsTest static void sendSMS_blocked_in_sandbox_for_unlisted_number() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp('+447700900111');
        PC1_SendGate.sandboxOverride = true;
        PC1_SendGate.resetCaches();
        Boolean threw = false;
        try { PC1_TwilioController.sendSMS(app.Id, 'hi'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a real client number must not be texted from the sandbox');
        System.assertEquals(0, [SELECT COUNT() FROM TwilioSF__Message__c]);
    }

    @IsTest static void sendSMS_twilio_rejection_surfaces() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp('+441234567890');
        Test.setMock(HttpCalloutMock.class, new TwilioMock(400));
        Boolean threw = false;
        try { PC1_TwilioController.sendSMS(app.Id, 'hi'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Twilio 4xx must reach the user');
        System.assertEquals(0, [SELECT COUNT() FROM TwilioSF__Message__c], 'nothing logged as sent');
    }

    @IsTest static void sendSMS_opted_out_throws() {
        seedTwilioCreds();
        PC1_Application__c app = makeApp('+441234567890');
        update new PC1_Application__c(Id = app.Id, SMS_OptOut__c = true);
        Boolean threw = false;
        try { PC1_TwilioController.sendSMS(app.Id, 'hi'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'STOP must be honoured');
    }

    @IsTest static void sendSMS_missing_creds_throws() {
        PC1_Application__c app = makeApp('+441234567890');
        Boolean threw = false;
        try { PC1_TwilioController.sendSMS(app.Id, 'hi'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'no Twilio credentials → clear error');
    }

    // ─── send: blank body ───────────────────────────────────────────
    @IsTest static void sendSMS_blank_body_throws() {
        PC1_Application__c app = makeApp('+441234567890');
        Boolean threw = false;
        try {
            PC1_TwilioController.sendSMS(app.Id, '   ');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Blank body should throw');
    }

    // ─── send: no phone on file ─────────────────────────────────────
    @IsTest static void sendSMS_no_phone_throws() {
        PC1_Application__c app = makeApp(null);
        Boolean threw = false;
        try {
            PC1_TwilioController.sendSMS(app.Id, 'hello');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Missing phone should throw');
    }

    // ─── send: bogus record id ──────────────────────────────────────
    @IsTest static void sendSMS_bad_recordId_throws() {
        // Manufacture a plausible-looking PC1_Application__c Id that doesn't
        // exist so the SOQL SingleRowException path is exercised.
        Id fakeId = PC1_Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000000';
        Boolean threw = false;
        try {
            PC1_TwilioController.sendSMS(fakeId, 'hi');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Bad recordId should throw');
    }

    // ─── read: mirrors sent row ─────────────────────────────────────
    @IsTest static void getThread_returns_row_by_parent_stamp() {
        PC1_Application__c app = makeApp('+441234567890');
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
        PC1_TwilioController.ThreadPayload out = PC1_TwilioController.getThread(app.Id);
        Test.stopTest();

        System.assertEquals('+441234567890', out.appPhone);
        System.assert(out.messages.size() >= 2, 'Expected at least the 2 seeded rows');
        Boolean sawOut = false, sawIn = false;
        for (PC1_TwilioController.MessageRow r : out.messages) {
            if (r.body == 'seeded outbound') { sawOut = true; System.assertEquals(true, r.isOutbound); }
            if (r.body == 'client reply')   { sawIn  = true; System.assertEquals(false, r.isOutbound); }
        }
        System.assert(sawOut, 'Outbound row should be visible via parent stamp');
        System.assert(sawIn,  'Inbound row should be visible via phone fallback');
    }

    // ─── read: no phone, no matches ─────────────────────────────────
    @IsTest static void getThread_empty_when_no_phone() {
        PC1_Application__c app = makeApp(null);
        Test.startTest();
        PC1_TwilioController.ThreadPayload out = PC1_TwilioController.getThread(app.Id);
        Test.stopTest();
        System.assertEquals(null, out.appPhone);
        System.assertEquals(0, out.messages.size());
    }

    // ─── read: bad record id ────────────────────────────────────────
    @IsTest static void getThread_bad_recordId_throws() {
        Id fakeId = PC1_Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000000';
        Boolean threw = false;
        try {
            PC1_TwilioController.getThread(fakeId);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Bad recordId should throw');
    }
}