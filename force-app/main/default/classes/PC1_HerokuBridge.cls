/**
 * PC1_HerokuBridge — kicks off a Fill Run on the Heroku worker.
 *
 * Invoked from:
 *   • Record-page "Fill on DWP" quick action (Flow -> Apex Action)
 *   • Flows / process automations that need to fire a fill programmatically
 *   • Apex tests / manual anonymous execution (call startFill directly)
 *
 * The Heroku endpoint returns 202 with the new Fill_Run__c Id — the record
 * is created ON THE HEROKU SIDE via jsforce so this Apex never touches
 * PC1_Fill_Run__c itself. If the callout fails we surface the error so the
 * UI can show it; no half-baked local Fill Run row is left behind.
 *
 * Auth is the shared secret in PC1_Config__c.Heroku_Internal_Token__c,
 * matched against HEROKU_INTERNAL_TOKEN on the Heroku app. Remote Site
 * Setting PC1_Heroku_Autofill must whitelist the base URL.
 */
public with sharing class PC1_HerokuBridge {

    @InvocableMethod(
        label='PC1 · Start Fill on DWP'
        description='POSTs /internal/fill/{appId} on the Heroku worker. Returns run_id + HTTP status.'
    )
    public static List<StartResult> startFill(List<Id> appIds) {
        return startFill(appIds, false);
    }
    public static List<StartResult> startFill(List<Id> appIds, Boolean force) {
        List<StartResult> out = new List<StartResult>();
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Heroku_Internal_Token__c);

        for (Id appId : appIds) {
            StartResult r = new StartResult();
            r.applicationId = appId;

            if (String.isBlank(base) || String.isBlank(token)) {
                r.success = false;
                r.errorMessage = 'PC1_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c';
                out.add(r); continue;
            }

            // Trim any trailing slash so we produce a canonical `${base}/internal/fill/${id}`
            String url = base.removeEnd('/') + '/internal/fill/' + appId;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('X-Heroku-Token', token);
            // Empty body preserves existing contract; force=true switches
            // to a JSON body the server reads and uses to skip the mandate
            // gate. Hard gates (DWP_Reference, fill_in_progress) still fire.
            req.setBody(force == true ? '{"force":true}' : '{}');
            // Heroku's edge closes idle sockets around 30s; the fill endpoint
            // itself is fire-and-forget (spawns worker + 202) so <5s is normal.
            // Give ourselves 30s for cold dyno spin-up.
            req.setTimeout(30000);

            HttpResponse res;
            try {
                res = new Http().send(req);
            } catch (Exception e) {
                r.success = false;
                r.errorMessage = 'Callout failed: ' + e.getMessage();
                out.add(r); continue;
            }

            r.statusCode = res.getStatusCode();
            r.responseBody = res.getBody();
            r.success = (r.statusCode == 202);
            if (r.success && String.isNotBlank(r.responseBody)) {
                try {
                    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(r.responseBody);
                    Object run = parsed.get('run_id');
                    if (run != null) r.runId = String.valueOf(run);
                } catch (Exception ignore) { /* body wasn't JSON — leave runId null */ }
            } else if (!r.success) {
                r.errorMessage = 'Heroku returned HTTP ' + r.statusCode + ': ' + r.responseBody;
            }
            out.add(r);
        }
        return out;
    }

    /**
     * startFillFromUi — @AuraEnabled wrapper around the invocable startFill
     * for the record-page header button. `testMode` is advisory for now: the
     * Heroku worker always runs with AUTO_SUBMIT disabled, so every fill is a
     * test fill. The flag is part of the signature so the UI contract holds
     * when live submits are eventually enabled server-side.
     * Returns the Heroku run_id (may be null if the body wasn't JSON).
     */
    @AuraEnabled
    public static String startFillFromUi(Id applicationId, Boolean testMode, Boolean force) {
        if (applicationId == null) throw new AuraHandledException('applicationId is required');
        Boolean forceRun = force == true;
        // Declaration signing check — unless the caller passes force=true.
        // The Force path exists for testing / manual override on
        // demonstrably-unsubmittable applications (mandate not yet at
        // Bacs, waiting for cross-signed declaration, etc). Server-side
        // idempotency guards (DWP_Reference, in-flight run) are still
        // enforced regardless.
        List<PC1_Application__c> apps = [
            SELECT Id, Declaration_Complete__c
              FROM PC1_Application__c
             WHERE Id = :applicationId
             LIMIT 1
        ];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found');
        if (apps[0].Declaration_Complete__c != true && !forceRun) {
            throw new AuraHandledException(
                'Declaration is not complete. Fill in Signature, Signatory Name and Date on the declaration before running Fill on DWP. (Use the Force option to override for testing.)'
            );
        }
        List<StartResult> results = startFill(new List<Id>{ applicationId }, forceRun);
        StartResult r = results[0];
        if (r.success != true) {
            // 2026-08-27: rewrite server-side gate errors into human sentences
            // so the LWC toast reads clearly instead of dumping raw JSON.
            String msg = String.isNotBlank(r.errorMessage) ? r.errorMessage : ('Fill failed (HTTP ' + r.statusCode + ')');
            String friendly = null;
            try {
                if (String.isNotBlank(r.responseBody)) {
                    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(r.responseBody);
                    String errCode = (String) body.get('error');
                    if (errCode == 'dd_mandate_not_active') {
                        friendly = 'Direct Debit mandate is not active yet. ' +
                            'DWP submit is blocked until Bacs confirms the mandate (usually 2–3 business days after the client signed). ' +
                            'Current mandate status: ' + String.valueOf(body.get('dd_mandate_status'));
                    } else if (errCode == 'already_submitted') {
                        friendly = 'This application already has a DWP reference (' + String.valueOf(body.get('dwp_reference')) +
                            '). Clear DWP_Reference__c on the record if you deliberately want to resubmit.';
                    } else if (errCode == 'application_not_found') {
                        friendly = 'Application not found on the Heroku worker — refresh the page and try again.';
                    } else if (errCode == 'fill_already_running') {
                        friendly = 'A fill run is already in progress for this application. Wait for it to finish (usually 2–3 minutes) then try again.';
                    } else if (errCode == 'unauthorized') {
                        friendly = 'The Heroku worker refused the request — token mismatch. Check PC1_Config__c.Heroku_Internal_Token__c.';
                    } else if (String.isNotBlank(errCode)) {
                        friendly = 'Fill blocked: ' + errCode + '. ' + String.valueOf(body.get('hint'));
                    }
                }
            } catch (Exception ignore) { /* body wasn't parseable JSON — leave as-is */ }
            throw new AuraHandledException(friendly != null ? friendly : msg);
        }
        return r.runId;
    }

    public class StartResult {
        @InvocableVariable public Id applicationId;
        @InvocableVariable public Boolean success;
        @InvocableVariable public Integer statusCode;
        @InvocableVariable public String responseBody;
        @InvocableVariable public String runId;
        @InvocableVariable public String errorMessage;
    }
}