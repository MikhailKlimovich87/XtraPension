/**
 * AA_RestUtilTest — the shared REST helpers (AA_FlagForHuman is their live
 * caller). Covered directly since the Mary REST twins and their tests were
 * removed on 2026-10-02.
 */
@isTest
private class AA_RestUtilTest {

    private static void setBody(String body) {
        RestRequest req = new RestRequest();
        req.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
    }

    @isTest static void parseBody_handlesEmptyValidAndInvalidJson() {
        setBody(null);
        System.assert(AA_RestUtil.parseBody().isEmpty());

        setBody('{"application_id":"AA-1","n":2}');
        Map<String, Object> ok = AA_RestUtil.parseBody();
        System.assertEquals('AA-1', AA_RestUtil.str(ok, 'application_id'));
        System.assertEquals('2', AA_RestUtil.str(ok, 'n'));
        System.assertEquals(null, AA_RestUtil.str(ok, 'missing'));

        setBody('{not json');
        Map<String, Object> bad = AA_RestUtil.parseBody();
        System.assert(bad.containsKey('_parseError'));
        System.assertEquals('{not json', bad.get('_raw'));
    }

    @isTest static void writeError_setsStatusAndBody() {
        setBody(null);
        AA_RestUtil.writeError(404, 'not found');
        System.assertEquals(404, RestContext.response.statusCode);
        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        System.assertEquals('error', resp.get('status'));
        System.assertEquals('not found', resp.get('error'));
    }

    @isTest static void findApplication_matchesByIdNameDwpRefAndPhone() {
        AA_Application__c app = new AA_Application__c(
            First_Name__c = 'Rest', Last_Name__c = 'Util', Phone__c = '+447700900123',
            DWP_Reference__c = 'AA-REST-UTIL-1', CurrencyIsoCode = 'GBP');
        insert app;
        String name = [SELECT Name FROM AA_Application__c WHERE Id = :app.Id].Name;

        System.assertEquals(app.Id, AA_RestUtil.findApplication(
            new Map<String, Object>{ 'application_id' => String.valueOf(app.Id) }).Id);
        System.assertEquals(app.Id, AA_RestUtil.findApplication(
            new Map<String, Object>{ 'application_id' => name }).Id);
        System.assertEquals(app.Id, AA_RestUtil.findApplication(
            new Map<String, Object>{ 'dwp_reference' => 'AA-REST-UTIL-1' }).Id);
        System.assertEquals(app.Id, AA_RestUtil.findApplication(
            new Map<String, Object>{ 'phone' => '+447700900123' }).Id);
        System.assertEquals(null, AA_RestUtil.findApplication(
            new Map<String, Object>{ 'phone' => '+447700900999' }));
        System.assertEquals(null, AA_RestUtil.findApplication(new Map<String, Object>()));
    }
}