/**
 * PC1_MaryBridge — UI bridge for Mary (Eleven Labs agent) outbound calls.
 *
 * callNow() POSTs `${base}/internal/mary/call-now` on the Heroku worker with
 * the Application Id. The Heroku endpoint is not implemented yet — this class
 * is the Salesforce side of the contract so the record-page buttons are wired
 * for real; when the endpoint lands it starts working with zero SF changes.
 *
 * Auth follows the same pattern as PC1_HerokuBridge: shared secret in
 * PC1_Config__c.Heroku_Internal_Token__c sent as X-Heroku-Token, base URL in
 * PC1_Config__c.Heroku_Base_Url__c (Remote Site Setting PC1_Heroku_Autofill
 * already whitelists it).
 */
public with sharing class PC1_MaryBridge {

    @TestVisible private static final Set<String> CALLABLE_STAGES = new Set<String>{
        'New', 'Awaiting First Call', 'Call In Progress', 'Partial Data', 'Data Complete',
        'Awaiting Bank Details', 'Needs Human', 'Ready for Review', 'Reviewed'
    };

    @AuraEnabled
    public static String callNow(Id applicationId) {
        if (applicationId == null) throw new AuraHandledException('applicationId is required');

        // Mary collects the claim data; after submission a Call Now flipped
        // the record back to Call In Progress → Data Complete and hid the
        // Award / Fee cards (audit 2026-10-02). Node enforces the same list.
        List<PC1_Application__c> apps = [SELECT Stage__c FROM PC1_Application__c WHERE Id = :applicationId LIMIT 1];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found.');
        if (!CALLABLE_STAGES.contains(apps[0].Stage__c)) {
            throw new AuraHandledException('Call Now is only for clients still giving their details. This application is at "'
                + apps[0].Stage__c + '".');
        }

        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Heroku_Internal_Token__c);
        if (String.isBlank(base) || String.isBlank(token)) {
            throw new AuraHandledException('PC1_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c');
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
            throw new AuraHandledException('Callout failed: ' + e.getMessage());
        }

        Integer code = res.getStatusCode();
        if (code != 200 && code != 202) {
            throw new AuraHandledException('Heroku returned HTTP ' + code + ': ' + res.getBody());
        }
        return res.getBody();
    }
}