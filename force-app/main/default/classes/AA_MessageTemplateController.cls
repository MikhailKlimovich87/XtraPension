/**
 * AA_MessageTemplateController — @AuraEnabled backing for the aaMessageTemplates
 * admin LWC. Owns list / upsert / delete / duplicate for AA_Message_Template__c,
 * plus the merge-schema catalog the palette chips render from, the mold catalog
 * the "Start from template" picker uses, the trigger-event catalog, the send-log
 * feed for the Send Log tab, and the preview bridge into the dispatcher (B3).
 *
 * Split ownership:
 *   B1 → AA_Message_Template__c object + fields.
 *   B2 → this class + the aaMessageTemplates LWC.
 *   B3 → AA_MessageDispatcher.render(templateId, appId) → returns a Rendered
 *        struct with { subject, body, resolvedMerges }. renderPreview()
 *        delegates to it without duplicating merge logic.
 */
public with sharing class AA_MessageTemplateController {

    // ── DTOs ────────────────────────────────────────────────────────
    public class TemplateRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String channel;
        @AuraEnabled public String triggerEvent;
        @AuraEnabled public String triggerEventLabel;
        @AuraEnabled public String subjectTemplate;
        @AuraEnabled public String bodyTemplate;
        @AuraEnabled public String contentText;
        @AuraEnabled public String contentMode;
        @AuraEnabled public String attachmentStaticResourceName;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String language;
        @AuraEnabled public Datetime lastPreviewAt;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    public class TemplateInput {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String channel;
        @AuraEnabled public String triggerEvent;
        @AuraEnabled public String subjectTemplate;
        @AuraEnabled public String bodyTemplate;
        @AuraEnabled public String contentText;
        @AuraEnabled public String contentMode;
        @AuraEnabled public String attachmentStaticResourceName;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String language;
    }

    public class MergeToken {
        @AuraEnabled public String token;    // e.g. "{{FirstName}}"
        @AuraEnabled public String label;    // human-readable
        @AuraEnabled public String category; // "Client" / "Call"
        @AuraEnabled public String example;  // sample rendered value
        public MergeToken(String t, String l, String c, String ex) {
            this.token = t; this.label = l; this.category = c; this.example = ex;
        }
    }

    public class PreviewResult {
        @AuraEnabled public String subject;
        @AuraEnabled public String body;
        @AuraEnabled public String attachmentName;
        @AuraEnabled public List<MergeToken> resolvedMerges;
    }

    public class TriggerEventOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public TriggerEventOption(String v, String l) { this.value = v; this.label = l; }
    }

    public class TemplateMold {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public String channel;         // Email / SMS
        @AuraEnabled public String triggerEvent;    // API value
        @AuraEnabled public String contentMode;     // Simple / Advanced
        @AuraEnabled public String subjectTemplate;
        @AuraEnabled public String contentText;
        @AuraEnabled public String bodyTemplate;
        public TemplateMold(String k, String l, String d) {
            this.key = k; this.label = l; this.description = d;
        }
    }

    public class SendLogRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public Id templateId;
        @AuraEnabled public String templateName;
        @AuraEnabled public Id applicationId;
        @AuraEnabled public String applicationName;
        @AuraEnabled public String channel;
        @AuraEnabled public String status;
        @AuraEnabled public String externalId;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String renderedSubject;
    }

    public class SendLogPage {
        @AuraEnabled public List<SendLogRow> rows;
        @AuraEnabled public Integer total;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer pageIndex;
    }

    // ── list ────────────────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<TemplateRow> listTemplates() {
        Map<String, String> triggerLabels = triggerLabelMap();
        List<TemplateRow> out = new List<TemplateRow>();
        for (AA_Message_Template__c t : [
            SELECT Id, Name, Channel__c, Trigger_Event__c,
                   Subject_Template__c, Body_Template__c,
                   Content_Text__c, Content_Mode__c,
                   Attachment_Static_Resource_Name__c,
                   Active__c, Language__c, Last_Preview_At__c, LastModifiedDate
            FROM AA_Message_Template__c
            ORDER BY Active__c DESC, Channel__c ASC, Name ASC
        ]) {
            TemplateRow r = new TemplateRow();
            r.id = t.Id;
            r.name = t.Name;
            r.channel = t.Channel__c;
            r.triggerEvent = t.Trigger_Event__c;
            r.triggerEventLabel = triggerLabels.containsKey(t.Trigger_Event__c)
                ? triggerLabels.get(t.Trigger_Event__c) : t.Trigger_Event__c;
            r.subjectTemplate = t.Subject_Template__c;
            r.bodyTemplate = t.Body_Template__c;
            r.contentText = t.Content_Text__c;
            // Smart contentMode fallback: legacy templates (pre-redesign) have
            // Body_Template__c populated but no Content_Text__c and no explicit
            // Content_Mode__c. Default them to Advanced so their existing HTML is
            // visible in the edit modal. Otherwise Simple is the default for new rows.
            if (String.isNotBlank(t.Content_Mode__c)) {
                r.contentMode = t.Content_Mode__c;
            } else if (String.isNotBlank(t.Content_Text__c)) {
                r.contentMode = 'Simple';
            } else if (String.isNotBlank(t.Body_Template__c)) {
                r.contentMode = 'Advanced';
            } else {
                r.contentMode = 'Simple';
            }
            r.attachmentStaticResourceName = t.Attachment_Static_Resource_Name__c;
            r.active = t.Active__c;
            r.language = t.Language__c;
            r.lastPreviewAt = t.Last_Preview_At__c;
            r.lastModifiedDate = t.LastModifiedDate;
            out.add(r);
        }
        return out;
    }

    // audit #56: template create/edit/duplicate/delete had no authorization gate
    // and every AA user could reach them. Restrict the mutations to System
    // Administrators (read/list/preview stay open to all AA users).
    private static void assertAdmin() {
        Profile p = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId() LIMIT 1];
        if (p == null || p.Name != 'System Administrator') {
            throw new AuraHandledException('Only a System Administrator can create, edit, duplicate or delete message templates.');
        }
    }

    // ── save (upsert) ───────────────────────────────────────────────
    @AuraEnabled
    public static Id saveTemplate(TemplateInput template) {
        assertAdmin();
        if (template == null) throw new AuraHandledException('Missing template payload.');
        if (String.isBlank(template.channel)) throw new AuraHandledException('Channel is required.');
        if (template.channel != 'Email' && template.channel != 'SMS') {
            throw new AuraHandledException('Channel must be Email or SMS.');
        }
        if (String.isBlank(template.triggerEvent)) throw new AuraHandledException('Trigger Event is required.');
        if (template.channel == 'Email' && String.isBlank(template.subjectTemplate)) {
            throw new AuraHandledException('Subject is required for Email templates.');
        }

        String mode = String.isBlank(template.contentMode) ? 'Simple' : template.contentMode;
        if (mode != 'Simple' && mode != 'Advanced') {
            throw new AuraHandledException('Content Mode must be Simple or Advanced.');
        }

        // Content requirement: Simple → contentText required; Advanced → bodyTemplate required.
        if (mode == 'Simple' && String.isBlank(template.contentText)) {
            throw new AuraHandledException('Content is required.');
        }
        if (mode == 'Advanced' && String.isBlank(template.bodyTemplate)) {
            throw new AuraHandledException('Body HTML is required in Advanced mode.');
        }
        // SMS always uses plain content — force Simple regardless of toggle.
        if (template.channel == 'SMS') mode = 'Simple';

        // Server-side token whitelist enforcement (mirrors LWC validator so
        // API callers can't smuggle broken merges past the UI).
        Set<String> allowed = allowedTokenSet();
        String primary = mode == 'Simple' ? template.contentText : template.bodyTemplate;
        for (String tok : extractTokens(primary)) {
            if (!allowed.contains(tok)) {
                throw new AuraHandledException('Unknown merge token {{' + tok + '}} in Body/Content.');
            }
        }
        if (template.channel == 'Email' && String.isNotBlank(template.subjectTemplate)) {
            for (String tok : extractTokens(template.subjectTemplate)) {
                if (!allowed.contains(tok)) {
                    throw new AuraHandledException('Unknown merge token {{' + tok + '}} in Subject.');
                }
            }
        }

        AA_Message_Template__c rec;
        if (template.id != null) {
            rec = [
                SELECT Id FROM AA_Message_Template__c WHERE Id = :template.id LIMIT 1
            ];
        } else {
            rec = new AA_Message_Template__c();
        }
        // Name is AutoNumber on AA_Message_Template__c so we can't write it
        // directly. Admins distinguish templates via Channel + Trigger_Event.
        rec.Channel__c = template.channel;
        rec.Trigger_Event__c = template.triggerEvent;
        rec.Content_Mode__c = mode;
        // Subject is meaningful only for Email; blank it for SMS so old
        // subject text doesn't linger after a channel switch.
        rec.Subject_Template__c = template.channel == 'Email'
            ? template.subjectTemplate
            : null;

        // Populate BOTH Content_Text__c (source of truth in Simple mode) AND
        // Body_Template__c (what the dispatcher ships for backward compat +
        // reports). In Simple mode Body_Template__c mirrors Content_Text__c
        // so raw-DB inspection still shows something meaningful.
        if (mode == 'Simple') {
            rec.Content_Text__c = template.contentText;
            rec.Body_Template__c = template.contentText;
        } else {
            rec.Content_Text__c = template.contentText; // preserved if user toggled from Simple
            rec.Body_Template__c = template.bodyTemplate;
        }

        rec.Attachment_Static_Resource_Name__c = template.channel == 'Email'
            ? template.attachmentStaticResourceName
            : null;
        rec.Active__c = template.active == true;
        rec.Language__c = String.isBlank(template.language) ? 'en-GB' : template.language;
        upsert rec;
        return rec.Id;
    }

    // ── delete ──────────────────────────────────────────────────────
    @AuraEnabled
    public static void deleteTemplate(Id templateId) {
        assertAdmin();
        if (templateId == null) throw new AuraHandledException('Missing template id.');
        delete [SELECT Id FROM AA_Message_Template__c WHERE Id = :templateId LIMIT 1];
    }

    // ── duplicate ───────────────────────────────────────────────────
    @AuraEnabled
    public static Id duplicateTemplate(Id templateId) {
        assertAdmin();
        if (templateId == null) throw new AuraHandledException('Missing template id.');
        AA_Message_Template__c src = [
            SELECT Id, Name, Channel__c, Trigger_Event__c,
                   Subject_Template__c, Body_Template__c,
                   Content_Text__c, Content_Mode__c,
                   Attachment_Static_Resource_Name__c,
                   Active__c, Language__c
            FROM AA_Message_Template__c
            WHERE Id = :templateId LIMIT 1
        ];
        AA_Message_Template__c copy = new AA_Message_Template__c(
            // Name is AutoNumber — auto-populated on insert.
            Channel__c = src.Channel__c,
            Trigger_Event__c = src.Trigger_Event__c,
            Subject_Template__c = src.Subject_Template__c,
            Body_Template__c = src.Body_Template__c,
            Content_Text__c = src.Content_Text__c,
            Content_Mode__c = src.Content_Mode__c,
            Attachment_Static_Resource_Name__c = src.Attachment_Static_Resource_Name__c,
            Language__c = src.Language__c,
            Active__c = false // clones start inactive so they never race the original
        );
        insert copy;
        return copy.Id;
    }

    // ── preview (delegates to B3 dispatcher) ────────────────────────
    @AuraEnabled
    public static PreviewResult renderPreview(Id templateId, Id appId) {
        if (templateId == null) throw new AuraHandledException('Missing template id.');
        if (appId == null) throw new AuraHandledException('Missing sample application id.');

        // B3 owns AA_MessageDispatcher.render(templateId, appId) →
        // returns Rendered { String subject; String body; Map<String,String> resolvedMerges; }
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(templateId, appId);

        PreviewResult out = new PreviewResult();
        out.subject = r == null ? null : r.subject;
        out.body = r == null ? null : r.body;

        // Attach the static-resource filename to the preview so the UI can
        // mock the "attached: X.pdf" line without a second SOQL round-trip.
        AA_Message_Template__c t = [
            SELECT Attachment_Static_Resource_Name__c
            FROM AA_Message_Template__c WHERE Id = :templateId LIMIT 1
        ];
        out.attachmentName = t.Attachment_Static_Resource_Name__c;

        // Normalize the dispatcher's Map<String,String> into a list of MergeToken
        // rows so the LWC can render "{{FirstName}} → Priya" side-by-side.
        List<MergeToken> merges = new List<MergeToken>();
        Map<String, MergeToken> catalog = new Map<String, MergeToken>();
        for (MergeToken mt : getMergeSchema()) catalog.put(mt.token, mt);
        if (r != null && r.resolvedMerges != null) {
            for (String key : r.resolvedMerges.keySet()) {
                String token = key.startsWith('{{') ? key : '{{' + key + '}}';
                MergeToken cat = catalog.get(token);
                merges.add(new MergeToken(
                    token,
                    cat == null ? key : cat.label,
                    cat == null ? 'Other' : cat.category,
                    r.resolvedMerges.get(key)
                ));
            }
        }
        out.resolvedMerges = merges;

        // Stamp Last_Preview_At__c so admins can spot templates that were
        // previewed but never sent (a symptom of stale drafts).
        update new AA_Message_Template__c(Id = templateId, Last_Preview_At__c = Datetime.now());
        return out;
    }

    // ── merge schema (used by palette chips + validator) ────────────
    @AuraEnabled(cacheable=true)
    public static List<MergeToken> getMergeSchema() {
        List<MergeToken> out = new List<MergeToken>();
        // Client group — resolved from AA_Application__c
        out.add(new MergeToken('{{FirstName}}',      'First name',            'Client', 'Priya'));
        out.add(new MergeToken('{{LastName}}',       'Last name',             'Client', 'Patel'));
        out.add(new MergeToken('{{FullName}}',       'Full name',             'Client', 'Priya Patel'));
        // DWP_Reference__c holds the client's NINO (the fill worker writes it),
        // and emails CC the helper: the label says so, so nobody drops it into
        // client copy by accident (audit 2026-10-02 F77).
        out.add(new MergeToken('{{DWPReference}}',   'DWP reference (client NINO: keep out of client messages)', 'Client', 'JT 12 34 56 A'));
        out.add(new MergeToken('{{ApplicationRef}}', 'Application ref',       'Client', 'AA-00042'));
        // Signed self-service form link; blank until the record is signed
        // (AA_MessageDispatcher.buildMergeMap, audit 2026-10-02 F179).
        out.add(new MergeToken('{{ClientFormUrl}}',  'Client form link (signed)', 'Client', 'https://aa-autofill-14d501200453.herokuapp.com/form/client/a2D000000000001?t=abc'));
        // Case group — application state & assignments
        out.add(new MergeToken('{{Stage}}',          'Stage',                 'Case',   'Submitted'));
        out.add(new MergeToken('{{SalesAgent}}',     'Sales agent',           'Case',   'Fiona'));
        out.add(new MergeToken('{{ValAgent}}',       'Val agent',             'Case',   'Sean'));
        out.add(new MergeToken('{{DecisionDueDate}}','Decision due date',     'Case',   '12/09/2026'));
        // Money examples are 2dp decimals with NO "£" (a thousands separator from
        // £1,000 up: "1,148.16") — the dispatcher's money() resolves them that
        // way and the templates write "£{{FeeAmount}}", so a "£" here rendered
        // "££520.00" in the WYSIWYG preview (audit 2026-09-09).
        out.add(new MergeToken('{{FeeAmount}}',      'Fee amount (20% of annual award)', 'Case', '800.00'));
        // Call group — resolved from latest AA_Call_Schedule__c
        out.add(new MergeToken('{{CallTime}}',       'Call time',             'Call',   '10:30'));
        out.add(new MergeToken('{{CallDate}}',       'Call date',             'Call',   'Mon 12 May'));
        out.add(new MergeToken('{{IssueDate}}',      'Today (issue date)',    'Call',   '12/05/2026'));
        // XtraPension contact constants (from AA_Config__c)
        out.add(new MergeToken('{{XPPhone}}',        'XtraPension phone',     'XP',     '+353 1 254 4116'));
        out.add(new MergeToken('{{XPEmail}}',        'XtraPension email',     'XP',     'help@xtrapension.com'));
        // Fee installment + DD mandate tokens — provided by AA_MessageDispatcher.buildMergeMap,
        // used by the Fee Receipt (installment) + DD templates. Must be in this palette so the
        // template editor's allow-list validation accepts them (else save/toggle throws).
        // Labels use the UK spelling "instalment"; the token names keep the API spelling.
        out.add(new MergeToken('{{FeeInstallmentNumber}}', 'Fee instalment # (last charged)', 'Case', '1'));
        out.add(new MergeToken('{{FeeInstallmentTotal}}',  'Fee instalments total', 'Case', '3'));
        out.add(new MergeToken('{{FeeInstallmentAmount}}', 'Fee instalment amount (last charged)', 'Case', '266.67'));
        // Next-pending trio used by the Bacs advance notice — the charge about
        // to be taken, not the last one taken (see AA_MessageDispatcher.buildMergeMap).
        // Date is the row's Scheduled_Date__c: the notice sweep runs T+1..T+5, so
        // "in 5 days" is wrong on catch-up days — the body must state the date.
        out.add(new MergeToken('{{FeeNextInstallmentNumber}}', 'Fee instalment # (next due)',     'Case', '1'));
        out.add(new MergeToken('{{FeeNextInstallmentAmount}}', 'Fee instalment amount (next due)', 'Case', '266.67'));
        out.add(new MergeToken('{{FeeNextInstallmentDate}}',   'Fee instalment date (next due)',   'Case', '28/09/2026'));
        out.add(new MergeToken('{{MandateId}}',            'DD mandate id',         'Case', 'MD0001'));
        out.add(new MergeToken('{{MandateStatus}}',        'DD mandate status',     'Case', 'active'));
        out.add(new MergeToken('{{MandateCreatedAt}}',     'DD mandate created',    'Case', '12/05/2026'));
        return out;
    }

    // ── trigger event options (drives filter dropdown + Add modal) ──
    @AuraEnabled(cacheable=true)
    public static List<TriggerEventOption> getTriggerEvents() {
        List<TriggerEventOption> out = new List<TriggerEventOption>();
        Schema.DescribeFieldResult f =
            AA_Message_Template__c.Trigger_Event__c.getDescribe();
        for (Schema.PicklistEntry p : f.getPicklistValues()) {
            if (!p.isActive()) continue;
            out.add(new TriggerEventOption(p.getValue(), p.getLabel()));
        }
        return out;
    }

    // ── molds ("Start from template" picker) ────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<TemplateMold> getMolds() {
        List<TemplateMold> out = new List<TemplateMold>();

        TemplateMold blank = new TemplateMold('blank', 'Blank', 'Start from an empty template.');
        blank.channel = 'Email';
        blank.triggerEvent = 'Custom_Manual';
        blank.contentMode = 'Simple';
        blank.subjectTemplate = '';
        blank.contentText = '';
        blank.bodyTemplate = '';
        out.add(blank);

        TemplateMold welcome = new TemplateMold(
            'welcome',
            'Welcome-style',
            'Intro + the details we ask the client to have to hand before the call.'
        );
        welcome.channel = 'Email';
        welcome.triggerEvent = 'Intake_Created';
        welcome.contentMode = 'Simple';
        welcome.subjectTemplate = 'Welcome to XtraPension ({{ApplicationRef}})';
        // Items mirror the live welcome pack (web/email-templates/welcome/
        // welcome.html). Attendance Allowance is NOT means-tested (DECISIONS.md
        // §2) — the PC1 mold this was cloned from asked for savings and income,
        // which an AA client is never asked for (audit 2026-09-09).
        welcome.contentText =
              'Hi {{FirstName}},\n\n'
            + 'Welcome to XtraPension. We are getting your Attendance Allowance application ready and want to make our call together as short as possible.\n\n'
            + 'Please have the following details handy before we speak:\n\n'
            + '**1.** Your **National Insurance number**.\n'
            + '**2.** The **name and address of your GP surgery** or medical centre.\n'
            + '**3.** A **list of your medicines**. Your repeat prescription list is ideal.\n'
            + '**4.** The **care and help you need day to day**: washing, dressing, eating, the toilet, or someone keeping you safe, by day and by night.\n'
            + '**5.** Any recent **hospital, care-home or hospice stays**: the dates in and out and the name of the place.\n'
            + '**6.** Your **bank account details** (sort code and account number) for DWP to pay into.\n\n'
            + 'If you have any questions, reply to this email or call {{XPPhone}}.\n\n'
            + 'Talk soon,\nClient Service, XtraPension';
        out.add(welcome);

        TemplateMold reminder = new TemplateMold(
            'reminder',
            'Reminder-style',
            'Short "we ring you today at {{CallTime}}" note.'
        );
        reminder.channel = 'SMS';
        reminder.triggerEvent = 'Call_Reminder_Morning_Of';
        reminder.contentMode = 'Simple';
        reminder.subjectTemplate = '';
        reminder.contentText =
              'Hi {{FirstName}}, this is a reminder that XtraPension will ring you today at {{CallTime}} about your Attendance Allowance application. If that no longer suits, call {{XPPhone}}.';
        out.add(reminder);

        TemplateMold status = new TemplateMold(
            'status',
            'Status Update-style',
            'Explain the current stage of the application to the client.'
        );
        status.channel = 'Email';
        status.triggerEvent = 'Custom_Manual';
        status.contentMode = 'Simple';
        status.subjectTemplate = 'Update on your Attendance Allowance application ({{ApplicationRef}})';
        status.contentText =
              'Hi {{FirstName}},\n\n'
            + 'Just a quick note to let you know where your Attendance Allowance application is right now.\n\n'
            + '**Current stage:** {{Stage}}\n'
            + '**Assigned to:** {{ValAgent}}\n'
            + '**Reference:** {{ApplicationRef}}\n\n'
            + 'We will contact you again as soon as there is anything new. If you need us in the meantime, reply to this email or call {{XPPhone}}.\n\n'
            + 'Best,\nClient Service, XtraPension';
        out.add(status);

        return out;
    }

    // ── send log feed (Send Log tab) ────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static SendLogPage listSendLogs(
            Date fromDate, Date toDate,
            Id templateId, String status,
            Integer pageIndex, Integer pageSize) {

        Integer psize  = (pageSize == null || pageSize <= 0 || pageSize > 200) ? 50 : pageSize;
        Integer pindex = (pageIndex == null || pageIndex < 0) ? 0 : pageIndex;
        Integer offset = pindex * psize;

        // WHERE builder — bind vars only, no string interp of filter values.
        List<String> whereList = new List<String>();
        if (fromDate != null) whereList.add('Sent_At__c >= :fromDt');
        if (toDate   != null) whereList.add('Sent_At__c <= :toDt');
        if (templateId != null) whereList.add('Template__c = :tmplId');
        if (String.isNotBlank(status) && status != 'All') whereList.add('Status__c = :statusVal');

        Datetime fromDt = fromDate == null ? null
            : Datetime.newInstance(fromDate, Time.newInstance(0,0,0,0));
        Datetime toDt   = toDate == null ? null
            : Datetime.newInstance(toDate, Time.newInstance(23,59,59,0));
        Id     tmplId    = templateId;
        String statusVal = status;

        String whereClause = whereList.isEmpty() ? '' : ('WHERE ' + String.join(whereList, ' AND '));

        Integer total = Database.countQuery(
            'SELECT count() FROM AA_Message_Send_Log__c ' + whereClause);

        List<AA_Message_Send_Log__c> rows = Database.query(
            'SELECT Id, Name, Sent_At__c, Template__c, Template__r.Name, '
          + 'Application__c, Application__r.Name, Channel__c, Status__c, '
          + 'External_Id__c, Error_Message__c, Rendered_Subject__c '
          + 'FROM AA_Message_Send_Log__c ' + whereClause + ' '
          + 'ORDER BY Sent_At__c DESC NULLS LAST '
          + 'LIMIT :psize OFFSET :offset');

        SendLogPage page = new SendLogPage();
        page.total = total;
        page.pageSize = psize;
        page.pageIndex = pindex;
        page.rows = new List<SendLogRow>();
        for (AA_Message_Send_Log__c r : rows) {
            SendLogRow s = new SendLogRow();
            s.id = r.Id;
            s.name = r.Name;
            s.sentAt = r.Sent_At__c;
            s.templateId = r.Template__c;
            s.templateName = r.Template__r == null ? null : r.Template__r.Name;
            s.applicationId = r.Application__c;
            s.applicationName = r.Application__r == null ? null : r.Application__r.Name;
            s.channel = r.Channel__c;
            s.status = r.Status__c;
            s.externalId = r.External_Id__c;
            s.errorMessage = r.Error_Message__c;
            s.renderedSubject = r.Rendered_Subject__c;
            page.rows.add(s);
        }
        return page;
    }

    // ── helpers ─────────────────────────────────────────────────────
    private static Set<String> allowedTokenSet() {
        Set<String> s = new Set<String>();
        for (MergeToken mt : getMergeSchema()) {
            // strip {{ }} → bare name for validator symmetry with extractTokens
            String bare = mt.token.substring(2, mt.token.length() - 2);
            s.add(bare);
        }
        return s;
    }

    private static List<String> extractTokens(String src) {
        List<String> found = new List<String>();
        if (String.isBlank(src)) return found;
        Matcher m = Pattern.compile('\\{\\{\\s*([^}\\s]+)\\s*\\}\\}').matcher(src);
        while (m.find()) {
            String t = m.group(1);
            if (t == '__CONTENT__') continue; // shell placeholder — not a merge
            found.add(t);
        }
        return found;
    }

    private static Map<String, String> triggerLabelMap() {
        Map<String, String> m = new Map<String, String>();
        for (TriggerEventOption o : getTriggerEvents()) {
            m.put(o.value, o.label);
        }
        return m;
    }

    private static String truncateName(String s) {
        if (s == null) return s;
        return s.length() > 80 ? s.substring(0, 80) : s;
    }
}