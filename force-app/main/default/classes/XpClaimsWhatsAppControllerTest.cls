@IsTest
private class XpClaimsWhatsAppControllerTest {

    private class Mock implements HttpCalloutMock {
        private Integer status;
        private String body;
        private Boolean fail;
        Mock(Integer status, String body, Boolean fail) {
            this.status = status;
            this.body = body;
            this.fail = fail;
        }
        public HttpResponse respond(HttpRequest req) {
            if (fail) {
                throw new CalloutException('down');
            }
            System.assert(req.getEndpoint().startsWith('callout:XP_AI_CLAIMS/wa/'), 'uses the Claims named credential');
            System.assertEquals(UserInfo.getUserId(), req.getHeader('X-XPAI-User'), 'sends who is asking');
            Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            if (!req.getEndpoint().contains('/wa/ai-reply/')) {
                System.assert(sent.get('contact') == 'client' || sent.get('contact') == 'helper', 'contact is client or helper: ' + sent.get('contact'));
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    // 15 characters: the 3-letter suffix depends on the capitals (the L of a1L), so it is left to Salesforce.
    private static Id fakeClaimId() {
        return Id.valueOf(Basic__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    @IsTest
    static void relaysReadsAndSends() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"status":"ok","messages":[]}', false));
        Id claimId = fakeClaimId();
        Test.startTest();
        Map<String, Object> t = XpClaimsWhatsAppController.getThread(claimId, 'helper');
        Map<String, Object> s = XpClaimsWhatsAppController.sendMessage(claimId, 'anything else', 'Hello');
        Map<String, Object> f = XpClaimsWhatsAppController.sendFileFromBrowser(claimId, null, 'a.pdf', 'application/pdf', 'JVBERi0=', null);
        Test.stopTest();
        System.assertEquals('ok', t.get('status'));
        System.assertEquals('ok', s.get('status'));
        System.assertEquals('ok', f.get('status'));
    }

    @IsTest
    static void draftsAiReply() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"status":"done","text":"Hi"}', false));
        Test.startTest();
        Map<String, Object> s = XpClaimsWhatsAppController.startAiReply(fakeClaimId(), 'client', 'say hi');
        System.assertEquals('done', XpClaimsWhatsAppController.startRewrite(fakeClaimId(), 'client', 'hi there').get('status'));
        Boolean emptyRefused = false;
        try { XpClaimsWhatsAppController.startRewrite(fakeClaimId(), 'client', ' '); } catch (AuraHandledException e) { emptyRefused = true; }
        System.assert(emptyRefused, 'empty rewrite refused');
        Map<String, Object> r = XpClaimsWhatsAppController.getAiReply('0f8fad5b-d9cb-469f-a165-70867728950e');
        Test.stopTest();
        System.assertEquals('done', s.get('status'));
        System.assertEquals('Hi', r.get('text'));
        Boolean threw = false;
        try { XpClaimsWhatsAppController.getAiReply('../admin'); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'bad job id refused');
    }

    @IsTest
    static void sendsSalesforceFile() {
        ContentVersion cv = new ContentVersion(Title = 'Doc', PathOnClient = 'Doc.pdf', VersionData = Blob.valueOf('x'));
        insert cv;
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"status":"ok"}', false));
        Test.startTest();
        Map<String, Object> r = XpClaimsWhatsAppController.sendFileMessage(fakeClaimId(), 'client', cv.Id, 'caption');
        Test.stopTest();
        System.assertEquals('ok', r.get('status'));
    }

    @IsTest
    static void listsLinkedFiles() {
        // A new ContentVersion is linked to its owner, so the user stands in for the record.
        insert new ContentVersion(Title = 'Doc', PathOnClient = 'Doc.pdf', VersionData = Blob.valueOf('x'));
        List<XpClaimsWhatsAppController.FileRow> rows = XpClaimsWhatsAppController.listClaimFiles(UserInfo.getUserId());
        System.assertEquals(1, rows.size());
        System.assertEquals('Doc', rows[0].title);
        System.assertEquals(0, XpClaimsWhatsAppController.listClaimFiles(fakeClaimId()).size());
    }

    @IsTest
    static void surfacesErrors() {
        Id claimId = fakeClaimId();
        Integer thrown = 0;
        try { XpClaimsWhatsAppController.sendMessage(claimId, 'client', ' '); } catch (AuraHandledException e) { thrown++; }
        try { XpClaimsWhatsAppController.sendFileMessage(claimId, 'client', null, null); } catch (AuraHandledException e) { thrown++; }
        try { XpClaimsWhatsAppController.sendFileFromBrowser(claimId, 'client', 'a', 'b', '', null); } catch (AuraHandledException e) { thrown++; }

        Test.setMock(HttpCalloutMock.class, new Mock(400, '{"error":"no phone"}', false));
        try { XpClaimsWhatsAppController.getThread(claimId, 'client'); } catch (AuraHandledException e) { thrown++; }
        Test.setMock(HttpCalloutMock.class, new Mock(401, '', false));
        try { XpClaimsWhatsAppController.getThread(claimId, 'client'); } catch (AuraHandledException e) { thrown++; }
        Test.setMock(HttpCalloutMock.class, new Mock(502, 'not json', false));
        try { XpClaimsWhatsAppController.getThread(claimId, 'client'); } catch (AuraHandledException e) { thrown++; }
        Test.setMock(HttpCalloutMock.class, new Mock(200, '', true));
        try { XpClaimsWhatsAppController.getThread(claimId, 'client'); } catch (AuraHandledException e) { thrown++; }
        System.assertEquals(7, thrown);
    }
}