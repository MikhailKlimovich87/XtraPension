/**
 * AA_MarkScheduleFiredTest — the compare-and-swap the scheduler tick relies on
 * to never dial the same Pending row twice (audit F157: the class was at 0%
 * coverage, which blocks a RunSpecifiedTests deploy of it and left the CAS
 * contract with no assertion at all).
 *
 * Contract (src/lib/schedule.js markScheduleFired reads it):
 *   Pending      -> 200 {fired:true,  status:'Fired'} and Fired_At__c stamped
 *   not Pending  -> 200 {fired:false, status:<current>} (the loser of a race)
 *   no id        -> 400 {fired:false, error}
 *   unknown id   -> 404 {fired:false, error}
 *   bad body     -> 500 {fired:false, error} (Node then falls back)
 */
@isTest
private class AA_MarkScheduleFiredTest {

    private static Id makePending() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Fire', Last_Name__c = 'Test' + System.now().getTime(),
            Phone__c = '+447700900123', Stage__c = 'Awaiting First Call', CurrencyIsoCode = 'GBP'
        );
        insert a;
        AA_Call_Schedule__c s = new AA_Call_Schedule__c(
            Application__c = a.Id, Status__c = 'Pending', Scheduled_At__c = Datetime.now().addDays(2)
        );
        insert s;
        return s.Id;
    }

    private static Map<String, Object> post(String rawBody) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/aa/mark-schedule-fired';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(rawBody);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        AA_MarkScheduleFired.fire();
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @isTest static void pending_row_is_fired_once_then_refused() {
        Id schedId = makePending();
        Test.startTest();
        Map<String, Object> first = post(JSON.serialize(new Map<String, Object>{ 'schedule_id' => schedId }));
        Integer firstCode = RestContext.response.statusCode;
        Map<String, Object> second = post(JSON.serialize(new Map<String, Object>{ 'schedule_id' => schedId }));
        Integer secondCode = RestContext.response.statusCode;
        Test.stopTest();

        System.assertEquals(200, firstCode);
        System.assertEquals(true, first.get('fired'), 'the first caller wins the CAS');
        System.assertEquals('Fired', first.get('status'));
        AA_Call_Schedule__c row = [SELECT Status__c, Fired_At__c FROM AA_Call_Schedule__c WHERE Id = :schedId];
        System.assertEquals('Fired', row.Status__c);
        System.assertNotEquals(null, row.Fired_At__c, 'Fired_At__c is stamped (Fired_Needs_Timestamp rule)');

        System.assertEquals(200, secondCode);
        System.assertEquals(false, second.get('fired'), 'the second caller must NOT dial');
        System.assertEquals('Fired', second.get('status'));
        System.assertEquals(null, second.get('error'), 'a lost race is not an error (Node treats error as fall-back)');
    }

    @isTest static void cancelled_row_is_not_fired() {
        Id schedId = makePending();
        update new AA_Call_Schedule__c(Id = schedId, Status__c = 'Cancelled', Cancelled_At__c = Datetime.now());
        Map<String, Object> out = post(JSON.serialize(new Map<String, Object>{ 'schedule_id' => schedId }));
        System.assertEquals(false, out.get('fired'));
        System.assertEquals('Cancelled', out.get('status'));
    }

    @isTest static void missing_id_is_400() {
        Map<String, Object> out = post('{}');
        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(false, out.get('fired'));
        System.assertEquals('schedule_id required', out.get('error'));
    }

    @isTest static void unknown_id_is_404() {
        Id schedId = makePending();
        delete [SELECT Id FROM AA_Call_Schedule__c WHERE Id = :schedId];
        Map<String, Object> out = post(JSON.serialize(new Map<String, Object>{ 'schedule_id' => schedId }));
        System.assertEquals(404, RestContext.response.statusCode);
        System.assertEquals('schedule_not_found', out.get('error'));
    }

    @isTest static void malformed_body_is_500_with_error() {
        Map<String, Object> out = post('not json');
        System.assertEquals(500, RestContext.response.statusCode);
        System.assertEquals(false, out.get('fired'));
        System.assertNotEquals(null, out.get('error'), 'an error makes Node use its 2-step fallback');
    }
}