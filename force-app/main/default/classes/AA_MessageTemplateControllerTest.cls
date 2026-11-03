/**
 * AA_MessageTemplateControllerTest — backing for the aaMessageTemplates admin
 * LWC: list / save / delete / duplicate, the merge-token palette, the molds,
 * the trigger-event catalog, the preview bridge and the Send Log feed.
 *
 * Regressions this class is meant to catch: a save that persists a template
 * the validator should have refused (bad channel, unknown {{Token}}, missing
 * content); the SMS channel keeping an email subject / attachment; a palette
 * token the dispatcher cannot resolve (the LWC would offer a chip that fails
 * every send); a mold that will not save; the legacy contentMode inference
 * hiding a template's HTML; the Send Log filters returning the wrong rows;
 * and the admin gate letting a non-admin mutate templates (audit #56).
 */
@isTest
private class AA_MessageTemplateControllerTest {

    // Non-admin user for the audit #56 gate. Created in @testSetup (its own
    // transaction) so it never collides with the non-setup DML in the tests
    // (MIXED_DML). Uses the 'Standard Platform User' profile: the Salesforce
    // license pool is full in this org, the Salesforce Platform pool is not.
    private static final String NONADMIN_ALIAS = 'aatplna';

    @testSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1];
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        insert new User(
            ProfileId         = p.Id,
            LastName          = 'TplNonAdmin',
            Email             = 'aa.tpl.nonadmin@example.com',
            Username          = 'aa.tpl.nonadmin.' + uniq + '@test.aa.invalid',
            Alias             = NONADMIN_ALIAS,
            TimeZoneSidKey    = 'Europe/London',
            LocaleSidKey      = 'en_GB',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static User nonAdmin() {
        return [SELECT Id FROM User WHERE Alias = :NONADMIN_ALIAS AND LastName = 'TplNonAdmin' LIMIT 1];
    }

    // ── fixtures ────────────────────────────────────────────────────

    private static AA_Application__c makeApp(String firstName) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c   = firstName,
            Last_Name__c    = 'Patel',
            Email__c        = 'priya@example.com',
            Phone__c        = '+441234567890',
            Stage__c        = 'New',
            CurrencyIsoCode = 'GBP'
        );
        insert a;
        // Re-query: the auto-number Name is not refreshed on the in-memory row.
        return [SELECT Id, Name, First_Name__c FROM AA_Application__c WHERE Id = :a.Id];
    }

    private static AA_MessageTemplateController.TemplateInput input(
            String channel, String triggerEvent, String subject, String content) {
        AA_MessageTemplateController.TemplateInput t = new AA_MessageTemplateController.TemplateInput();
        t.channel         = channel;
        t.triggerEvent    = triggerEvent;
        t.subjectTemplate = subject;
        t.contentText     = content;
        t.contentMode     = 'Simple';
        t.active          = true;
        return t;
    }

    private static Boolean saveRejected(AA_MessageTemplateController.TemplateInput t) {
        try {
            AA_MessageTemplateController.saveTemplate(t);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    private static Integer templateCount() {
        return [SELECT COUNT() FROM AA_Message_Template__c];
    }

    // Inserted directly (bypassing the controller) for list / duplicate /
    // preview fixtures.
    private static AA_Message_Template__c insertTemplate(String channel, String triggerEvent,
            String subject, String body, String contentText, String mode, Boolean active) {
        AA_Message_Template__c t = new AA_Message_Template__c(
            Channel__c          = channel,
            Trigger_Event__c    = triggerEvent,
            Subject_Template__c = subject,
            Body_Template__c    = body,
            Content_Text__c     = contentText,
            Content_Mode__c     = mode,
            Active__c           = active
        );
        insert t;
        return t;
    }

    private static AA_Message_Send_Log__c log(AA_Message_Template__c t, AA_Application__c app,
            String channel, String status, Datetime sentAt, String subject) {
        return new AA_Message_Send_Log__c(
            Template__c = t.Id, Application__c = app.Id, Channel__c = channel,
            Status__c = status, Sent_At__c = sentAt, Rendered_Subject__c = subject
        );
    }

    // Noon in the running user's timezone on a calendar day — always inside
    // that day's [00:00, 23:59:59] window, whatever the DST situation.
    private static Datetime noonDaysAgo(Integer days) {
        return Datetime.newInstance(Date.today().addDays(-days), Time.newInstance(12, 0, 0, 0));
    }

    // ── saveTemplate: validator ─────────────────────────────────────

    @isTest static void saveTemplate_rejects_invalid_payloads_and_persists_nothing() {
        System.assert(saveRejected(null), 'a null payload must be rejected');
        System.assert(saveRejected(input('', 'Intake_Created', 's', 'c')), 'a blank channel must be rejected');
        System.assert(saveRejected(input('Fax', 'Intake_Created', 's', 'c')), 'a channel other than Email/SMS must be rejected');
        System.assert(saveRejected(input('Email', '', 's', 'c')), 'a blank trigger event must be rejected');
        System.assert(saveRejected(input('Email', 'Intake_Created', '', 'c')), 'an Email without a subject must be rejected');
        System.assert(saveRejected(input('Email', 'Intake_Created', 's', '')), 'Simple mode without content must be rejected');

        AA_MessageTemplateController.TemplateInput badMode = input('Email', 'Intake_Created', 's', 'c');
        badMode.contentMode = 'Markdown';
        System.assert(saveRejected(badMode), 'a content mode other than Simple/Advanced must be rejected');

        AA_MessageTemplateController.TemplateInput advNoBody = input('Email', 'Intake_Created', 's', 'c');
        advNoBody.contentMode  = 'Advanced';
        advNoBody.bodyTemplate = '';
        System.assert(saveRejected(advNoBody), 'Advanced mode without body HTML must be rejected');

        System.assert(saveRejected(input('Email', 'Intake_Created', 's', 'Hi {{NopeToken}}')),
            'an unknown merge token in the content must be rejected');
        System.assert(saveRejected(input('Email', 'Intake_Created', 'Re {{Nope}}', 'c')),
            'an unknown merge token in the subject must be rejected');

        AA_MessageTemplateController.TemplateInput advBadBody = input('Email', 'Intake_Created', 's', null);
        advBadBody.contentMode  = 'Advanced';
        advBadBody.bodyTemplate = '<p>{{Nope}}</p>';
        System.assert(saveRejected(advBadBody), 'an unknown merge token in an Advanced body must be rejected');

        System.assertEquals(0, templateCount(), 'no rejected payload may reach the database');
    }

    // ── saveTemplate: persistence ───────────────────────────────────

    @isTest static void saveTemplate_simple_email_mirrors_content_into_body_and_defaults_language() {
        AA_MessageTemplateController.TemplateInput t = input('Email', 'Intake_Created',
            'Welcome {{FirstName}}', 'Hi {{FirstName}}, ref {{ApplicationRef}}');
        t.contentMode = null;   // blank → Simple
        t.language    = null;   // blank → en-GB
        t.attachmentStaticResourceName = 'AA_Welcome_Guide';

        Test.startTest();
        Id id = AA_MessageTemplateController.saveTemplate(t);
        Test.stopTest();

        AA_Message_Template__c saved = [
            SELECT Channel__c, Trigger_Event__c, Subject_Template__c, Content_Mode__c,
                   Content_Text__c, Body_Template__c, Attachment_Static_Resource_Name__c,
                   Active__c, Language__c
              FROM AA_Message_Template__c WHERE Id = :id];
        System.assertEquals('Email', saved.Channel__c);
        System.assertEquals('Intake_Created', saved.Trigger_Event__c);
        System.assertEquals('Welcome {{FirstName}}', saved.Subject_Template__c);
        System.assertEquals('Simple', saved.Content_Mode__c, 'a blank contentMode must default to Simple');
        System.assertEquals('Hi {{FirstName}}, ref {{ApplicationRef}}', saved.Content_Text__c, 'Simple content is the source of truth');
        System.assertEquals(saved.Content_Text__c, saved.Body_Template__c, 'Simple mode must mirror the content into Body_Template__c');
        System.assertEquals('AA_Welcome_Guide', saved.Attachment_Static_Resource_Name__c, 'an Email keeps its attachment');
        System.assertEquals(true, saved.Active__c);
        System.assertEquals('en-GB', saved.Language__c, 'a blank language must default to en-GB');
    }

    @isTest static void saveTemplate_advanced_email_keeps_raw_html_and_preserves_simple_text() {
        AA_MessageTemplateController.TemplateInput t = input('Email', 'Custom_Manual', 'Update', 'plain fallback {{FirstName}}');
        t.contentMode  = 'Advanced';
        t.bodyTemplate = '<p>Hello {{FullName}}</p>';
        t.language     = 'cy-GB';

        Id id = AA_MessageTemplateController.saveTemplate(t);

        AA_Message_Template__c saved = [SELECT Content_Mode__c, Content_Text__c, Body_Template__c, Language__c
                                        FROM AA_Message_Template__c WHERE Id = :id];
        System.assertEquals('Advanced', saved.Content_Mode__c);
        System.assertEquals('<p>Hello {{FullName}}</p>', saved.Body_Template__c, 'an Advanced body is stored verbatim');
        System.assertEquals('plain fallback {{FirstName}}', saved.Content_Text__c, 'the Simple text must survive an Advanced save');
        System.assertEquals('cy-GB', saved.Language__c, 'an explicit language is kept');
    }

    // SMS is plain text: Simple is forced even when the toggle says Advanced,
    // and the email-only fields are blanked so a channel switch cannot leave a
    // stale subject or attachment behind.
    @isTest static void saveTemplate_sms_forces_simple_and_blanks_email_only_fields() {
        AA_MessageTemplateController.TemplateInput t = input('SMS', 'Call_Reminder_Morning_Of',
            'stale subject', 'Ring you at {{CallTime}}');
        t.contentMode  = 'Advanced';
        t.bodyTemplate = '<p>html {{CallTime}}</p>';
        t.attachmentStaticResourceName = 'AA_Welcome_Guide';

        Id id = AA_MessageTemplateController.saveTemplate(t);

        AA_Message_Template__c saved = [SELECT Content_Mode__c, Content_Text__c, Body_Template__c,
                                               Subject_Template__c, Attachment_Static_Resource_Name__c
                                        FROM AA_Message_Template__c WHERE Id = :id];
        System.assertEquals('Simple', saved.Content_Mode__c, 'SMS must always be Simple');
        System.assertEquals('Ring you at {{CallTime}}', saved.Body_Template__c, 'the SMS body is the plain content, never the HTML');
        System.assertEquals('Ring you at {{CallTime}}', saved.Content_Text__c);
        System.assertEquals(null, saved.Subject_Template__c, 'an SMS must not keep a subject');
        System.assertEquals(null, saved.Attachment_Static_Resource_Name__c, 'an SMS must not keep an attachment');
    }

    @isTest static void saveTemplate_with_id_updates_in_place() {
        Id id = AA_MessageTemplateController.saveTemplate(input('Email', 'Intake_Created', 'v1', 'body v1'));

        AA_MessageTemplateController.TemplateInput edit = input('Email', 'Fee_Charged', 'v2', 'body v2');
        edit.id     = id;
        edit.active = false;
        Id again = AA_MessageTemplateController.saveTemplate(edit);

        System.assertEquals(id, again, 'saving with an id must update, not insert');
        System.assertEquals(1, templateCount(), 'no second row on update');
        AA_Message_Template__c saved = [SELECT Trigger_Event__c, Subject_Template__c, Content_Text__c, Active__c
                                        FROM AA_Message_Template__c WHERE Id = :id];
        System.assertEquals('Fee_Charged', saved.Trigger_Event__c);
        System.assertEquals('v2', saved.Subject_Template__c);
        System.assertEquals('body v2', saved.Content_Text__c);
        System.assertEquals(false, saved.Active__c, 'active=false must deactivate');
    }

    // ── delete / duplicate ──────────────────────────────────────────

    @isTest static void deleteTemplate_removes_row_and_rejects_missing_id() {
        AA_Message_Template__c t = insertTemplate('SMS', 'Intake_Created', null, 'bye', 'bye', 'Simple', true);

        Boolean threw = false;
        try { AA_MessageTemplateController.deleteTemplate(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a null id must be rejected');
        System.assertEquals(1, templateCount(), 'a rejected delete must not touch other rows');

        AA_MessageTemplateController.deleteTemplate(t.Id);
        System.assertEquals(0, templateCount(), 'the template must be gone');
    }

    @isTest static void duplicateTemplate_copies_everything_but_starts_inactive() {
        AA_Message_Template__c src = new AA_Message_Template__c(
            Channel__c = 'Email', Trigger_Event__c = 'Fee_Receipt',
            Subject_Template__c = 'Receipt {{ApplicationRef}}',
            Body_Template__c = '<p>{{FeeAmount}}</p>', Content_Text__c = 'fee {{FeeAmount}}',
            Content_Mode__c = 'Advanced', Attachment_Static_Resource_Name__c = 'AA_Service_Agreement',
            Language__c = 'en-GB', Active__c = true
        );
        insert src;

        Boolean threw = false;
        try { AA_MessageTemplateController.duplicateTemplate(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a null id must be rejected');

        Id copyId = AA_MessageTemplateController.duplicateTemplate(src.Id);

        System.assertNotEquals(src.Id, copyId, 'the duplicate must be a new row');
        System.assertEquals(2, templateCount());
        AA_Message_Template__c copy = [
            SELECT Channel__c, Trigger_Event__c, Subject_Template__c, Body_Template__c, Content_Text__c,
                   Content_Mode__c, Attachment_Static_Resource_Name__c, Language__c, Active__c
              FROM AA_Message_Template__c WHERE Id = :copyId];
        System.assertEquals('Email', copy.Channel__c);
        System.assertEquals('Fee_Receipt', copy.Trigger_Event__c);
        System.assertEquals('Receipt {{ApplicationRef}}', copy.Subject_Template__c);
        System.assertEquals('<p>{{FeeAmount}}</p>', copy.Body_Template__c);
        System.assertEquals('fee {{FeeAmount}}', copy.Content_Text__c);
        System.assertEquals('Advanced', copy.Content_Mode__c);
        System.assertEquals('AA_Service_Agreement', copy.Attachment_Static_Resource_Name__c);
        System.assertEquals('en-GB', copy.Language__c);
        System.assertEquals(false, copy.Active__c, 'a clone must start inactive so it never races the original');
        System.assertEquals(true, [SELECT Active__c FROM AA_Message_Template__c WHERE Id = :src.Id].Active__c,
            'the original must stay active');
    }

    // ── audit #56: mutations are System-Administrator-only ──────────

    @isTest static void mutations_refused_for_non_admin_and_rows_untouched() {
        AA_Message_Template__c existing = insertTemplate('SMS', 'Intake_Created', null, 'keep', 'keep', 'Simple', true);
        User u = nonAdmin();

        Boolean saveThrew = false, dupThrew = false, delThrew = false;
        System.runAs(u) {
            // AuraHandledException.getMessage() reads 'Script-thrown exception'
            // in tests, so assert the type fired and the state that proves the
            // guard held, never the message text.
            try { AA_MessageTemplateController.saveTemplate(input('Email', 'Intake_Created', 's', 'c')); }
            catch (AuraHandledException e) { saveThrew = true; }
            try { AA_MessageTemplateController.duplicateTemplate(existing.Id); }
            catch (AuraHandledException e) { dupThrew = true; }
            try { AA_MessageTemplateController.deleteTemplate(existing.Id); }
            catch (AuraHandledException e) { delThrew = true; }
        }
        System.assert(saveThrew, 'a non-admin save must be refused');
        System.assert(dupThrew,  'a non-admin duplicate must be refused');
        System.assert(delThrew,  'a non-admin delete must be refused');
        System.assertEquals(1, templateCount(), 'no row may be created, cloned or deleted by a non-admin');
        System.assertEquals('keep', [SELECT Content_Text__c FROM AA_Message_Template__c WHERE Id = :existing.Id].Content_Text__c,
            'the existing template must be untouched');
    }

    // ── listTemplates: legacy contentMode inference + ordering ──────

    @isTest static void listTemplates_infers_content_mode_for_legacy_rows_and_labels_events() {
        // Explicit Advanced, inactive → must sort last (Active__c DESC).
        AA_Message_Template__c explicitAdv = insertTemplate('Email', 'Intake_Created', 's', '<p>html</p>', null, 'Advanced', false);
        // Legacy rows: Content_Mode__c cleared AFTER insert (an insert may apply
        // the picklist default; an update to null never does).
        AA_Message_Template__c legacyText  = insertTemplate('Email', 'Custom_Manual', 's', 'mirror', 'text only', 'Simple', true);
        AA_Message_Template__c legacyHtml  = insertTemplate('Email', 'Fee_Charged', 's', '<p>legacy html</p>', null, 'Advanced', true);
        AA_Message_Template__c legacyEmpty = insertTemplate('SMS', 'DD_Setup', null, 'x', null, 'Simple', true);
        update new List<AA_Message_Template__c>{
            new AA_Message_Template__c(Id = legacyText.Id,  Content_Mode__c = null),
            new AA_Message_Template__c(Id = legacyHtml.Id,  Content_Mode__c = null),
            new AA_Message_Template__c(Id = legacyEmpty.Id, Content_Mode__c = null, Body_Template__c = null, Content_Text__c = null)
        };

        List<AA_MessageTemplateController.TemplateRow> rows = AA_MessageTemplateController.listTemplates();

        System.assertEquals(4, rows.size());
        Map<Id, AA_MessageTemplateController.TemplateRow> byId = new Map<Id, AA_MessageTemplateController.TemplateRow>();
        for (AA_MessageTemplateController.TemplateRow r : rows) byId.put(r.id, r);
        System.assertEquals('Advanced', byId.get(explicitAdv.Id).contentMode, 'an explicit Content_Mode__c wins');
        System.assertEquals('Simple',   byId.get(legacyText.Id).contentMode, 'a legacy row with Content_Text__c reads as Simple');
        System.assertEquals('Advanced', byId.get(legacyHtml.Id).contentMode,
            'a legacy row with only Body_Template__c must surface as Advanced so its HTML is visible in the editor');
        System.assertEquals('Simple',   byId.get(legacyEmpty.Id).contentMode, 'an empty legacy row defaults to Simple');
        System.assertEquals('Intake Created', byId.get(explicitAdv.Id).triggerEventLabel, 'the trigger event is labelled from the picklist');
        System.assertEquals('<p>legacy html</p>', byId.get(legacyHtml.Id).bodyTemplate);
        System.assertEquals(false, byId.get(explicitAdv.Id).active);
        System.assertEquals(explicitAdv.Id, rows[3].id, 'inactive templates must sort after active ones');
    }

    // ── renderPreview: dispatcher bridge ────────────────────────────

    @isTest static void renderPreview_resolves_merges_labels_them_and_stamps_last_preview() {
        AA_Application__c app = makeApp('Priya');
        AA_Message_Template__c t = insertTemplate('Email', 'Custom_Manual',
            'Hi {{FirstName}}', 'Ref {{ApplicationRef}} from {{XPEmail}}', null, 'Advanced', true);
        t.Attachment_Static_Resource_Name__c = 'AA_Welcome_Guide';
        update t;

        Test.startTest();
        AA_MessageTemplateController.PreviewResult out = AA_MessageTemplateController.renderPreview(t.Id, app.Id);
        Test.stopTest();

        System.assertEquals('Hi Priya', out.subject, 'the subject must be rendered through the dispatcher');
        System.assert(out.body.contains('Ref ' + app.Name), 'the body must carry the resolved ApplicationRef: ' + out.body);
        System.assertEquals('AA_Welcome_Guide', out.attachmentName, 'the preview must surface the attachment name');

        Map<String, AA_MessageTemplateController.MergeToken> byToken = new Map<String, AA_MessageTemplateController.MergeToken>();
        for (AA_MessageTemplateController.MergeToken m : out.resolvedMerges) byToken.put(m.token, m);
        System.assert(byToken.containsKey('{{FirstName}}'), 'resolved merges must be keyed as {{Token}}');
        System.assertEquals('Priya',      byToken.get('{{FirstName}}').example, 'example is the value resolved for this app');
        System.assertEquals('First name', byToken.get('{{FirstName}}').label, 'the label comes from the palette catalog');
        System.assertEquals('Client',     byToken.get('{{FirstName}}').category);
        System.assertEquals(app.Name,     byToken.get('{{ApplicationRef}}').example);
        // The dispatcher also resolves footer tokens the palette does not list.
        System.assert(byToken.containsKey('{{XPWhatsApp}}'), 'dispatcher-only tokens must still be listed');
        System.assertEquals('Other',      byToken.get('{{XPWhatsApp}}').category, 'tokens outside the palette are categorised Other');
        System.assertEquals('XPWhatsApp', byToken.get('{{XPWhatsApp}}').label);

        System.assertNotEquals(null, [SELECT Last_Preview_At__c FROM AA_Message_Template__c WHERE Id = :t.Id].Last_Preview_At__c,
            'a preview must stamp Last_Preview_At__c');
    }

    @isTest static void renderPreview_rejects_missing_ids_without_stamping() {
        AA_Application__c app = makeApp('Priya');
        AA_Message_Template__c t = insertTemplate('Email', 'Custom_Manual', 's', 'b', null, 'Advanced', true);

        Boolean noTemplate = false, noApp = false;
        try { AA_MessageTemplateController.renderPreview(null, app.Id); } catch (AuraHandledException e) { noTemplate = true; }
        try { AA_MessageTemplateController.renderPreview(t.Id, null);   } catch (AuraHandledException e) { noApp = true; }
        System.assert(noTemplate, 'a missing template id must be rejected');
        System.assert(noApp, 'a missing application id must be rejected');
        System.assertEquals(null, [SELECT Last_Preview_At__c FROM AA_Message_Template__c WHERE Id = :t.Id].Last_Preview_At__c,
            'a rejected preview must not stamp Last_Preview_At__c');
    }

    // ── merge schema: every palette chip must be resolvable by the dispatcher ──
    // Otherwise the LWC offers a token that fails every send with "Unknown
    // merge token" — the palette and buildMergeMap have drifted before.

    @isTest static void mergeSchema_tokens_are_unique_and_all_resolve_through_the_dispatcher() {
        List<AA_MessageTemplateController.MergeToken> palette = AA_MessageTemplateController.getMergeSchema();
        System.assert(palette.size() >= 24, 'palette unexpectedly small: ' + palette.size());

        Set<String> tokens = new Set<String>();
        List<String> parts = new List<String>();
        for (AA_MessageTemplateController.MergeToken m : palette) {
            System.assert(Pattern.matches('\\{\\{[A-Za-z0-9_]+\\}\\}', m.token), 'malformed palette token: ' + m.token);
            System.assert(String.isNotBlank(m.label) && String.isNotBlank(m.category), 'a palette chip needs a label and a category: ' + m.token);
            tokens.add(m.token);
            parts.add(m.token);
        }
        System.assertEquals(palette.size(), tokens.size(), 'the palette must not list a token twice');

        AA_Application__c app = makeApp('Priya');
        AA_Message_Template__c t = insertTemplate('Email', 'Custom_Manual',
            'All: {{FirstName}} {{FeeAmount}} {{CallTime}}', String.join(parts, ' | '), null, 'Advanced', true);

        Test.startTest();
        AA_MessageDispatcher.Rendered r = AA_MessageDispatcher.render(t.Id, app.Id);
        Test.stopTest();

        System.assert(!r.body.contains('{{') && !r.subject.contains('{{'),
            'every palette token must resolve through the dispatcher (unresolved left in: ' + r.body + ')');
        System.assert(r.body.contains('Priya'), 'FirstName must be resolved in the body');
    }

    // ── trigger events ──────────────────────────────────────────────

    @isTest static void getTriggerEvents_mirrors_the_active_picklist_and_includes_the_dispatched_events() {
        List<AA_MessageTemplateController.TriggerEventOption> opts = AA_MessageTemplateController.getTriggerEvents();
        Map<String, String> expected = new Map<String, String>();
        for (Schema.PicklistEntry p : AA_Message_Template__c.Trigger_Event__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) expected.put(p.getValue(), p.getLabel());
        }
        System.assertEquals(expected.size(), opts.size(), 'one option per active picklist value, inactive ones excluded');
        Set<String> values = new Set<String>();
        for (AA_MessageTemplateController.TriggerEventOption o : opts) {
            values.add(o.value);
            System.assertEquals(expected.get(o.value), o.label, 'the label must match the picklist for ' + o.value);
        }
        // The events the Apex dispatch sites fire must be selectable, or an
        // admin can never wire a template to them.
        for (String fired : new List<String>{
                'Intake_Created',            // AA_ApplicationTrigger (mandate landed)
                'Application_Submitted_DWP', // AA_StageTransitionHelper
                'Bacs_Advance_Notice',       // AA_FeeInstallmentScheduler
                'Fee_Receipt_Installment',   // charge-fee webhook
                'Call_Reminder_Morning_Of'   // AA_MorningReminderScheduler
        }) {
            System.assert(values.contains(fired), 'dispatched event missing from the picklist: ' + fired);
        }
    }

    // ── molds: every "Start from template" mold must survive the validator ──

    @isTest static void molds_are_saveable_lead_with_blank_and_never_ask_for_means_test_data() {
        List<AA_MessageTemplateController.TemplateMold> molds = AA_MessageTemplateController.getMolds();
        System.assertEquals(4, molds.size(), 'expected blank + welcome + reminder + status molds');
        System.assertEquals('blank', molds[0].key, 'the blank mold must come first');

        Set<String> keys = new Set<String>();
        // Client copy carries no em dashes (product rule; audit 2026-10-02 F78).
        String emDash = String.fromCharArray(new List<Integer>{ 8212 });
        for (AA_MessageTemplateController.TemplateMold m : molds) {
            keys.add(m.key);
            System.assert(!String.valueOf(m.contentText).contains(emDash) && !String.valueOf(m.subjectTemplate).contains(emDash),
                'mold ' + m.key + ' puts an em dash in client copy');
            System.assert(String.isNotBlank(m.label) && String.isNotBlank(m.description), 'mold ' + m.key + ' needs a label and a description');
            System.assert(m.channel == 'Email' || m.channel == 'SMS', 'mold ' + m.key + ' has an unsupported channel');
            AA_MessageTemplateController.TemplateInput t = new AA_MessageTemplateController.TemplateInput();
            t.channel         = m.channel;
            t.triggerEvent    = m.triggerEvent;
            t.contentMode     = m.contentMode;
            t.subjectTemplate = m.subjectTemplate;
            t.contentText     = m.contentText;
            t.bodyTemplate    = m.bodyTemplate;
            t.active          = false;
            if (m.key == 'blank') {
                System.assert(saveRejected(t), 'the blank mold has no content and must be refused as-is');
            } else {
                // Throws on an unknown token / bad event; the DML rejects an SMS > 480 chars.
                Id id = AA_MessageTemplateController.saveTemplate(t);
                System.assertNotEquals(null, id, 'mold ' + m.key + ' must save');
            }
            if (m.key == 'welcome') {
                // Attendance Allowance is not means-tested (DECISIONS.md §2): the
                // PC1 mold this was cloned from asked for savings and income.
                String text = m.contentText.toLowerCase();
                System.assert(!text.contains('savings') && !text.contains('income'),
                    'the AA welcome mold must not ask the client for savings or income');
                System.assert(text.contains('national insurance'), 'the welcome mold must ask for the NI number');
            }
        }
        System.assertEquals(new Set<String>{ 'blank', 'welcome', 'reminder', 'status' }, keys);
        System.assertEquals(3, templateCount(), 'the three content molds must persist');
        AA_Message_Template__c reminder = [SELECT Channel__c FROM AA_Message_Template__c WHERE Trigger_Event__c = 'Call_Reminder_Morning_Of' LIMIT 1];
        System.assertEquals('SMS', reminder.Channel__c, 'the reminder mold is an SMS');
    }

    // ── listSendLogs: filters, ordering, paging ─────────────────────

    @isTest static void listSendLogs_filters_orders_and_pages() {
        AA_Application__c app = makeApp('Priya');
        AA_Message_Template__c tA = insertTemplate('Email', 'Intake_Created', 'a', 'a', null, 'Advanced', true);
        AA_Message_Template__c tB = insertTemplate('SMS',   'Intake_Created', null, 'b', null, 'Advanced', true);
        tA = [SELECT Id, Name FROM AA_Message_Template__c WHERE Id = :tA.Id];
        insert new List<AA_Message_Send_Log__c>{
            log(tA, app, 'Email', 'Sent',            noonDaysAgo(1),  'one'),
            log(tA, app, 'Email', 'Failed',          noonDaysAgo(2),  'two'),
            log(tB, app, 'SMS',   'Sent',            noonDaysAgo(3),  'three'),
            log(tB, app, 'SMS',   'Skipped-Deduped', noonDaysAgo(10), 'four'),
            log(tA, app, 'Email', 'Sent',            null,            'no-date')
        };

        // No filters: everything, newest first, null Sent_At__c last, default page size.
        AA_MessageTemplateController.SendLogPage all = AA_MessageTemplateController.listSendLogs(null, null, null, 'All', null, null);
        System.assertEquals(5, all.total);
        System.assertEquals(50, all.pageSize, 'a null pageSize defaults to 50');
        System.assertEquals(0, all.pageIndex);
        System.assertEquals(5, all.rows.size());
        System.assertEquals('one',     all.rows[0].renderedSubject, 'newest Sent_At__c first');
        System.assertEquals('four',    all.rows[3].renderedSubject);
        System.assertEquals('no-date', all.rows[4].renderedSubject, 'rows without Sent_At__c sort last');
        System.assertEquals(tA.Name,   all.rows[0].templateName, 'the template name is joined');
        System.assertEquals(app.Name,  all.rows[0].applicationName, 'the application name is joined');
        System.assertEquals('Email',   all.rows[0].channel);
        System.assertEquals('Sent',    all.rows[0].status);

        // Template filter.
        System.assertEquals(3, AA_MessageTemplateController.listSendLogs(null, null, tA.Id, null, 0, 50).total, 'template filter');
        // Status filter.
        AA_MessageTemplateController.SendLogPage failed = AA_MessageTemplateController.listSendLogs(null, null, null, 'Failed', 0, 50);
        System.assertEquals(1, failed.total, 'status filter');
        System.assertEquals('two', failed.rows[0].renderedSubject);
        // Date window today-4 .. today-2 (inclusive, whole days) → 'two' and 'three'.
        AA_MessageTemplateController.SendLogPage window = AA_MessageTemplateController.listSendLogs(
            Date.today().addDays(-4), Date.today().addDays(-2), null, 'All', 0, 50);
        System.assertEquals(2, window.total, 'the date window must include both end days');
        System.assertEquals('two',   window.rows[0].renderedSubject);
        System.assertEquals('three', window.rows[1].renderedSubject);
        // Combined: template B + Sent.
        AA_MessageTemplateController.SendLogPage combo = AA_MessageTemplateController.listSendLogs(null, null, tB.Id, 'Sent', 0, 50);
        System.assertEquals(1, combo.total, 'filters must combine with AND');
        System.assertEquals('three', combo.rows[0].renderedSubject);

        // Paging: 2 per page, second page.
        AA_MessageTemplateController.SendLogPage p1 = AA_MessageTemplateController.listSendLogs(null, null, null, null, 1, 2);
        System.assertEquals(5, p1.total, 'total counts across pages');
        System.assertEquals(2, p1.pageSize);
        System.assertEquals(1, p1.pageIndex);
        System.assertEquals(2, p1.rows.size());
        System.assertEquals('three', p1.rows[0].renderedSubject, 'page 1 starts at the third newest row');
        System.assertEquals('four',  p1.rows[1].renderedSubject);
        // Out-of-range paging inputs are clamped, not passed to SOQL.
        AA_MessageTemplateController.SendLogPage clamped = AA_MessageTemplateController.listSendLogs(null, null, null, null, -3, 999);
        System.assertEquals(50, clamped.pageSize, 'a pageSize > 200 falls back to 50');
        System.assertEquals(0, clamped.pageIndex, 'a negative pageIndex clamps to 0');
        System.assertEquals(5, clamped.rows.size());
    }
}