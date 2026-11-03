/**
 * PC1_MessageDispatcher (B3) — message send engine for PC1_Message_Template__c.
 *
 * Two paths:
 *   dispatch(appId | Set<Id>, triggerEvent)  → enqueues a Queueable so trigger
 *                                              context (no callouts) can safely
 *                                              request sends.
 *   render(templateId, appId)                → sync render used by B2's preview
 *                                              LWC + by the Queueable itself.
 *                                              Throws AuraHandledException on
 *                                              any unknown {{Token}} so preview
 *                                              can red-flag pre-save.
 *
 * Schema alignment (B1-deployed field names, NOT the design-doc names):
 *   PC1_Message_Template__c: Subject_Template__c, Body_Template__c,
 *                            Attachment_Static_Resource_Name__c
 *   PC1_Message_Send_Log__c: Template__c, Application__c, Channel__c,
 *                            Sent_At__c, Status__c (Sent|Failed|Skipped-Deduped),
 *                            External_Id__c, Error_Message__c,
 *                            Rendered_Subject__c, Rendered_Body_Preview__c
 *
 * Send strategy:
 *   Email → Messaging.SingleEmailMessage, batched (single Messaging.sendEmail
 *           call per Queueable run). Optional StaticResource attachment.
 *   SMS   → direct Twilio HTTPS POST — mirrors PC1_TwilioController.sendSMS
 *           pattern (grep confirmed that is the ONLY outbound SMS path in the
 *           repo). Callout inlined here so we can defer TwilioSF__Message__c
 *           DML to the end of the Queueable transaction (satisfies the "no
 *           callouts after DML" governor rule when multiple SMS templates fire
 *           in one run). Reuses XtraPension_Data__c custom setting credentials.
 *
 * Governor plan: all SOQL up-front → all callouts → all DML.
 *
 * Dedup: skip (template, app) if PC1_Message_Send_Log__c has Status__c='Sent'
 * within the last 24 h. Guards against trigger re-fires on record recovery.
 */
