/**
 * AA_MaryBridge — UI bridge for Mary (Eleven Labs agent) outbound calls.
 *
 * callNow() POSTs `${base}/internal/mary/call-now/:appId` on the Heroku worker
 * (src/server.js mounts it; the handler is callNow in
 * src/webhooks/scheduler.js), which books a Manual schedule row, sets
 * Stage__c = 'Call In Progress' and dials.
 *
 * Auth follows the same pattern as AA_HerokuBridge: shared secret in
 * AA_Config__c.Heroku_Internal_Token__c sent as X-Heroku-Token, base URL in
 * AA_Config__c.Heroku_Base_Url__c (Remote Site Setting AA_Heroku_Autofill
 * already whitelists it).
 *
 * Stage guard (audit 2026-10-02 F50/F86): the Heroku handler only refuses a
 * missing phone or Do Not Contact, and it overwrites Stage__c with 'Call In
 * Progress' whatever the stage was. So one click on an Awarded / Fee Charged /
 * Submitted / Needs Human record rolled the stage back and hid the money
 * cards, and a second click while a call was live rang the client twice.
 * Call Now is therefore refused here unless the record is in a stage where
 * Mary is still collecting answers. An operator who really needs Mary to ring
 * a later-stage client moves the stage back first (stage moves are free since
 * 2026-07-30), which is a deliberate, logged act.
 */
public with sharing class AA_MaryBridge {

    /** Stages where Mary is still collecting the questionnaire. */
    @TestVisible
    private static final Set<String> CALLABLE_STAGES = new Set<String>{
        'New', 'Awaiting First Call', 'Partial Data', 'Data Complete'
    };

    @AuraEnabled
    public static String callNow(Id applicationId) {
        if (applicationId == null) throw new AuraHandledException('applicationId is required');

        List<AA_Application__c> apps = [
            SELECT Id, Stage__c, Do_Not_Contact__c
              FROM AA_Application__c
             WHERE Id = :applicationId
             LIMIT 1
        ];
        if (apps.isEmpty()) fail('Application not found.');
        AA_Application__c app = apps[0];
        if (app.Do_Not_Contact__c == true) {
            fail('This client is marked Do Not Contact, so Mary cannot call them.');
        }
        if (app.Stage__c == 'Call In Progress') {
            fail('Mary is already on a call with this client (stage is Call In Progress). '
                + 'Wait for that call to finish. If the stage is stuck, move it back to Partial Data first.');
        }
        if (!CALLABLE_STAGES.contains(app.Stage__c)) {
            fail('Call Now only works while Mary is still collecting answers (New, Awaiting First Call, '
                + 'Partial Data or Data Complete). This application is at "' + app.Stage__c + '", and a call '
                + 'would move it back to Call In Progress. If Mary really needs to call, move the stage back first.');
        }

        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Heroku_Internal_Token__c);
        if (String.isBlank(base) || String.isBlank(token)) {
            fail('AA_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c');
        }

        // Heroku route is /internal/mary/call-now/:appId — the appId is a
        // path param, no body needed. Auth via X-Heroku-Token.
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base.removeEnd('/') + '/internal/mary/call-now/' + applicationId);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Heroku-Token', token);
        req.setBody('{}');
        req.setTimeout(30000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            fail('Callout failed: ' + e.getMessage());
        }

        Integer code = res.getStatusCode();
        if (code != 200 && code != 202) {
            fail('Heroku returned HTTP ' + code + ': ' + res.getBody());
        }
        return res.getBody();
    }

    /** setMessage so the text reaches Apex callers too, not only the LWC toast. */
    private static void fail(String msg) {
        AuraHandledException e = new AuraHandledException(msg);
        e.setMessage(msg);
        throw e;
    }
}