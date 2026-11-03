/**
 * Tests for PC1_MessageTemplateController (backs the pc1MessageTemplates LWC).
 *
 * The class had NO test until 2026-10-02 (0% coverage), which blocked every
 * deploy touching it. Two behaviours here are regressions guards for real
 * client-facing bugs:
 *   - an SMS template must never be stored as HTML (clients received raw
 *     "<p>…</p>" after an admin fixed a typo in the editor)
 *   - the merge-token catalogue must offer the real fee tokens
 */
@IsTest
private class PC1_MessageTemplateControllerTest {

    private static PC1_MessageTemplateController.TemplateInput input(
            String channel, String trig, String subject, String content) {
        PC1_MessageTemplateController.TemplateInput t = new PC1_MessageTemplateController.TemplateInput();
        t.channel = channel;
        t.triggerEvent = trig;
        t.subjectTemplate = subject;
        t.contentText = content;
        t.contentMode = 'Simple';
        t.active = true;
        return t;
    }

    private static PC1_Application__c makeApp() {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Ada', Last_Name__c = 'Lane', Stage__c = 'New', Email__c = 'ada@example.com');
        insert a;
        return a;
    }

    // ── SMS must be plain text ──────────────────────────────────────

    @IsTest static void sms_saved_from_rich_editor_is_stored_as_plain_text() {
        Id id = PC1_MessageTemplateController.saveTemplate(input('SMS', 'Call_Reminder_Morning_Of', null,
            '<p>Hi {{FirstName}}, we ring you at {{CallTime}} &amp; then email.</p><p>Thanks</p>'));
        PC1_Message_Template__c t = [SELECT Content_Text__c, Body_Template__c, Subject_Template__c
                                       FROM PC1_Message_Template__c WHERE Id = :id];
        System.assert(!t.Content_Text__c.contains('<'), 'no tags may reach an SMS: ' + t.Content_Text__c);
        System.assert(t.Content_Text__c.contains('Hi {{FirstName}}, we ring you at {{CallTime}} & then email.'),
            'entities decoded, tokens kept: ' + t.Content_Text__c);
        System.assert(t.Content_Text__c.contains('\n\nThanks'), 'paragraphs become line breaks: ' + t.Content_Text__c);
        System.assertEquals(null, t.Subject_Template__c, 'SMS has no subject');
    }

    @IsTest static void to_plain_text_handles_breaks_and_blank() {
        System.assertEquals('a\nb', PC1_MessageTemplateController.toPlainText('a<br/>b'));
        System.assertEquals(null, PC1_MessageTemplateController.toPlainText(null));
        System.assertEquals('plain', PC1_MessageTemplateController.toPlainText('plain'));
    }

    @IsTest static void email_keeps_its_content() {
        Id id = PC1_MessageTemplateController.saveTemplate(input('Email', 'Custom_Manual', 'Hi {{FirstName}}',
            '**Bold** for {{FullName}}'));
        PC1_Message_Template__c t = [SELECT Content_Text__c, Body_Template__c, Content_Mode__c, Language__c
                                       FROM PC1_Message_Template__c WHERE Id = :id];
        System.assertEquals('**Bold** for {{FullName}}', t.Content_Text__c);
        System.assertEquals(t.Content_Text__c, t.Body_Template__c, 'Simple mode mirrors content into body');
        System.assertEquals('en-GB', t.Language__c, 'default language');
    }

    // ── validation ─────────────────────────────────────────────────

    private static String errorOf(PC1_MessageTemplateController.TemplateInput t) {
        try { PC1_MessageTemplateController.saveTemplate(t); }
        catch (AuraHandledException e) { return 'threw'; }
        return 'saved';
    }

