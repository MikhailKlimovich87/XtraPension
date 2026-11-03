/**
 * AA_HerokuBridge — kicks off a Fill Run on the Heroku worker.
 *
 * Invoked from:
 *   • Record-page "Fill on DWP" quick action (Flow -> Apex Action)
 *   • Flows / process automations that need to fire a fill programmatically
 *   • Apex tests / manual anonymous execution (call startFill directly)
 *
 * The Heroku endpoint returns 202 with the new Fill_Run__c Id — the record
 * is created ON THE HEROKU SIDE via jsforce so this Apex never touches
 * AA_Fill_Run__c itself. If the callout fails we surface the error so the
 * UI can show it; no half-baked local Fill Run row is left behind.
 *
 * Auth is the shared secret in AA_Config__c.Heroku_Internal_Token__c,
 * matched against HEROKU_INTERNAL_TOKEN on the Heroku app. Remote Site
 * Setting AA_Heroku_Autofill must whitelist the base URL.
 */
public with sharing class AA_HerokuBridge {

    /**
     * Stages from which Fill on DWP may start (audit 2026-10-02 F142). Same
     * list as FILL_STAGES in src/webhooks/internal.js and the LWC gates; the
     * Heroku endpoint enforces it too, so automated callers are covered.
     */
    public static final Set<String> FILL_STAGES = new Set<String>{
        'Data Complete', 'Ready for Review', 'Reviewed', 'Awaiting Bank Details',
        'Filling', 'Ready for Submit', 'Special Rules Fast-Track'
    };

    @InvocableMethod(
        label='AA · Start Fill on DWP'
        description='POSTs /internal/fill/{appId} on the Heroku worker. Returns run_id + HTTP status.'
    )
    public static List<StartResult> startFill(List<Id> appIds) {
        List<StartResult> out = new List<StartResult>();
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Heroku_Internal_Token__c);

        for (Id appId : appIds) {
            StartResult r = new StartResult();
            r.applicationId = appId;

            if (String.isBlank(base) || String.isBlank(token)) {
                r.success = false;
                r.errorMessage = 'AA_Config__c missing Heroku_Base_Url__c or Heroku_Internal_Token__c';
                out.add(r); continue;
            }

            // Trim any trailing slash so we produce a canonical `${base}/internal/fill/${id}`
            String url = base.removeEnd('/') + '/internal/fill/' + appId;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(url);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('X-Heroku-Token', token);
            req.setBody('{}');
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
                r.errorMessage = friendlyError(r.statusCode, r.responseBody);
            }
            out.add(r);
        }
        return out;
    }

    /**
     * startFillFromUi — @AuraEnabled wrapper around the invocable startFill
     * for the record-page header button. `testMode` is advisory and ignored:
     * the Heroku worker never submits (AUTO_SUBMIT off + canary lock). Every
     * fill stops at the Declaration in a hosted live view where a human
     * reviews and submits. The flag stays in the signature for the UI contract.
     * Returns the Heroku run_id (may be null if the body wasn't JSON).
     */
    @AuraEnabled
    public static String startFillFromUi(Id applicationId, Boolean testMode) {
        if (applicationId == null) throw new AuraHandledException('applicationId is required');
        // Declaration must be signed manually before Fill DWP — the 3
        // declaration fields (decl checkbox + declname + decldate triplet)
        // are outside Mary's scope on purpose. Blocking here so the button
        // can't accidentally kick off a fill on an unsigned application.
        List<AA_Application__c> apps = [
            SELECT Id, Declaration_Complete__c, Stage__c
              FROM AA_Application__c
             WHERE Id = :applicationId
             LIMIT 1
        ];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found');
        if (!FILL_STAGES.contains(apps[0].Stage__c)) {
            throw new AuraHandledException(
                'Fill on DWP is not available at stage "' + apps[0].Stage__c + '". It can run from: '
                + String.join(new List<String>(FILL_STAGES), ', ') + '.'
            );
        }
        if (apps[0].Declaration_Complete__c != true) {
            throw new AuraHandledException(
                'Declaration is not complete. Fill in Signature, Signatory Name and Date on the declaration before running Fill on DWP.'
            );
        }
        List<StartResult> results = startFill(new List<Id>{ applicationId });
        StartResult r = results[0];
        if (r.success != true) {
            throw new AuraHandledException(
                String.isNotBlank(r.errorMessage) ? r.errorMessage : ('Fill failed (HTTP ' + r.statusCode + ')')
            );
        }
        return r.runId;
    }

    /**
     * Turn a non-202 Heroku reply into a sentence an operator can act on. The
     * raw "Heroku returned HTTP 409: {json}" used to reach the toast verbatim
     * (audit 2026-10-02 F56/F149). Unknown shapes keep the raw text.
     */
    @TestVisible
    private static String friendlyError(Integer statusCode, String body) {
        String code;
        String hintText;
        String mandateStatus;
        try {
            Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
            code = (String) m.get('error');
            hintText = (String) m.get('hint');
            mandateStatus = m.get('dd_mandate_status') == null ? null : String.valueOf(m.get('dd_mandate_status'));
        } catch (Exception ignore) { /* not JSON */ }
        if (code == 'dd_mandate_not_active') {
            return 'The Direct Debit mandate is not active yet (status: ' + mandateStatus + '). '
                + 'The application is now in Awaiting Bank Details, and the fill starts automatically once GoCardless confirms the mandate.';
        }
        if (code == 'already_submitted') {
            return 'This application already has a DWP reference, so it was submitted before. '
                + 'Clear the DWP Reference field only if you really mean to submit it again.';
        }
        if (code == 'fill_in_progress') {
            return 'A fill is already running for this application. Wait for it to finish; the Latest Fill Run card updates every few seconds.';
        }
        if (code == 'review_session_open') {
            // The last fill's form may still be open for review (wave 2, W3).
            return String.isNotBlank(hintText) ? hintText
                : 'The form filled by the last run may still be open for review. Submit it there, or set Stage back to Reviewed to fill again.';
        }
        if (code == 'declaration_incomplete') {
            return 'Declaration is not complete. Fill in Signature, Signatory Name and Date on the declaration before running Fill on DWP.';
        }
        if (code == 'stage_not_fillable') {
            return String.isNotBlank(hintText) ? hintText : 'Fill on DWP is not available at this stage.';
        }
        if (code == 'application_not_found') {
            return 'The fill server could not find this application.';
        }
        if (statusCode == 401) {
            return 'The fill server rejected the request (check Heroku_Internal_Token__c in AA Config).';
        }
        if (String.isNotBlank(code)) {
            return 'Fill on DWP failed (' + code + ')' + (String.isNotBlank(hintText) ? ': ' + hintText : '.');
        }
        return 'Heroku returned HTTP ' + statusCode + ': ' + body;
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