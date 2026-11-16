@IsTest
private class XpAiClaimsControllerTest {

    private class Mock implements HttpCalloutMock {
        private Integer status;
        private Boolean fail;
        Mock(Integer status, Boolean fail) {
            this.status = status;
            this.fail = fail;
        }
        public HttpResponse respond(HttpRequest req) {
            if (fail) {
                throw new CalloutException('down');
            }
            System.assert(req.getEndpoint().startsWith('callout:XP_AI_CLAIMS/'), 'uses the Claims named credential');
            System.assertEquals(UserInfo.getUserId(), req.getHeader('X-XPAI-User'), 'sends who is asking');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    @IsTest
    static void relaysAllowedCalls() {
        Test.setMock(HttpCalloutMock.class, new Mock(200, false));
        Test.startTest();
        String out = XpAiClaimsController.send('POST', '/turn', '{"text":"hi"}');
        String out2 = XpAiClaimsController.send('GET', '/history?recordId=a1LVg000003GgzFMAS', null);
        Test.stopTest();
        System.assertEquals('{"ok":true}', out);
        System.assertEquals('{"ok":true}', out2);
    }

    @IsTest
    static void refusesOtherPaths() {
        System.assert(!XpAiClaimsController.isAllowed('GET', '/admin'));
        System.assert(!XpAiClaimsController.isAllowed('DELETE', '/turn'));
        System.assert(!XpAiClaimsController.isAllowed(null, null));
        System.assert(XpAiClaimsController.isAllowed('GET', '/turn/0f8fad5b-d9cb-469f-a165-70867728950e'));
        System.assert(XpAiClaimsController.isAllowed('GET', '/context?recordId=a1LVg000003GgzFMAS'));
        System.assert(XpAiClaimsController.isAllowed('GET', '/history'));
        System.assert(XpAiClaimsController.isAllowed('GET', '/chats'));
        System.assert(XpAiClaimsController.isAllowed('POST', '/reset'));
        System.assert(XpAiClaimsController.isAllowed('POST', '/feedback'));
        // The Claims service has no drafts, actions or DWP chase: those paths are refused here.
        System.assert(!XpAiClaimsController.isAllowed('POST', '/draft/0f8fad5b-d9cb-469f-a165-70867728950e/save'));
        System.assert(!XpAiClaimsController.isAllowed('POST', '/action/0f8fad5b-d9cb-469f-a165-70867728950e/confirm'));
        System.assert(!XpAiClaimsController.isAllowed('GET', '/dwp/chase?recordId=a1LVg000003GgzFMAS'));
        System.assert(!XpAiClaimsController.isAllowed('GET', '/history?recordId=x;drop'));
        Boolean threw = false;
        try {
            XpAiClaimsController.send('GET', '/admin', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'unknown path refused');
    }

    @IsTest
    static void reportsRefusalAndOutage() {
        Test.setMock(HttpCalloutMock.class, new Mock(401, false));
        Boolean threw = false;
        try {
            XpAiClaimsController.send('POST', '/reset', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, '401 surfaces');

        Test.setMock(HttpCalloutMock.class, new Mock(200, true));
        threw = false;
        try {
            XpAiClaimsController.send('POST', '/reset', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'outage surfaces');
    }
}