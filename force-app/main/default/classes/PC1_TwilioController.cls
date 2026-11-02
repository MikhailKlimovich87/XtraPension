/**
 * PC1_TwilioController — LWC-facing @AuraEnabled proxy to the TwilioSF managed
 * package (Twilio for Salesforce v4.155). Powers pc1SmsPanel on the PC1
 * Application record page, right under pc1WhatsAppPanel.
 *
 * Send pattern: TwilioSF exposes NO global send class (TwilioSF.TwilioSendSMS
 * exists but is not `global`, so it's uncallable from packaged Apex). The
 * supported path is to insert a TwilioSF__Message__c with Direction =
 * 'outbound-api' — TwilioSF.MessageTrigger then dispatches to Twilio and
 * updates Status/Message_SID_c/Error_Code asynchronously (via
 * TwilioSF__Twilio_Message_Status__e platform event). Confirmed by describe:
 * that trigger is live on TwilioSF__Message__c in this org and historical
 * outbound-api rows exist with the same shape (2026-05..07 sends from
 * From_Number = "XtraPension").
 *
 * Thread read: no direct FK between TwilioSF__Message__c and
 * PC1_Application__c that we can trust for legacy data (the managed
 * Application__c reference points to a different "Application__c" object,
 * NOT PC1_Application__c). We stamp the parent id on
 * TwilioSF__SF_Parent_Record_Id__c when we send, and fall back to phone match
 * against PC1_Application.Phone__c so historical rows still surface.
 */
