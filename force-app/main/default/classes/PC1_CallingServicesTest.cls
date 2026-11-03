/**
 * Tests for the small call/record-page services that had no test until
 * 2026-10-02: PC1_LastContactUpdater + PC1_CallLogTrigger,
 * PC1_MarkScheduleFired, PC1_CallScheduleService, PC1_HandoffService,
 * PC1_ApplicationHistoryController and PC1_AnswersController.
 * PC1_CallLogTrigger at 0% alone blocks any production deploy.
 */
@IsTest
private class PC1_CallingServicesTest {

    private static PC1_Application__c makeApp() {
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'Call', Last_Name__c = 'Svc', Stage__c = 'New');
        insert a;
        return a;
    }

    // ── Last contact (trigger on call logs) ──────────────────────────

    @IsTest static void call_log_updates_last_contact_and_ignores_older() {
        PC1_Application__c a = makeApp();
        Datetime t1 = Datetime.now().addHours(-2);
        insert new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t1, Status__c = 'completed',
            Direction__c = 'outbound', Source__c = 'Mary');
        PC1_Application__c after = [SELECT Last_Contact_Type__c, Last_Contact_Who__c, Last_Contact_At__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('Phone Chat', after.Last_Contact_Type__c);
        System.assertEquals('Mary', after.Last_Contact_Who__c);
        System.assertEquals(t1, after.Last_Contact_At__c);

        // An older log must not overwrite the newer contact.
        insert new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addHours(-5), Status__c = 'completed',
            Direction__c = 'outbound', Source__c = 'Human', Rep_Name__c = 'Fiona');
        System.assertEquals(t1, [SELECT Last_Contact_At__c FROM PC1_Application__c WHERE Id = :a.Id].Last_Contact_At__c);

        // Newer human no-answer → No Answer, attributed to the rep.
        insert new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = Datetime.now(), Status__c = 'no_answer',
            Direction__c = 'outbound', Source__c = 'Human', Rep_Name__c = 'Fiona');
        after = [SELECT Last_Contact_Type__c, Last_Contact_Who__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('No Answer', after.Last_Contact_Type__c);
        System.assertEquals('Fiona', after.Last_Contact_Who__c);
    }

    @IsTest static void derive_helpers() {
        System.assertEquals('Phone Chat', PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(Status__c = 'completed')));
        System.assertEquals(null, PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c()), 'no status = still open');
        System.assertEquals(null, PC1_LastContactUpdater.deriveWho(new PC1_Call_Log__c()));
        System.assertEquals('Human', PC1_LastContactUpdater.deriveWho(new PC1_Call_Log__c(Source__c = 'Human')));
        System.assertEquals('Fiona', PC1_LastContactUpdater.deriveWho(new PC1_Call_Log__c(Source__c = 'Human', Rep_Name__c = 'Fiona')));
        PC1_LastContactUpdater.fromCallLogs(null);
        PC1_LastContactUpdater.fromCallLogs(new List<PC1_Call_Log__c>{ new PC1_Call_Log__c() });
    }

    // 2026-10-29 call-history audit: every case of the contact-type contract.
    @IsTest static void derive_type_contract() {
        // voicemail before the Mary shortcut
        System.assertEquals('V/Mail Left', PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'no_answer', Voicemail_Left__c = true)));
        System.assertEquals('No Answer', PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'no_answer')));
        System.assertEquals('No Answer', PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Human', Direction__c = 'outbound', Status__c = 'failed')));
        System.assertEquals('Phone Chat', PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'rescheduled')));
        System.assertEquals('Phone Chat', PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'inbound_known', Status__c = 'completed')));
        // not contacts
        System.assertEquals(null, PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'inbound_known', Status__c = 'completed', Personalization_Only__c = true)));
        System.assertEquals(null, PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'in_progress')));
        System.assertEquals(null, PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Human', Direction__c = 'inbound', Status__c = 'no_answer')));
        System.assertEquals(null, PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'inbound_unknown', Status__c = 'failed')));
        System.assertEquals(null, PC1_LastContactUpdater.deriveType(new PC1_Call_Log__c(
            Source__c = 'Human', Direction__c = 'inbound', Status__c = 'completed', Voicemail_Left__c = true)),
            'a voicemail the client left us is not our contact');
    }

    @IsTest static void last_contact_skips_placeholders_missed_inbound_and_open_calls() {
        PC1_Application__c a = makeApp();
        Datetime t1 = Datetime.now().addHours(-3);
        insert new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t1, Status__c = 'completed',
            Direction__c = 'outbound', Source__c = 'Human', Rep_Name__c = 'Grace');
        insert new List<PC1_Call_Log__c>{
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addHours(1), Status__c = 'no_answer',
                Direction__c = 'inbound_known', Source__c = 'Mary', Personalization_Only__c = true),
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addHours(2), Status__c = 'no_answer',
                Direction__c = 'inbound', Source__c = 'Human', Rep_Name__c = 'Reception XtraPension'),
            new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addMinutes(150), Status__c = 'in_progress',
                Direction__c = 'outbound', Source__c = 'Mary')
        };
        PC1_Application__c after = [SELECT Last_Contact_Type__c, Last_Contact_Who__c, Last_Contact_At__c FROM PC1_Application__c WHERE Id = :a.Id];
        Datetime graceAt = [SELECT Started_At__c FROM PC1_Call_Log__c WHERE Application__c = :a.Id AND Rep_Name__c = 'Grace'].Started_At__c;
        System.assertEquals(graceAt, after.Last_Contact_At__c, 'none of the later rows is a contact');
        System.assertEquals('Phone Chat', after.Last_Contact_Type__c);
        System.assertEquals('Grace', after.Last_Contact_Who__c);
    }

    @IsTest static void last_contact_rederives_when_the_same_call_closes() {
        PC1_Application__c a = makeApp();
        Datetime t = Datetime.now().addMinutes(-30);
        PC1_Call_Log__c cl = new PC1_Call_Log__c(Application__c = a.Id, Started_At__c = t, Status__c = 'in_progress',
            Direction__c = 'outbound', Source__c = 'Mary');
        insert cl;
        System.assertEquals(null, [SELECT Last_Contact_At__c FROM PC1_Application__c WHERE Id = :a.Id].Last_Contact_At__c,
            'an open call is not mirrored');

        Test.startTest();
        cl.Status__c = 'no_answer';
        cl.Voicemail_Left__c = true;
        update cl;
        PC1_Application__c mid = [SELECT Last_Contact_Type__c, Last_Contact_Who__c, Last_Contact_At__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('V/Mail Left', mid.Last_Contact_Type__c, 'Mary voicemail is V/Mail Left, not Phone Chat');
        System.assertEquals('Mary', mid.Last_Contact_Who__c);
        System.assertEquals([SELECT Started_At__c FROM PC1_Call_Log__c WHERE Id = :cl.Id].Started_At__c, mid.Last_Contact_At__c);

        // Same Started_At__c, corrected outcome → re-derived (the gate is >, not >=).
        cl.Status__c = 'completed';
        cl.Voicemail_Left__c = false;
        update cl;
        Test.stopTest();
        System.assertEquals('Phone Chat', [SELECT Last_Contact_Type__c FROM PC1_Application__c WHERE Id = :a.Id].Last_Contact_Type__c);
    }

    // ── Call schedules ───────────────────────────────────────────────

    @IsTest static void schedule_create_cancel_and_reads() {
        PC1_Application__c a = makeApp();
        Id s = PC1_CallScheduleService.createSchedule(a.Id, Datetime.now().addDays(1));
        System.assertEquals(s, PC1_CallScheduleService.getActivePending(a.Id).Id);
        System.assertEquals(1, PC1_CallScheduleService.getScheduleHistory(a.Id, null).size());
        PC1_CallScheduleService.cancelSchedule(s, 'client asked');
        System.assertEquals('Cancelled', [SELECT Status__c FROM PC1_Call_Schedule__c WHERE Id = :s].Status__c);
        System.assertEquals(null, PC1_CallScheduleService.getActivePending(a.Id));

        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_CallScheduleService.cancelSchedule(s, null); } catch (AuraHandledException e) { t1 = true; }   // not Pending
        try { PC1_CallScheduleService.cancelSchedule(null, null); } catch (AuraHandledException e) { t2 = true; }
        try { PC1_CallScheduleService.createSchedule(null, Datetime.now()); } catch (AuraHandledException e) { t3 = true; }
        try { PC1_CallScheduleService.createSchedule(a.Id, null); } catch (AuraHandledException e) { t4 = true; }
        System.assert(t1 && t2 && t3 && t4);
        System.assertEquals(null, PC1_CallScheduleService.getActivePending(null));
        System.assertEquals(0, PC1_CallScheduleService.getScheduleHistory(null, 5).size());
    }

    // ── REST: mark schedule fired (called by the Heroku scheduler) ───

    private static Map<String, Object> fire(String body) {
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf(body);
        RestContext.response = new RestResponse();
        PC1_MarkScheduleFired.fire();
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @IsTest static void mark_schedule_fired_once() {
        PC1_Application__c a = makeApp();
        PC1_Call_Schedule__c s = new PC1_Call_Schedule__c(Application__c = a.Id, Scheduled_At__c = Datetime.now().addMinutes(5), Status__c = 'Pending');
        insert s;
        System.assertEquals(true, fire('{"schedule_id":"' + s.Id + '"}').get('fired'));
        System.assertEquals(false, fire('{"schedule_id":"' + s.Id + '"}').get('fired'), 'second fire is a no-op');
        System.assertEquals('schedule_id required', fire('{}').get('error'));
        System.assertEquals('schedule_not_found', fire('{"schedule_id":"' + a.Id + '"}').get('error'));
        System.assertEquals(false, fire('not json').get('fired'));
    }

    // ── Handoffs + fill run panel ────────────────────────────────────

    @IsTest static void handoff_and_fill_run() {
        PC1_Application__c a = makeApp();
        System.assertEquals(null, PC1_HandoffService.getLatestOpenHandoff(a.Id));
        System.assertEquals(null, PC1_HandoffService.getLatestFillRun(a.Id));
        PC1_Handoff__c h = new PC1_Handoff__c(Application__c = a.Id, Escalation_Type__c = 'confused', Reason__c = 'x');
        insert h;
        insert new PC1_Fill_Run__c(Application__c = a.Id, Status__c = 'failed', Error_Message__c = 'page not found');
        System.assertEquals(h.Id, PC1_HandoffService.getLatestOpenHandoff(a.Id).Id);
        System.assertEquals('failed', PC1_HandoffService.getLatestFillRun(a.Id).Status__c);
        PC1_HandoffService.FillRunPanelData d = PC1_HandoffService.getFillRunPanelData(a.Id);
        System.assertEquals('New', d.stage);
        System.assertEquals('page not found', d.fillRun.Error_Message__c);
        PC1_HandoffService.markResolved(h.Id);
        System.assertEquals(null, PC1_HandoffService.getLatestOpenHandoff(a.Id));
    }

    // ── Field history + answers list ─────────────────────────────────

    @IsTest static void history_and_answers() {
        PC1_Application__c a = makeApp();
        insert new List<PC1_Application__History>{
            new PC1_Application__History(ParentId = a.Id, Field = 'created'),
            new PC1_Application__History(ParentId = a.Id, Field = 'Stage__c')
        };
        List<PC1_ApplicationHistoryController.HistoryRow> rows = PC1_ApplicationHistoryController.getHistory(a.Id, null);
        System.assertEquals(2, rows.size());
        System.assertEquals(2, PC1_ApplicationHistoryController.getHistoryCount(a.Id));
        Set<String> labels = new Set<String>();
        for (PC1_ApplicationHistoryController.HistoryRow r : rows) labels.add(r.FieldLabel);
        System.assert(labels.contains('Created') && labels.contains('Stage'));
        System.assertEquals(0, PC1_ApplicationHistoryController.getHistory(null, 5).size());
        System.assertEquals(0, PC1_ApplicationHistoryController.getHistoryCount(null));

        insert new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q7_town', Value__c = 'York', Source__c = 'human');
        System.assert(PC1_AnswersController.getAnswers(a.Id).size() > 1, 'defaults seeded on insert + the saved answer');
        System.assertEquals(0, PC1_AnswersController.getAnswers(null).size());
    }
}