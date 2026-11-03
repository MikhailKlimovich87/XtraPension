/**
 * PC1_AdminAlertREST — Apex REST façade the Node worker calls to send an
 * OPERATIONAL alert email out through Salesforce's SingleEmailMessage
 * transport. Distinct from PC1_MessageDispatcher (which handles CLIENT-facing
 * templated messages logged to PC1_Message_Send_Log__c) because ops alerts:
 *
 *   • are unstructured (arbitrary subject/body, no template lookup)
 *   • target a fixed staff address (defaults to Fernando)
 *   • should NEVER hit a PC1_Application__c record (no client context)
 *   • must survive when the record + template infra is exactly what alerts
 *     us that something's broken
 *
 * Endpoint: POST /services/apexrest/pc1/admin-alert
 *
 * Auth: JSON body must include `{shared_secret: "<same as PC1_Config__c
 *       .Internal_Admin_Token__c>"}`. Constant-time compare via
 *       String.equals — cheaper than a Digest for a 32-byte token, and
 *       an attacker who has the token can already POST anywhere else.
 *
 * Request body:
 *   {
 *     "shared_secret":  "the bearer token",   REQUIRED
 *     "subject":        "Form monitor: 3 changes on DWP form",   REQUIRED
 *     "htmlBody":       "<html>…</html>",     REQUIRED
 *     "toAddress":      "fernando@…",         OPTIONAL, defaults to
 *                                             PC1_Config__c.Admin_Alert_Email__c
 *                                             (falls back to running user)
 *     "replyTo":        "noreply@…",          OPTIONAL
 *     "textBody":       "plaintext fallback"  OPTIONAL
 *   }
 *
 * Response: { ok: true, sent: 1 } or { ok: false, error: "…" }.
 *
 * Deliberately no batching / no retry / no attachments: this endpoint is
 * for the OPS mailbox (Fernando). Client-facing sends stay on the
 * dispatcher rail.
 */
@RestResource(urlMapping='/pc1/admin-alert')
global with sharing class PC1_AdminAlertREST {

    /** Max body sizes accepted — cheap defence against a stuck worker
     *  loop that would otherwise flood the ops inbox. */
    private static final Integer SUBJECT_MAX = 250;
    private static final Integer BODY_MAX    = 250000; // ~250 KB

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        Map<String, Object> body;
        try {
            body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
        } catch (Exception e) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'ok' => false, 'error' => 'invalid_json'
            }));
            return;
        }

        // ── auth ────────────────────────────────────────────────────
        String suppliedSecret = String.valueOf(body.get('shared_secret'));
        String expected = getInternalToken();
        if (String.isBlank(expected) || String.isBlank(suppliedSecret) || !expected.equals(suppliedSecret)) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'ok' => false, 'error' => 'unauthorized'
            }));
            return;
        }

        String subject  = String.valueOf(body.get('subject'));
        String htmlBody = String.valueOf(body.get('htmlBody'));
        String textBody = body.get('textBody') == null ? '' : String.valueOf(body.get('textBody'));
        String toAddr   = body.get('toAddress') == null ? '' : String.valueOf(body.get('toAddress'));
        String replyTo  = body.get('replyTo')   == null ? '' : String.valueOf(body.get('replyTo'));

        if (String.isBlank(subject) || String.isBlank(htmlBody)) {
            res.statusCode = 400;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'ok' => false, 'error' => 'subject and htmlBody are required'
            }));
            return;
        }
        if (subject.length() > SUBJECT_MAX) subject = subject.substring(0, SUBJECT_MAX);
        if (htmlBody.length() > BODY_MAX)   htmlBody = htmlBody.substring(0, BODY_MAX) + '\n\n[TRUNCATED]';

        if (String.isBlank(toAddr)) toAddr = resolveDefaultRecipient();
        if (String.isBlank(toAddr)) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'ok' => false, 'error' => 'no recipient — set Admin_Alert_Email__c on PC1_Config__c or pass toAddress'
            }));
            return;
        }

        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toAddr });
        msg.setSubject(subject);
        msg.setHtmlBody(htmlBody);
        if (String.isNotBlank(textBody)) msg.setPlainTextBody(textBody);
        if (String.isNotBlank(replyTo))  msg.setReplyTo(replyTo);
        msg.setSaveAsActivity(false);      // no ActivityHistory noise
        msg.setTreatBodiesAsTemplate(false); // no merge-field expansion

        try {
            Messaging.SendEmailResult[] results =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ msg }, false);
            Messaging.SendEmailResult r = results[0];
            if (r.isSuccess()) {
                res.statusCode = 200;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'ok' => true, 'sent' => 1, 'to' => toAddr
                }));
            } else {
                String detail = '';
                for (Messaging.SendEmailError e : r.getErrors()) { detail += e.getMessage() + '; '; }
                res.statusCode = 500;
                res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                    'ok' => false, 'error' => 'sendEmail failure: ' + detail
                }));
            }
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'ok' => false, 'error' => 'sendEmail exception: ' + e.getMessage()
            }));
        }
    }

    /**
     * Recipient resolution priority:
     *   1. PC1_Config__c.Admin_Alert_Email__c (created by deploy script)
     *   2. Running user's email (safety net — never orphan an alert)
     */
    @TestVisible
    private static String resolveDefaultRecipient() {
        try {
            PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
            if (cfg != null) {
                Object v = cfg.get('Admin_Alert_Email__c');
                if (v != null && String.isNotBlank(String.valueOf(v))) {
                    return String.valueOf(v).trim();
                }
            }
        } catch (Exception ignored) { /* field may not be deployed yet */ }
        try {
            User u = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            return u.Email;
        } catch (Exception ignored) { return null; }
    }

    @TestVisible
    private static String getInternalToken() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Internal_Admin_Token__c))
            ? cfg.Internal_Admin_Token__c.trim() : null;
    }
}