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
    // Stages at which a fill may be started. The same list as FILL_READY_STAGES
    // in the pc1QuickActionFillOnDwp LWC: until 2026-11-11 the check lived in
    // the browser only, so the invocable (or any direct call) started the
    // engine on a New / Partial Data record (audit PC-SFUI-9). `force` does
    // not bypass it: Force is for the declaration and mandate gates.
    @TestVisible private static final Set<String> FILL_READY_STAGES = new Set<String>{
        'Data Complete', 'Reviewed', 'Filling', 'Ready for Submit', 'Submitted'
    };

    @TestVisible
    private static String stageRefusal(String stage) {
        return 'Fill on DWP is not available at stage "' + stage + '". The application must be at Data Complete, '
            + 'Reviewed, Filling, Ready for Submit or Submitted.';
    }

    public static List<StartResult> startFill(List<Id> appIds, Boolean force) {
        // Callers that do not say otherwise start a TEST run (the invocable
        // included): which callers may file a real claim is a go-live decision.
        return startFill(appIds, force, true);
    }

    /**
     * `testMode` is sent to Heroku on every request (audit 2026-11-11
     * PC-ENGINE-9). It used to be dropped here, so the worker could not tell
     * a test run from a real one. Anything but an explicit false is a test
     * run, and a test run or a forced run never presses Submit at DWP.
     */
    public static List<StartResult> startFill(List<Id> appIds, Boolean force, Boolean testMode) {
        List<StartResult> out = new List<StartResult>();
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Heroku_Internal_Token__c);
        Map<Id, PC1_Application__c> stageById = new Map<Id, PC1_Application__c>(
            [SELECT Id, Stage__c FROM PC1_Application__c WHERE Id IN :appIds]);

        for (Id appId : appIds) {
            StartResult r = new StartResult();
            r.applicationId = appId;

            if (String.isBlank(base) || String.isBlank(token)) {
                r.success = false;
                r.errorMessage = 'PC1_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c';
                out.add(r); continue;
            }
            PC1_Application__c known = stageById.get(appId);
            if (known != null && !FILL_READY_STAGES.contains(known.Stage__c)) {
                r.success = false;
                r.errorMessage = stageRefusal(known.Stage__c);
                out.add(r); continue;
            }

            // Trim any trailing slash so we produce a canonical `${base}/internal/fill/${id}`
            String url = base.removeEnd('/') + '/internal/fill/' + appId;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('X-Heroku-Token', token);
            // force=true lets the server skip the mandate / declaration
            // gates; the hard gates (DWP_Reference, fill_in_progress, stage)
            // still fire. Both keys are always sent.
            req.setBody(JSON.serialize(new Map<String, Object>{
                'force'    => (force == true),
                'testMode' => (testMode != false)
            }));
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
     * for the record-page header button. `testMode` is passed on to Heroku
     * and enforced by the worker: null or true is a test run (never submits
     * at DWP), only an explicit false can be a real one, and then only with
     * AUTO_SUBMIT, Auto_Submit_DWP__c and a signed declaration as well.
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
            SELECT Id, Declaration_Complete__c, Stage__c
              FROM PC1_Application__c
             WHERE Id = :applicationId
             LIMIT 1
        ];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found');
        if (!FILL_READY_STAGES.contains(apps[0].Stage__c)) {
            throw new AuraHandledException(stageRefusal(apps[0].Stage__c));
        }
        if (apps[0].Declaration_Complete__c != true && !forceRun) {
            throw new AuraHandledException(
                'Declaration is not complete. Fill in Signature, Signatory Name and Date on the declaration before running Fill on DWP. (Use the Force option to override for testing.)'
            );
        }
        List<StartResult> results = startFill(new List<Id>{ applicationId }, forceRun, testMode);
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
                    } else if (errCode == 'fill_in_progress' || errCode == 'fill_already_running') {
                        // Node sends fill_in_progress; the old name never matched
                        // (audit 2026-11-11 PC-NODE-18).
                        friendly = 'A fill run is already in progress for this application. Wait for it to finish (usually 2–3 minutes) then try again.';
                    } else if (errCode == 'unauthorized') {
                        friendly = 'The Heroku worker refused the request — token mismatch. Check PC1_Config__c.Heroku_Internal_Token__c.';
                    } else if (String.isNotBlank(errCode)) {
                        Object hintVal = body.get('hint');
                        friendly = 'Fill blocked: ' + errCode + '.' + (hintVal == null ? '' : ' ' + String.valueOf(hintVal));
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