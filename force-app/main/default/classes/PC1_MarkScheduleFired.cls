/**
 * PC1_MarkScheduleFired — truly-atomic compare-and-swap for the scheduler
 * tick's "flip Pending → Fired" step (Bug M7 / re-audit BUG-6).
 *
 * The Node-side markScheduleFired (src/lib/schedule.js) used to SELECT the
 * Status then UPDATE in two REST round-trips — two overlapping scheduler
 * ticks could both read 'Pending' and both dial the client. This endpoint
 * does the whole CAS inside ONE Apex transaction with a `FOR UPDATE` row
 * lock, so the loser blocks until the winner commits and then sees
 * Status='Fired' → returns fired=false → its tick aborts the dial.
 *
 * POST /services/apexrest/pc1/mark-schedule-fired
 *   body: { "schedule_id": "a1Z..." }
 *   resp: { "fired": true | false, "status": "<current status>" }
 */
@RestResource(urlMapping='/pc1/mark-schedule-fired')
global with sharing class PC1_MarkScheduleFired {

    @HttpPost
    global static void fire() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        Map<String, Object> out = new Map<String, Object>();
        try {
            Map<String, Object> body = (Map<String, Object>)
                JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            String schedId = (String) body.get('schedule_id');
            if (String.isBlank(schedId)) {
                res.statusCode = 400;
                out.put('fired', false);
                out.put('error', 'schedule_id required');
                res.responseBody = Blob.valueOf(JSON.serialize(out));
                return;
            }
            // FOR UPDATE = row lock for the rest of this transaction. A
            // concurrent call for the same row waits here, then reads the
            // committed 'Fired' status and bails.
            List<PC1_Call_Schedule__c> rows = [
                SELECT Id, Status__c FROM PC1_Call_Schedule__c
                WHERE Id = :schedId LIMIT 1 FOR UPDATE
            ];
            if (rows.isEmpty()) {
                res.statusCode = 404;
                out.put('fired', false);
                out.put('error', 'schedule_not_found');
            } else if (rows[0].Status__c != 'Pending') {
                res.statusCode = 200;
                out.put('fired', false);
                out.put('status', rows[0].Status__c);
            } else {
                rows[0].Status__c = 'Fired';
                rows[0].Fired_At__c = System.now();
                update rows[0];
                res.statusCode = 200;
                out.put('fired', true);
                out.put('status', 'Fired');
            }
        } catch (Exception e) {
            res.statusCode = 500;
            out.put('fired', false);
            out.put('error', e.getMessage());
        }
        res.responseBody = Blob.valueOf(JSON.serialize(out));
    }
}