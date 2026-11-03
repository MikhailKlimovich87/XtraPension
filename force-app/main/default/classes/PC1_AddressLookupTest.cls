/**
 * Tests for PC1_AddressLookup (Loqate proxy for pc1AddressEditor).
 * Added 2026-10-02 — the class had no test (0%).
 */
@IsTest
private class PC1_AddressLookupTest {

    private class LoqateMock implements HttpCalloutMock {
        Integer status = 200;
        String body;
        LoqateMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    private static void key(String k) {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c c = rows.isEmpty() ? new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId()) : new PC1_Config__c(Id = rows[0].Id);
        c.Loqate_Key__c = k;
        upsert c;
    }

    @IsTest static void find_returns_addresses_and_containers() {
        key('KEY');
        Test.startTest();  // setup DML above, callouts below
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Id":"A1","Type":"Address","Text":"1 High St","Description":"London"},'
            + '{"Id":"C1","Type":"Postcode","Text":"SW1A 1AA","Description":"12 addresses"}]}'));
        List<PC1_AddressLookup.Suggestion> s = PC1_AddressLookup.findAddress('SW1A', null, null);
        System.assertEquals(2, s.size());
        System.assertEquals('Address', s[0].type);
        System.assertEquals('Container', s[1].type);
        System.assertEquals(2, PC1_AddressLookup.findAddress('', 'C1', null).size(), 'drill into a container');
        System.assertEquals(0, PC1_AddressLookup.findAddress('', null, null).size(), 'nothing to search');
    }

    @IsTest static void find_errors() {
        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_AddressLookup.findAddress('x', null, null); } catch (AuraHandledException e) { t1 = true; } // no key
        key('KEY');
        Test.startTest();  // setup DML above, callouts below
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '{"Items":[{"Error":"2","Description":"Unknown key"}]}'));
        try { PC1_AddressLookup.findAddress('x', null, null); } catch (AuraHandledException e) { t2 = true; }
        Test.setMock(HttpCalloutMock.class, new LoqateMock(500, 'oops'));
        try { PC1_AddressLookup.findAddress('x', null, null); } catch (AuraHandledException e) { t3 = true; }
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, 'not json'));
        try { PC1_AddressLookup.findAddress('x', null, null); } catch (AuraHandledException e) { t4 = true; }
        System.assert(t1 && t2 && t3 && t4);
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '{}'));
        System.assertEquals(0, PC1_AddressLookup.findAddress('x', null, null).size());
    }

    @IsTest static void retrieve_maps_fields_and_fallbacks() {
        key('KEY');
        Test.startTest();  // setup DML above, callouts below
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Line1":"","BuildingNumber":"10","Street":"Downing Street","Line2":"Westminster","Line3":"",'
            + '"City":"","PostTown":"London","ProvinceName":"","AdminAreaName":"Greater London","PostalCode":"SW1A 2AA"}]}'));
        PC1_AddressLookup.Address a = PC1_AddressLookup.retrieveAddress('GB|1');
        System.assertEquals('10 Downing Street', a.line1);
        System.assertEquals('Westminster', a.line2);
        System.assertEquals('London', a.town);
        System.assertEquals('Greater London', a.county);
        System.assertEquals('SW1A 2AA', a.postcode);
        System.assertEquals('United Kingdom', a.country);

        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Line1":"","Company":"XtraPension Ltd","City":"Leeds","PostalCode":"LS1 1AA","CountryName":"United Kingdom"}]}'));
        System.assertEquals('XtraPension Ltd', PC1_AddressLookup.retrieveAddress('GB|2').line1);
    }

    @IsTest static void retrieve_errors() {
        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_AddressLookup.retrieveAddress('x'); } catch (AuraHandledException e) { t1 = true; } // no key
        key('KEY');
        Test.startTest();  // setup DML above, callouts below
        try { PC1_AddressLookup.retrieveAddress(''); } catch (AuraHandledException e) { t2 = true; }
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '{"Items":[]}'));
        try { PC1_AddressLookup.retrieveAddress('x'); } catch (AuraHandledException e) { t3 = true; }
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '{"Items":[{"Error":"1","Description":"bad id"}]}'));
        try { PC1_AddressLookup.retrieveAddress('x'); } catch (AuraHandledException e) { t4 = true; }
        System.assert(t1 && t2 && t3 && t4);
    }
}