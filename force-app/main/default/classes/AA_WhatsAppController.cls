/**
 * AA_WhatsAppController — LWC-facing @AuraEnabled proxy to the Heroku
 * WhatsApp endpoints (which in turn talk to Timelines AI). Also reads the
 * mirror table AA_WA_Message__c for offline availability.
 *
 * The LWC (aaWhatsAppPanel) calls these three methods:
 *   getThread(applicationId)     — returns { chat, messages, optIn, ... }
 *   sendMessage(applicationId, body)
 *   setOptIn(applicationId, granted) — for ops to grant/revoke manually
 *
 * Auth pattern mirrors AA_HerokuBridge: base URL + token from
 * AA_Config__c.Heroku_Base_Url__c / Heroku_Internal_Token__c. Remote Site
 * Setting AA_Heroku_Autofill whitelists the base.
 */
public with sharing class AA_WhatsAppController {

    private static final Integer CALLOUT_TIMEOUT_MS = 15000;

    /** Return everything the LWC needs to render the chat panel. */
    @AuraEnabled(cacheable=false)
    public static ThreadPayload getThread(Id applicationId) {
        Map<String, Object> body = new Map<String, Object>{ 'appId' => (String) applicationId };
        Map<String, Object> resp = callHeroku('/internal/whatsapp/thread', body);
        ThreadPayload out = new ThreadPayload();
        out.status    = (String) resp.get('status');
        out.chat      = (Map<String, Object>) resp.get('chat');
        out.messages  = (List<Object>) resp.get('messages');
        out.optIn     = (Boolean) resp.get('optIn') == true;
        out.appPhone  = (String) resp.get('appPhone');
        out.fullName  = (String) resp.get('fullName');
        return out;
    }

    /** Send a file already uploaded to SF (ContentVersion) — used for both
     *  the "upload from computer" flow (lightning-file-upload wrote a new CV
     *  first) AND the "attach existing SF file" picker. Caption optional. */
    @AuraEnabled(cacheable=false)
    public static SendResult sendFileMessage(Id applicationId, Id contentVersionId, String caption) {
        if (contentVersionId == null) throw new AuraHandledException('contentVersionId required');
        assertContactable(applicationId);
        Map<String, Object> body = new Map<String, Object>{
            'appId'            => (String) applicationId,
            'contentVersionId' => (String) contentVersionId,
            'caption'          => caption,
            'sfUser'           => UserInfo.getName() + ' <' + UserInfo.getUserEmail() + '>'
        };
        Map<String, Object> resp = callHeroku('/internal/whatsapp/send-file', body);
        SendResult r = new SendResult();
        r.status = (String) resp.get('status');
        Map<String, Object> msg = (Map<String, Object>) resp.get('message');
        r.uid = msg == null ? null : (String) (msg.get('uid') != null ? msg.get('uid') : msg.get('message_uid'));
        return r;
    }

    /** Send a file selected via the LWC's native file input (bytes arrive as
     *  base64 through Apex). Bypasses SF ContentDocument creation — good for
     *  quick sends where audit-trail isn't needed. */
    @AuraEnabled(cacheable=false)
    public static SendResult sendFileFromBrowser(Id applicationId, String filename, String mime, String base64Body, String caption) {
        if (String.isBlank(base64Body)) throw new AuraHandledException('base64Body required');
        assertContactable(applicationId);
        Map<String, Object> body = new Map<String, Object>{
            'appId'      => (String) applicationId,
            'filename'   => filename,
            'mime'       => mime,
            'base64Body' => base64Body,
            'caption'    => caption,
            'sfUser'     => UserInfo.getName() + ' <' + UserInfo.getUserEmail() + '>'
        };
        Map<String, Object> resp = callHeroku('/internal/whatsapp/send-file-inline', body);
        SendResult r = new SendResult();
        r.status = (String) resp.get('status');
        Map<String, Object> msg = (Map<String, Object>) resp.get('message');
        r.uid = msg == null ? null : (String) (msg.get('uid') != null ? msg.get('uid') : msg.get('message_uid'));
        return r;
    }

    // sendVoiceNote removed 2026-07-31 — Timelines/WA cross-decoder unreliable.

    /** List all files (ContentVersion latest version per ContentDocument)
     *  linked to a AA_Application — powers the "Attach from SF Files"
     *  picker in the WA panel. */
    @AuraEnabled(cacheable=true)
    public static List<FileRow> listApplicationFiles(Id applicationId) {
        // Two-step: ContentDocumentLinks → ContentVersions of the LatestPublished.
        List<Id> docIds = new List<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId
        ]) docIds.add(cdl.ContentDocumentId);
        if (docIds.isEmpty()) return new List<FileRow>();
        List<FileRow> out = new List<FileRow>();
        for (ContentVersion cv : [
            SELECT Id, Title, PathOnClient, FileType, ContentSize, CreatedDate, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
            ORDER BY CreatedDate DESC
        ]) {
            FileRow r = new FileRow();
            r.contentVersionId = cv.Id;
            r.title            = cv.Title;
            r.filename         = cv.PathOnClient;
            r.fileType         = cv.FileType;
            r.size             = cv.ContentSize;
            r.createdAt        = cv.CreatedDate;
            out.add(r);
        }
        return out;
    }
    public class FileRow {
        @AuraEnabled public String   contentVersionId;
        @AuraEnabled public String   title;
        @AuraEnabled public String   filename;
        @AuraEnabled public String   fileType;
        @AuraEnabled public Integer  size;
        @AuraEnabled public Datetime createdAt;
    }

    /** Send a text message. Returns the Timelines uid + status. */
    @AuraEnabled(cacheable=false)
    public static SendResult sendMessage(Id applicationId, String messageBody) {
        if (String.isBlank(messageBody)) throw new AuraHandledException('Message body is empty.');
        assertContactable(applicationId);
        Map<String, Object> body = new Map<String, Object>{
            'appId'  => (String) applicationId,
            'body'   => messageBody,
            'sfUser' => UserInfo.getName() + ' <' + UserInfo.getUserEmail() + '>'
        };
        Map<String, Object> resp = callHeroku('/internal/whatsapp/send', body);
        SendResult r = new SendResult();
        r.status  = (String) resp.get('status');
        Map<String, Object> msg = (Map<String, Object>) resp.get('message');
        r.uid     = msg == null ? null : (String) msg.get('uid');
        r.sfRowId = (String) resp.get('sfRowId');
        return r;
    }

    /** Flip the opt-in checkbox from the LWC (ops has confirmed by phone). */
    @AuraEnabled
    public static void setOptIn(Id applicationId, Boolean granted) {
        AA_Application__c app = new AA_Application__c(
            Id = applicationId,
            WhatsApp_OptIn__c    = granted == true,
            WhatsApp_OptIn_At__c = granted == true ? System.now() : null
        );
        update app;
    }

    /** Fallback for the LWC when the Heroku endpoint is unreachable — reads
     *  the SF mirror directly. Chronological asc, capped 200 rows. */
    @AuraEnabled(cacheable=true)
    public static List<AA_WA_Message__c> getMirroredThread(Id applicationId) {
        return [
            SELECT Id, Name, External_Id__c, Direction__c, Body__c,
                   Sent_At__c, Delivered_At__c, Read_At__c, Status__c,
                   From_Phone__c, To_Phone__c, Sender_Name__c,
                   Attachment_URL__c, Attachment_Filename__c
            FROM AA_WA_Message__c
            WHERE Application__c = :applicationId
            ORDER BY Sent_At__c ASC NULLS FIRST
            LIMIT 200
        ];
    }

    // ─────────────────────────── plumbing ──────────────────────────────

    /**
     * Refuse every outbound WhatsApp to a Do_Not_Contact__c client before the
     * callout (audit 2026-10-02 F54). Heroku (src/webhooks/whatsapp.js)
     * enforces the same rule; this gives the operator the reason without a
     * round-trip and keeps the guard if the Heroku check is ever bypassed.
     */
    @TestVisible
    private static void assertContactable(Id applicationId) {
        List<AA_Application__c> apps = [
            SELECT Do_Not_Contact__c FROM AA_Application__c WHERE Id = :applicationId LIMIT 1
        ];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found.');
        if (apps[0].Do_Not_Contact__c == true) {
            throw new AuraHandledException('This client is marked Do Not Contact. WhatsApp is blocked; speak to a supervisor before contacting them.');
        }
    }

    private static Map<String, Object> callHeroku(String path, Map<String, Object> body) {
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Heroku_Internal_Token__c);
        if (String.isBlank(base) || String.isBlank(token)) {
            throw new AuraHandledException('AA_Config__c is missing Heroku_Base_Url__c or Heroku_Internal_Token__c.');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base.removeEnd('/') + path);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Heroku-Token', token);
        req.setBody(JSON.serialize(body));
        req.setTimeout(CALLOUT_TIMEOUT_MS);

        HttpResponse resp;
        try { resp = new Http().send(req); }
        catch (Exception e) { throw new AuraHandledException('Heroku unreachable: ' + e.getMessage()); }

        Integer sc = resp.getStatusCode();
        String rawBody = resp.getBody();
        Map<String, Object> parsed = null;
        try { parsed = (Map<String, Object>) JSON.deserializeUntyped(rawBody); } catch (Exception e) {}

        if (sc < 200 || sc >= 300) {
            // Prefer the human-readable Timelines detail if present so the
            // LWC toast surfaces the real cause (e.g. "audio too short" or
            // "bad audio format") instead of the machine code.
            String errMsg = parsed != null && parsed.get('detail') != null
                ? String.valueOf(parsed.get('detail'))
                : parsed != null && parsed.get('msg') != null
                    ? String.valueOf(parsed.get('msg'))
                    : parsed != null && parsed.get('error') != null
                        ? String.valueOf(parsed.get('error'))
                        : 'HTTP ' + sc;
            throw new AuraHandledException(errMsg);
        }
        return parsed == null ? new Map<String, Object>() : parsed;
    }

    // ─────────────────────────── DTOs ──────────────────────────────

    public class ThreadPayload {
        @AuraEnabled public String status;
        @AuraEnabled public Map<String, Object> chat;
        @AuraEnabled public List<Object> messages;
        @AuraEnabled public Boolean optIn;
        @AuraEnabled public String appPhone;
        @AuraEnabled public String fullName;
    }
    public class SendResult {
        @AuraEnabled public String status;
        @AuraEnabled public String uid;
        @AuraEnabled public String sfRowId;
    }
}