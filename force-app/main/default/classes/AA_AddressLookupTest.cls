/**
 * AA_AddressLookupTest — Loqate proxy behind the aaAddressEditor card.
 *
 * Added 2026-10-02 (audit F157): the class had 0% coverage. Every callout is
 * mocked; nothing reaches Loqate.
 */
@isTest
private class AA_AddressLookupTest {

    private class LoqateMock implements HttpCalloutMock {
        Integer status;
        String body;
        LoqateMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().startsWith('https://api.addressy.com/'), 'only Loqate is called');
            System.assert(req.getEndpoint().contains('Key=TEST-KEY'), 'the org key is sent');
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    private static void setKey(String key) {
        insert new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId(), Loqate_Key__c = key);
    }

    @isTest static void find_withoutKey_throws() {
        Boolean threw = false;
        try { AA_AddressLookup.findAddress('SW1A', null, null); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'missing key must fail loudly');
    }

    @isTest static void find_blankSearch_returnsEmptyWithoutCallout() {
        setKey('TEST-KEY');
        System.assertEquals(0, AA_AddressLookup.findAddress('  ', null, null).size(), 'blank search: no callout, no rows');
    }

    @isTest static void find_mapsAddressesAndContainers() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[' +
            '{"Id":"GB|1","Type":"Address","Text":"10 Downing Street","Description":"London, SW1A 2AA"},' +
            '{"Id":"GB|C","Type":"Postcode","Text":"SW1A 2AA","Description":"12 Addresses"}]}'));
        Test.startTest();
        List<AA_AddressLookup.Suggestion> out = AA_AddressLookup.findAddress('SW1A 2AA', null, 'GB|C0');
        Test.stopTest();
        System.assertEquals(2, out.size(), 'two suggestions');
        System.assertEquals('Address', out[0].type, 'address kept as Address');
        System.assertEquals('Container', out[1].type, 'anything else is a Container');
        System.assertEquals('10 Downing Street', out[0].text, 'text mapped');
    }

    @isTest static void find_loqateError_throws() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Error":"2","Description":"Unknown key"}]}'));
        Boolean threw = false;
        Test.startTest();
        try { AA_AddressLookup.findAddress('SW1A', 'GB|1', null); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'a Loqate error item must surface');
    }

    @isTest static void find_httpError_throws() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(500, 'oops'));
        Boolean threw = false;
        Test.startTest();
        try { AA_AddressLookup.findAddress('SW1A', null, null); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'HTTP 500 must surface');
    }

    @isTest static void find_nonJson_throws() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '<html>login</html>'));
        Boolean threw = false;
        Test.startTest();
        try { AA_AddressLookup.findAddress('SW1A', null, null); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'non-JSON must surface');
    }

    @isTest static void find_noItems_returnsEmpty() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '{}'));
        Test.startTest();
        System.assertEquals(0, AA_AddressLookup.findAddress('SW1A', null, null).size(), 'no Items: empty list');
        Test.stopTest();
    }

    @isTest static void retrieve_mapsLines() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Line1":"Flat 2","Line2":"10 High Street","Line3":"Old Town",' +
            '"City":"Bristol","ProvinceName":"Avon","PostalCode":"BS1 4ST","CountryName":"United Kingdom"}]}'));
        Test.startTest();
        AA_AddressLookup.Address a = AA_AddressLookup.retrieveAddress('GB|1');
        Test.stopTest();
        System.assertEquals('Flat 2', a.line1, 'line1');
        System.assertEquals('10 High Street, Old Town', a.line2, 'lines 2..5 collapsed');
        System.assertEquals('Bristol', a.town, 'town');
        System.assertEquals('BS1 4ST', a.postcode, 'postcode');
    }

    @isTest static void retrieve_blankLine1_fallsBackToNumberAndStreet() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Line1":"","BuildingNumber":"7","Street":"Mill Lane","PostTown":"Leeds","PostalCode":"LS1 1AA"}]}'));
        Test.startTest();
        AA_AddressLookup.Address a = AA_AddressLookup.retrieveAddress('GB|2');
        Test.stopTest();
        System.assertEquals('7 Mill Lane', a.line1, 'number + street when Line1 is blank');
        System.assertEquals('Leeds', a.town, 'PostTown when City is blank');
        System.assertEquals('United Kingdom', a.country, 'country defaults');
    }

    @isTest static void retrieve_errorsSurface() {
        setKey('TEST-KEY');
        Boolean blankId = false;
        try { AA_AddressLookup.retrieveAddress(''); } catch (AuraHandledException e) { blankId = true; }
        System.assert(blankId, 'blank id rejected');

        Test.setMock(HttpCalloutMock.class, new LoqateMock(200, '{"Items":[]}'));
        Boolean empty = false;
        Test.startTest();
        try { AA_AddressLookup.retrieveAddress('GB|3'); } catch (AuraHandledException e) { empty = true; }
        Test.stopTest();
        System.assert(empty, 'no address returned must surface');
    }

    @isTest static void retrieve_loqateErrorItem_throws() {
        setKey('TEST-KEY');
        Test.setMock(HttpCalloutMock.class, new LoqateMock(200,
            '{"Items":[{"Error":"1001","Description":"Id invalid"}]}'));
        Boolean threw = false;
        Test.startTest();
        try { AA_AddressLookup.retrieveAddress('bad'); } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'error item must surface');
    }

    @isTest static void retrieve_withoutKey_throws() {
        Boolean threw = false;
        try { AA_AddressLookup.retrieveAddress('GB|1'); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'missing key must fail loudly');
    }
}