    @IsTest static void save_rejects_bad_input() {
        System.assertEquals('threw', errorOf(input(null, 'Custom_Manual', 's', 'c')), 'channel required');
        System.assertEquals('threw', errorOf(input('Fax', 'Custom_Manual', 's', 'c')), 'channel must be Email/SMS');
        System.assertEquals('threw', errorOf(input('Email', null, 's', 'c')), 'trigger required');
        System.assertEquals('threw', errorOf(input('Email', 'Custom_Manual', null, 'c')), 'email subject required');
        System.assertEquals('threw', errorOf(input('Email', 'Custom_Manual', 's', '')), 'content required');
        System.assertEquals('threw', errorOf(input('Email', 'Custom_Manual', 's', 'Hi {{NotAToken}}')), 'unknown token in body');
        System.assertEquals('threw', errorOf(input('Email', 'Custom_Manual', 'Hi {{Nope}}', 'c')), 'unknown token in subject');

        PC1_MessageTemplateController.TemplateInput adv = input('Email', 'Custom_Manual', 's', null);
        adv.contentMode = 'Advanced';
        System.assertEquals('threw', errorOf(adv), 'advanced needs body html');
        adv.contentMode = 'Weird';
        System.assertEquals('threw', errorOf(adv), 'mode must be Simple/Advanced');

        boolean threw = false;
        try { PC1_MessageTemplateController.saveTemplate(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'null payload');
    }

    @IsTest static void save_accepts_the_new_fee_tokens() {
        Id id = PC1_MessageTemplateController.saveTemplate(input('Email', 'Custom_Manual', 'Notice',
            'On {{NextChargeDate}} we collect £{{NextChargeAmount}} of £{{FeeAmount}}'));
        System.assertNotEquals(null, id, 'NextChargeDate / NextChargeAmount / FeeAmount are valid tokens');
    }

    @IsTest static void save_updates_existing_template() {
        Id id = PC1_MessageTemplateController.saveTemplate(input('Email', 'Custom_Manual', 'v1', 'one'));
        PC1_MessageTemplateController.TemplateInput t = input('Email', 'Custom_Manual', 'v2', 'two');
        t.id = id;
        System.assertEquals(id, PC1_MessageTemplateController.saveTemplate(t), 'same record updated');
        System.assertEquals('v2', [SELECT Subject_Template__c FROM PC1_Message_Template__c WHERE Id = :id].Subject_Template__c);
    }

    // ── list / duplicate / delete ──────────────────────────────────

    @IsTest static void list_duplicate_delete() {
        Id id = PC1_MessageTemplateController.saveTemplate(input('Email', 'Custom_Manual', 's', 'c'));
        List<PC1_MessageTemplateController.TemplateRow> rows = PC1_MessageTemplateController.listTemplates();
        System.assert(!rows.isEmpty(), 'listed');

        Id copy = PC1_MessageTemplateController.duplicateTemplate(id);
        System.assertNotEquals(id, copy);
        System.assertEquals(false, [SELECT Active__c FROM PC1_Message_Template__c WHERE Id = :copy].Active__c,
            'clones start inactive');

        PC1_MessageTemplateController.deleteTemplate(copy);
        System.assertEquals(0, [SELECT COUNT() FROM PC1_Message_Template__c WHERE Id = :copy]);

        Boolean t1 = false, t2 = false;
        try { PC1_MessageTemplateController.deleteTemplate(null); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_MessageTemplateController.duplicateTemplate(null); } catch (AuraHandledException e) { t2 = true; }
        System.assert(t1 && t2, 'null ids rejected');
    }

    @IsTest static void legacy_rows_get_sensible_content_mode() {
        insert new PC1_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Custom_Manual',
            Active__c = true, Subject_Template__c = 's', Body_Template__c = '<p>legacy</p>');
        insert new PC1_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Custom_Manual',
            Active__c = true, Subject_Template__c = 's', Content_Text__c = 'new style');
        // Content_Mode__c may carry a field default, so only assert every row
        // ends up with a usable mode (the LWC needs one to pick the editor).
        for (PC1_MessageTemplateController.TemplateRow r : PC1_MessageTemplateController.listTemplates()) {
            System.assert(r.contentMode == 'Simple' || r.contentMode == 'Advanced', 'mode: ' + r.contentMode);
        }
    }

    // ── preview ────────────────────────────────────────────────────

    @IsTest static void preview_renders_and_stamps() {
        PC1_Application__c app = makeApp();
        Id id = PC1_MessageTemplateController.saveTemplate(input('Email', 'Custom_Manual', 'Hi {{FirstName}}',
            'Ref {{ApplicationRef}}'));
        Test.startTest();
        PC1_MessageTemplateController.PreviewResult r = PC1_MessageTemplateController.renderPreview(id, app.Id);
        Test.stopTest();
        System.assertEquals('Hi Ada', r.subject);
        System.assertNotEquals(null, r.resolvedMerges);
        System.assertNotEquals(null, [SELECT Last_Preview_At__c FROM PC1_Message_Template__c WHERE Id = :id].Last_Preview_At__c);

        Boolean t1 = false, t2 = false;
        try { PC1_MessageTemplateController.renderPreview(null, app.Id); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_MessageTemplateController.renderPreview(id, null); } catch (AuraHandledException e) { t2 = true; }
        System.assert(t1 && t2, 'missing ids rejected');
    }

    // ── catalogues ─────────────────────────────────────────────────

    @IsTest static void catalogues() {
        Set<String> toks = new Set<String>();
        for (PC1_MessageTemplateController.MergeToken m : PC1_MessageTemplateController.getMergeSchema()) toks.add(m.token);
        System.assert(toks.contains('{{NextChargeAmount}}') && toks.contains('{{NextChargeDate}}'),
            'Bacs notice tokens offered in the editor');
        System.assert(!PC1_MessageTemplateController.getTriggerEvents().isEmpty());
        System.assertEquals(4, PC1_MessageTemplateController.getMolds().size());
    }

    // ── send log feed ──────────────────────────────────────────────

    @IsTest static void send_log_feed_filters_and_pages() {
        PC1_Application__c app = makeApp();
        Id tid = PC1_MessageTemplateController.saveTemplate(input('Email', 'Custom_Manual', 's', 'c'));
        insert new PC1_Message_Send_Log__c(Template__c = tid, Application__c = app.Id,
            Channel__c = 'Email', Status__c = 'Sent', Sent_At__c = Datetime.now());
        insert new PC1_Message_Send_Log__c(Template__c = tid, Application__c = app.Id,
            Channel__c = 'Email', Status__c = 'Failed', Sent_At__c = Datetime.now());

        PC1_MessageTemplateController.SendLogPage all =
            PC1_MessageTemplateController.listSendLogs(null, null, tid, 'All', null, null);
        System.assertEquals(2, all.total, 'scoped to this template (app insert may log its own sends)');
        System.assertEquals(50, all.pageSize, 'default page size');

        PC1_MessageTemplateController.SendLogPage failed =
            PC1_MessageTemplateController.listSendLogs(Date.today().addDays(-1), Date.today().addDays(1), tid, 'Failed', 0, 10);
        System.assertEquals(1, failed.total);
        System.assertEquals('Failed', failed.rows[0].status);
    }
}