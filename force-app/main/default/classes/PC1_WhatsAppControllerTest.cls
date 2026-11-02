/**
 * Tests for PC1_WhatsAppController (pc1WhatsAppPanel → Heroku → Timelines).
 * Added 2026-10-02: the class had no test (0%) and its sends bypassed the
 * sandbox gate.
 */
@IsTest
private class PC1_WhatsAppControllerTest {

    private class HerokuMock implements HttpCalloutMock {
        Integer status = 200;
        String body;
        String lastPath;
        HerokuMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            lastPath = req.getEndpoint();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    private static PC1_Application__c setup(String phone) {
        List<PC1_Config__c> cfg = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c c = cfg.isEmpty() ? new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId()) : new PC1_Config__c(Id = cfg[0].Id);
        c.Heroku_Base_Url__c = 'https://example.herokuapp.com';
        c.Heroku_Internal_Token__c = 'tok';
        upsert c;
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'Wa', Last_Name__c = 'Test', Stage__c = 'New', Phone__c = phone);
        insert a;
        return a;
    }

    @IsTest static void thread_and_sends() {
        PC1_Application__c a = setup('+441234567890');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200,
            '{"status":"ok","chat":{"id":1},"messages":[],"optIn":true,"appPhone":"+441234567890","fullName":"Wa Test",'
            + '"message":{"uid":"U1"},"sfRowId":"a00000000000000"}'));
        Test.startTest();
        PC1_WhatsAppController.ThreadPayload t = PC1_WhatsAppController.getThread(a.Id);
        PC1_WhatsAppController.SendResult s1 = PC1_WhatsAppController.sendMessage(a.Id, 'hello');
        PC1_WhatsAppController.SendResult s2 = PC1_WhatsAppController.sendFileFromBrowser(a.Id, 'a.pdf', 'application/pdf', 'QQ==', 'cap');
        Test.stopTest();
        System.assertEquals(true, t.optIn);
        System.assertEquals('Wa Test', t.fullName);
        System.assertEquals('U1', s1.uid);
        System.assertEquals('U1', s2.uid);
    }

    @IsTest static void send_existing_file_and_list_files() {
        PC1_Application__c a = setup('+441234567890');
        ContentVersion cv = new ContentVersion(Title = 'Doc', PathOnClient = 'doc.pdf',
            VersionData = Blob.valueOf('x'), FirstPublishLocationId = a.Id);
        insert cv;
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200, '{"status":"ok","message":{"message_uid":"M9"}}'));
        Test.startTest();
        List<PC1_WhatsAppController.FileRow> files = PC1_WhatsAppController.listApplicationFiles(a.Id);
        PC1_WhatsAppController.SendResult r = PC1_WhatsAppController.sendFileMessage(a.Id, cv.Id, null);
        Test.stopTest();
        System.assertEquals(1, files.size());
        System.assertEquals('M9', r.uid);
    }

    @IsTest static void heroku_error_surfaces_detail() {
        PC1_Application__c a = setup('+441234567890');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(502, '{"detail":"audio too short"}'));
        Boolean threw = false;
        try { PC1_WhatsAppController.sendMessage(a.Id, 'x'); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }

    @IsTest static void sandbox_gate_blocks_unlisted_number() {
        PC1_Application__c a = setup('+447700900222');
        PC1_SendGate.sandboxOverride = true;
        PC1_SendGate.resetCaches();
        Boolean t1 = false, t2 = false, t3 = false;
        try { PC1_WhatsAppController.sendMessage(a.Id, 'x'); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_WhatsAppController.sendFileFromBrowser(a.Id, 'a', 'b', 'QQ==', null); } catch (AuraHandledException e) { t2 = true; }
        try { PC1_WhatsAppController.sendFileMessage(a.Id, a.Id, null); } catch (AuraHandledException e) { t3 = true; }
        System.assert(t1 && t2 && t3, 'no WhatsApp to a client number from the sandbox');
    }

    @IsTest static void input_validation_and_optin_and_mirror() {
        PC1_Application__c a = setup('+441234567890');
        Boolean t1 = false, t2 = false, t3 = false;
        try { PC1_WhatsAppController.sendMessage(a.Id, ' '); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_WhatsAppController.sendFileMessage(a.Id, null, null); } catch (AuraHandledException e) { t2 = true; }
        try { PC1_WhatsAppController.sendFileFromBrowser(a.Id, 'a', 'b', '', null); } catch (AuraHandledException e) { t3 = true; }
        System.assert(t1 && t2 && t3);

        PC1_WhatsAppController.setOptIn(a.Id, true);
        System.assertEquals(true, [SELECT WhatsApp_OptIn__c FROM PC1_Application__c WHERE Id = :a.Id].WhatsApp_OptIn__c);
        System.assertEquals(0, PC1_WhatsAppController.getMirroredThread(a.Id).size());
        System.assertEquals(0, PC1_WhatsAppController.listApplicationFiles(a.Id).size());
    }

    @IsTest static void missing_config_throws() {
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'N', Last_Name__c = 'C', Stage__c = 'New');
        insert a;
        Boolean threw = false;
        try { PC1_WhatsAppController.getThread(a.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }
}