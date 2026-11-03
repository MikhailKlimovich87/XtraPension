/**
 * Tests for PC1_RecordPageService (record-page + Clients home LWCs).
 * Added 2026-10-02 — the class had no test (0%).
 */
@IsTest
private class PC1_RecordPageServiceTest {

    private static PC1_Application__c makeApp(String stage, String notes) {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Rp', Last_Name__c = 'Test', Stage__c = stage, Notes__c = notes, Phone__c = '+441234567890');
        insert a;
        return a;
    }

    @IsTest static void reads() {
        PC1_Application__c a = makeApp('New', null);
        insert new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q3', Value__c = 'Rp', Source__c = 'human');
        insert new ContentVersion(Title = 'f', PathOnClient = 'f.txt', VersionData = Blob.valueOf('x'), FirstPublishLocationId = a.Id);

        System.assertEquals(a.Id, PC1_RecordPageService.getApplication(a.Id).Id);
        System.assertEquals(null, PC1_RecordPageService.getApplication(UserInfo.getUserId()));
        System.assert(PC1_RecordPageService.getAnswers(a.Id).size() >= 1);
        System.assertEquals(0, PC1_RecordPageService.getCallHistory(a.Id).size());
        System.assertNotEquals(null, PC1_RecordPageService.getStageHistory(a.Id));
        System.assertNotEquals(null, PC1_RecordPageService.getStages());
        System.assertNotEquals(null, PC1_RecordPageService.getFlowConfig());
        List<Map<String, Object>> files = PC1_RecordPageService.getFiles(a.Id);
        System.assertEquals(1, files.size());

        PC1_RecordPageService.deleteFile((Id) files[0].get('id'));
        System.assertEquals(0, PC1_RecordPageService.getFiles(a.Id).size());
        Boolean threw = false;
        try { PC1_RecordPageService.deleteFile(null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }

    @IsTest static void save_field_creates_then_updates() {
        PC1_Application__c a = makeApp('New', null);
        Id first = PC1_RecordPageService.saveField(a.Id, 'q7_town', 'Leeds', null);
        Id second = PC1_RecordPageService.saveField(a.Id, 'q7_town', 'York', 'mary');
        System.assertEquals(first, second, 'same row updated');
        PC1_Answer__c r = [SELECT Value__c, Source__c FROM PC1_Answer__c WHERE Id = :first];
        System.assertEquals('York', r.Value__c);
        System.assertEquals('mary', r.Source__c);
        Boolean threw = false;
        try { PC1_RecordPageService.saveField(a.Id, '', 'x', null); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }

    @IsTest static void notes_and_stage_change() {
        PC1_Application__c a = makeApp('New', null);
        PC1_RecordPageService.saveNotes(a.Id, 'Prefers mornings');
        PC1_RecordPageService.changeStage(a.Id, 'Needs Human', null);
        PC1_Application__c after = [SELECT Notes__c, Stage__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('Prefers mornings', after.Notes__c);
        System.assertEquals('Needs Human', after.Stage__c);
        List<PC1_Stage_Log__c> logs = [SELECT Note__c FROM PC1_Stage_Log__c WHERE Application__c = :a.Id];
        System.assertEquals(1, logs.size(), 'one audit row per change (was two)');
        System.assertEquals('Changed via record page', logs[0].Note__c);
        Boolean threw = false;
        try { PC1_RecordPageService.changeStage(UserInfo.getUserId(), 'New', 'x'); } catch (Exception e) { threw = true; }
        System.assert(threw);
    }

    @IsTest static void clients_list_filters() {
        makeApp('New', 'short note');
        makeApp('Awarded', 'x'.repeat(120));
        makeApp('Needs Human', null);

        System.assertEquals(3, PC1_RecordPageService.getClientsCount('all'));
        System.assertEquals(1, PC1_RecordPageService.getClientsCount('stage:Awarded'),
            'post-submission stages filter (were missing from the allowlist)');
        System.assertEquals(3, PC1_RecordPageService.getClientsCount('stage:Bogus\' OR Name != null'),
            'unknown stage → no filter, never injected');
        System.assertEquals(1, PC1_RecordPageService.getClientsCount('needs_human'));
        System.assertEquals(0, PC1_RecordPageService.getClientsCount('awaiting_first_call'));
        System.assertEquals(0, PC1_RecordPageService.getClientsCount('ready_for_review'));
        System.assertEquals(0, PC1_RecordPageService.getClientsCount('ready_for_submit'));
        System.assertEquals(3, PC1_RecordPageService.getClientsCount('my_clients'));

        List<Map<String, Object>> rows = PC1_RecordPageService.getClientsList(null, null, null);
        System.assertEquals(3, rows.size());
        Boolean truncated = false;
        for (Map<String, Object> r : rows) {
            String d = (String) r.get('descriptor');
            if (d != null && d.endsWith('...')) truncated = true;
        }
        System.assert(truncated, 'long notes are shortened for the list');
        System.assertEquals(1, PC1_RecordPageService.getClientsList('stage:New', 10, 0).size());
    }

    @IsTest static void submitted_notice_on_first_submission_with_reference() {
        PC1_Application__c a = makeApp('Ready for Submit', null);
        insert new PC1_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Application_Submitted_DWP',
            Active__c = true, Subject_Template__c = 'Submitted', Body_Template__c = 'Hi');
        update new PC1_Application__c(Id = a.Id, Email__c = 'sub@example.com');
        Test.startTest();
        update new PC1_Application__c(Id = a.Id, Stage__c = 'Submitted', DWP_Reference__c = 'REF123');
        // A correction: out of Submitted and back in must not notify again.
        PC1_RecordPageService.changeStage(a.Id, 'Needs Human', null);
        PC1_RecordPageService.changeStage(a.Id, 'Submitted', 'back after fix');
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Message_Send_Log__c WHERE Application__c = :a.Id],
            'one submission notice per application');
    }

    // ── Call history (2026-10-29 call-history audit) ─────────────────

    @IsTest static void call_history_hides_closed_placeholders_and_resigns_links() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = 'pc1-files-test-secret-2026';
        upsert cfg;
        PC1_Application__c a = makeApp('New', null);
        Datetime t = Datetime.now().addHours(-3);
        String base = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com/files/';
        insert new List<PC1_Call_Log__c>{
            // a real Mary call with a link signed under the pre-2026-08-29 scheme
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t, Status__c = 'completed',
                Direction__c = 'outbound', Source__c = 'Mary', Conversation_Id__c = 'conv_0123456789abcdefghij',
                Transcript_URL__c = base + 'transcript/conv_0123456789abcdefghij?t=OLDTOKENOLDTOKENOLDTOK',
                Recording_URL__c = base + 'recording/conv_0123456789abcdefghij?t=OLDTOKENOLDTOKENOLDTOK'),
            // a human call with a Nuacom recording
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t.addMinutes(30), Status__c = 'completed',
                Direction__c = 'inbound', Source__c = 'Human', Rep_Name__c = 'Richard',
                Recording_URL__c = base + 'nuacom-recording/svr16-core6-1730203200.4567?t=stale'),
            // personalization placeholder closed without a call → hidden
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t.addMinutes(60), Status__c = 'no_answer',
                Direction__c = 'inbound_known', Source__c = 'Mary', Personalization_Only__c = true),
            // placeholder for a call still ringing → shown
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t.addMinutes(90), Status__c = 'in_progress',
                Direction__c = 'inbound_known', Source__c = 'Mary', Personalization_Only__c = true)
        };

        List<PC1_Call_Log__c> rows = PC1_RecordPageService.getCallHistory(a.Id);
        System.assertEquals(3, rows.size(), 'the closed placeholder is hidden');
        System.assertEquals(3, PC1_RecordPageService.getCallHistoryCount(a.Id), 'count uses the same filter');
        System.assertEquals('in_progress', rows[0].Status__c, 'newest first');
        System.assertEquals('Richard', rows[1].Rep_Name__c, 'rep is returned for the card');
        System.assertEquals(base + 'nuacom-recording/svr16-core6-1730203200.4567?t=09sM3kuSibxHiTSb6DEoSQ', rows[1].Recording_URL__c);
        System.assertEquals(base + 'transcript/conv_0123456789abcdefghij?t=4PbAEnJD14mCKx9VZRc-TV', rows[2].Transcript_URL__c);
        System.assertEquals(base + 'recording/conv_0123456789abcdefghij?t=4PbAEnJD14mCKx9VZRc-TV', rows[2].Recording_URL__c);
        System.assertEquals(base + 'transcript/conv_0123456789abcdefghij?t=OLDTOKENOLDTOKENOLDTOK',
            [SELECT Transcript_URL__c FROM PC1_Call_Log__c WHERE Id = :rows[2].Id].Transcript_URL__c,
            'the stored row is not changed');
    }
}