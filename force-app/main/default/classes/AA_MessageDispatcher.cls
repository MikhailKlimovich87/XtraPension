/**
 * AA_MessageDispatcher (B3) — message send engine for AA_Message_Template__c.
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
 *   AA_Message_Template__c: Subject_Template__c, Body_Template__c,
 *                            Attachment_Static_Resource_Name__c
 *   AA_Message_Send_Log__c: Template__c, Application__c, Channel__c,
 *                            Sent_At__c, Status__c (Sent|Failed|Skipped-Deduped|Skipped-Missing-Attachment|
 *                            Skipped-Do-Not-Contact|Skipped-SMS-Opt-Out|Skipped-Stage-Gate, see skipStatus),
 *                            External_Id__c, Error_Message__c,
 *                            Rendered_Subject__c, Rendered_Body_Preview__c
 *
 * Send strategy:
 *   Email → Messaging.SingleEmailMessage, batched (single Messaging.sendEmail
 *           call per Queueable run). Optional StaticResource attachment.
 *   SMS   → direct Twilio HTTPS POST — mirrors AA_TwilioController.sendSMS
 *           pattern (grep confirmed that is the ONLY outbound SMS path in the
 *           repo). Callout inlined here so we can defer TwilioSF__Message__c
 *           DML to the end of the Queueable transaction (satisfies the "no
 *           callouts after DML" governor rule when multiple SMS templates fire
 *           in one run). Reuses XtraPension_Data__c custom setting credentials.
 *
 * Governor plan: all SOQL up-front → all callouts → all DML.
 *
 * Dedup: skip (template, app) if AA_Message_Send_Log__c has Status__c='Sent'
 * within the last 24 h. Guards against trigger re-fires on record recovery.
 * The DWP decision messages (ONCE_PER_APP_EVENTS) dedup on ANY earlier Sent
 * row instead: a client is told "approved" or "refused" once, however often
 * the stage moves back through Awarded / Closed - Refused.
 *
 * Do Not Contact (audit 2026-10-02 F54/F70/F85; owner decision 2026-10-02):
 * an app with Do_Not_Contact__c = true gets NO automated message of any kind.
 * There used to be an exception for the Bacs advance notice; it went when
 * Fernando decided that Do Not Contact also pauses fee collection (the fee
 * scheduler stops charging DNC apps), so there is no collection to announce.
 * Each suppressed send writes a log row so the val team can see why nothing
 * went out.
 *
 * SMS opt-out (owner decision 2026-10-02): SMS_Opt_Out__c (set when the client
 * replies STOP, cleared on START; src/webhooks/twilio-inbound.js) skips SMS
 * templates only. Email still goes and Mary still calls.
 *
 * Stage gates (owner decision 2026-10-02): money, Direct Debit and DWP
 * decision messages only go out in the stages listed in ALLOWED_STAGES for
 * their category (CATEGORY_BY_EVENT). Checked here, at send time, so no
 * caller (a trigger, a webhook, a scheduler, a future one) can send a fee or
 * Bacs message to a client whose claim was refused.
 *
 * Sender (audit 2026-10-02 F74): every email goes out from the clients@
 * Org-Wide Email Address when the org has it, not from whichever user owns
 * the cron / JWT session.
 */
