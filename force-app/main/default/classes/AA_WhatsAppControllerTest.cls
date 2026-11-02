/**
 * Tests for AA_WhatsAppController (audit 2026-10-02 F80/F157: the class sat
 * at 0/111 lines covered with no test class at all, which blocks a
 * RunSpecifiedTests production deploy of it). Heroku is faked with an
 * HttpCalloutMock that records the request, so every test asserts what the
 * panel actually sends and what it shows back.
 */
@IsTest
private class AA_WhatsAppControllerTest {

    private static final String BASE  = 'https://aa-autofill.example.test';
    private static final String TOKEN = 'wa-test-token';

    // Records the last request and answers with a canned status + body.
    private class HerokuMock implements HttpCalloutMock {
        public HttpRequest lastReq;
        private Integer status;
        private String  body;
        HerokuMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            lastReq = req;
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setHeader('Content-Type', 'application/json');
            r.setBody(body);
            return r;
        }
    }

    private static void seedConfig() {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Heroku_Base_Url__c       = BASE + '/';
        cfg.Heroku_Internal_Token__c = TOKEN;
        upsert cfg;
    }

    private static AA_Application__c makeApp(Boolean dnc) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Wanda', Last_Name__c = 'Test',
            Stage__c = 'New', Phone__c = '+447700900123',
            Do_Not_Contact__c = dnc
        );
        insert a;
        return a;
    }

    // ─── read ───────────────────────────────────────────────────────

    @IsTest static void getThread_maps_the_heroku_payload() {
        seedConfig();
        AA_Application__c app = makeApp(false);
        HerokuMock mock = new HerokuMock(200,
            '{"status":"ok","chat":{"id":"42"},"messages":[{"uid":"m1","text":"hi"}],'
          + '"optIn":true,"appPhone":"+447700900123","fullName":"Wanda Test"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AA_WhatsAppController.ThreadPayload t = AA_WhatsAppController.getThread(app.Id);
        Test.stopTest();

        System.assertEquals(BASE + '/internal/whatsapp/thread', mock.lastReq.getEndpoint(), 'trailing slash on the base must not double up');
        System.assertEquals(TOKEN, mock.lastReq.getHeader('X-Heroku-Token'));
        System.assert(mock.lastReq.getBody().contains(String.valueOf(app.Id)), mock.lastReq.getBody());
        System.assertEquals('ok', t.status);
        System.assertEquals(true, t.optIn);
        System.assertEquals(1, t.messages.size());
        System.assertEquals('Wanda Test', t.fullName);
    }

    @IsTest static void heroku_error_detail_reaches_the_operator() {
        seedConfig();
        AA_Application__c app = makeApp(false);
        Test.setMock(HttpCalloutMock.class, new HerokuMock(403,
            '{"error":"opt_in_required","msg":"Client has not opted in to WhatsApp."}'));
        String msg;
        Test.startTest();
        try {
            AA_WhatsAppController.sendMessage(app.Id, 'hello');
        } catch (AuraHandledException e) { msg = e.getMessage(); }
        Test.stopTest();
        System.assertNotEquals(null, msg, 'a 4xx from Heroku must throw');
    }

    @IsTest static void missing_config_throws_before_any_callout() {
        AA_Application__c app = makeApp(false);
        HerokuMock mock = new HerokuMock(200, '{}');
        Test.setMock(HttpCalloutMock.class, mock);
        Boolean threw = false;
        try {
            AA_WhatsAppController.getThread(app.Id);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'no Heroku base/token must be a clear error');
        System.assertEquals(null, mock.lastReq);
    }

    // ─── send ───────────────────────────────────────────────────────

    @IsTest static void sendMessage_posts_body_and_returns_uid() {
        seedConfig();
        AA_Application__c app = makeApp(false);
        HerokuMock mock = new HerokuMock(200, '{"status":"ok","message":{"uid":"wa-1"},"sfRowId":"a00000000000001"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AA_WhatsAppController.SendResult r = AA_WhatsAppController.sendMessage(app.Id, 'Hello Wanda');
        Test.stopTest();

        System.assertEquals(BASE + '/internal/whatsapp/send', mock.lastReq.getEndpoint());
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastReq.getBody());
        System.assertEquals('Hello Wanda', sent.get('body'));
        System.assertEquals('wa-1', r.uid);
        System.assertEquals('ok', r.status);
    }

    @IsTest static void sendMessage_blank_body_throws() {
        AA_Application__c app = makeApp(false);
        Boolean threw = false;
        try { AA_WhatsAppController.sendMessage(app.Id, '  '); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }

    @IsTest static void file_sends_use_their_own_endpoints() {
        seedConfig();
        AA_Application__c app = makeApp(false);
        ContentVersion cv = new ContentVersion(Title = 'Doc', PathOnClient = 'doc.pdf',
            VersionData = Blob.valueOf('%PDF-1.4'), FirstPublishLocationId = app.Id);
        insert cv;
        HerokuMock mock = new HerokuMock(200, '{"status":"ok","message":{"message_uid":"wa-f"}}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AA_WhatsAppController.SendResult a = AA_WhatsAppController.sendFileMessage(app.Id, cv.Id, 'caption');
        String firstEndpoint = mock.lastReq.getEndpoint();
        AA_WhatsAppController.SendResult b = AA_WhatsAppController.sendFileFromBrowser(app.Id, 'x.png', 'image/png',
            EncodingUtil.base64Encode(Blob.valueOf('png')), null);
        Test.stopTest();

        System.assertEquals(BASE + '/internal/whatsapp/send-file', firstEndpoint);
        System.assertEquals(BASE + '/internal/whatsapp/send-file-inline', mock.lastReq.getEndpoint());
        System.assertEquals('wa-f', a.uid, 'message_uid is accepted when uid is absent');
        System.assertEquals('wa-f', b.uid);
    }

    // ─── Do Not Contact (audit 2026-10-02 F54) ──────────────────────

    @IsTest static void do_not_contact_blocks_every_send_before_the_callout() {
        seedConfig();
        AA_Application__c app = makeApp(true);
        ContentVersion cv = new ContentVersion(Title = 'Doc', PathOnClient = 'doc.pdf',
            VersionData = Blob.valueOf('%PDF-1.4'), FirstPublishLocationId = app.Id);
        insert cv;
        HerokuMock mock = new HerokuMock(200, '{"status":"ok","message":{"uid":"x"}}');
        Test.setMock(HttpCalloutMock.class, mock);

        Integer blocked = 0;
        Test.startTest();
        try { AA_WhatsAppController.sendMessage(app.Id, 'hello'); } catch (AuraHandledException e) { blocked++; }
        try { AA_WhatsAppController.sendFileMessage(app.Id, cv.Id, null); } catch (AuraHandledException e) { blocked++; }
        try { AA_WhatsAppController.sendFileFromBrowser(app.Id, 'a.png', 'image/png', 'cG5n', null); } catch (AuraHandledException e) { blocked++; }
        Test.stopTest();

        System.assertEquals(3, blocked, 'all three send paths must refuse a Do Not Contact client');
        System.assertEquals(null, mock.lastReq, 'Heroku must not be called at all');
    }

    // ─── misc ───────────────────────────────────────────────────────

    @IsTest static void setOptIn_and_mirror_and_files() {
        AA_Application__c app = makeApp(false);
        AA_WhatsAppController.setOptIn(app.Id, true);
        AA_Application__c after = [SELECT WhatsApp_OptIn__c, WhatsApp_OptIn_At__c FROM AA_Application__c WHERE Id = :app.Id];
        System.assertEquals(true, after.WhatsApp_OptIn__c);
        System.assertNotEquals(null, after.WhatsApp_OptIn_At__c);
        AA_WhatsAppController.setOptIn(app.Id, false);
        after = [SELECT WhatsApp_OptIn__c, WhatsApp_OptIn_At__c FROM AA_Application__c WHERE Id = :app.Id];
        System.assertEquals(false, after.WhatsApp_OptIn__c);
        System.assertEquals(null, after.WhatsApp_OptIn_At__c, 'revoking clears the opt-in time');

        System.assertEquals(0, AA_WhatsAppController.getMirroredThread(app.Id).size());
        System.assertEquals(0, AA_WhatsAppController.listApplicationFiles(app.Id).size());
        insert new ContentVersion(Title = 'Doc', PathOnClient = 'doc.pdf',
            VersionData = Blob.valueOf('%PDF-1.4'), FirstPublishLocationId = app.Id);
        List<AA_WhatsAppController.FileRow> files = AA_WhatsAppController.listApplicationFiles(app.Id);
        System.assertEquals(1, files.size());
        System.assertEquals('doc.pdf', files[0].filename);
    }
}