public with sharing class PC1_MessageDispatcher implements Queueable, Database.AllowsCallouts {

    // ─── constants ──────────────────────────────────────────────────
    private static final String  SMS_FROM       = '+447476907490'; // parity with PC1_TwilioController
    private static final String  TWILIO_ENDPOINT= 'https://api.twilio.com/2010-04-01/Accounts/';
    private static final String  STATUS_CB      = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com/webhooks/twilio/status';
    private static final Integer DEDUP_HOURS    = 24;
    private static final String  TZ_UK          = 'Europe/London';
    // Audit R9-CRIT#2 — chunk size for the execute() loop. Apex sync callout
    // limit is 100 per tx (Queueable has its own tx). Worst case is 3 active
    // SMS templates per trigger × N apps = 3N callouts; capping N at 25
    // leaves ~25 callouts of headroom. Also caps loadAppFiles heap growth
    // (audit HIGH #7). Apps above the cap get self-chained as a follow-up.
    private static final Integer MAX_APPS_PER_EXECUTE = 25;

    // Audit R7-H4 — FeeInstallment token pre-fetch cache. Populated once
    // per execute() call so buildMergeMap doesn't do 2 SOQL per app in
    // the send loop (governor SOQL cap 200 async killed bulk dispatch).
    private static Map<Id, Integer> feeInstTotalCache = new Map<Id, Integer>();
    private static Map<Id, PC1_Fee_Installment__c> feeInstLatestCache = new Map<Id, PC1_Fee_Installment__c>();
    // The NEXT installment still to be collected, per app. The Bacs advance
    // notice is about that charge, so it needs that row's amount and date —
    // not the total fee and not the last paid installment.
    private static Map<Id, PC1_Fee_Installment__c> feeInstNextCache = new Map<Id, PC1_Fee_Installment__c>();

    // ─── queueable state ────────────────────────────────────────────
    private final Set<Id> appIds;
    private final String  triggerEvent;

    private PC1_MessageDispatcher(Set<Id> appIds, String triggerEvent) {
        this.appIds       = appIds;
        this.triggerEvent = triggerEvent;
    }

    // ═════════════════════════ HELPERS ══════════════════════════════

    /**
     * Fernando 2026-08-19: file naming convention across the org is
     * "{AppName}_{First}_{Last}_{DocType with spaces}" (example he showed:
     * PC00033_Fernando_Rampon_Pre Submit.pdf). Legacy titles like
     * "PC1_Welcome_Guide" get normalised to "Welcome Guide" (strip PC1_,
     * swap underscores for spaces) so template config values + StaticResource
     * DevNames don't have to change. Node-side twin lives in
     * src/webhooks/gocardless-internal.js.
     */
    @TestVisible
    private static String friendlyDocTitle(PC1_Application__c app, String rawDocType) {
        if (app == null || String.isBlank(rawDocType)) return rawDocType;
        String docType = rawDocType.startsWith('PC1_')
            ? rawDocType.substring(4).replace('_', ' ')
            : rawDocType;
        String first = String.isBlank(app.First_Name__c) ? '' : app.First_Name__c.trim();
        String last  = String.isBlank(app.Last_Name__c)  ? '' : app.Last_Name__c.trim();
        return app.Name + '_' + first + '_' + last + '_' + docType;
    }

    // ═════════════════════════ ENTRY POINTS ═════════════════════════

    /** Single-app convenience. Returns Queueable job Id, or null on no-op. */
    public static Id dispatch(Id appId, String triggerEvent) {
        if (appId == null) return null;
        return dispatch(new Set<Id>{ appId }, triggerEvent);
    }

    /**
     * Bulk dispatch — trigger.new goes in as one Queueable so bulk imports
     * don't blow the 50-async cap. From batch/future context we run
     * synchronously (enqueue would fail).
     */
    public static Id dispatch(Set<Id> appIds, String triggerEvent) {
        if (appIds == null || appIds.isEmpty() || String.isBlank(triggerEvent)) return null;
        PC1_MessageDispatcher job = new PC1_MessageDispatcher(appIds, triggerEvent);
        // Audit R9-batch-D — was "no extra enqueue allowed" from Future.
        // Actually System.enqueueJob IS legal from @future (limit 1). Prior
        // sync fallback ran the whole dispatcher (with SMS callouts) in
        // the future's own tx AFTER Phase-B DML in PC1_FeeInstallmentScheduler
        // → 'uncommitted work pending' on any SMS template attached to
        // Bacs_Advance_Notice. Latent bug (no SMS template today) but one
        // config away from silent Failed logs. Enqueue in @future too.
        // Batch context: enqueue is still allowed but only from start/execute
        // (not finish) and self-limits to 50; if we hit that limit, fall
        // back to sync + WARN.
        if (System.isBatch()) {
            try {
                return System.enqueueJob(job);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'PC1_MessageDispatcher: enqueueJob from Batch failed (' + e.getMessage() +
                    ') — running sync as fallback. May hit callout-after-DML.');
                job.execute(null);
                return null;
            }
        }
        return System.enqueueJob(job);
    }

    // ═════════════════════════ QUEUEABLE BODY ═══════════════════════

    public void execute(QueueableContext ctx) {
        if (appIds == null || appIds.isEmpty() || String.isBlank(triggerEvent)) return;

        // Audit R9-CRIT#2 + R9-batch-D residual (c) — dynamic chunk size
        // based on SMS-template count. Prior fixed cap 25 was safe for
        // ≤3 SMS templates (75 callouts vs 100 cap) but a 5th template
        // would push to 125 callouts → uncatchable. Now: query templates
        // first, compute effective chunk = floor(80 / smsTemplateCount),
        // minimum 5 (so we always make forward progress). Email-only
        // triggers get full 200-cap chunk (no callout budget concern).
        List<PC1_Message_Template__c> templatesForBudget = [
            SELECT Id, Channel__c, Attach_App_File_Titles__c FROM PC1_Message_Template__c
             WHERE Active__c = true AND Trigger_Event__c = :triggerEvent
        ];
        if (templatesForBudget.isEmpty()) return;
        Integer smsTplCount = 0;
        Boolean anyAttachmentTemplate = false;
        for (PC1_Message_Template__c t : templatesForBudget) {
            if ('SMS'.equalsIgnoreCase(t.Channel__c)) smsTplCount++;
            if (String.isNotBlank(t.Attach_App_File_Titles__c)) anyAttachmentTemplate = true;
        }
        Integer effectiveMax = smsTplCount == 0
            ? MAX_APPS_PER_EXECUTE
            : Math.max(5, Math.min(MAX_APPS_PER_EXECUTE, 80 / smsTplCount));
        // Audit R10-MED-5: attachment-carrying templates load ContentVersion
        // VersionData blobs into the async 12MB heap. 25 × 1MB welcome PDF +
        // base64 copies for emailBatch = uncatchable heap. Cap to 8 apps
        // when any template carries attachments — one-line safeguard until
        // per-app streaming refactor of loadAppFiles lands.
        if (anyAttachmentTemplate) effectiveMax = Math.min(effectiveMax, 8);

        Set<Id> thisChunk = new Set<Id>();
        Set<Id> remainder = new Set<Id>();
        for (Id id : appIds) {
            if (thisChunk.size() < effectiveMax) thisChunk.add(id);
            else remainder.add(id);
        }
        Boolean canChain = !System.isBatch() && !System.isFuture();
        // From Batch/Future, we can't System.enqueueJob — process everything
        // sync and warn. Upstream callers in those contexts should chunk.
        Set<Id> chunkIds = canChain ? thisChunk : appIds;
        if (!canChain && !remainder.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                'PC1_MessageDispatcher: oversized fire in Batch/Future context ' +
                '(' + appIds.size() + ' apps, threshold ' + effectiveMax +
                ', sms_templates=' + smsTplCount + ') — processing sync, may hit callout cap. Chunk upstream.');
        }


        // 1. Active templates for this event ─────────────────────────
        List<PC1_Message_Template__c> templates = [
            SELECT Id, Name, Channel__c, Trigger_Event__c,
                   Subject_Template__c, Body_Template__c,
                   Content_Text__c, Content_Mode__c,
                   Attachment_Static_Resource_Name__c,
                   Attach_App_File_Titles__c, Active__c
              FROM PC1_Message_Template__c
             WHERE Active__c = true
               AND Trigger_Event__c = :triggerEvent
        ];
        if (templates.isEmpty()) return;

        // 2. Apps ────────────────────────────────────────────────────
        Map<Id, PC1_Application__c> appMap = new Map<Id, PC1_Application__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c,
                   Email__c, Phone__c, SMS_OptOut__c, DWP_Reference__c,
                   Stage__c, Stage_Changed_At__c, Sales_Agent__c, Val_Agent__c,
                   DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c,
                   Helper_First_Name__c, Helper_Last_Name__c, Helper_Email__c, Helper_Phone__c,
                   Fee_Amount__c
              FROM PC1_Application__c
             WHERE Id IN :chunkIds
        ]);
        if (appMap.isEmpty()) return;

        // 3. Latest PC1_Call_Schedule__c per app (CallDate / CallTime) ─
        Map<Id, Datetime> latestCallByApp = loadLatestCalls(appMap.keySet());

        // 3b. Audit R7-H4 fix — bulk preload FeeInstallment tokens ONCE for
        //     all appIds so buildMergeMap doesn't do 2 SOQL per (template,
        //     app) inside the loop (governor SOQL limit killed at ~95).
        primeFeeInstallmentCachesFor(chunkIds);

        // 4. Dedup pre-check — one SOQL for all combos ───────────────
        Set<Id> templateIds = new Set<Id>();
        for (PC1_Message_Template__c t : templates) templateIds.add(t.Id);
        Datetime cutoff = Datetime.now().addHours(-DEDUP_HOURS);
        Set<String> recentSent = new Set<String>();
        for (PC1_Message_Send_Log__c prior : [
                SELECT Template__c, Application__c
                  FROM PC1_Message_Send_Log__c
                 WHERE Template__c IN :templateIds
                   AND Application__c IN :chunkIds
                   AND Status__c = 'Sent'
                   AND Sent_At__c >= :cutoff
        ]) {
            recentSent.add(prior.Template__c + '|' + prior.Application__c);
        }

        // 5. Preload static resources referenced by any template ─────
        Map<String, StaticResource> resourceByName = loadStaticResources(templates);

        // 5b. Preload per-app ContentVersions referenced by any template.
        //     Map key = appId + '|' + title (both trimmed / case-preserved).
        //     Value  = ContentVersion (latest by CreatedDate for that title
        //     on that Application). Missing titles → simply not in the map
        //     and the per-send code silently omits (already tolerant of
        //     missing attachments — same UX as static resources).
        Map<String, ContentVersion> appFileByKey = loadAppFiles(templates, appMap);

        // 6. Build sends ─────────────────────────────────────────────
        List<Messaging.SingleEmailMessage>    emailBatch     = new List<Messaging.SingleEmailMessage>();
        List<PC1_Message_Send_Log__c>         emailLogs      = new List<PC1_Message_Send_Log__c>();
        List<PC1_Application__c>              emailApps      = new List<PC1_Application__c>();
        List<PC1_Message_Template__c>         emailTemplates = new List<PC1_Message_Template__c>();
        List<PC1_Message_Send_Log__c>         pendingLogs    = new List<PC1_Message_Send_Log__c>();
        List<TwilioSF__Message__c>            twilioRows     = new List<TwilioSF__Message__c>();

        for (PC1_Message_Template__c t : templates) {
            for (Id appId : appMap.keySet()) {
                PC1_Application__c app = appMap.get(appId);
                PC1_Message_Send_Log__c log = new PC1_Message_Send_Log__c(
                    Template__c    = t.Id,
                    Application__c = appId,
                    Channel__c     = t.Channel__c
                );

                // Dedup guard ────────────────────────────────────────
                if (recentSent.contains(t.Id + '|' + appId)) {
                    log.Status__c      = 'Skipped-Deduped';
                    log.Sent_At__c     = Datetime.now();
                    log.Error_Message__c = 'Duplicate suppressed — a Sent row already exists for this template+app within ' + DEDUP_HOURS + 'h.';
                    pendingLogs.add(log);
                    continue;
                }

                // Render ─────────────────────────────────────────────
                Rendered rendered;
                try {
                    rendered = renderInternal(t, app, latestCallByApp.get(appId));
                } catch (Exception e) {
                    log.Status__c      = 'Failed';
                    log.Sent_At__c     = Datetime.now();
                    log.Error_Message__c = trunc('Render failed: ' + e.getMessage(), 4000);
                    pendingLogs.add(log);
                    continue;
                }
                log.Rendered_Subject__c      = trunc(rendered.subject, 255);
                log.Rendered_Body_Preview__c = trunc(rendered.body, 1000);

                // Channel branch ─────────────────────────────────────
                if ('Email'.equalsIgnoreCase(t.Channel__c)) {
                    if (String.isBlank(app.Email__c)) {
                        log.Status__c        = 'Failed';
                        log.Sent_At__c       = Datetime.now();
                        log.Error_Message__c = 'App has no Email__c.';
                        pendingLogs.add(log);
                        continue;
                    }
                    // SANDBOX GATE (2026-09-28). Production clients@xtrapension.com has
                    // been forwarded into the sandbox for weeks, so sandbox records
                    // carry REAL client addresses — dispatching off them reaches an
                    // actual customer with "Sandbox:" stamped on the subject. Block
                    // unless allowlisted; production is never gated.
                    // See docs/INCIDENT-2026-09-28-sandbox-email-leak.md.
                    if (!PC1_SendGate.allowEmail(app.Email__c)) {
                        log.Status__c        = 'Skipped-Sandbox-Gate';
                        log.Sent_At__c       = Datetime.now();
                        log.External_Id__c   = app.Email__c;
                        log.Error_Message__c = PC1_SendGate.blockReason(app.Email__c);
                        pendingLogs.add(log);
                        continue;
                    }
                    Messaging.SingleEmailMessage builtMsg = buildEmail(t, app, rendered, resourceByName, appFileByKey, log);
                    // Fernando's rule (2026-08-18): if a required per-app
                    // attachment is missing (e.g. GC mandate PDF still being
                    // fetched by the Node endpoint), DO NOT send an
                    // incomplete email. Skip + log so val team can retry
                    // once the file lands. Same-txn Node retry-order fix
                    // makes this rare, but we still refuse to leak a
                    // partial-attachment welcome.
                    if (hasMissingAppAttachment(log)) {
                        log.Status__c        = 'Skipped-Missing-Attachment';
                        log.Sent_At__c       = Datetime.now();
                        log.External_Id__c   = app.Email__c;
                        // Error_Message__c already populated by buildEmail
                        pendingLogs.add(log);
                        continue;
                    }
                    emailBatch.add(builtMsg);
                    emailLogs.add(log);
                    emailApps.add(app);
                    emailTemplates.add(t);
                    log.External_Id__c = app.Email__c;
                    log.Sent_At__c     = Datetime.now();
                    log.Status__c      = 'Sent'; // provisional; corrected after sendEmail
                    pendingLogs.add(log);

                } else if ('SMS'.equalsIgnoreCase(t.Channel__c)) {
                    if (String.isBlank(app.Phone__c)) {
                        log.Status__c        = 'Failed';
                        log.Sent_At__c       = Datetime.now();
                        log.Error_Message__c = 'App has no Phone__c.';
                        pendingLogs.add(log);
                        continue;
                    }
                    // PECR audit C3 R5 — hard block SMS to opted-out numbers.
                    // ICO fines up to £500k per incident post-STOP.
                    // Audit R6 H11 fix: 'Skipped' was not a valid picklist
                    // value — DML threw INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST
                    // on the first opted-out send. Use 'Skipped-OptOut'
                    // (added to picklist in this same commit).
                    if (app.SMS_OptOut__c == true) {
                        log.Status__c        = 'Skipped-OptOut';
                        log.Sent_At__c       = Datetime.now();
                        log.Error_Message__c = 'Blocked: SMS_OptOut__c=true (PECR opt-out honoured).';
                        pendingLogs.add(log);
                        continue;
                    }
                    // Same sandbox gate as the email branch — a real mobile number
                    // on a sandbox record is still a real person's phone.
                    if (!PC1_SendGate.allowSms(app.Phone__c)) {
                        log.Status__c        = 'Skipped-Sandbox-Gate';
                        log.Sent_At__c       = Datetime.now();
                        log.External_Id__c   = app.Phone__c;
                        log.Error_Message__c = PC1_SendGate.blockReason(app.Phone__c);
                        pendingLogs.add(log);
                        continue;
                    }
                    SmsResult sr = smsCallout(app.Phone__c, rendered.body);
                    log.Sent_At__c = Datetime.now();
                    if (sr.success) {
                        log.Status__c      = 'Sent';
                        log.External_Id__c = sr.messageSid;
                        twilioRows.add(new TwilioSF__Message__c(
                            TwilioSF__From_Number__c         = sr.fromNumber,
                            TwilioSF__To_Number__c           = sr.toNumber,
                            TwilioSF__Body__c                = rendered.body,
                            TwilioSF__Direction__c           = 'outbound-api',
                            TwilioSF__Status__c              = sr.status,
                            TwilioSF__Message_SID__c         = sr.messageSid,
                            TwilioSF__Date_Sent__c           = Datetime.now(),
                            TwilioSF__SF_Parent_Record_Id__c = String.valueOf(app.Id),
                            TwilioSF__Recipient_Name__c      = app.Full_Name__c
                        ));
                    } else {
                        log.Status__c        = 'Failed';
                        log.Error_Message__c = trunc('Twilio: ' + sr.errorMessage, 4000);
                    }
                    pendingLogs.add(log);

                } else {
                    log.Status__c        = 'Failed';
                    log.Sent_At__c       = Datetime.now();
                    log.Error_Message__c = 'Unknown Channel__c: ' + t.Channel__c;
                    pendingLogs.add(log);
                }
            }
        }

        // 7. Send emails (single batched sendEmail) ──────────────────
        //   After a successful send, also insert an EmailMessage record
        //   linked to the RelatedToId=PC1_Application so it shows up in
        //   the Email Messages related list on the record page (Fernando
        //   2026-08-18: emails were sending but not appearing in the tab
        //   because SendEmail alone doesn't create EmailMessage records).
        // Parallel arrays so we can link attachments after EmailMessage.insert
        // returns Ids. `emailMessageAppFiles[i]` is the list of ContentVersion
        // Ids that were attached to the email at index i via
        // Attach_App_File_Titles__c (per-app files, e.g. PC1_Mandate). We
        // rehydrate ContentDocumentLinks pointing at the new EmailMessage
        // so the SF Email Messages tab shows the attachments (setFileAttach
        // on Messaging.SingleEmailMessage only affects the outbound MIME —
        // it doesn't create any SF-side attachment link on its own).
        List<EmailMessage> emailMessagesToInsert = new List<EmailMessage>();
        List<PC1_Application__c> emailMessageApps = new List<PC1_Application__c>();
        List<List<Id>> emailMessageAppFiles = new List<List<Id>>();
        List<List<String>> emailMessageStaticRes = new List<List<String>>();
        if (!emailBatch.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results =
                    Messaging.sendEmail(emailBatch, false);
                for (Integer i = 0; i < results.size(); i++) {
                    PC1_Message_Send_Log__c log = emailLogs[i];
                    Messaging.SingleEmailMessage sent = emailBatch[i];
                    PC1_Application__c appI = emailApps[i];
                    PC1_Message_Template__c tI = emailTemplates[i];
                    Messaging.SendEmailResult r = results[i];
                    if (r.isSuccess()) {
                        log.Status__c = 'Sent';
                        // Mirror sent email into EmailMessage for the tab.
                        Boolean hasAttach = (sent.getFileAttachments() != null && !sent.getFileAttachments().isEmpty());
                        // 2026-08-27 audit fix: previously the mirror rows had
                        // From/Reply-To/MessageIdentifier blank, so PC1_Inbound-
                        // EmailHandler couldn't thread replies via In-Reply-To.
                        // Set all three now — replies to clients@xtrapension.com
                        // resolve back to this app via the Message-Id header.
                        PC1_Config__c cfgLocal = PC1_Config__c.getOrgDefaults();
                        String xpFromEmail = (cfgLocal != null && String.isNotBlank(cfgLocal.XP_Email__c))
                            ? cfgLocal.XP_Email__c : 'clients@xtrapension.com';
                        EmailMessage em = new EmailMessage();
                        em.RelatedToId   = appI.Id;
                        em.Subject       = sent.getSubject();
                        em.HtmlBody      = sent.getHtmlBody();
                        em.TextBody      = sent.getPlainTextBody();
                        em.FromAddress   = xpFromEmail;
                        em.FromName      = 'XtraPension';
                        em.ValidatedFromAddress = xpFromEmail;
                        // MessageIdentifier carries the SAME 16-hex nonce
                        // that buildEmail stamped in the subject token
                        // [<AppName>-<nonce>]. PC1_InboundEmailHandler
                        // extracts the nonce from a reply's subject and
                        // verifies it against MessageIdentifier suffix here,
                        // making the token unforgeable without seeing the
                        // original outbound email.
                        String subjNonce = extractNonceFromSubject(sent.getSubject());
                        String msgId = String.valueOf(appI.Id) + '-' + String.valueOf(tI.Id) + '-' +
                            (subjNonce != null ? subjNonce : EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16))
                            + '@xtrapension.com';
                        em.MessageIdentifier = msgId;
                        // Insert as Draft first so we can attach files via
                        // ContentDocumentLink (SF blocks CDL insert on
                        // EmailMessage once Status='3' — 'not in draft
                        // state' error). We flip to Sent below after all
                        // attachment links are wired up.
                        em.Status        = '5'; // 5 = Draft
                        em.MessageDate   = Datetime.now();
                        em.Incoming      = false;
                        // Note: EmailMessage.HasAttachment is auto-managed by
                        // SF (flips true after we insert the first
                        // ContentDocumentLink below). Attempting to write it
                        // manually errors with 'Field is not writeable'.
                        em.ToAddress     = String.join(sent.getToAddresses() == null ? new List<String>() : sent.getToAddresses(), ', ');
                        if (sent.getCcAddresses() != null && !sent.getCcAddresses().isEmpty()) {
                            em.CcAddress = String.join(sent.getCcAddresses(), ', ');
                        }
                        emailMessagesToInsert.add(em);
                        emailMessageApps.add(appI);
                        // Record which per-app CV Ids + static resource names
                        // this email carried, so we can link them once
                        // EmailMessage gets an Id from the insert below.
                        List<Id> perAppCvIds = new List<Id>();
                        for (String rawType : parseAttachmentList(tI.Attach_App_File_Titles__c)) {
                            // Look up by the friendly title (app-scoped) —
                            // dispatcher writes CVs with friendlyDocTitle so
                            // the lookup key must use the same normaliser.
                            String fullTitle = friendlyDocTitle(appI, rawType);
                            ContentVersion cv = appFileByKey == null ? null : appFileByKey.get(appI.Id + '|' + fullTitle);
                            if (cv != null) perAppCvIds.add(cv.Id);
                        }
                        emailMessageAppFiles.add(perAppCvIds);
                        List<String> staticNames = new List<String>();
                        for (String name : parseAttachmentList(tI.Attachment_Static_Resource_Name__c)) {
                            if (resourceByName.containsKey(name)) staticNames.add(name);
                        }
                        emailMessageStaticRes.add(staticNames);
                    } else {
                        log.Status__c = 'Failed';
                        String err = '';
                        for (Messaging.SendEmailError e : r.getErrors()) {
                            err += (err.length() > 0 ? '\n' : '') + e.getStatusCode() + ': ' + e.getMessage();
                        }
                        log.Error_Message__c = trunc(err, 4000);
                    }
                }
            } catch (Exception e) {
                for (PC1_Message_Send_Log__c log : emailLogs) {
                    log.Status__c        = 'Failed';
                    log.Error_Message__c = trunc('sendEmail exception: ' + e.getMessage(), 4000);
                }
            }
        }

        // 8. Bulk DML — send logs + twilio rows ──────────────────────
        // Audit R7 meta-H3 fix: Database.insert(list, false) with per-row
        // error surfacing so ONE bad row (e.g. picklist drift, required-
        // field violation) can never wipe the whole batch. Previous
        // insert-throw-swallow lost ALL Sent rows on any single failure,
        // disabling the 24h dedup and re-sending on next trigger.
        if (!pendingLogs.isEmpty()) {
            Database.SaveResult[] logResults = Database.insert(pendingLogs, false);
            for (Integer i = 0; i < logResults.size(); i++) {
                if (!logResults[i].isSuccess()) {
                    String errs = '';
                    for (Database.Error err : logResults[i].getErrors()) errs += err.getStatusCode() + ':' + err.getMessage() + '; ';
                    System.debug(LoggingLevel.ERROR,
                        'PC1_MessageDispatcher: send-log row ' + i + ' insert failed — ' + errs);
                }
            }
        }
        if (!twilioRows.isEmpty()) {
            Database.SaveResult[] twResults = Database.insert(twilioRows, false);
            for (Integer i = 0; i < twResults.size(); i++) {
                if (!twResults[i].isSuccess()) {
                    String errs = '';
                    for (Database.Error err : twResults[i].getErrors()) errs += err.getStatusCode() + ':' + err.getMessage() + '; ';
                    System.debug(LoggingLevel.WARN,
                        'PC1_MessageDispatcher: TwilioSF row ' + i + ' insert failed — ' + errs);
                }
            }
        }
        if (!emailMessagesToInsert.isEmpty()) {
            try { insert emailMessagesToInsert; }
            catch (Exception e) {
                // Non-fatal — the email went, the audit log is present, we
                // just failed to mirror into the standard EmailMessage tab.
                // Common causes: FLS on EmailMessage for the running user,
                // Enhanced Email disabled in org.
                System.debug(LoggingLevel.WARN,
                    'PC1_MessageDispatcher: EmailMessage mirror insert failed — ' + e.getMessage());
            }
            // Link attachments (per-app ContentVersions + on-the-fly
            // ContentVersions built from static resources) to each
            // EmailMessage so the SF Email Messages tab shows the PDFs
            // that actually went out. Fernando 2026-08-18: attachments
            // were missing from the mirrored EmailMessages.
            linkEmailAttachments(emailMessagesToInsert, emailMessageApps, emailMessageAppFiles, emailMessageStaticRes);
            // Now flip Draft → Sent. Attachment links landed while the
            // EmailMessage was still Draft (SF rule); once Sent, no more
            // ContentDocumentLinks can be added to it.
            List<EmailMessage> flipToSent = new List<EmailMessage>();
            for (EmailMessage em : emailMessagesToInsert) {
                if (em.Id != null) flipToSent.add(new EmailMessage(Id = em.Id, Status = '3'));
            }
            if (!flipToSent.isEmpty()) {
                try { update flipToSent; }
                catch (Exception e) {
                    System.debug(LoggingLevel.WARN,
                        'PC1_MessageDispatcher: EmailMessage flip-to-Sent failed — ' + e.getMessage());
                }
            }
        }

        // Audit R9-CRIT#2 — chain the remainder chunk as a follow-up job so
        // the next MAX_APPS_PER_EXECUTE apps get their own tx with fresh
        // callout / DML budgets. Only enqueue if canChain (Queueable ctx);
        // Batch/Future context can't enqueue and the WARN above already
        // signalled the oversized fire.
        if (canChain && !remainder.isEmpty()) {
            try {
                System.enqueueJob(new PC1_MessageDispatcher(remainder, triggerEvent));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'PC1_MessageDispatcher: remainder chain enqueue failed (' +
                    remainder.size() + ' apps dropped) — ' + e.getMessage());
            }
        }
    }

    // ─── EmailMessage attachment linking ─────────────────────────────
    // Two goals per Fernando (2026-08-18):
    //   1) Attachments appear on the EmailMessage in the SF Email Messages
    //      tab (linked via ContentDocumentLink).
    //   2) Static-resource-backed PDFs (Welcome guide + Service agreement)
    //      also appear in the record's Files section — we materialise them
    //      as ContentVersion on the app once + reuse on later sends.
    // Per-app files (PC1_Mandate) are already ContentVersions on the app
    // (uploaded by Node) — we just link them to the EmailMessage. All
    // steps best-effort so a permission bump doesn't break the send audit.
    private static void linkEmailAttachments(
            List<EmailMessage> ems,
            List<PC1_Application__c> apps,
            List<List<Id>> perAppCvIds,
            List<List<String>> staticNames) {
        if (ems == null || ems.isEmpty()) return;

        // Load static resource bodies once per unique name across the batch.
        Set<String> allNames = new Set<String>();
        for (List<String> names : staticNames) if (names != null) allNames.addAll(names);
        Map<String, StaticResource> resByName = new Map<String, StaticResource>();
        if (!allNames.isEmpty()) {
            for (StaticResource sr : [SELECT Id, Name, Body, ContentType FROM StaticResource WHERE Name IN :allNames]) {
                resByName.put(sr.Name, sr);
            }
        }

        // Idempotency lookup: has THIS app already got a ContentVersion
        // titled <friendlyTitle>? If yes, reuse; if no, create fresh linked
        // to the app so it lands in the Files section. Keyed as 'appId|
        // friendlyTitle' — MUST match the key format used at line 560
        // where we compute friendlyDocTitle(app, name).
        //
        // Audit R7 meta-M7 fix: query previously filtered
        // ContentDocument.Title IN :allNames (raw DevNames like
        // 'PC1_Welcome_Guide') but files were STORED under friendly
        // titles ('PC00137_John_Ryan_Welcome Guide'), so query always
        // returned zero. Dedup never fired: every send accumulated a
        // duplicate ContentVersion. Now compute the same friendlyTitle
        // set the write side uses.
        Set<Id> appIds = new Set<Id>();
        for (PC1_Application__c a : apps) if (a != null) appIds.add(a.Id);
        Set<String> allFriendlyTitles = new Set<String>();
        for (Integer i = 0; i < apps.size(); i++) {
            PC1_Application__c app = apps[i];
            if (app == null) continue;
            List<String> names = (staticNames.size() > i ? staticNames[i] : new List<String>());
            if (names == null) continue;
            for (String name : names) {
                allFriendlyTitles.add(friendlyDocTitle(app, name));
            }
        }
        Map<String, Id> existingCvByAppTitle = new Map<String, Id>();
        Map<Id, Id> docByCv = new Map<Id, Id>();
        if (!appIds.isEmpty() && !allFriendlyTitles.isEmpty()) {
            for (ContentDocumentLink l : [
                SELECT LinkedEntityId,
                       ContentDocument.Title,
                       ContentDocument.LatestPublishedVersionId,
                       ContentDocumentId
                  FROM ContentDocumentLink
                 WHERE LinkedEntityId IN :appIds
                   AND ContentDocument.Title IN :allFriendlyTitles
            ]) {
                String key = String.valueOf(l.LinkedEntityId) + '|' + l.ContentDocument.Title;
                existingCvByAppTitle.put(key, l.ContentDocument.LatestPublishedVersionId);
                docByCv.put(l.ContentDocument.LatestPublishedVersionId, l.ContentDocumentId);
            }
        }

        // Build fresh ContentVersions for missing static resources. Link to
        // the APP (FirstPublishLocationId = app.Id) so they show in Files.
        List<ContentVersion> newCvs = new List<ContentVersion>();
        List<Integer> newCvEmailIdx = new List<Integer>();
        List<String> newCvTitle = new List<String>();
        for (Integer i = 0; i < ems.size(); i++) {
            Id appId = apps[i] != null ? apps[i].Id : null;
            if (appId == null) continue;
            for (String name : (staticNames.size() > i ? staticNames[i] : new List<String>())) {
                // Fernando 2026-08-19: convert StaticResource DevName
                // ("PC1_Welcome_Guide") to a friendly per-app title
                // ("PC00137_John_Ryan_Welcome Guide") on write. Lookup key
                // used further below MUST match this same friendly title.
                PC1_Application__c app = apps[i];
                String friendlyTitle = friendlyDocTitle(app, name);
                String key = String.valueOf(appId) + '|' + friendlyTitle;
                if (existingCvByAppTitle.containsKey(key)) continue; // already in Files
                StaticResource sr = resByName.get(name);
                if (sr == null || sr.Body == null) continue;
                ContentVersion cv = new ContentVersion(
                    Title = friendlyTitle,
                    PathOnClient = friendlyTitle + '.pdf',
                    VersionData = sr.Body,
                    FirstPublishLocationId = appId
                );
                newCvs.add(cv);
                newCvEmailIdx.add(i);
                newCvTitle.add(friendlyTitle);
            }
        }
        if (!newCvs.isEmpty()) {
            try {
                insert newCvs;
                Set<Id> insertedIds = new Set<Id>();
                for (ContentVersion cv : newCvs) if (cv.Id != null) insertedIds.add(cv.Id);
                if (!insertedIds.isEmpty()) {
                    for (ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :insertedIds]) {
                        docByCv.put(cv.Id, cv.ContentDocumentId);
                    }
                }
                for (Integer j = 0; j < newCvs.size(); j++) {
                    ContentVersion cv = newCvs[j];
                    if (cv.Id == null) continue;
                    Integer eIdx = newCvEmailIdx[j];
                    Id appId = apps[eIdx].Id;
                    existingCvByAppTitle.put(String.valueOf(appId) + '|' + newCvTitle[j], cv.Id);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'PC1_MessageDispatcher: static-resource CV insert failed — ' + e.getMessage());
            }
        }

        // Resolve per-app CVs (PC1_Mandate etc) to their ContentDocumentIds
        // so we can link them to the EmailMessage below.
        Set<Id> appCvIds = new Set<Id>();
        for (List<Id> ids : perAppCvIds) if (ids != null) appCvIds.addAll(ids);
        if (!appCvIds.isEmpty()) {
            for (ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :appCvIds]) {
                docByCv.put(cv.Id, cv.ContentDocumentId);
            }
        }

        // Insert ContentDocumentLinks: EmailMessage ↔ every attachment doc
        // (per-app PDFs + newly-materialised static PDFs both).
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Integer i = 0; i < ems.size(); i++) {
            Id emailId = ems[i].Id;
            if (emailId == null) continue;
            Id appId = apps[i] != null ? apps[i].Id : null;
            Set<Id> docsForThisEmail = new Set<Id>();
            // Per-app PDFs
            for (Id cvId : (perAppCvIds.size() > i ? perAppCvIds[i] : new List<Id>())) {
                Id docId = docByCv.get(cvId);
                if (docId != null) docsForThisEmail.add(docId);
            }
            // Static-resource-backed PDFs (idempotent per app)
            // Audit R8-M5 fix: was using raw DevName (`name`) as key but
            // the put-side (lines 560/610) uses friendlyDocTitle(app, name).
            // The lookup NEVER matched → static-resource PDFs were never
            // linked to the mirrored EmailMessage in SF's Email Messages
            // tab (client inbox unaffected because MIME path is separate).
            for (String name : (staticNames.size() > i ? staticNames[i] : new List<String>())) {
                if (appId == null) continue;
                String key = String.valueOf(appId) + '|' + friendlyDocTitle(apps[i], name);
                Id cvId = existingCvByAppTitle.get(key);
                if (cvId == null) continue;
                Id docId = docByCv.get(cvId);
                if (docId != null) docsForThisEmail.add(docId);
            }
            for (Id docId : docsForThisEmail) {
                links.add(new ContentDocumentLink(
                    LinkedEntityId = emailId,
                    ContentDocumentId = docId,
                    ShareType = 'V',        // V = Viewer
                    Visibility = 'AllUsers'
                ));
            }
        }
        if (!links.isEmpty()) {
            try {
                insert links;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'PC1_MessageDispatcher: EmailMessage attachment link insert failed — ' + e.getMessage());
            }
        }
    }

    // ═════════════════════════ RENDER ═══════════════════════════════

    /**
     * Public entry — B2's preview LWC calls this. Unknown tokens throw so the
     * validator can red-flag them; production dispatch catches and demotes to
     * Failed status instead of blowing up the Queueable.
     */
    @AuraEnabled
    public static Rendered render(Id templateId, Id appId) {
        if (templateId == null || appId == null) {
            throw new AuraHandledException('templateId and appId are required.');
        }
        List<PC1_Message_Template__c> tpls = [
            SELECT Id, Name, Channel__c, Trigger_Event__c,
                   Subject_Template__c, Body_Template__c,
                   Content_Text__c, Content_Mode__c,
                   Attachment_Static_Resource_Name__c
              FROM PC1_Message_Template__c
             WHERE Id = :templateId LIMIT 1];
        if (tpls.isEmpty()) throw new AuraHandledException('Template not found.');
        List<PC1_Application__c> apps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c,
                   Email__c, Phone__c, SMS_OptOut__c, DWP_Reference__c,
                   Stage__c, Stage_Changed_At__c, Sales_Agent__c, Val_Agent__c,
                   DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c,
                   Helper_First_Name__c, Helper_Last_Name__c, Helper_Email__c, Helper_Phone__c,
                   Fee_Amount__c
              FROM PC1_Application__c WHERE Id = :appId LIMIT 1];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found.');
        Datetime callAt = loadLatestCalls(new Set<Id>{ apps[0].Id }).get(apps[0].Id);
        // Audit R7 meta-H4 fix — populate FeeInstallment caches for this
        // one app so the preview matches what dispatch will actually
        // render. Was blank pre-fix because caches only populate in
        // execute() bulk path.
        primeFeeInstallmentCachesFor(new Set<Id>{ apps[0].Id });
        return renderInternal(tpls[0], apps[0], callAt);
    }

    /** Bulk-preload FeeInstallment token caches for a set of appIds. Used
     *  by both execute() (all-apps) and render() (one app). */
    @TestVisible
    private static void primeFeeInstallmentCachesFor(Set<Id> appIds) {
        feeInstTotalCache = new Map<Id, Integer>();
        feeInstLatestCache = new Map<Id, PC1_Fee_Installment__c>();
        feeInstNextCache = new Map<Id, PC1_Fee_Installment__c>();
        if (appIds == null || appIds.isEmpty()) return;
        try {
            for (AggregateResult r : [
                SELECT Application__c app, COUNT(Id) n FROM PC1_Fee_Installment__c
                WHERE Application__c IN :appIds GROUP BY Application__c
            ]) {
                feeInstTotalCache.put((Id) r.get('app'), Integer.valueOf(r.get('n')));
            }
            for (PC1_Fee_Installment__c row : [
                SELECT Id, Application__c, Installment_Number__c, Amount__c
                  FROM PC1_Fee_Installment__c
                 WHERE Application__c IN :appIds AND Payment_Status__c = 'paid'
                 ORDER BY Installment_Number__c DESC
            ]) {
                if (!feeInstLatestCache.containsKey(row.Application__c)) {
                    feeInstLatestCache.put(row.Application__c, row);
                }
            }
            for (PC1_Fee_Installment__c row : [
                SELECT Id, Application__c, Installment_Number__c, Amount__c, Scheduled_Date__c
                  FROM PC1_Fee_Installment__c
                 WHERE Application__c IN :appIds AND Payment_Status__c = 'pending'
                 ORDER BY Scheduled_Date__c ASC, Installment_Number__c ASC
            ]) {
                if (!feeInstNextCache.containsKey(row.Application__c)) {
                    feeInstNextCache.put(row.Application__c, row);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'FeeInstallment cache prime skipped — ' + e.getMessage());
        }
    }

    // Internal render — no @AuraEnabled. Same throw-on-unknown-token contract.
    // If Content_Mode__c = Simple, resolve merges against Content_Text__c and
    // wrap the result in the XtraPension email shell (Body_Template__c is
    // ignored on send-path). If Advanced (or blank content-text), resolve
    // against Body_Template__c as before.
    private static Rendered renderInternal(
            PC1_Message_Template__c t, PC1_Application__c app, Datetime latestCall) {
        Map<String, String> vals = buildMergeMap(app, latestCall);
        Rendered out = new Rendered();
        out.subject = resolve(t.Subject_Template__c, vals);

        Boolean isSimple = 'Simple'.equalsIgnoreCase(t.Content_Mode__c);
        Boolean isEmail  = 'Email'.equalsIgnoreCase(t.Channel__c);

        if (isSimple && String.isNotBlank(t.Content_Text__c)) {
            String mergedContent = resolve(t.Content_Text__c, vals);
            // Only wrap in the HTML shell for Email — SMS stays plain text.
            out.body = isEmail
                ? PC1_EmailShellRenderer.wrap(mergedContent)
                : mergedContent;
        } else {
            out.body = resolve(t.Body_Template__c, vals);
        }
        out.resolvedMerges = vals;
        return out;
    }

    // ═════════════════════════ MERGE MAP ════════════════════════════

    private static Map<String, String> buildMergeMap(PC1_Application__c app, Datetime latestCall) {
        Map<String, String> m = new Map<String, String>();
        m.put('FirstName',      nvl(app.First_Name__c));
        m.put('LastName',       nvl(app.Last_Name__c));
        m.put('FullName',       nvl(app.Full_Name__c));
        m.put('ApplicationRef', nvl(app.Name));
        m.put('DWPReference',   nvl(app.DWP_Reference__c));
        if (latestCall != null) {
            m.put('CallTime', latestCall.format('HH:mm',     TZ_UK));
            m.put('CallDate', latestCall.format('dd/MM/yyyy', TZ_UK));
        } else {
            m.put('CallTime', '');
            m.put('CallDate', '');
        }
        m.put('IssueDate', Datetime.now().format('dd/MM/yyyy', TZ_UK));

        // Stage + agent metadata — added in the PC Messages redesign so admins
        // can build "status update" templates without hand-typing everything.
        m.put('Stage',       nvl(app.Stage__c));
        m.put('SalesAgent',  nvl(app.Sales_Agent__c));
        m.put('ValAgent',    nvl(app.Val_Agent__c));

        // Decision-due placeholder: DWP typically decides ~3 months after
        // Submitted. Stage_Changed_At__c is stamped by StageTransitionHelper.
        String decision = '';
        if (app.Stage_Changed_At__c != null && 'Submitted'.equalsIgnoreCase(app.Stage__c)) {
            decision = app.Stage_Changed_At__c.addMonths(3).format('dd/MM/yyyy', TZ_UK);
        }
        m.put('DecisionDueDate', decision);

        // Fee tokens. These used to be a hardcoded placeholder, so every Bacs
        // advance notice and fee receipt told the client "we'll collect
        // £[fee amount, calculated post-award]" (found 2026-10-02).
        //
        // A token is ONLY put when its value is known. If it is missing,
        // resolve() throws, the send is logged Failed with the token name, and
        // nothing goes out. A Bacs advance notice with no amount or date must
        // never reach a client — failing loudly is the correct outcome.
        // Fee_Amount__c is a formula, ROUND(Award_Amount__c * 0.20, 2), that
        // treats a blank award as zero — so an application with no award yet
        // reads 0.00, not null. A zero fee is never a real amount to notify,
        // so it counts as unknown (caught by a test before release: the
        // missing-fee case was about to send "we will collect £0.00").
        if (app.Fee_Amount__c != null && app.Fee_Amount__c > 0) {
            m.put('FeeAmount', app.Fee_Amount__c.setScale(2).toPlainString());
        }
        PC1_Fee_Installment__c nextInst = feeInstNextCache.get(app.Id);
        if (nextInst != null && nextInst.Amount__c != null && nextInst.Amount__c > 0) {
            m.put('NextChargeAmount', nextInst.Amount__c.setScale(2).toPlainString());
        }
        if (nextInst != null && nextInst.Scheduled_Date__c != null) {
            m.put('NextChargeDate', Datetime.newInstance(
                nextInst.Scheduled_Date__c, Time.newInstance(12, 0, 0, 0)).format('EEEE d MMMM yyyy', TZ_UK));
        }

        // Audit R6 H12 + R7-H4 fix — installment receipt tokens.
        // R7-H4: was 2 SOQL PER (template, app) inside the send loop —
        // bulk dispatch of 100+ apps blew the SOQL governor. Now the
        // dispatcher's execute() pre-fetches once for all appIds into
        // feeInstTotalCache / feeInstLatestCache; this
        // block just reads from the cache.
        String finstNumber = '';
        String finstTotal  = '';
        String finstAmount = '';
        Integer totCached = feeInstTotalCache.get(app.Id);
        if (totCached != null) finstTotal = String.valueOf(totCached);
        PC1_Fee_Installment__c latestCached = feeInstLatestCache.get(app.Id);
        if (latestCached != null) {
            if (latestCached.Installment_Number__c != null) finstNumber = String.valueOf(Integer.valueOf(latestCached.Installment_Number__c));
            if (latestCached.Amount__c != null) finstAmount = latestCached.Amount__c.setScale(2).toPlainString();
        }
        m.put('FeeInstallmentNumber', finstNumber);
        m.put('FeeInstallmentTotal',  finstTotal);
        m.put('FeeInstallmentAmount', finstAmount);

        // Direct Debit mandate metadata — populated by the GoCardless flow
        // (PC1_GoCardlessController.createMandateForApplication). These are
        // used by the Welcome Email template to show the client that their
        // DD is in place; templates that fire before the mandate exists
        // still render safely (values fall through to empty strings).
        m.put('MandateId',        nvl(app.DD_Mandate_Id__c));
        m.put('MandateStatus',    nvl(app.DD_Mandate_Status__c));
        m.put('MandateCreatedAt', app.DD_Mandate_Created_At__c == null
            ? '' : app.DD_Mandate_Created_At__c.format('dd/MM/yyyy', TZ_UK));

        // XtraPension constants — resolved via PC1_Config__c so they stay in
        // sync with the shell footer. Fallbacks live in EmailShellRenderer.
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        String xpPhone = (cfg != null && String.isNotBlank(cfg.XP_Phone__c))
            ? cfg.XP_Phone__c : '+353 1 254 4116';
        String xpEmail = (cfg != null && String.isNotBlank(cfg.XP_Email__c))
            ? cfg.XP_Email__c : 'clients@xtrapension.com';
        // Audit R7 meta-M8 fix: XPWhatsApp + XPOffice were in getMergeSchema
        // (palette suggests they're valid) but buildMergeMap didn't define
        // them → any admin who used those tokens had EVERY dispatch throw
        // "Unknown merge token" and log Failed silently. Client got nothing.
        String xpWa = (cfg != null && String.isNotBlank(cfg.XP_WhatsApp__c))
            ? cfg.XP_WhatsApp__c : '+353 87 654 3210';
        String xpOffice = (cfg != null && String.isNotBlank(cfg.XP_Office__c))
            ? cfg.XP_Office__c : '25 Merrion Sq, Dublin 2';
        m.put('XPPhone',    xpPhone);
        m.put('XPEmail',    xpEmail);
        m.put('XPWhatsApp', xpWa);
        m.put('XPOffice',   xpOffice);

        return m;
    }

    private static final Pattern TOKEN_RX = Pattern.compile('\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}');

    /** Resolve all {{Token}} in text against vals. Unknown token → throw. */
    /** Tokens that are valid but only have a value once the case reaches a
     *  certain point (fee recorded, installment scheduled). */
    private static final Set<String> KNOWN_VALUE_TOKENS = new Set<String>{
        'FeeAmount', 'NextChargeAmount', 'NextChargeDate'
    };

    private static String resolve(String text, Map<String, String> vals) {
        if (String.isBlank(text)) return text;
        Matcher mt = TOKEN_RX.matcher(text);
        String out = '';
        Integer last = 0;
        while (mt.find()) {
            out += text.substring(last, mt.start());
            String tok = mt.group(1);
            if (!vals.containsKey(tok)) {
                // AuraHandledException.getMessage() returns "Script-thrown
                // exception" outside an Aura call unless setMessage() is used,
                // so every Failed send log read "Render failed: Script-thrown
                // exception" and never named the token.
                String msg = KNOWN_VALUE_TOKENS.contains(tok)
                    ? 'Merge token {{' + tok + '}} has no value for this application yet (e.g. no fee or installment recorded).'
                    : 'Unknown merge token: {{' + tok + '}}';
                AuraHandledException ex = new AuraHandledException(msg);
                ex.setMessage(msg);
                throw ex;
            }
            out += nvl(vals.get(tok));
            last = mt.end();
        }
        out += text.substring(last);
        return out;
    }

    // ═════════════════════════ EMAIL BUILD ══════════════════════════

    private static Messaging.SingleEmailMessage buildEmail(
            PC1_Message_Template__c t, PC1_Application__c app,
            Rendered rendered, Map<String, StaticResource> resources,
            Map<String, ContentVersion> appFiles,
            PC1_Message_Send_Log__c log) {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ app.Email__c });
        // Helper CC (Fernando 2026-08-18): a friend/relative the client
        // designated at intake gets CC'd on ALL emails XtraPension sends.
        // Never for SMS. Skip if Helper_Email__c is blank OR (defensively)
        // equal to the client's own email — the intake form already blocks
        // the same-email case, but a stale record from before the check
        // shouldn't send two copies.
        if (String.isNotBlank(app.Helper_Email__c)
                && !app.Helper_Email__c.equalsIgnoreCase(String.valueOf(app.Email__c))) {
            msg.setCcAddresses(new List<String>{ app.Helper_Email__c });
        }
        // C1 threading (audit round-2 revision after H1 spoof finding).
        // SF's SingleEmailMessage doesn't expose Message-Id header, so our
        // stamped MessageIdentifier never reaches SMTP → In-Reply-To match
        // is inert. Fallback: prepend a support-desk-style reference token.
        //
        // Round-1 approach was [<AppName>] alone — attacker could send
        // [PC00042] in the subject from ANY email and land on Margaret's
        // record. Round-2 fix: append a 16-hex nonce from the same key
        // that MessageIdentifier uses, giving 64 bits of entropy per token.
        // Inbound handler verifies the nonce matches an EmailMessage row
        // we own; unforgeable without knowing the specific outbound thread.
        String nonce = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);
        String rawSubj = String.isBlank(rendered.subject) ? '(no subject)' : rendered.subject;
        String refToken = '[' + app.Name + '-' + nonce + ']';
        // Avoid double-prepending if the template already includes any token
        // with the same Name (rare — templates shouldn't).
        String finalSubj = rawSubj.contains('[' + app.Name) ? rawSubj : (refToken + ' ' + rawSubj);
        msg.setSubject(finalSubj);
        // Stash the nonce so the caller can persist it on the mirror
        // EmailMessage.MessageIdentifier (the loop below).
        // We overload MessageIdentifier's suffix to carry this nonce.

        String body = rendered.body == null ? '' : rendered.body;
        if (body.contains('<html') || body.contains('<body') || body.contains('<p>')) {
            msg.setHtmlBody(body);
            msg.setPlainTextBody(body.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim());
        } else {
            msg.setPlainTextBody(body);
        }
        msg.setSaveAsActivity(false);
        msg.setUseSignature(false);

        // 2026-08-27 (Fernando audit fix): set Reply-To to XP_Email so client
        // replies land in the monitored inbox (clients@xtrapension.com) — the
        // From address on outbound is the SF Org Wide Address (typically
        // noreply@...), which prevents replies from reaching a real human.
        // Reply-To overrides it. Also set SenderDisplayName so the client's
        // inbox shows "XtraPension" not the org-wide sender.
        PC1_Config__c cfgReply = PC1_Config__c.getOrgDefaults();
        String replyToAddr = (cfgReply != null && String.isNotBlank(cfgReply.XP_Email__c))
            ? cfgReply.XP_Email__c : 'clients@xtrapension.com';
        msg.setReplyTo(replyToAddr);
        msg.setSenderDisplayName('XtraPension');

        // Attachments — two orthogonal sources:
        //   1) Attachment_Static_Resource_Name__c  → comma-list of StaticResource DevNames
        //   2) Attach_App_File_Titles__c            → comma-list of ContentDocument.Title
        //      values to pull from the RECIPIENT'S PC1_Application__c files.
        // Both feed into one setFileAttachments list. Missing items are
        // logged (Error_Message__c) but never block the send.
        List<Messaging.EmailFileAttachment> atts = new List<Messaging.EmailFileAttachment>();
        List<String> missing = new List<String>();

        for (String name : parseAttachmentList(t.Attachment_Static_Resource_Name__c)) {
            StaticResource sr = resources.get(name);
            if (sr != null && sr.Body != null) {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                att.setFileName(name + '.pdf');
                att.setBody(sr.Body);
                att.setContentType(String.isBlank(sr.ContentType) ? 'application/pdf' : sr.ContentType);
                atts.add(att);
            } else {
                missing.add('static:' + name);
            }
        }

        for (String title : parseAttachmentList(t.Attach_App_File_Titles__c)) {
            // Files are stored as "{AppName}_{First}_{Last}_{DocType}" since
            // 2026-08-19 (friendlyDocTitle). Looking them up by the bare
            // template value ("Mandate") missed every one, so the welcome email
            // was logged Skipped-Missing-Attachment and has not gone out since
            // 2026-08-18. Same normaliser as the post-send link path.
            ContentVersion cv = appFiles == null ? null : appFiles.get(app.Id + '|' + friendlyDocTitle(app, title));
            if (cv != null && cv.VersionData != null) {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                // Prefer PathOnClient (has the real extension) but fall back
                // to Title + .pdf so mandate PDFs get a sensible filename.
                String fname = String.isNotBlank(cv.PathOnClient) ? cv.PathOnClient : (title + '.pdf');
                att.setFileName(fname);
                att.setBody(cv.VersionData);
                att.setContentType('application/pdf');
                atts.add(att);
            } else {
                missing.add('app:' + title);
            }
        }

        if (!atts.isEmpty()) msg.setFileAttachments(atts);
        // Fernando 2026-08-18: never ship an email with a missing per-app
        // attachment. If PC1_Mandate (or any other Attach_App_File_Titles
        // entry) is missing, the client would get a "3 PDF welcome" with
        // only 2 PDFs — that's the exact issue we want to prevent. Signal
        // the caller by leaving Error_Message__c populated with a
        // recognisable marker (see execute() where we skip the send).
        // Missing STATIC resources are still sent (they're always present
        // in a deployed org — a missing static is a config error, not a
        // race, so shipping with 2/3 PDFs is still preferable to no email).
        if (!missing.isEmpty()) {
            log.Error_Message__c = 'Attachment(s) not found: ' + String.join(missing, ', ');
        }
        return msg;
    }

    /** Returns true iff any of the missing markers are "app:*" — those are
     *  the per-app ContentVersion files that race with async uploads (like
     *  the GC-generated mandate PDF). Static resources are always in the
     *  deployed org, so a "static:*" miss is a config bug, not a race. */
    private static Boolean hasMissingAppAttachment(PC1_Message_Send_Log__c log) {
        if (log == null || String.isBlank(log.Error_Message__c)) return false;
        return log.Error_Message__c.startsWith('Attachment(s) not found: ')
            && log.Error_Message__c.contains('app:');
    }

    /**
     * Split a comma-separated Attachment_Static_Resource_Name__c value into a
     * dedup'd, whitespace-trimmed list. Empty / null field → empty list.
     */
    private static List<String> parseAttachmentList(String raw) {
        List<String> out = new List<String>();
        if (String.isBlank(raw)) return out;
        Set<String> seen = new Set<String>();
        for (String part : raw.split(',')) {
            String name = part == null ? '' : part.trim();
            if (String.isBlank(name)) continue;
            if (seen.contains(name)) continue;
            seen.add(name);
            out.add(name);
        }
        return out;
    }

    // ═════════════════════════ SMS CALLOUT ══════════════════════════

    /**
     * Mirrors PC1_TwilioController.sendSMS — direct Twilio HTTP with BasicAuth
     * from XtraPension_Data__c credentials — but returns a struct so the
     * Queueable can defer TwilioSF__Message__c DML to the end of the txn.
     */
    private static SmsResult smsCallout(String toE164, String body) {
        SmsResult r = new SmsResult();
        r.toNumber   = toE164;
        r.fromNumber = SMS_FROM;

        XtraPension_Data__c xpd = XtraPension_Data__c.getInstance();
        String acct  = xpd != null ? xpd.Twilio_Account__c : null;
        String token = xpd != null ? xpd.Twilio_Token__c   : null;
        if (String.isBlank(acct) || String.isBlank(token)) {
            r.success      = false;
            r.errorMessage = 'Twilio credentials not configured in XtraPension_Data__c.';
            return r;
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(TWILIO_ENDPOINT + acct + '/Messages.json');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(acct + ':' + token)));
        req.setTimeout(10000);
        req.setBody(
              'From='            + EncodingUtil.urlEncode(SMS_FROM, 'UTF-8')
            + '&To='             + EncodingUtil.urlEncode(toE164,   'UTF-8')
            + '&Body='           + EncodingUtil.urlEncode(body,     'UTF-8')
            + '&StatusCallback=' + EncodingUtil.urlEncode(STATUS_CB,'UTF-8'));

        HttpResponse resp;
        try { resp = new Http().send(req); }
        catch (Exception e) {
            r.success      = false;
            r.errorMessage = 'Twilio unreachable: ' + e.getMessage();
            return r;
        }
        if (resp.getStatusCode() < 200 || resp.getStatusCode() >= 300) {
            r.success      = false;
            r.errorMessage = 'HTTP ' + resp.getStatusCode() + ' — ' + resp.getBody();
            return r;
        }
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            r.messageSid = (String) data.get('sid');
            r.status     = (String) data.get('status');
            if (data.get('to')   != null) r.toNumber   = (String) data.get('to');
            if (data.get('from') != null) r.fromNumber = (String) data.get('from');
            r.success    = true;
        } catch (Exception e) {
            r.success      = false;
            r.errorMessage = 'Twilio returned non-JSON: ' + e.getMessage();
        }
        return r;
    }

    // ═════════════════════════ HELPERS ══════════════════════════════

    private static Map<Id, Datetime> loadLatestCalls(Set<Id> appIds) {
        Map<Id, Datetime> out = new Map<Id, Datetime>();
        for (PC1_Call_Schedule__c cs : [
                SELECT Application__c, Scheduled_At__c
                  FROM PC1_Call_Schedule__c
                 WHERE Application__c IN :appIds AND Scheduled_At__c != null
                 ORDER BY Scheduled_At__c DESC]) {
            if (!out.containsKey(cs.Application__c)) {
                out.put(cs.Application__c, cs.Scheduled_At__c);
            }
        }
        return out;
    }

    /**
     * For every template that requests per-app file attachments via
     * Attach_App_File_Titles__c, pre-load the latest ContentVersion linked
     * to each app in scope by that Title. Returns a map keyed
     * `appId + '|' + title` → latest ContentVersion.
     *
     * "Latest" = highest CreatedDate on that ContentDocument (SF surfaces
     * that as ContentVersion.IsLatest=true on the current version).
     *
     * All SOQL happens up-front so the send loop stays governor-clean.
     */
    private static Map<String, ContentVersion> loadAppFiles(
            List<PC1_Message_Template__c> templates, Map<Id, PC1_Application__c> appMap) {
        Set<String> rawShortTypes = new Set<String>();
        for (PC1_Message_Template__c t : templates) {
            for (String tt : parseAttachmentList(t.Attach_App_File_Titles__c)) {
                rawShortTypes.add(tt);
            }
        }
        Map<String, ContentVersion> out = new Map<String, ContentVersion>();
        if (rawShortTypes.isEmpty() || appMap == null || appMap.isEmpty()) return out;

        // Fernando 2026-08-19: compute the expected friendly titles per
        // (app, template shortType) pair — every CV is now written under
        // "{Name}_{First}_{Last}_{DocType}" so we look up by that pattern.
        Set<String> expectedTitles = new Set<String>();
        for (PC1_Application__c app : appMap.values()) {
            for (String rst : rawShortTypes) expectedTitles.add(friendlyDocTitle(app, rst));
        }
        Set<Id> appIds = appMap.keySet();

        // Two-step: (a) find ContentDocumentLinks for our apps/titles;
        //          (b) load the latest ContentVersion for each doc.
        Map<Id, Id> docToApp = new Map<Id, Id>();
        Map<Id, String> docToTitle = new Map<Id, String>();
        for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId, LinkedEntityId,
                       ContentDocument.Title, ContentDocument.CreatedDate
                  FROM ContentDocumentLink
                 WHERE LinkedEntityId IN :appIds
                   AND ContentDocument.Title IN :expectedTitles]) {
            // If two ContentDocuments on the same app share a title (legacy
            // dupes), keep the first one — buildEmail attaches ONE version
            // per title per email. If Fernando needs "all versions", we'd
            // model that with numbered titles instead.
            String key = String.valueOf(cdl.LinkedEntityId) + '|' + cdl.ContentDocument.Title;
            if (!docToApp.containsKey(cdl.ContentDocumentId)
                && !out.containsKey(key)) {
                docToApp.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
                docToTitle.put(cdl.ContentDocumentId, cdl.ContentDocument.Title);
            }
        }
        if (docToApp.isEmpty()) return out;

        // R13-HIGH-2 fix — combine per-app cap (fairness) with a global
        // ceiling (heap safety). Prior R12 had ONLY per-app 2MB × 8 apps
        // = 16MB potential, over the 12MB async heap. Now: per-app 2MB
        // AS a first pass (whale-PDF app evicts itself), then a global
        // 6MB ceiling as second pass evicting apps in DESC total-size
        // order until we're under budget (whales go first, small apps
        // survive).
        final Integer APP_BUDGET_BYTES = 2 * 1024 * 1024;
        final Integer GLOBAL_BUDGET_BYTES = 6 * 1024 * 1024;
        // Step 1: fetch ContentSize per doc + group by app.
        Map<Id, List<ContentVersion>> sizedByApp = new Map<Id, List<ContentVersion>>();
        for (ContentVersion cvSize : [
                SELECT Id, ContentDocumentId, ContentSize
                  FROM ContentVersion
                 WHERE ContentDocumentId IN :docToApp.keySet()
                   AND IsLatest = true
                 ORDER BY ContentSize ASC NULLS FIRST]) {
            Id appId = docToApp.get(cvSize.ContentDocumentId);
            if (appId == null) continue;
            if (!sizedByApp.containsKey(appId)) sizedByApp.put(appId, new List<ContentVersion>());
            sizedByApp.get(appId).add(cvSize);
        }
        // Step 2: per-app budget accounting. Track per-app kept size for
        // step 3.
        Map<Id, Set<Id>> keepByApp = new Map<Id, Set<Id>>();
        Map<Id, Integer> perAppKept = new Map<Id, Integer>();
        for (Id appId : sizedByApp.keySet()) {
            Integer running = 0;
            Set<Id> apDocs = new Set<Id>();
            for (ContentVersion cvSize : sizedByApp.get(appId)) {
                Integer sz = cvSize.ContentSize == null ? 0 : cvSize.ContentSize;
                if (running + sz > APP_BUDGET_BYTES) {
                    System.debug(LoggingLevel.WARN,
                        'loadAppFiles: per-app budget hit for ' + appId +
                        ' at ' + (running / 1024) + 'KB — skipping ContentVersion ' +
                        cvSize.Id + ' (' + (sz / 1024) + 'KB) for this app.');
                    break;
                }
                running += sz;
                apDocs.add(cvSize.ContentDocumentId);
            }
            keepByApp.put(appId, apDocs);
            perAppKept.put(appId, running);
        }
        // Step 3: global ceiling. Sum kept sizes; if over, evict apps in
        // DESC size order (whales first) until under budget. Ensures the
        // async 12MB heap can't be exceeded even with a full 8-app chunk.
        Integer globalRunning = 0;
        for (Integer v : perAppKept.values()) globalRunning += v;
        if (globalRunning > GLOBAL_BUDGET_BYTES) {
            // Sort app IDs by per-app kept size DESC.
            List<Id> appsBySize = new List<Id>(perAppKept.keySet());
            // Manual insertion sort — Apex has no builtin generic sort on Id.
            for (Integer i = 1; i < appsBySize.size(); i++) {
                Id cur = appsBySize[i]; Integer j = i;
                while (j > 0 && perAppKept.get(appsBySize[j - 1]) < perAppKept.get(cur)) {
                    appsBySize[j] = appsBySize[j - 1]; j--;
                }
                appsBySize[j] = cur;
            }
            for (Id appId : appsBySize) {
                if (globalRunning <= GLOBAL_BUDGET_BYTES) break;
                Integer evicted = perAppKept.get(appId);
                globalRunning -= evicted;
                keepByApp.put(appId, new Set<Id>());
                System.debug(LoggingLevel.WARN,
                    'loadAppFiles: global budget hit — evicted ALL docs for app ' +
                    appId + ' (' + (evicted / 1024) + 'KB). Val team will see ' +
                    'Skipped-Missing-Attachment on this send.');
            }
        }
        Set<Id> keepDocs = new Set<Id>();
        for (Set<Id> apDocs : keepByApp.values()) keepDocs.addAll(apDocs);
        if (keepDocs.isEmpty()) return out;

        for (ContentVersion cv : [
                SELECT Id, Title, PathOnClient, VersionData, ContentDocumentId
                  FROM ContentVersion
                 WHERE ContentDocumentId IN :keepDocs
                   AND IsLatest = true]) {
            Id appId = docToApp.get(cv.ContentDocumentId);
            String title = docToTitle.get(cv.ContentDocumentId);
            if (appId == null || title == null) continue;
            out.put(appId + '|' + title, cv);
        }
        return out;
    }

    private static Map<String, StaticResource> loadStaticResources(List<PC1_Message_Template__c> templates) {
        Set<String> names = new Set<String>();
        for (PC1_Message_Template__c t : templates) {
            // Field is a comma-separated list — split & collect so a template
            // that attaches Welcome_Guide + Service_Agreement pulls both in
            // one SOQL round-trip.
            for (String n : parseAttachmentList(t.Attachment_Static_Resource_Name__c)) {
                names.add(n);
            }
        }
        Map<String, StaticResource> out = new Map<String, StaticResource>();
        if (names.isEmpty()) return out;
        for (StaticResource sr : [SELECT Name, Body, ContentType FROM StaticResource WHERE Name IN :names]) {
            out.put(sr.Name, sr);
        }
        return out;
    }

    /**
     * Pull the 16-hex nonce out of the subject's [AppName-nonce] token.
     * Returns null if the token isn't there — inbound handler treats a null
     * nonce as "no subject-token match" and falls through to sender-match.
     */
    @TestVisible
    private static String extractNonceFromSubject(String subject) {
        if (String.isBlank(subject)) return null;
        Pattern p = Pattern.compile('\\[[A-Z]{1,4}[- ]?\\d{3,10}-([a-f0-9]{16})\\]');
        Matcher m = p.matcher(subject);
        return m.find() ? m.group(1) : null;
    }

    private static String nvl(String s) { return s == null ? '' : s; }
    private static String trunc(String s, Integer max) {
        if (s == null) return null;
        return s.length() > max ? s.substring(0, max) : s;
    }

    // ═════════════════════════ DTOs ═════════════════════════════════

    /**
     * DTO used by both B2 preview LWC (via controller) and internal dispatch.
     * Named `Rendered` (not `RenderedMessage`) so PC1_MessageTemplateController
     * can compile against `PC1_MessageDispatcher.Rendered r = ...`.
     */
    public class Rendered {
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public Map<String, String> resolvedMerges;
    }

    private class SmsResult {
        Boolean success = false;
        String  messageSid;
        String  status;
        String  toNumber;
        String  fromNumber;
        String  errorMessage;
    }
}