public with sharing class AA_MessageDispatcher implements Queueable, Database.AllowsCallouts {

    // ─── constants ──────────────────────────────────────────────────
    private static final String  SMS_FROM       = '+447476900311'; // parity with AA_TwilioController
    private static final String  TWILIO_ENDPOINT= 'https://api.twilio.com/2010-04-01/Accounts/';
    private static final String  STATUS_CB      = 'https://aa-autofill-14d501200453.herokuapp.com/webhooks/twilio/status';
    private static final Integer DEDUP_HOURS    = 24;
    private static final String  TZ_UK          = 'Europe/London';
    // The From address for every client email. Must be a verified Org-Wide
    // Email Address (it is: 0D2RR0000000jOX0AY, IsAllowAllProfiles=true). Kept
    // equal to the Reply-To and to the mirror's FromAddress so the record of
    // the email matches what the client actually received.
    @TestVisible private static final String CLIENT_FROM_ADDRESS = 'clients@xtrapension.com';
    // ─── stage gates (owner decision 2026-10-02) ─────────────────────
    // Stages where a fee is owed or may still be collected: after the award,
    // including a failed collection that ops can retry and a post-award change
    // of circumstances. Not Closed - Paid (nothing left to collect), not
    // DD Chargeback (disputed, collection halted), and never before an award
    // or after a refusal.
    // This list (through the FeeCollection category) is ALSO the fee sweep's
    // collection gate: AA_FeeInstallmentScheduler derives the stages in which
    // it notices and collects from allowedStagesFor('Bacs_Advance_Notice'),
    // so a client is never charged in a stage where the notice is suppressed.
    // Changing it changes who is charged, not only who is emailed.
    private static final Set<String> FEE_DUE_STAGES = new Set<String>{
        'Awarded', 'Fee Charged', 'Closed - Fee Failed', 'Change of Circumstances Review'
    };
    // Every open stage up to and including the DWP decision, plus the MR /
    // appeal stages (a refusal overturned there still leads to a fee). This is
    // where a Direct Debit mandate is set up and can change.
    private static final Set<String> PRE_DECISION_STAGES = new Set<String>{
        'New', 'Awaiting First Call', 'Call In Progress', 'Partial Data', 'Data Complete',
        'Ready for Review', 'Reviewed', 'Awaiting Bank Details', 'Filling', 'Ready for Submit',
        'Submitted', 'Needs Human', 'Awaiting DWP Decision', 'Special Rules Fast-Track',
        'Awaiting SR1 from GP', 'Awaiting Posted Pack Return',
        'Mandatory Reconsideration Requested', 'Appeal Lodged'
    };
    // Template category per trigger event. An event that is not listed has no
    // stage gate (call reminders, the submitted notice, chases, manual sends).
    @TestVisible private static final Map<String, String> CATEGORY_BY_EVENT = new Map<String, String>{
        'Bacs_Advance_Notice'         => 'FeeCollection',
        'Fee_Charged'                 => 'FeeCollection',
        'Fee_Receipt'                 => 'FeeOutcome',
        'Fee_Receipt_Installment'     => 'FeeOutcome',
        'Fee_Failed_Contact_Client'   => 'FeeOutcome',
        // The welcome pack attaches the Direct Debit mandate and talks about
        // the fee, so it is a Direct Debit message too.
        'Intake_Created'              => 'DirectDebit',
        'DD_Setup'                    => 'DirectDebit',
        'DD_Mandate_Confirmed'        => 'DirectDebit',
        'DD_Mandate_Failed'           => 'DirectDebit',
        'Application_Approved_by_DWP' => 'DecisionAwarded',
        'Application_Rejected_by_DWP' => 'DecisionRefused'
    };
    // Allow-list per category: a stage not listed (including a new picklist
    // value nobody classified yet) blocks the send, which fails safe.
    @TestVisible private static final Map<String, Set<String>> ALLOWED_STAGES = buildAllowedStages();
    private static Map<String, Set<String>> buildAllowedStages() {
        Set<String> feeOutcome = new Set<String>(FEE_DUE_STAGES);
        feeOutcome.add('Closed - Paid'); // the final receipt is sent right after the case closes as paid
        Set<String> directDebit = new Set<String>(PRE_DECISION_STAGES);
        directDebit.addAll(FEE_DUE_STAGES);
        return new Map<String, Set<String>>{
            'FeeCollection'   => new Set<String>(FEE_DUE_STAGES),
            'FeeOutcome'      => feeOutcome,
            'DirectDebit'     => directDebit,
            // The decision message only while the record still says so: a stage
            // set by mistake and corrected before the job runs sends nothing.
            'DecisionAwarded' => new Set<String>{ 'Awarded', 'Fee Charged', 'Change of Circumstances Review' },
            'DecisionRefused' => new Set<String>{ 'Closed - Refused', 'Mandatory Reconsideration Requested', 'Appeal Lodged' }
        };
    }

    /**
     * The stage gate, public so other classes follow the SAME list instead of
     * keeping their own (audit 2026-10-02 wave 4, W4-1). Above all for
     * AA_FeeInstallmentScheduler: it stamps Bacs_Notice_Sent__c as soon as
     * dispatch() returns and then lets the charge go ahead, so if it noticed
     * and collected in a stage this gate blocks (e.g. 'Mandatory
     * Reconsideration Requested' after a lower-rate award), the client would
     * be charged with no 5-day advance notice. The scheduler therefore builds
     * its COLLECTABLE_STAGES from allowedStagesFor('Bacs_Advance_Notice')
     * (minus its HALT_STAGES) and notices and collects only there.
     *
     * allowedStagesFor: a COPY of the allow-list for the event, or null when
     * the event has no stage gate (call reminders, chases, manual sends).
     * stageAllows: true when the event is not gated or the stage is listed;
     * a blank or unclassified stage is blocked, as in execute().
     */
    public static Set<String> allowedStagesFor(String triggerEvent) {
        Set<String> allowed = ALLOWED_STAGES.get(CATEGORY_BY_EVENT.get(triggerEvent));
        return allowed == null ? null : new Set<String>(allowed);
    }

    public static Boolean stageAllows(String triggerEvent, String stage) {
        Set<String> allowed = ALLOWED_STAGES.get(CATEGORY_BY_EVENT.get(triggerEvent));
        return allowed == null || allowed.contains(stage);
    }
    // DWP decision messages sent automatically on a stage change (W3-1). Each
    // goes to a client once, ever (see the dedup in execute()).
    @TestVisible private static final Map<String, String> OUTCOME_EVENT_BY_STAGE = new Map<String, String>{
        'Awarded'          => 'Application_Approved_by_DWP',
        'Closed - Refused' => 'Application_Rejected_by_DWP'
    };
    @TestVisible private static final Set<String> ONCE_PER_APP_EVENTS = new Set<String>(OUTCOME_EVENT_BY_STAGE.values());

    // ─── queueable state ────────────────────────────────────────────
    private final Set<Id> appIds;
    private final String  triggerEvent;
    // true = re-send of an event whose email was held for a missing per-app
    // file (AA_WelcomePackWatchdog). Dedup then looks at EVERY earlier Sent row
    // for the template+app, not just the last 24 h, so only the parts that
    // never went out are sent.
    private final Boolean resendHeld;

    private AA_MessageDispatcher(Set<Id> appIds, String triggerEvent) {
        this(appIds, triggerEvent, false);
    }

    private AA_MessageDispatcher(Set<Id> appIds, String triggerEvent, Boolean resendHeld) {
        this.appIds       = appIds;
        this.triggerEvent = triggerEvent;
        this.resendHeld   = resendHeld == true;
    }

    // ═════════════════════════ HELPERS ══════════════════════════════

    /**
     * Fernando 2026-08-19: file naming convention across the org is
     * "{AppName}_{First}_{Last}_{DocType with spaces}" (example he showed:
     * PC00033_Fernando_Rampon_Pre Submit.pdf). Legacy titles like
     * "AA_Welcome_Guide" get normalised to "Welcome Guide" (strip AA_,
     * swap underscores for spaces) so template config values + StaticResource
     * DevNames don't have to change. Node-side twin lives in
     * src/webhooks/gocardless-internal.js.
     */
    @TestVisible
    private static String friendlyDocTitle(AA_Application__c app, String rawDocType) {
        if (app == null || String.isBlank(rawDocType)) return rawDocType;
        String docType = rawDocType.startsWith('AA_')
            ? rawDocType.substring(3).replace('_', ' ')
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
        return run(new AA_MessageDispatcher(appIds, triggerEvent));
    }

    /**
     * Re-send of an event whose email was held for a missing per-app file
     * (audit 2026-10-02 F73), used by AA_WelcomePackWatchdog once the file
     * has landed. Same as dispatch() except dedup: any earlier Sent row for
     * the template+app (at any time) skips it, so the held email and its held
     * SMS go out and nothing that already went is repeated.
     */
    public static Id dispatchHeldResend(Set<Id> appIds, String triggerEvent) {
        if (appIds == null || appIds.isEmpty() || String.isBlank(triggerEvent)) return null;
        return run(new AA_MessageDispatcher(appIds, triggerEvent, true));
    }

    /**
     * DWP decision messages (owner decision 2026-10-02, W3-1): an application
     * whose Stage__c has just moved INTO 'Awarded' gets
     * Application_Approved_by_DWP, into 'Closed - Refused' gets
     * Application_Rejected_by_DWP. Until then both templates were active but
     * dispatched by nothing (audit F76). Called from the after-update trigger
     * AA_ApplicationNeedsHumanNotifyTrigger. Do Not Contact, the stage gate and
     * the once-per-application dedup are applied by execute(), like any send.
     * No job is enqueued when the event has no active template.
     */
    private static Set<String> outcomeDispatchedThisTxn = new Set<String>();

    public static void dispatchStageOutcomes(List<AA_Application__c> newList, Map<Id, AA_Application__c> oldMap) {
        if (newList == null || oldMap == null) return;
        Map<String, Set<Id>> appsByEvent = new Map<String, Set<Id>>();
        for (AA_Application__c app : newList) {
            AA_Application__c prev = oldMap.get(app.Id);
            if (prev == null || app.Stage__c == prev.Stage__c) continue;
            String ev = OUTCOME_EVENT_BY_STAGE.get(app.Stage__c);
            if (ev == null) continue;
            // A trigger re-fire in the same transaction (workflow / flow field
            // update) sees the same old stage; enqueue once. Two parallel jobs
            // could both pass the Sent-row dedup before either logs.
            if (!outcomeDispatchedThisTxn.add(ev + '|' + app.Id)) continue;
            if (!appsByEvent.containsKey(ev)) appsByEvent.put(ev, new Set<Id>());
            appsByEvent.get(ev).add(app.Id);
        }
        if (appsByEvent.isEmpty()) return;
        Set<String> live = new Set<String>();
        for (AA_Message_Template__c t : [
                SELECT Trigger_Event__c FROM AA_Message_Template__c
                 WHERE Active__c = true AND Trigger_Event__c IN :appsByEvent.keySet()]) {
            live.add(t.Trigger_Event__c);
        }
        for (String ev : appsByEvent.keySet()) {
            if (live.contains(ev)) dispatch(appsByEvent.get(ev), ev);
        }
    }

    private static Id run(AA_MessageDispatcher job) {
        if (System.isFuture() || System.isBatch()) {
            job.execute(null); // nested async: run sync (no extra enqueue allowed)
            return null;
        }
        return System.enqueueJob(job);
    }

    /**
     * Of these apps, the ones whose email(s) for this event would NOT be held
     * today: every Attach_App_File_Titles__c entry of every active Email
     * template is either on the application's Files (friendly title) or has
     * a generic static stand-in (staticFallbackName). Do-Not-Contact apps are
     * left out (the dispatcher would only suppress them). Metadata-only
     * queries (no VersionData), so the watchdog can check many apps at once.
     */
    public static Set<Id> appsWithAttachmentsReady(Set<Id> appIds, String triggerEvent) {
        Set<Id> out = new Set<Id>();
        if (appIds == null || appIds.isEmpty() || String.isBlank(triggerEvent)) return out;
        List<AA_Message_Template__c> emailTpls = [
            SELECT Id, Attach_App_File_Titles__c
              FROM AA_Message_Template__c
             WHERE Active__c = true AND Trigger_Event__c = :triggerEvent AND Channel__c = 'Email'];
        Map<Id, AA_Application__c> apps = new Map<Id, AA_Application__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c
              FROM AA_Application__c
             WHERE Id IN :appIds AND Do_Not_Contact__c = false]);
        if (apps.isEmpty()) return out;

        Set<String> rawTitles = new Set<String>();
        for (AA_Message_Template__c t : emailTpls) rawTitles.addAll(parseAttachmentList(t.Attach_App_File_Titles__c));
        if (rawTitles.isEmpty()) return apps.keySet().clone();

        Set<String> fallbackNames = new Set<String>();
        for (String rt : rawTitles) fallbackNames.add(staticFallbackName(rt));
        Set<String> staticPresent = new Set<String>();
        for (StaticResource sr : [SELECT Name FROM StaticResource WHERE Name IN :fallbackNames]) staticPresent.add(sr.Name);

        Set<String> expected = new Set<String>();
        for (AA_Application__c a : apps.values()) {
            for (String rt : rawTitles) expected.add(friendlyDocTitle(a, rt));
        }
        Set<String> onApp = new Set<String>();
        for (ContentDocumentLink l : [
                SELECT LinkedEntityId, ContentDocument.Title
                  FROM ContentDocumentLink
                 WHERE LinkedEntityId IN :apps.keySet()
                   AND ContentDocument.Title IN :expected]) {
            onApp.add(String.valueOf(l.LinkedEntityId) + '|' + l.ContentDocument.Title);
        }
        for (AA_Application__c a : apps.values()) {
            Boolean ready = true;
            for (String rt : rawTitles) {
                if (!onApp.contains(a.Id + '|' + friendlyDocTitle(a, rt))
                        && !staticPresent.contains(staticFallbackName(rt))) {
                    ready = false;
                    break;
                }
            }
            if (ready) out.add(a.Id);
        }
        return out;
    }

    // ═════════════════════════ QUEUEABLE BODY ═══════════════════════

    public void execute(QueueableContext ctx) {
        if (appIds == null || appIds.isEmpty() || String.isBlank(triggerEvent)) return;

        // 1. Active templates for this event ─────────────────────────
        List<AA_Message_Template__c> templates = [
            SELECT Id, Name, Channel__c, Trigger_Event__c,
                   Subject_Template__c, Body_Template__c,
                   Content_Text__c, Content_Mode__c,
                   Attachment_Static_Resource_Name__c,
                   Attach_App_File_Titles__c, Active__c
              FROM AA_Message_Template__c
             WHERE Active__c = true
               AND Trigger_Event__c = :triggerEvent
        ];
        if (templates.isEmpty()) return;

        // 2. Apps ────────────────────────────────────────────────────
        Map<Id, AA_Application__c> appMap = new Map<Id, AA_Application__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c,
                   Email__c, Phone__c, DWP_Reference__c,
                   Stage__c, Stage_Changed_At__c, Sales_Agent__c, Val_Agent__c,
                   DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c,
                   Fee_Plan_Installments__c, Award_Amount__c, Fee_Amount__c,
                   Helper_First_Name__c, Helper_Last_Name__c, Helper_Email__c, Helper_Phone__c,
                   Do_Not_Contact__c, SMS_Opt_Out__c, Client_Form_URL__c, Signature__c
              FROM AA_Application__c
             WHERE Id IN :appIds
        ]);
        if (appMap.isEmpty()) return;

        // 3. Latest AA_Call_Schedule__c per app (CallDate / CallTime) ─
        Map<Id, Datetime> latestCallByApp = loadLatestCalls(appMap.keySet());
        // 3b. Current AA_Fee_Installment__c per app — for the per-installment
        //     receipt merge tokens ({{FeeInstallmentNumber/Amount}}). One SOQL
        //     up-front keeps the send loop governor-clean (same idiom as
        //     loadLatestCalls / loadAppFiles).
        Map<Id, AA_Fee_Installment__c> currentInstByApp = loadCurrentInstallment(appMap.keySet());
        // 3c. Next PENDING installment per app — for the Bacs advance-notice
        //     tokens ({{FeeNextInstallmentNumber/Amount/Date}}), which describe
        //     the charge that is ABOUT to happen rather than the last one taken.
        Map<Id, AA_Fee_Installment__c> nextInstByApp = loadNextPendingInstallment(appMap.keySet());

        // 4. Dedup pre-check — one SOQL for all combos ───────────────
        Set<Id> templateIds = new Set<Id>();
        for (AA_Message_Template__c t : templates) templateIds.add(t.Id);
        // A held-resend counts every earlier Sent row (see dispatchHeldResend),
        // and so does a DWP decision message: once per application, ever.
        Boolean dedupForever = resendHeld || ONCE_PER_APP_EVENTS.contains(triggerEvent);
        Datetime cutoff = dedupForever
            ? Datetime.newInstanceGmt(2000, 1, 1)
            : Datetime.now().addHours(-DEDUP_HOURS);
        Set<String> recentSent = new Set<String>();
        for (AA_Message_Send_Log__c prior : [
                SELECT Template__c, Application__c
                  FROM AA_Message_Send_Log__c
                 WHERE Template__c IN :templateIds
                   AND Application__c IN :appIds
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

        // 5c. clients@ Org-Wide Email Address, once per run (null → the
        //     running user sends, as before; see buildEmail).
        Id clientsOweaId = loadClientsOwea();

        // 5d. Email templates first. An SMS for the same event (Intake_Created:
        //     welcome email + "check your email shortly" SMS) must know whether
        //     its email was held back for a missing attachment before it goes.
        templates = emailsFirst(templates);
        Set<Id> emailHeldForApp = new Set<Id>();
        List<String> heldSummaries = new List<String>();
        String dncStatus   = skipStatus(STATUS_SKIP_DNC);
        String optOutStatus = skipStatus(STATUS_SKIP_SMS_OPT_OUT);
        String gateStatus  = skipStatus(STATUS_SKIP_STAGE_GATE);
        Set<String> allowedStages = ALLOWED_STAGES.get(CATEGORY_BY_EVENT.get(triggerEvent)); // null = no gate

        // 6. Build sends ─────────────────────────────────────────────
        List<Messaging.SingleEmailMessage>    emailBatch     = new List<Messaging.SingleEmailMessage>();
        List<AA_Message_Send_Log__c>         emailLogs      = new List<AA_Message_Send_Log__c>();
        List<AA_Application__c>              emailApps      = new List<AA_Application__c>();
        List<AA_Message_Template__c>         emailTemplates = new List<AA_Message_Template__c>();
        List<AA_Message_Send_Log__c>         pendingLogs    = new List<AA_Message_Send_Log__c>();
        List<TwilioSF__Message__c>            twilioRows     = new List<TwilioSF__Message__c>();

        for (AA_Message_Template__c t : templates) {
            for (Id appId : appMap.keySet()) {
                AA_Application__c app = appMap.get(appId);
                AA_Message_Send_Log__c log = new AA_Message_Send_Log__c(
                    Template__c    = t.Id,
                    Application__c = appId,
                    Channel__c     = t.Channel__c
                );

                // Dedup guard ────────────────────────────────────────
                if (recentSent.contains(t.Id + '|' + appId)) {
                    log.Status__c      = 'Skipped-Deduped';
                    log.Sent_At__c     = Datetime.now();
                    log.Error_Message__c = resendHeld
                        ? 'Re-send of a held event: this part was already Sent earlier, so it is not repeated.'
                        : (dedupForever
                            ? 'Duplicate suppressed: this message goes to a client once, and it was already Sent.'
                            : 'Duplicate suppressed — a Sent row already exists for this template+app within ' + DEDUP_HOURS + 'h.');
                    pendingLogs.add(log);
                    continue;
                }

                // Do Not Contact guard (audit 2026-10-02 F54/F70; no
                // exceptions since the owner decision of 2026-10-02) ──────
                if (app.Do_Not_Contact__c == true) {
                    log.Status__c        = dncStatus;
                    log.Sent_At__c       = Datetime.now();
                    log.Error_Message__c = 'Suppressed: Do_Not_Contact__c is true on this application. Nothing was sent.';
                    pendingLogs.add(log);
                    continue;
                }

                // Stage gate (owner decision 2026-10-02) ─────────────
                if (allowedStages != null && !allowedStages.contains(app.Stage__c)) {
                    log.Status__c        = gateStatus;
                    log.Sent_At__c       = Datetime.now();
                    log.Error_Message__c = 'Suppressed: ' + triggerEvent + ' is a '
                        + CATEGORY_BY_EVENT.get(triggerEvent) + ' message and the application is in stage "'
                        + app.Stage__c + '", where it may not be sent. Nothing was sent.';
                    pendingLogs.add(log);
                    continue;
                }

                // SMS opt-out guard: SMS only; email and calls carry on ──
                if ('SMS'.equalsIgnoreCase(t.Channel__c) && app.SMS_Opt_Out__c == true) {
                    log.Status__c        = optOutStatus;
                    log.Sent_At__c       = Datetime.now();
                    log.Error_Message__c = 'Suppressed: SMS_Opt_Out__c is true (the client replied STOP). No SMS was sent; email and calls are not affected.';
                    pendingLogs.add(log);
                    continue;
                }

                // Render ─────────────────────────────────────────────
                Rendered rendered;
                try {
                    rendered = renderInternal(t, app, latestCallByApp.get(appId),
                        currentInstByApp.get(appId), nextInstByApp.get(appId));
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
                    Messaging.SingleEmailMessage builtMsg = buildEmail(t, app, rendered, resourceByName, appFileByKey, log, clientsOweaId);
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
                        // Audit 2026-10-02 F73: this used to be silent, so a
                        // client whose welcome pack failed to render simply
                        // never got the email. Remember it (to hold the SMS of
                        // the same event) and tell ops after the sends.
                        emailHeldForApp.add(appId);
                        heldSummaries.add(app.Name + ' (' + nvl(app.Full_Name__c) + ', ' + appId + '): '
                            + t.Trigger_Event__c + ' email held. ' + log.Error_Message__c);
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
                    // The intro SMS says "check your email shortly". If that
                    // email was just held for a missing attachment, hold the
                    // SMS too; a re-dispatch of the event sends both together
                    // (dedup only counts Sent rows). Audit 2026-10-02 F73.
                    if (emailHeldForApp.contains(appId)) {
                        log.Status__c        = 'Skipped-Missing-Attachment';
                        log.Sent_At__c       = Datetime.now();
                        log.Error_Message__c = 'Held back: the email for this event is waiting for its attachments. The SMS goes out with it when the event is re-sent.';
                        pendingLogs.add(log);
                        continue;
                    }
                    if (String.isBlank(app.Phone__c)) {
                        log.Status__c        = 'Failed';
                        log.Sent_At__c       = Datetime.now();
                        log.Error_Message__c = 'App has no Phone__c.';
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
        //   linked to the RelatedToId=AA_Application so it shows up in
        //   the Email Messages related list on the record page (Fernando
        //   2026-08-18: emails were sending but not appearing in the tab
        //   because SendEmail alone doesn't create EmailMessage records).
        // Parallel arrays so we can link attachments after EmailMessage.insert
        // returns Ids. `emailMessageAppFiles[i]` is the list of ContentVersion
        // Ids that were attached to the email at index i via
        // Attach_App_File_Titles__c (per-app files, e.g. AA_Mandate). We
        // rehydrate ContentDocumentLinks pointing at the new EmailMessage
        // so the SF Email Messages tab shows the attachments (setFileAttach
        // on Messaging.SingleEmailMessage only affects the outbound MIME —
        // it doesn't create any SF-side attachment link on its own).
        List<EmailMessage> emailMessagesToInsert = new List<EmailMessage>();
        List<AA_Application__c> emailMessageApps = new List<AA_Application__c>();
        List<List<Id>> emailMessageAppFiles = new List<List<Id>>();
        List<List<String>> emailMessageStaticRes = new List<List<String>>();
        if (!emailBatch.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results =
                    Messaging.sendEmail(emailBatch, false);
                for (Integer i = 0; i < results.size(); i++) {
                    AA_Message_Send_Log__c log = emailLogs[i];
                    Messaging.SingleEmailMessage sent = emailBatch[i];
                    AA_Application__c appI = emailApps[i];
                    AA_Message_Template__c tI = emailTemplates[i];
                    Messaging.SendEmailResult r = results[i];
                    if (r.isSuccess()) {
                        log.Status__c = 'Sent';
                        // Mirror build runs in its OWN try so a post-send failure
                        // (e.g. today's AES bug) can never downgrade an already-
                        // delivered email's log to Failed — that false Failed also
                        // defeated dedup and caused duplicate client emails.
                        try {
                        // Mirror sent email into EmailMessage for the tab.
                        Boolean hasAttach = (sent.getFileAttachments() != null && !sent.getFileAttachments().isEmpty());
                        EmailMessage em = new EmailMessage();
                        em.RelatedToId   = appI.Id;
                        em.Subject       = sent.getSubject();
                        em.HtmlBody      = sent.getHtmlBody();
                        em.TextBody      = sent.getPlainTextBody();
                        // 2026-08-28: From/Reply-To/MessageIdentifier so the shared
                        // inbound handler can thread replies back to this app
                        // (parity with PC1_MessageDispatcher). clients@ is a
                        // verified Org-Wide Email Address.
                        em.FromAddress   = 'clients@xtrapension.com';
                        em.FromName      = 'XtraPension';
                        em.ValidatedFromAddress = 'clients@xtrapension.com';
                        // NB: Crypto.generateAesKey only accepts 128/192/256 —
                        // PC1's audit-fix used 64, which throws "Invalid size for
                        // AES key generation" and silently killed the mirror.
                        String msgId = String.valueOf(appI.Id) + '-' + String.valueOf(tI.Id) + '-' +
                            EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16) + '@xtrapension.com';
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
                        // Generic static PDFs that stood in for a missing per-app
                        // file (see buildEmail) went out too: file them as well.
                        for (String rawType : parseAttachmentList(tI.Attach_App_File_Titles__c)) {
                            String fullTitle = friendlyDocTitle(appI, rawType);
                            Boolean hadAppFile = appFileByKey != null && appFileByKey.containsKey(appI.Id + '|' + fullTitle);
                            String fb = staticFallbackName(rawType);
                            // Marked so linkEmailAttachments files it under a
                            // "(general copy)" title, never the personalised one.
                            if (!hadAppFile && resourceByName.containsKey(fb) && !staticNames.contains(FALLBACK_MARK + fb)) {
                                staticNames.add(FALLBACK_MARK + fb);
                            }
                        }
                        emailMessageStaticRes.add(staticNames);
                        } catch (Exception mirrorEx) {
                            System.debug(LoggingLevel.WARN,
                                'AA_MessageDispatcher: mirror build failed for app ' + appI.Id + ' (email WAS sent) — ' + mirrorEx.getMessage());
                        }
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
                // A throw here means Messaging.sendEmail itself failed — mirror
                // -build errors are caught per-record above and never reach here.
                // Never overwrite a 'Sent' outcome (the hole the AES bug used).
                for (AA_Message_Send_Log__c log : emailLogs) {
                    if (log.Status__c != 'Sent') {
                        log.Status__c        = 'Failed';
                        log.Error_Message__c = trunc('sendEmail exception: ' + e.getMessage(), 4000);
                    }
                }
                System.debug(LoggingLevel.ERROR,
                    'AA_MessageDispatcher: sendEmail block threw — ' + e.getMessage());
            }
        }

        // 8. Bulk DML — send logs + twilio rows ──────────────────────
        if (!pendingLogs.isEmpty()) {
            try { insert pendingLogs; }
            catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'AA_MessageDispatcher: send-log insert failed — ' + e.getMessage());
            }
        }
        if (!twilioRows.isEmpty()) {
            try { insert twilioRows; }
            catch (Exception e) {
                System.debug(LoggingLevel.WARN,
                    'AA_MessageDispatcher: TwilioSF row insert failed — ' + e.getMessage());
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
                    'AA_MessageDispatcher: EmailMessage mirror insert failed — ' + e.getMessage());
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
                        'AA_MessageDispatcher: EmailMessage flip-to-Sent failed — ' + e.getMessage());
                }
            }
        }

        // 9. Ops alert for held emails (audit 2026-10-02 F73). One digest per
        //    run, after every callout (an email send counts as pending work).
        if (!heldSummaries.isEmpty()) {
            AA_HandoffService.emailOps(
                'AA: ' + heldSummaries.size() + ' client email(s) held for a missing attachment',
                'These client emails were NOT sent because a per-application PDF is missing. '
                + 'Once the file is on the application, AA_WelcomePackWatchdog re-sends the '
                + 'event within the hour (for up to 7 days), with the SMS of the same event that was '
                + 'held too. If this repeats for the same client, the file is not landing: upload it '
                + 'by hand to the application\'s Files, titled {AppName}_{First}_{Last}_{Document} '
                + '(for example AA00012_Mary_Smith_Mandate).\n\n'
                + String.join(heldSummaries, '\n'));
        }
    }

    /** Email templates before SMS ones, otherwise in query order. */
    private static List<AA_Message_Template__c> emailsFirst(List<AA_Message_Template__c> tpls) {
        List<AA_Message_Template__c> emails = new List<AA_Message_Template__c>();
        List<AA_Message_Template__c> others = new List<AA_Message_Template__c>();
        for (AA_Message_Template__c t : tpls) {
            if ('Email'.equalsIgnoreCase(t.Channel__c)) emails.add(t); else others.add(t);
        }
        emails.addAll(others);
        return emails;
    }

    @TestVisible private static final String STATUS_SKIP_DNC          = 'Skipped-Do-Not-Contact';
    @TestVisible private static final String STATUS_SKIP_SMS_OPT_OUT  = 'Skipped-SMS-Opt-Out';
    @TestVisible private static final String STATUS_SKIP_STAGE_GATE   = 'Skipped-Stage-Gate';

    /**
     * Status for a suppressed send (Do Not Contact, SMS opt-out, stage gate).
     * Status__c is a restricted picklist and the org may not have the
     * dedicated value yet (each is added in sf-src first), so this returns the
     * value when it is active and 'Failed' (with an explicit "Suppressed:"
     * message) until then. 'Failed' never counts for dedup, so nothing is lost
     * when the flag is cleared or the stage changes.
     */
    @TestVisible
    private static String skipStatus(String preferred) {
        for (Schema.PicklistEntry pe : AA_Message_Send_Log__c.Status__c.getDescribe().getPicklistValues()) {
            if (pe.isActive() && pe.getValue() == preferred) return pe.getValue();
        }
        return 'Failed';
    }

    /** Id of the clients@ Org-Wide Email Address, or null when the org has none. */
    @TestVisible
    private static Id loadClientsOwea() {
        try {
            for (OrgWideEmailAddress o : [SELECT Id FROM OrgWideEmailAddress WHERE Address = :CLIENT_FROM_ADDRESS LIMIT 1]) {
                return o.Id;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AA_MessageDispatcher: OWEA lookup failed: ' + e.getMessage());
        }
        return null;
    }

    /**
     * Generic StaticResource that may stand in for a missing per-app file:
     * "Welcome Guide" -> AA_Welcome_Guide, "Service Agreement" ->
     * AA_Service_Agreement. There is no static Mandate, so a missing mandate
     * PDF still holds the email (it is personal and cannot be faked).
     */
    @TestVisible
    private static String staticFallbackName(String rawTitle) {
        if (String.isBlank(rawTitle)) return null;
        String t = rawTitle.trim();
        return t.startsWith('AA_') ? t : 'AA_' + t.replace(' ', '_');
    }

    // The generic stand-ins are NOT about one client: their cover lines are
    // neutral ("The person named in your welcome email", "The date of your
    // welcome email"; regenerate with
    //   node scripts/generate-service-agreement-pdf.cjs --client "The person named in your welcome email" --ref "In the subject line of your welcome email" --date "The date of your welcome email"
    //   node scripts/generate-welcome-pdf.cjs --client "The person named in your welcome email" --ref "In the subject line of your welcome email" --date "With your welcome email"
    // and copy the PDFs over the .resource files). So they must not LOOK
    // personalised either (audit 2026-10-02 W1 review of F73): the client
    // sees "XtraPension Service Agreement.pdf", and the copy filed on the
    // application is titled "<AppName>_Service Agreement (general copy)", which
    // also keeps it from being mistaken for the per-app render by
    // loadAppFiles / appsWithAttachmentsReady (they look for the personal title).
    @TestVisible private static final String FALLBACK_MARK = 'fallback:';

    /** "AA_Service_Agreement" or "Service Agreement" -> "Service Agreement". */
    private static String docTypeOf(String raw) {
        if (String.isBlank(raw)) return raw;
        String t = raw.trim();
        return t.startsWith('AA_') ? t.substring(3).replace('_', ' ') : t;
    }

    /** File name the client sees for a generic stand-in PDF. */
    @TestVisible
    private static String fallbackFileName(String rawTitle) {
        return 'XtraPension ' + docTypeOf(rawTitle) + '.pdf';
    }

    /** StaticResource name behind a staticNames entry (strips FALLBACK_MARK). */
    private static String resourceNameOf(String n) {
        return (n != null && n.startsWith(FALLBACK_MARK)) ? n.substring(FALLBACK_MARK.length()) : n;
    }

    /** Title of the ContentVersion a static PDF is filed under on the app. */
    @TestVisible
    private static String staticCvTitle(AA_Application__c app, String n) {
        if (n != null && n.startsWith(FALLBACK_MARK)) {
            return app.Name + '_' + docTypeOf(resourceNameOf(n)) + ' (general copy)';
        }
        return friendlyDocTitle(app, n);
    }

    // ─── EmailMessage attachment linking ─────────────────────────────
    // Two goals per Fernando (2026-08-18):
    //   1) Attachments appear on the EmailMessage in the SF Email Messages
    //      tab (linked via ContentDocumentLink).
    //   2) Static-resource-backed PDFs (Welcome guide + Service agreement)
    //      also appear in the record's Files section — we materialise them
    //      as ContentVersion on the app once + reuse on later sends.
    // Per-app files (AA_Mandate) are already ContentVersions on the app
    // (uploaded by Node) — we just link them to the EmailMessage. All
    // steps best-effort so a permission bump doesn't break the send audit.
    private static void linkEmailAttachments(
            List<EmailMessage> ems,
            List<AA_Application__c> apps,
            List<List<Id>> perAppCvIds,
            List<List<String>> staticNames) {
        if (ems == null || ems.isEmpty()) return;

        // Load static resource bodies once per unique name across the batch.
        Set<String> allNames = new Set<String>();
        for (List<String> names : staticNames) {
            if (names == null) continue;
            for (String n : names) allNames.add(resourceNameOf(n));
        }
        Map<String, StaticResource> resByName = new Map<String, StaticResource>();
        if (!allNames.isEmpty()) {
            for (StaticResource sr : [SELECT Id, Name, Body, ContentType FROM StaticResource WHERE Name IN :allNames]) {
                resByName.put(sr.Name, sr);
            }
        }

        // Idempotency lookup: has THIS app already got a ContentVersion
        // titled <name>? If yes, reuse; if no, create fresh linked to the
        // app so it lands in the Files section. Keyed as 'appId|title'.
        Set<Id> appIds = new Set<Id>();
        for (AA_Application__c a : apps) if (a != null) appIds.add(a.Id);
        Map<String, Id> existingCvByAppTitle = new Map<String, Id>();
        Map<Id, Id> docByCv = new Map<Id, Id>();
        // Static-resource CVs are stored under FRIENDLY per-app titles
        // (friendlyDocTitle), never the raw DevName, so the idempotency query
        // must look for the friendly titles — otherwise it matches nothing,
        // re-creates a duplicate CV every send, and fails to link them to the
        // mirror EmailMessage below (audit 2026-08-28).
        Set<String> expectedFriendly = new Set<String>();
        for (Integer i = 0; i < apps.size(); i++) {
            if (apps[i] == null) continue;
            for (String name : (staticNames.size() > i ? staticNames[i] : new List<String>())) {
                expectedFriendly.add(staticCvTitle(apps[i], name));
            }
        }
        if (!appIds.isEmpty() && !expectedFriendly.isEmpty()) {
            for (ContentDocumentLink l : [
                SELECT LinkedEntityId,
                       ContentDocument.Title,
                       ContentDocument.LatestPublishedVersionId,
                       ContentDocumentId
                  FROM ContentDocumentLink
                 WHERE LinkedEntityId IN :appIds
                   AND ContentDocument.Title IN :expectedFriendly
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
                // ("AA_Welcome_Guide") to a friendly per-app title
                // ("PC00137_John_Ryan_Welcome Guide") on write. Lookup key
                // used further below MUST match this same friendly title.
                AA_Application__c app = apps[i];
                String friendlyTitle = staticCvTitle(app, name);
                String key = String.valueOf(appId) + '|' + friendlyTitle;
                if (existingCvByAppTitle.containsKey(key)) continue; // already in Files
                StaticResource sr = resByName.get(resourceNameOf(name));
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
                    'AA_MessageDispatcher: static-resource CV insert failed — ' + e.getMessage());
            }
        }

        // Resolve per-app CVs (AA_Mandate etc) to their ContentDocumentIds
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
            for (String name : (staticNames.size() > i ? staticNames[i] : new List<String>())) {
                if (appId == null) continue;
                Id cvId = existingCvByAppTitle.get(String.valueOf(appId) + '|' + staticCvTitle(apps[i], name));
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
                    'AA_MessageDispatcher: EmailMessage attachment link insert failed — ' + e.getMessage());
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
        List<AA_Message_Template__c> tpls = [
            SELECT Id, Name, Channel__c, Trigger_Event__c,
                   Subject_Template__c, Body_Template__c,
                   Content_Text__c, Content_Mode__c,
                   Attachment_Static_Resource_Name__c
              FROM AA_Message_Template__c
             WHERE Id = :templateId LIMIT 1];
        if (tpls.isEmpty()) throw new AuraHandledException('Template not found.');
        List<AA_Application__c> apps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c,
                   Email__c, Phone__c, DWP_Reference__c,
                   Stage__c, Stage_Changed_At__c, Sales_Agent__c, Val_Agent__c,
                   DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c,
                   Fee_Plan_Installments__c, Award_Amount__c, Fee_Amount__c,
                   Helper_First_Name__c, Helper_Last_Name__c, Helper_Email__c, Helper_Phone__c,
                   Do_Not_Contact__c, Client_Form_URL__c, Signature__c
              FROM AA_Application__c WHERE Id = :appId LIMIT 1];
        if (apps.isEmpty()) throw new AuraHandledException('Application not found.');
        Datetime callAt = loadLatestCalls(new Set<Id>{ apps[0].Id }).get(apps[0].Id);
        AA_Fee_Installment__c inst = loadCurrentInstallment(new Set<Id>{ apps[0].Id }).get(apps[0].Id);
        AA_Fee_Installment__c nextInst = loadNextPendingInstallment(new Set<Id>{ apps[0].Id }).get(apps[0].Id);
        try {
            return renderInternal(tpls[0], apps[0], callAt, inst, nextInst);
        } catch (RenderException re) {
            // Preserve the LWC preview's readable message — RenderException
            // carries the real token; re-throw as AuraHandledException for Aura.
            throw new AuraHandledException(re.getMessage());
        }
    }

    // Internal render — no @AuraEnabled. Same throw-on-unknown-token contract.
    // If Content_Mode__c = Simple, resolve merges against Content_Text__c and
    // wrap the result in the XtraPension email shell (Body_Template__c is
    // ignored on send-path). If Advanced (or blank content-text), resolve
    // against Body_Template__c as before.
    private static Rendered renderInternal(
            AA_Message_Template__c t, AA_Application__c app, Datetime latestCall,
            AA_Fee_Installment__c inst, AA_Fee_Installment__c nextInst) {
        Map<String, String> vals = buildMergeMap(app, latestCall, inst, nextInst);
        Boolean isEmail  = 'Email'.equalsIgnoreCase(t.Channel__c);
        Boolean isSimple = 'Simple'.equalsIgnoreCase(t.Content_Mode__c)
            && String.isNotBlank(t.Content_Text__c);
        // Simple content is either rich text from the LWC (trusted as HTML) or
        // legacy plain text that simpleToHtml escapes. Take that verdict on the
        // TEMPLATE, before any client value is merged in, and carry it to the
        // renderer — a raw value's "<p>" must never get to choose the pipeline.
        Boolean simpleIsHtml = isSimple && AA_EmailShellRenderer.looksLikeHtml(t.Content_Text__c);

        // HTML-escape merge VALUES so client-controlled data (First_Name__c
        // etc.) can never inject markup into the HTML body or the mirrored
        // EmailMessage (audit 2026-08-28) — but exactly ONCE per path:
        //   Email + Simple + plain-text content → simpleToHtml escapes the whole
        //     merged string downstream, so pre-escaping here double-encoded
        //     every & ' < > in a name or address and claimants read the literal
        //     "O&#39;Connor &amp; Sons" (fixed 2026-09-11). Values stay raw.
        //   Email + Simple + HTML content → simpleToHtml trusts the string as
        //     rich text, so values MUST be pre-escaped here.
        //   Email + Advanced (Body_Template__c) → no later pass; pre-escape.
        //   Subject + SMS → plain text, never escaped.
        // Advanced (Body_Template__c) email whose body is NOT HTML: buildEmail
        // used to send it as text/plain, but the values had been pre-escaped
        // for HTML, so the client read literal ** markers and "O&#39;Connor"
        // (live MSG-0003 until its re-seed; audit 2026-10-02 F77). Route it
        // through the same plain-text shell pipeline as Simple content: values
        // stay raw and simpleToHtml escapes the merged text exactly once.
        Boolean advancedPlainEmail = isEmail && !isSimple
            && String.isNotBlank(t.Body_Template__c)
            && !AA_EmailShellRenderer.looksLikeHtml(t.Body_Template__c);
        Boolean preEscape = isEmail && !(isSimple && !simpleIsHtml) && !advancedPlainEmail;
        Map<String, String> bodyVals = preEscape ? htmlEscapeVals(vals) : vals;

        Rendered out = new Rendered();
        out.subject = resolve(t.Subject_Template__c, vals);

        if (advancedPlainEmail) {
            out.body = AA_EmailShellRenderer.wrap(resolve(applyConditionals(t.Body_Template__c, vals), vals), false);
        } else if (isSimple) {
            String mergedContent = resolve(applyConditionals(t.Content_Text__c, vals), bodyVals);
            // Only wrap in the HTML shell for Email — SMS stays plain text.
            out.body = isEmail
                ? AA_EmailShellRenderer.wrap(mergedContent, simpleIsHtml)
                : mergedContent;
        } else {
            out.body = resolve(applyConditionals(t.Body_Template__c, vals), bodyVals);
        }
        out.resolvedMerges = vals;
        return out;
    }

    // <!--if:Token--> ... <!--endif:Token--> keeps the enclosed part only when
    // the token has a value (owner decision 2026-10-02, W3-5). Made for
    // {{ClientFormUrl}}, which is blank until the record is signed: without it
    // the welcome email would show a "your personal link" paragraph with an
    // empty link. HTML comments, so a template sent by an older dispatcher
    // still renders (both parts, nothing broken), and resolve()'s token regex
    // never sees them.
    private static final Pattern COND_RX = Pattern.compile(
        '(?s)<!--\\s*if:([A-Za-z0-9_]+)\\s*-->(.*?)<!--\\s*endif:\\1\\s*-->');

    @TestVisible
    private static String applyConditionals(String text, Map<String, String> vals) {
        if (String.isBlank(text) || !text.contains('<!--')) return text;
        Matcher mt = COND_RX.matcher(text);
        String out = '';
        Integer last = 0;
        while (mt.find()) {
            out += text.substring(last, mt.start());
            String tok = mt.group(1);
            if (!vals.containsKey(tok)) {
                // Same contract as resolve(): a typo must fail the render, not
                // silently drop (or keep) the block.
                throw new RenderException('Unknown merge token in condition: <!--if:' + tok + '-->');
            }
            if (String.isNotBlank(vals.get(tok))) out += mt.group(2);
            last = mt.end();
        }
        out += text.substring(last);
        return out;
    }

    /** HTML-escape every VALUE in a merge map (for Email body renders) so
     *  client-controlled data can't inject markup. Tokens/keys untouched. */
    private static Map<String, String> htmlEscapeVals(Map<String, String> vals) {
        Map<String, String> out = new Map<String, String>();
        for (String k : vals.keySet()) {
            String v = vals.get(k);
            out.put(k, v == null ? '' : v.escapeHtml4());
        }
        return out;
    }

    // ═════════════════════════ MERGE MAP ════════════════════════════

    private static Map<String, String> buildMergeMap(
            AA_Application__c app, Datetime latestCall, AA_Fee_Installment__c inst,
            AA_Fee_Installment__c nextInst) {
        Map<String, String> m = new Map<String, String>();
        m.put('FirstName',      nvl(app.First_Name__c));
        m.put('LastName',       nvl(app.Last_Name__c));
        m.put('FullName',       nvl(app.Full_Name__c));
        m.put('ApplicationRef', nvl(app.Name));
        // NB DWP_Reference__c holds the client's NINO (src/fill/worker.js), so
        // client copy should not print it (audit 2026-10-02 F77).
        m.put('DWPReference',   nvl(app.DWP_Reference__c));
        // Signed self-service form link (audit 2026-10-02 F179). Blank until
        // the record is really signed: the formula would otherwise print a
        // link ending "?t=UNSIGNED" (or AA_UrlSigner's "UNCONFIGURED" marker)
        // that the form rejects.
        Boolean signed = String.isNotBlank(app.Signature__c) && app.Signature__c != 'UNCONFIGURED';
        m.put('ClientFormUrl',  signed ? nvl(app.Client_Form_URL__c) : '');
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

        // Fee amount — Fee_Amount__c, the formula 20% of the ANNUAL
        // Award_Amount__c. Rendered by money() — "1,148.16", no currency symbol
        // — the same convention as the installment amounts below: the templates
        // supply the "£". Guard on Award_Amount__c rather than the formula
        // — Fee_Amount__c is BlankAsZero, so before an award it reads 0.00, not
        // null, and a pre-award template would print "£0.00". Until the audit
        // of 2026-09-09 this was a PC1 placeholder string, so every money
        // email told the client "£[fee amount, calculated post-award]".
        m.put('FeeAmount', (app.Award_Amount__c != null && app.Fee_Amount__c != null)
            ? money(app.Fee_Amount__c) : '');

        // Per-installment receipt tokens (Fee_Receipt_Installment / MSG-0011).
        // Without these three, resolve() throws "Unknown merge token" the moment
        // that template renders. Number + amount come from the current
        // AA_Fee_Installment__c row; the planned total comes from the parent
        // Application's fee plan. All fall through to '' when there is no
        // installment context, so any template that doesn't use them (or a
        // preview on an app with no installments) still renders safely.
        m.put('FeeInstallmentNumber', (inst != null && inst.Installment_Number__c != null)
            ? String.valueOf(inst.Installment_Number__c.intValue()) : '');
        m.put('FeeInstallmentTotal', app.Fee_Plan_Installments__c != null
            ? String.valueOf(app.Fee_Plan_Installments__c.intValue()) : '');
        m.put('FeeInstallmentAmount', (inst != null && inst.Amount__c != null)
            ? money(inst.Amount__c) : '');

        // Next-pending tokens for the Bacs advance notice (Bacs_Advance_Notice /
        // MSG-0008). That notice goes out 5 calendar days BEFORE a charge, while
        // its row is still 'pending', so it must state the amount about to be
        // taken. The receipt tokens above cannot do that — loadCurrentInstallment
        // excludes pending rows, so at notice time they hold the PREVIOUS
        // installment (or nothing before the first). Announcing {{FeeAmount}}
        // instead was worse: under a 3x plan it told the client we would take
        // three times what was actually debited (audit 2026-09-09). '' when
        // nothing is pending, like the tokens above.
        m.put('FeeNextInstallmentNumber', (nextInst != null && nextInst.Installment_Number__c != null)
            ? String.valueOf(nextInst.Installment_Number__c.intValue()) : '');
        m.put('FeeNextInstallmentAmount', (nextInst != null && nextInst.Amount__c != null)
            ? money(nextInst.Amount__c) : '');
        // The collection date itself. The scheduler sweeps T+1..T+5 so a missed
        // cron run catches up, which means the notice can go out anywhere from
        // five days to one day ahead — a body that says "in 5 days" is then a
        // wrong date on a Bacs advance notice. Stating Scheduled_Date__c is right
        // on every day of the window (review 2026-09-11).
        m.put('FeeNextInstallmentDate', (nextInst != null && nextInst.Scheduled_Date__c != null)
            ? ukDate(nextInst.Scheduled_Date__c) : '');

        // Direct Debit mandate metadata — populated by the GoCardless flow
        // (AA_GoCardlessController.createMandateForApplication). These are
        // used by the Welcome Email template to show the client that their
        // DD is in place; templates that fire before the mandate exists
        // still render safely (values fall through to empty strings).
        m.put('MandateId',        nvl(app.DD_Mandate_Id__c));
        m.put('MandateStatus',    nvl(app.DD_Mandate_Status__c));
        m.put('MandateCreatedAt', app.DD_Mandate_Created_At__c == null
            ? '' : app.DD_Mandate_Created_At__c.format('dd/MM/yyyy', TZ_UK));

        // XtraPension constants — resolved via AA_Config__c so they stay in
        // sync with the shell footer. Fallbacks live in EmailShellRenderer.
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String xpPhone = (cfg != null && String.isNotBlank(cfg.XP_Phone__c))
            ? cfg.XP_Phone__c : '+353 1 254 4116';
        String xpEmail = (cfg != null && String.isNotBlank(cfg.XP_Email__c))
            ? cfg.XP_Email__c : 'help@xtrapension.com';
        m.put('XPPhone', xpPhone);
        m.put('XPEmail', xpEmail);
        // Match the footer's token vocabulary (AA_EmailShellRenderer resolves
        // XPWhatsApp + XPOffice too) so a body/subject that uses them doesn't hit
        // resolve()'s unknown-token throw and fail the template (audit 2026-08-28).
        m.put('XPWhatsApp', (cfg != null && String.isNotBlank(cfg.XP_WhatsApp__c)) ? cfg.XP_WhatsApp__c : '');
        m.put('XPOffice',   (cfg != null && String.isNotBlank(cfg.XP_Office__c))   ? cfg.XP_Office__c   : '');

        return m;
    }

    private static final Pattern TOKEN_RX = Pattern.compile('\\{\\{\\s*([A-Za-z0-9_]+)\\s*\\}\\}');

    /** Resolve all {{Token}} in text against vals. Unknown token → throw. */
    private static String resolve(String text, Map<String, String> vals) {
        if (String.isBlank(text)) return text;
        Matcher mt = TOKEN_RX.matcher(text);
        String out = '';
        Integer last = 0;
        while (mt.find()) {
            out += text.substring(last, mt.start());
            String tok = mt.group(1);
            if (!vals.containsKey(tok)) {
                // Custom exception (not AuraHandledException) so the dispatch
                // catch's getMessage() surfaces the real token in the send log
                // instead of a generic "Script-thrown exception" (audit 2026-08-28).
                throw new RenderException('Unknown merge token: {{' + tok + '}}');
            }
            out += nvl(vals.get(tok));
            last = mt.end();
        }
        out += text.substring(last);
        return out;
    }

    // ═════════════════════════ EMAIL BUILD ══════════════════════════

    private static Messaging.SingleEmailMessage buildEmail(
            AA_Message_Template__c t, AA_Application__c app,
            Rendered rendered, Map<String, StaticResource> resources,
            Map<String, ContentVersion> appFiles,
            AA_Message_Send_Log__c log, Id clientsOweaId) {
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
        msg.setSubject(String.isBlank(rendered.subject) ? '(no subject)' : rendered.subject);

        String body = rendered.body == null ? '' : rendered.body;
        if (body.contains('<html') || body.contains('<body') || body.contains('<p>')) {
            msg.setHtmlBody(body);
            // Strip tags, collapse whitespace, THEN unescape. The HTML body
            // carries entities (&amp; &#39;), and a text/plain alternative that
            // keeps them shows the claimant a literal "O&#39;Connor &amp; Sons".
            // Unescape LAST so escaped markup becomes the literal text the
            // client typed rather than a live tag.
            msg.setPlainTextBody(body.replaceAll('<[^>]+>', ' ').replaceAll('\\s+', ' ').trim().unescapeHtml4());
        } else {
            msg.setPlainTextBody(body);
        }
        msg.setSaveAsActivity(false);
        msg.setUseSignature(false);

        // 2026-08-28: set Reply-To to clients@ so client replies land in the
        // monitored inbox (routed back to this app by ClientSupportEmailService-
        // Handler). The From is the running user / org-wide address; Reply-To
        // overrides it so replies reach a human. SenderDisplayName shows
        // "XtraPension" in the client's inbox. Mirrors PC1_MessageDispatcher.
        msg.setReplyTo(CLIENT_FROM_ADDRESS);
        // Audit 2026-10-02 F74: without an Org-Wide address the From was the
        // RUNNING user (fernando@ for every cron and JWT-driven send) while the
        // mirror recorded clients@. Salesforce refuses an OWEA together with a
        // sender display name, so the display name is only the fallback.
        if (clientsOweaId != null) {
            msg.setOrgWideEmailAddressId(clientsOweaId);
        } else {
            msg.setSenderDisplayName('XtraPension');
        }

        // Attachments — two orthogonal sources:
        //   1) Attachment_Static_Resource_Name__c  → comma-list of StaticResource DevNames
        //   2) Attach_App_File_Titles__c            → comma-list of ContentDocument.Title
        //      values to pull from the RECIPIENT'S AA_Application__c files.
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
            // appFiles is keyed by the FRIENDLY per-app title (friendlyDocTitle),
            // not the raw config title — convert before the lookup, else every
            // per-app attachment reads as "missing" and the whole email is
            // skipped (this silently killed the Welcome email; audit 2026-08-28).
            ContentVersion cv = appFiles == null ? null : appFiles.get(app.Id + '|' + friendlyDocTitle(app, title));
            StaticResource fallback = resources == null ? null : resources.get(staticFallbackName(title));
            if (cv != null && cv.VersionData != null) {
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                // Prefer PathOnClient (has the real extension) but fall back
                // to Title + .pdf so mandate PDFs get a sensible filename.
                String fname = String.isNotBlank(cv.PathOnClient) ? cv.PathOnClient : (title + '.pdf');
                att.setFileName(fname);
                att.setBody(cv.VersionData);
                att.setContentType('application/pdf');
                atts.add(att);
            } else if (fallback != null && fallback.Body != null) {
                // Audit 2026-10-02 F73: when the personalised render failed
                // (Chromium down on the dyno, etc.) the generic static PDF of
                // the same document goes instead, so the welcome email is not
                // held for a cosmetic cover page. Only the per-app copy is
                // missing here, so the client still gets ONE copy of each.
                Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
                att.setFileName(fallbackFileName(title)); // generic name: it is not personalised
                att.setBody(fallback.Body);
                att.setContentType('application/pdf');
                atts.add(att);
                missing.add('fallback-static:' + staticFallbackName(title));
            } else {
                missing.add('app:' + title);
            }
        }

        if (!atts.isEmpty()) msg.setFileAttachments(atts);
        // Fernando 2026-08-18: never ship an email with a missing per-app
        // attachment. If AA_Mandate (or any other Attach_App_File_Titles
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
    private static Boolean hasMissingAppAttachment(AA_Message_Send_Log__c log) {
        if (log == null || String.isBlank(log.Error_Message__c)) return false;
        // Match the exact ", app:" / ": app:" marker: "fallback-static:" (a
        // per-app file replaced by its generic static PDF) must not hold the email.
        String m = log.Error_Message__c;
        return m.startsWith('Attachment(s) not found: ')
            && (m.contains(': app:') || m.contains(', app:'));
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
     * Mirrors AA_TwilioController.sendSMS — direct Twilio HTTP with BasicAuth
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

    /**
     * {{CallTime}}/{{CallDate}} source per app: the EARLIEST Pending slot from
     * the start of today (UK) onwards, i.e. the call that will actually happen.
     * Only when there is none, the latest slot of any status (history).
     * Audit 2026-10-02 F71: this used to take the latest slot of ANY status,
     * and a reschedule cancels the old row but keeps its time, so a call moved
     * EARLIER (Thu 15:00 -> Wed 10:00) made Wednesday's reminder say 15:00.
     */
    @TestVisible
    private static Map<Id, Datetime> loadLatestCalls(Set<Id> appIds) {
        Map<Id, Datetime> nextPending = new Map<Id, Datetime>();
        Map<Id, Datetime> latestAny   = new Map<Id, Datetime>();
        Datetime todayStartUk = AA_UkTime.ukDayBoundsUtc(Datetime.now())[0];
        for (AA_Call_Schedule__c cs : [
                SELECT Application__c, Scheduled_At__c, Status__c
                  FROM AA_Call_Schedule__c
                 WHERE Application__c IN :appIds AND Scheduled_At__c != null
                 ORDER BY Scheduled_At__c ASC]) {
            latestAny.put(cs.Application__c, cs.Scheduled_At__c); // ASC → last write wins = latest
            if (cs.Status__c == 'Pending' && cs.Scheduled_At__c >= todayStartUk
                    && !nextPending.containsKey(cs.Application__c)) {
                nextPending.put(cs.Application__c, cs.Scheduled_At__c);
            }
        }
        Map<Id, Datetime> out = new Map<Id, Datetime>(latestAny);
        out.putAll(nextPending);
        return out;
    }

    /**
     * The "current" AA_Fee_Installment__c per app for the per-installment
     * receipt tokens. The Fee_Receipt_Installment template renders right after
     * an installment charge confirms, so "current" = the most-recently-charged
     * row (one that has left Payment_Status__c='pending' and is not 'paused':
     * a Do Not Contact hold was never charged), picked by
     * Charged_At__c DESC then Installment_Number__c DESC. Apps with only
     * pending rows have no current installment (tokens resolve to '').
     * One SOQL for the whole batch — mirrors loadLatestCalls.
     */
    private static Map<Id, AA_Fee_Installment__c> loadCurrentInstallment(Set<Id> appIds) {
        Map<Id, AA_Fee_Installment__c> out = new Map<Id, AA_Fee_Installment__c>();
        if (appIds == null || appIds.isEmpty()) return out;
        for (AA_Fee_Installment__c fi : [
                SELECT Application__c, Installment_Number__c, Amount__c,
                       Charged_At__c, Payment_Status__c
                  FROM AA_Fee_Installment__c
                 WHERE Application__c IN :appIds
                   AND Payment_Status__c NOT IN ('pending', 'paused')
                 ORDER BY Application__c,
                          Charged_At__c DESC NULLS LAST,
                          Installment_Number__c DESC]) {
            if (!out.containsKey(fi.Application__c)) out.put(fi.Application__c, fi);
        }
        return out;
    }

    /**
     * The NEXT pending AA_Fee_Installment__c per app for the Bacs advance-notice
     * tokens ({{FeeNextInstallmentNumber/Amount/Date}}). AA_FeeInstallmentScheduler
     * dispatches Bacs_Advance_Notice when a pending row's Scheduled_Date__c is
     * 5 calendar days out, without telling the dispatcher which row — so
     * "next" = the earliest pending row dated today or later. The date floor
     * keeps an overdue row the same sweep is about to charge from being
     * announced in place of the one the notice is for. Apps with nothing
     * pending have no next installment (tokens resolve to '').
     * One SOQL for the whole batch — mirrors loadCurrentInstallment.
     */
    private static Map<Id, AA_Fee_Installment__c> loadNextPendingInstallment(Set<Id> appIds) {
        Map<Id, AA_Fee_Installment__c> out = new Map<Id, AA_Fee_Installment__c>();
        if (appIds == null || appIds.isEmpty()) return out;
        Date notBefore = Date.today();
        for (AA_Fee_Installment__c fi : [
                SELECT Application__c, Installment_Number__c, Amount__c, Scheduled_Date__c
                  FROM AA_Fee_Installment__c
                 WHERE Application__c IN :appIds
                   AND Payment_Status__c = 'pending'
                   AND Scheduled_Date__c >= :notBefore
                 ORDER BY Application__c,
                          Scheduled_Date__c ASC,
                          Installment_Number__c ASC]) {
            if (!out.containsKey(fi.Application__c)) out.put(fi.Application__c, fi);
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
            List<AA_Message_Template__c> templates, Map<Id, AA_Application__c> appMap) {
        Set<String> rawShortTypes = new Set<String>();
        for (AA_Message_Template__c t : templates) {
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
        for (AA_Application__c app : appMap.values()) {
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

        for (ContentVersion cv : [
                SELECT Id, Title, PathOnClient, VersionData, ContentDocumentId
                  FROM ContentVersion
                 WHERE ContentDocumentId IN :docToApp.keySet()
                   AND IsLatest = true]) {
            Id appId = docToApp.get(cv.ContentDocumentId);
            String title = docToTitle.get(cv.ContentDocumentId);
            if (appId == null || title == null) continue;
            out.put(appId + '|' + title, cv);
        }
        return out;
    }

    private static Map<String, StaticResource> loadStaticResources(List<AA_Message_Template__c> templates) {
        Set<String> names = new Set<String>();
        for (AA_Message_Template__c t : templates) {
            // Field is a comma-separated list — split & collect so a template
            // that attaches Welcome_Guide + Service_Agreement pulls both in
            // one SOQL round-trip.
            for (String n : parseAttachmentList(t.Attachment_Static_Resource_Name__c)) {
                names.add(n);
            }
            // Possible stand-ins for per-app files (see buildEmail).
            for (String n : parseAttachmentList(t.Attach_App_File_Titles__c)) {
                names.add(staticFallbackName(n));
            }
        }
        Map<String, StaticResource> out = new Map<String, StaticResource>();
        if (names.isEmpty()) return out;
        for (StaticResource sr : [SELECT Name, Body, ContentType FROM StaticResource WHERE Name IN :names]) {
            out.put(sr.Name, sr);
        }
        return out;
    }

    private static String nvl(String s) { return s == null ? '' : s; }
    private static String trunc(String s, Integer max) {
        if (s == null) return null;
        return s.length() > max ? s.substring(0, max) : s;
    }

    /**
     * Client-facing money: two decimals, "." decimal point, "," thousands
     * separator — "1,148.16" — and never a currency symbol (the templates
     * write "£{{FeeAmount}}"). Built by hand so the string cannot depend on
     * the RUNNING user's locale: Decimal.format() is locale-aware, not
     * currency-aware — it inserts the user's own separators ("1.148,16" for a
     * de/pt admin previewing or re-running a send) and its zero-trimming can
     * turn "800.00" into "800". The previous String.valueOf(setScale(2)) was
     * locale-safe but had no grouping, so a higher-rate award read "£1148.16"
     * in every money email (review 2026-09-11). Null → '' so a pre-award
     * template renders blank rather than "£0.00".
     */
    @TestVisible
    private static String money(Decimal amount) {
        if (amount == null) return '';
        String s = String.valueOf(amount.setScale(2));   // plain notation, e.g. "1148.16"
        String sign = s.startsWith('-') ? '-' : '';
        if (sign != '') s = s.substring(1);
        String whole = s.substringBefore('.');
        String frac  = s.substringAfter('.');
        String grouped = '';
        while (whole.length() > 3) {
            grouped = ',' + whole.substring(whole.length() - 3) + grouped;
            whole   = whole.substring(0, whole.length() - 3);
        }
        return sign + whole + grouped + '.' + frac;
    }

    /**
     * dd/MM/yyyy for a Date field, matching the Datetime tokens (CallDate /
     * IssueDate / MandateCreatedAt). Date has no pattern formatter, and going
     * through Datetime.format(pattern, TZ_UK) could move the day for a running
     * user whose timezone is not Europe/London — a Date has no timezone, so
     * GMT in, GMT out is the only conversion that cannot shift it.
     */
    @TestVisible
    private static String ukDate(Date d) {
        if (d == null) return '';
        return Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0)).formatGmt('dd/MM/yyyy');
    }

    // ═════════════════════════ DTOs ═════════════════════════════════

    /**
     * DTO used by both B2 preview LWC (via controller) and internal dispatch.
     * Named `Rendered` (not `RenderedMessage`) so AA_MessageTemplateController
     * can compile against `AA_MessageDispatcher.Rendered r = ...`.
     */
    /** Render-time failure (e.g. unknown merge token). Unlike AuraHandledException,
     *  its getMessage() is preserved server-side so the send log shows the real
     *  cause; the @AuraEnabled render() re-wraps it for the LWC (audit 2026-08-28). */
    public class RenderException extends Exception {}

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