public with sharing class PC1_TwilioController {

    // 2026-08-01: 1-way SMS from UK long-code. Fernando's call after testing:
    // cross-border (US→IE) fails because Twilio Carrier substitutes the
    // account's alphanumeric "XtraPension" for IE, killing replies. Not worth
    // chasing — real clients are UK-based (99% of the pensioner base) and
    // UK-to-UK sends deliver + replies land back cleanly. Reply handling for
    // UK still works through /webhooks/twilio/inbound.
    @TestVisible private static final String DEFAULT_FROM = '+447476907490';

    // ─────────────────────────── read ──────────────────────────────
    /**
     * Thread payload = ordered list of message dicts + the E.164 phone we
     * used to look them up (so the UI can show a "no phone on file" placeholder
     * without a second round-trip). NOT cacheable — the panel polls every 30 s.
     */
    @AuraEnabled(cacheable=false)
    public static ThreadPayload getThread(Id recordId) {
        ThreadPayload out = new ThreadPayload();
        out.messages = new List<MessageRow>();

        PC1_Application__c app;
        try {
            app = [
                SELECT Id, Phone__c, Full_Name__c
                FROM PC1_Application__c
                WHERE Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Application not found.');
        }
        out.appPhone = app.Phone__c;
        out.fullName = app.Full_Name__c;

        if (String.isBlank(app.Phone__c) && recordId == null) return out;

        // Match on parent-id stamp OR either phone slot. Historical rows only
        // have the phone match; new rows will match both. Dynamic SOQL because
        // the phone clause has to disappear when no phone is on file (can't
        // gate a SOQL predicate on an Apex expression like String.isNotBlank).
        String phone = app.Phone__c;
        String appIdStr = String.valueOf(app.Id);
        String soql =
            'SELECT Id, TwilioSF__From_Number__c, TwilioSF__To_Number__c, '
          + '       TwilioSF__Body__c, TwilioSF__Status__c, '
          + '       TwilioSF__Direction__c, TwilioSF__Date_Sent__c, '
          + '       TwilioSF__Date_Created__c, TwilioSF__Error_Code__c, '
          + '       TwilioSF__Message_SID__c, TwilioSF__SF_Parent_Record_Id__c, '
          + '       TwilioSF__Recipient_Name__c, CreatedDate, CreatedBy.Name '
          + 'FROM TwilioSF__Message__c '
          + 'WHERE TwilioSF__SF_Parent_Record_Id__c = :appIdStr';
        if (String.isNotBlank(phone)) {
            soql += ' OR TwilioSF__To_Number__c = :phone OR TwilioSF__From_Number__c = :phone';
        }
        soql += ' ORDER BY CreatedDate ASC LIMIT 200';
        List<TwilioSF__Message__c> rows = Database.query(soql);
        for (TwilioSF__Message__c m : rows) {
            MessageRow r = new MessageRow();
            r.id           = m.Id;
            r.direction    = m.TwilioSF__Direction__c;   // 'outbound-api' | 'outbound-reply' | 'inbound' | 'outbound-call'
            r.isOutbound   = m.TwilioSF__Direction__c != null && m.TwilioSF__Direction__c.startsWith('outbound');
            r.body         = m.TwilioSF__Body__c;
            r.fromNumber   = m.TwilioSF__From_Number__c;
            r.toNumber     = m.TwilioSF__To_Number__c;
            r.status       = m.TwilioSF__Status__c;
            r.errorCode    = m.TwilioSF__Error_Code__c;
            r.messageSid   = m.TwilioSF__Message_SID__c;
            r.timestamp    = (m.TwilioSF__Date_Sent__c != null)
                             ? m.TwilioSF__Date_Sent__c
                             : (m.TwilioSF__Date_Created__c != null ? m.TwilioSF__Date_Created__c : m.CreatedDate);
            r.senderName   = m.CreatedBy != null ? m.CreatedBy.Name : null;
            r.recipientName= m.TwilioSF__Recipient_Name__c;
            out.messages.add(r);
        }
        return out;
    }

    // ─────────────────────────── send ──────────────────────────────
    /**
     * Insert TwilioSF__Message__c with Direction='outbound-api' + status='queued'
     * — TwilioSF.MessageTrigger picks it up and dispatches to Twilio. Returns
     * the new row Id so the LWC can reconcile the optimistic bubble.
     *
     * Throws AuraHandledException on validation issues (blank body, no phone,
     * DML failure). Twilio-side delivery failures show up asynchronously in
     * Status = 'failed' + Error_Code_c on the same row.
     */
    /**
     * Mirrors the working DwpEmailController.sendDWPsmsMessage flow used by
     * the Sales side: read credentials from XtraPension_Data__c custom setting
     * (Twilio_Account__c + Twilio_Token__c), call Twilio directly via the
     * TwilioSF.TwilioApiClient helper (which handles auth signing), then
     * insert TwilioSF__Message__c ourselves with the response payload.
     *
     * The TwilioSF managed package's own MessageTrigger dispatch path was
     * failing with 20003 (auth error) even after adding Fernando to the team
     * — because the managed package's stored credentials aren't the ones the
     * XtraPension Twilio account uses. Sales-side works by bypassing the
     * managed dispatcher entirely and calling Twilio direct.
     */
    @AuraEnabled(cacheable=false)
    public static Id sendSMS(Id recordId, String body) {
        if (String.isBlank(body)) {
            throw new AuraHandledException('Message body is empty.');
        }
        PC1_Application__c app;
        try {
            app = [
                SELECT Id, Phone__c, Full_Name__c, SMS_OptOut__c
                FROM PC1_Application__c
                WHERE Id = :recordId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Application not found.');
        }
        if (String.isBlank(app.Phone__c)) {
            throw new AuraHandledException('No phone number on this application.');
        }
        // PECR audit C3 R5 — client has opted out. ICO enforcement risk.
        if (app.SMS_OptOut__c == true) {
            throw new AuraHandledException(
                'This client has opted out of SMS (replied STOP). Cannot send. ' +
                'They must text START to re-subscribe.'
            );
        }

        // Same sandbox gate as the automatic dispatcher (2026-10-02 audit):
        // the manual SMS panel called Twilio directly and could text a real
        // client from the sandbox.
        if (!PC1_SendGate.allowSms(app.Phone__c)) {
            throw new AuraHandledException(PC1_SendGate.blockReason(app.Phone__c));
        }

        XtraPension_Data__c xpd = XtraPension_Data__c.getInstance();
        String acct  = xpd != null ? xpd.Twilio_Account__c : null;
        String token = xpd != null ? xpd.Twilio_Token__c   : null;
        if (String.isBlank(acct) || String.isBlank(token)) {
            throw new AuraHandledException('Twilio Account SID/Token not configured in XtraPension_Data__c custom setting.');
        }

        // Direct HTTP callout — bypasses TwilioSF.TwilioApiClient because
        // that helper reads its Auth Token from the managed-package's own
        // internal config (which has been stale since March 2026 — same
        // reason the Sales-side DwpEmailController.sendDWPsmsMessage has
        // been failing with 20003 for months). Basic Auth = base64(SID:TOKEN).
        String messageSid, status, toResp, fromResp, bodyResp;
        {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.twilio.com/2010-04-01/Accounts/' + acct + '/Messages.json');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(acct + ':' + token)));
            req.setTimeout(10000);
            // StatusCallback tells Twilio to POST every state change
            // (queued/sending/sent/delivered/failed) back to our Heroku
            // endpoint, which updates Status on the TwilioSF__Message__c
            // row so the pc1SmsPanel UI can show ✓ → ✓✓ in real time.
            String cbUrl = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com/webhooks/twilio/status';
            String reqBody =
                'From=' + EncodingUtil.urlEncode(DEFAULT_FROM, 'UTF-8')
              + '&To=' + EncodingUtil.urlEncode(app.Phone__c, 'UTF-8')
              + '&Body=' + EncodingUtil.urlEncode(body, 'UTF-8')
              + '&StatusCallback=' + EncodingUtil.urlEncode(cbUrl, 'UTF-8');
            req.setBody(reqBody);

            HttpResponse resp;
            try { resp = new Http().send(req); }
            catch (Exception e) { throw new AuraHandledException('Twilio unreachable: ' + e.getMessage()); }

            if (resp.getStatusCode() < 200 || resp.getStatusCode() >= 300) {
                // Try to surface Twilio's `message` field from the JSON body.
                String errDetail = '';
                try {
                    Map<String, Object> em = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                    errDetail = ' — ' + String.valueOf(em.get('message'));
                } catch (Exception ignored) {}
                throw new AuraHandledException('Twilio rejected the send (HTTP ' + resp.getStatusCode() + ')' + errDetail);
            }

            Map<String, Object> data;
            try { data = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody()); }
            catch (Exception e) { throw new AuraHandledException('Twilio returned non-JSON'); }

            messageSid = (String) data.get('sid');
            status     = (String) data.get('status');
            toResp     = (String) data.get('to');
            fromResp   = (String) data.get('from');
            bodyResp   = (String) data.get('body');
        }

        // Log the actual Twilio response — Message SID is now real, no more
        // waiting for MessageTrigger to fill it in.
        TwilioSF__Message__c m = new TwilioSF__Message__c(
            TwilioSF__From_Number__c         = fromResp,
            TwilioSF__To_Number__c           = toResp,
            TwilioSF__Body__c                = bodyResp,
            TwilioSF__Direction__c           = 'outbound-api',
            TwilioSF__Status__c              = status,          // 'queued'|'accepted'|'sending'
            TwilioSF__Message_SID__c         = messageSid,
            TwilioSF__Date_Sent__c           = Datetime.now(),
            TwilioSF__SF_Parent_Record_Id__c = String.valueOf(app.Id),
            TwilioSF__Recipient_Name__c      = app.Full_Name__c
        );
        try {
            insert m;
        } catch (DmlException e) {
            // Twilio already accepted the send — logging failed but message went.
            throw new AuraHandledException('Sent to Twilio but log insert failed: ' + e.getDmlMessage(0));
        }

        // ── Last Contact mirror. SMS sends do NOT create a PC1_Call_Log__c,
        //    so we bump the Application's Last_Contact_* fields directly.
        //    Who = full UserInfo.getName() now that the picklist is
        //    unrestricted (2026-08-01) — Fernando wants the actual SF user.
        try {
            Datetime now = Datetime.now();
            PC1_Application__c cur = [
                SELECT Id, Last_Contact_At__c FROM PC1_Application__c WHERE Id = :recordId LIMIT 1
            ];
            if (cur.Last_Contact_At__c == null || cur.Last_Contact_At__c < now) {
                update new PC1_Application__c(
                    Id                    = recordId,
                    Last_Contact_Type__c  = 'SMS Sent',
                    Last_Contact_Who__c   = UserInfo.getName(),
                    Last_Contact_At__c    = now,
                    Last_Contact_Date__c  = now.date()
                );
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'SMS last-contact bump failure: ' + e.getMessage());
        }

        return m.Id;
    }

    // ─────────────────────────── DTOs ──────────────────────────────
    public class ThreadPayload {
        @AuraEnabled public String appPhone;
        @AuraEnabled public String fullName;
        @AuraEnabled public List<MessageRow> messages;
    }
    public class MessageRow {
        @AuraEnabled public String   id;
        @AuraEnabled public String   direction;
        @AuraEnabled public Boolean  isOutbound;
        @AuraEnabled public String   body;
        @AuraEnabled public String   fromNumber;
        @AuraEnabled public String   toNumber;
        @AuraEnabled public String   status;
        @AuraEnabled public String   errorCode;
        @AuraEnabled public String   messageSid;
        @AuraEnabled public Datetime timestamp;
        @AuraEnabled public String   senderName;
        @AuraEnabled public String   recipientName;
    }
}