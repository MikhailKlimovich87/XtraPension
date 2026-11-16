@IsTest
private class XpValidationCallControllerTest {

    private class Mock implements HttpCalloutMock {
        Integer status;
        String body;
        Boolean fail = false;
        HttpRequest seen;
        Mock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            seen = req;
            if (fail) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    private static void settings(String key) {
        insert new XP_Booking_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Key__c = key, Base_URL__c = 'https://book.example.com/');
    }

    private static Basic__c claim(String email, String country) {
        Basic__c c = new Basic__c(
            Status__c = 'Form In Progress', Email__c = email, First_Name__c = 'Ann', Last_Name__c = 'Doyle',
            Phone__c = '+61 412 000 000', Current_Address_Abroad_Country__c = country
        );
        insert c;
        return c;
    }

    @IsTest
    static void readsTheCallFromXpBooking() {
        settings('k1');
        Basic__c c = claim('ann.doyle@example.com', 'AU');
        Mock m = new Mock(200, '{"offers":"Becky","call":{"state":"booked","irish":"Thu 12 Nov, 10:00 Irish time","hostName":"Becky"}}');
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        Map<String, Object> r = XpValidationCallController.getCall(c.Id);
        Test.stopTest();

        System.assertEquals('ok', r.get('status'));
        System.assertEquals('Becky', r.get('agent'), 'AUS/NZ claims go to Becky');
        System.assertEquals('AUS/NZ', r.get('region'));
        Map<String, Object> call = (Map<String, Object>) r.get('call');
        System.assertEquals('booked', call.get('state'));
        System.assertEquals('https://book.example.com/api/book/claims/validation-call', m.seen.getEndpoint());
        System.assertEquals('k1', m.seen.getHeader('X-XP-Key'));
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(m.seen.getBody());
        System.assertEquals('ann.doyle@example.com', sent.get('email'));
        System.assertEquals('Becky', sent.get('agent'));
        System.assertEquals('claim-aus', sent.get('page'));
        System.assertEquals('Becky', r.get('offers'));
        String book = (String) r.get('bookUrl');
        System.assert(book.startsWith('https://book.example.com/go/claim-aus?name=Ann+Doyle&email=ann.doyle%40example.com&a1=%2B61+412+000+000'), book);
        System.assert(book.endsWith('&utm_source=salesforce'), book);
        System.assert(!((String) r.get('clientUrl')).contains('utm_source'), 'the client link carries no Salesforce mark');
    }

    @IsTest
    static void noCallYet() {
        settings('k1');
        Basic__c c = claim('nocall@example.com', 'IE');
        Test.setMock(HttpCalloutMock.class, new Mock(200, '{"call":null}'));

        Test.startTest();
        Map<String, Object> r = XpValidationCallController.getCall(c.Id);
        Test.stopTest();

        System.assertEquals('ok', r.get('status'));
        System.assertEquals(null, r.get('call'));
        System.assertEquals('EU/ROW', r.get('region'));
        System.assert(((String) r.get('bookUrl')).contains('/go/claim-eu?'));
    }

    @IsTest
    static void xpBookingDownShowsTheClaimsOwnField() {
        settings('k1');
        Basic__c c = claim('down@example.com', 'IE');
        update new Basic__c(Id = c.Id, Val_Call_Booked_Date__c = '12/11/2026 10:00 (Irish time) - Ciara');
        Test.setMock(HttpCalloutMock.class, new Mock(503, '{"error":"down"}'));

        Test.startTest();
        Map<String, Object> r = XpValidationCallController.getCall(c.Id);
        Test.stopTest();

        System.assertEquals('offline', r.get('status'));
        System.assertEquals('XP Booking answered 503', r.get('detail'));
        System.assertEquals('12/11/2026 10:00 (Irish time) - Ciara', r.get('fallback'));
    }

    @IsTest
    static void aTimeoutIsOfflineToo() {
        settings('k1');
        Basic__c c = claim('slow@example.com', 'IE');
        Mock m = new Mock(200, '{}');
        m.fail = true;
        Test.setMock(HttpCalloutMock.class, m);

        Test.startTest();
        Map<String, Object> r = XpValidationCallController.getCall(c.Id);
        Test.stopTest();

        System.assertEquals('offline', r.get('status'));
        System.assertEquals('Read timed out', r.get('detail'));
    }

    @IsTest
    static void noKeyNoEmail() {
        Basic__c c = claim('nokey@example.com', 'IE');
        Basic__c noEmail = claim(null, 'IE');

        Test.startTest();
        Map<String, Object> r = XpValidationCallController.getCall(c.Id);
        Map<String, Object> e = XpValidationCallController.getCall(noEmail.Id);
        Test.stopTest();

        System.assertEquals('offline', r.get('status'), 'no key set: nothing is asked');
        System.assertEquals('XP Booking Settings has no key', r.get('detail'));
        System.assert(((String) r.get('bookUrl')).startsWith(XpValidationCallController.DEFAULT_BASE + '/go/claim-eu'));
        System.assertEquals('no_email', e.get('status'));
    }
}