/**
 * AA_RecordPageServiceTest — the @AuraEnabled bridge behind the record-page
 * LWCs (Header, PathBar, ApplicationData, CallHistory, StageTimeline, Files)
 * and the home-page Clients list.
 *
 * The home-page Clients filter must honour EVERY Stage__c picklist value.
 * Until 2026-09-11 the KNOWN_STAGES allowlist was a hand-kept list that
 * stopped at 'Needs Human' (and carried 'Ready for Autofill', never a
 * Stage__c value), and resolveFilter drops the WHERE for a value it does not
 * know — so 'stage:Awarded' silently returned every client (review-backlog
 * 2026-09-11, cluster sf-metadata).
 *
 * The record-page reads/writes (getApplication, getAnswers/saveField,
 * getCallHistory, getStageHistory/changeStage, getStages, getFlowConfig,
 * getFiles/deleteFile, saveNotes) had no coverage before 2026-09-11; each
 * test below asserts the rows the LWC would render, not just that a call ran.
 */
@isTest
private class AA_RecordPageServiceTest {

    private static AA_Application__c makeApp(String stage) {
        // Inserting straight onto a post-submission stage is fine: the stage
        // state machine (AA_StageTransitionHelper) only runs before UPDATE, and
        // AA_FeeInstallmentSchedulerTest already inserts at 'Awarded'.
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Filter',
            Last_Name__c  = 'Test' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c      = '+441234567890',
            DOB__c        = Date.newInstance(1955, 3, 20),
            Postcode__c   = 'SW1A 1AA',
            // With an email on file the 5 policy defaults are seeded (email-submit
            // is only defaulted when an email exists, audit 2026-10-02 F27).
            Email__c      = 'filter@example.com',
            Stage__c      = stage
        );
        insert a;
        return a;
    }

    // A post-submission stage filter returns exactly the record on that stage.
    @isTest static void stageFilter_honoursPostSubmissionStages() {
        AA_Application__c awarded = makeApp('Awarded');
        makeApp('Closed - Refused');

        Test.startTest();
        Integer nAwarded = AA_RecordPageService.getClientsCount('stage:Awarded');
        Integer nRefused = AA_RecordPageService.getClientsCount('stage:Closed - Refused');
        List<Map<String, Object>> rows = AA_RecordPageService.getClientsList('stage:Awarded', 50, 0);
        Test.stopTest();

        System.assertEquals(1, nAwarded, 'stage:Awarded must count only the Awarded record');
        System.assertEquals(1, nRefused, 'stage:Closed - Refused must count only the refused record');
        System.assertEquals(1, rows.size(), 'stage:Awarded must list only the Awarded record');
        System.assertEquals(awarded.Id, (Id) rows[0].get('id'), 'the listed row is the Awarded record');
        System.assertEquals('Awarded', (String) rows[0].get('stage'), 'row carries its stage');
    }

    // Every picklist value narrows the list. With one record on 'New', a
    // filter on any other value must count 0 — the pre-fix failure was a
    // value missing from the allowlist falling through to "no WHERE", which
    // would count 1 here (i.e. every client).
    @isTest static void stageFilter_everyPicklistValueNarrows() {
        makeApp('New');
        System.assertEquals(1, AA_RecordPageService.getClientsCount('all'), 'baseline: one record in the test transaction');
        System.assertEquals(1, AA_RecordPageService.getClientsCount('stage:New'), 'stage:New finds the record');
        for (Schema.PicklistEntry e : Schema.SObjectType.AA_Application__c.fields.Stage__c.getPicklistValues()) {
            if (e.getValue() == 'New') continue;
            System.assertEquals(0, AA_RecordPageService.getClientsCount('stage:' + e.getValue()),
                'stage:' + e.getValue() + ' must narrow to records on that stage (none here), not return every client');
        }
    }

    // ── getClientsList: legacy shortcut filters, my_clients, paging clamps ──

    @isTest static void clientsList_legacy_filters_my_clients_and_paging_clamps() {
        makeApp('Needs Human');
        makeApp('Awaiting First Call');
        makeApp('Ready for Review');
        makeApp('Ready for Submit');
        makeApp('Reviewed');
        makeApp('New');

        System.assertEquals(1, AA_RecordPageService.getClientsCount('needs_human'),         'needs_human shortcut');
        System.assertEquals(1, AA_RecordPageService.getClientsCount('AWAITING_FIRST_CALL'), 'legacy keys are case-insensitive');
        System.assertEquals(1, AA_RecordPageService.getClientsCount('ready_for_review'),    'ready_for_review shortcut');
        System.assertEquals(2, AA_RecordPageService.getClientsCount('ready_for_submit'),    'ready_for_submit covers Ready for Submit + Reviewed');
        System.assertEquals(6, AA_RecordPageService.getClientsCount('my_clients'),          'my_clients = records owned by the running user');
        System.assertEquals(6, AA_RecordPageService.getClientsCount(null),                  'a null filter means all');

        System.assertEquals(6, AA_RecordPageService.getClientsList('all', null, null).size(), 'null paging falls back to defaults');
        System.assertEquals(2, AA_RecordPageService.getClientsList('all', 2, 0).size(),       'pageSize honoured');
        System.assertEquals(2, AA_RecordPageService.getClientsList('all', 2, 4).size(),       'offset honoured');
        System.assertEquals(0, AA_RecordPageService.getClientsList('all', 2, 6).size(),       'offset past the end yields nothing');
        System.assertEquals(6, AA_RecordPageService.getClientsList('all', 0, -1).size(),      'pageSize 0 / negative offset clamp to defaults');
        System.assertEquals(6, AA_RecordPageService.getClientsList('all', 500, 0).size(),     'pageSize > 200 clamps to the default 100');

        List<Map<String, Object>> rows = AA_RecordPageService.getClientsList('needs_human', 50, 0);
        System.assertEquals(1, rows.size());
        System.assertEquals('Needs Human',   (String) rows[0].get('stage'));
        System.assertEquals('+441234567890', (String) rows[0].get('phone'), 'the row carries the phone');
        System.assert(rows[0].containsKey('progressPct') && rows[0].containsKey('createdAt') && rows[0].containsKey('fullName'),
            'the row carries progress, created date and full name for the list card');
    }

    // ── getApplication ───────────────────────────────────────────────

    @isTest static void getApplication_returns_the_record_or_null() {
        AA_Application__c a = makeApp('New');

        AA_Application__c got = AA_RecordPageService.getApplication(a.Id);

        System.assertNotEquals(null, got, 'an existing record must be returned');
        System.assertEquals(a.Id, got.Id);
        System.assertEquals('Filter', got.First_Name__c, 'header fields are selected');
        System.assertEquals('New', got.Stage__c);
        System.assertEquals('Filter ' + a.Last_Name__c, got.Full_Name__c, 'the Full_Name__c formula is selected');
        System.assertEquals('SW1A 1AA', got.Postcode__c);
        System.assertNotEquals(null, got.CreatedDate);

        Id missing = Id.valueOf(AA_Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
        System.assertEquals(null, AA_RecordPageService.getApplication(missing), 'an unknown id must return null, not throw');
    }

    // ── saveField / getAnswers ───────────────────────────────────────

    @isTest static void saveField_creates_then_updates_in_place() {
        AA_Application__c a = makeApp('New');

        Boolean threw = false;
        try { AA_RecordPageService.saveField(a.Id, '  ', 'x', 'human'); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a blank field_id must be rejected');

        Test.startTest();
        Id first = AA_RecordPageService.saveField(a.Id, 'first-name', 'Aoife', null);
        Id again = AA_RecordPageService.saveField(a.Id, 'first-name', 'Aoife-updated', 'mary');
        Test.stopTest();

        System.assertEquals(first, again, 'a second save of the same field must update the existing row');
        List<AA_Answer__c> rows = [SELECT Value__c, Source__c FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'first-name'];
        System.assertEquals(1, rows.size(), 'exactly one AA_Answer__c per field_id');
        System.assertEquals('Aoife-updated', rows[0].Value__c, 'the value is updated in place');
        System.assertEquals('mary', rows[0].Source__c, 'an explicit source is stored');
        // audit 2026-10-02 F44/F177: the retired Mary_Progress_* counter no
        // longer runs on saves, and this test no longer reads those fields so
        // they can be dropped from the AA_User permission set and report type.
        // The real counter is still written by AA_AnswerTrigger.
        System.assertNotEquals(null, [SELECT Progress_Total__c FROM AA_Application__c WHERE Id = :a.Id].Progress_Total__c,
            'saving an answer keeps the real Progress_* counters current');
    }

    // ── saveField validation (audit 2026-10-02 F40/F58/F171) ────────

    @isTest static void saveField_normalises_like_the_heroku_paths() {
        AA_Application__c a = makeApp('New');

        Id ni = AA_RecordPageService.saveField(a.Id, 'national-insurance', ' ab 12 34 56 c ', 'human');
        Id pc = AA_RecordPageService.saveField(a.Id, 'home-address-manual-postcode', 'sw1a 2aa', 'human');
        Id em = AA_RecordPageService.saveField(a.Id, 'contact-by-email', ' margaret @example.com ', 'human');
        Id ph = AA_RecordPageService.saveField(a.Id, 'gp-telephone', ' 020 7946 0123 ', 'human');
        Id hp = AA_RecordPageService.saveField(a.Id, 'healthcare-professional-telephone__2', '07700 900982', 'human');

        System.assertEquals('AB123456C', [SELECT Value__c FROM AA_Answer__c WHERE Id = :ni].Value__c, 'NI upper-cased, spaces removed');
        System.assertEquals('SW1A 2AA', [SELECT Value__c FROM AA_Answer__c WHERE Id = :pc].Value__c, 'postcode upper-cased');
        System.assertEquals('margaret@example.com', [SELECT Value__c FROM AA_Answer__c WHERE Id = :em].Value__c, 'email whitespace removed');
        System.assertEquals('020 7946 0123', [SELECT Value__c FROM AA_Answer__c WHERE Id = :ph].Value__c, 'phone kept as typed, trimmed');
        System.assertEquals('07700 900982', [SELECT Value__c FROM AA_Answer__c WHERE Id = :hp].Value__c, 'loop entries are checked against their base field');
        System.assertEquals('M1 2AB', AA_RecordPageService.normaliseAnswer('representative-address-postcode', 'm1 2ab'));
        System.assertEquals('margaret@example.com', AA_RecordPageService.normaliseAnswer('supporting-documents-email-confirm', ' margaret @example.com '),
            'a confirm box is an email too');
        System.assertEquals('free text', AA_RecordPageService.normaliseAnswer('health-conditions__1', 'free text'), 'other fields pass through');
        System.assertEquals('', AA_RecordPageService.normaliseAnswer('national-insurance', ''), 'a blank value clears the answer');
    }

    @isTest static void saveField_rejects_values_dwp_would_refuse() {
        AA_Application__c a = makeApp('New');
        Map<String, String> bad = new Map<String, String>{
            'national-insurance'               => 'banana',
            'representative-national-insurance'=> 'QQ123456C',
            'main-contact-number'              => '12345',
            'home-address-postcode'            => 'NOT A POSTCODE',
            'contact-by-email'                 => 'yes',
            // validateSave holds the confirm boxes to the email shape too (F10).
            'contact-by-email-confirm'         => 'yes'
        };
        for (String fid : bad.keySet()) {
            String msg = null;
            try { AA_RecordPageService.saveField(a.Id, fid, bad.get(fid), 'human'); }
            catch (AuraHandledException e) { msg = e.getMessage(); }
            System.assertNotEquals(null, msg, fid + '=' + bad.get(fid) + ' must be rejected');
            System.assert(!msg.contains('—'), 'operator messages carry no em dash: ' + msg);
        }
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c IN :bad.keySet()],
            'nothing invalid is stored');
    }

    // ── option answers held to the catalogue (e2e 2026-10-08 C5) ─────
    //
    // The e2e probe stored each value refused below as sent, while the client
    // form and Mary (src/lib/mary-validator.js validateSave) refuse every one.
    // The LWC only offers catalogue codes, so only a direct caller of the
    // @AuraEnabled method could store them.

    /** The AuraHandledException message saveField raised, or null when it saved. */
    private static String rejection(Id appId, String fieldId, String value) {
        try {
            AA_RecordPageService.saveField(appId, fieldId, value, 'human');
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    /** The question a catalogue field asks, as the operator messages quote it. */
    private static String labelOf(String fieldId) {
        for (Object po : AA_FlowEngine.flowPages()) {
            for (Object fo : (List<Object>) ((Map<String, Object>) po).get('fields')) {
                Map<String, Object> f = (Map<String, Object>) fo;
                if (fieldId.equals((String) f.get('id'))) return (String) f.get('label');
            }
        }
        System.assert(false, fieldId + ' is not in the catalogue');
        return null;
    }

    /** The PAGES list of a catalogue body, as AA_FlowEngine.flowPages() hands it over. */
    private static List<Object> pagesOf(String flowJson) {
        return (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(flowJson)).get('PAGES');
    }

    @isTest static void option_answers_off_the_catalogue_are_refused() {
        AA_Application__c a = makeApp('New');
        String formatsBefore = [SELECT Value__c FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'alternative-formats'].Value__c;

        Test.startTest();
        String mars    = rejection(a.Id, 'residence-country', 'mars');
        String scalar  = rejection(a.Id, 'day-difficulties', 'daytime-washing');
        String offList = rejection(a.Id, 'day-difficulties', '["daytime-washing","daytime-flying"]');
        // DWP made alternative-formats a single-choice radio on 2026-10-08: the
        // old checkbox value must not come back through the record page.
        String legacy  = rejection(a.Id, 'alternative-formats', '["format-none"]');
        Map<String, String> others = new Map<String, String>{
            'who-is-applying=martian'            => rejection(a.Id, 'who-is-applying', 'martian'),
            'alternative-formats=telepathy'      => rejection(a.Id, 'alternative-formats', 'format-telepathy'),
            'day-difficulties=not-a-json-array'  => rejection(a.Id, 'day-difficulties', 'not-a-json-array'),
            'day-difficulties=a JSON object'     => rejection(a.Id, 'day-difficulties', '{"daytime-bed": true}'),
            'day-difficulties=broken JSON'       => rejection(a.Id, 'day-difficulties', '["daytime-bed"')
        };
        Test.stopTest();

        System.assert(mars != null && mars.startsWith('"mars" is not an option for "' + labelOf('residence-country') + '".')
            && mars.contains('Choose one of: england, scotland'), 'the value, the question and the codes it takes: ' + mars);
        System.assert(scalar != null && scalar.contains('as a list of the ticked options, like ["daytime-bed"]'),
            'a tick-box answer is a list, even when the code itself is right: ' + scalar);
        System.assert(offList != null && offList.startsWith('Not an option for "' + labelOf('day-difficulties') + '": ')
            && offList.contains('"daytime-flying"') && !offList.contains('"daytime-washing"'),
            'one off-list entry refuses the list, and only that entry is named: ' + offList);
        System.assert(legacy != null && legacy.startsWith('"' + labelOf('alternative-formats') + '" takes one option, not a list.')
            && legacy.contains('format-standard'), 'the legacy checkbox value is refused on the radio: ' + legacy);
        for (String k : others.keySet()) System.assertNotEquals(null, others.get(k), k + ' must be refused');
        for (String msg : new List<String>{ mars, scalar, offList, legacy }) {
            System.assert(!msg.contains('—'), 'operator messages carry no em dash: ' + msg);
        }
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id
                                 AND Field_Id__c IN ('residence-country', 'who-is-applying', 'day-difficulties')],
            'nothing refused is stored');
        System.assertEquals(formatsBefore, [SELECT Value__c FROM AA_Answer__c WHERE Application__c = :a.Id
                                              AND Field_Id__c = 'alternative-formats'].Value__c,
            'a refused save leaves the stored answer as it was');
    }

    @isTest static void option_answers_are_stored_as_the_catalogue_codes() {
        AA_Application__c a = makeApp('New');

        Test.startTest();
        Id country = AA_RecordPageService.saveField(a.Id, 'residence-country', ' England ', 'human');
        Id days    = AA_RecordPageService.saveField(a.Id, 'day-difficulties', '[ "daytime-bed", "DAYTIME-WASHING" ]', 'human');
        Id formats = AA_RecordPageService.saveField(a.Id, 'alternative-formats', 'format-large', 'human');
        // A loop entry ("<field>__<n>") is held to its base field. DWP spells
        // this field's codes 'Yes' / 'No'.
        Id aid2    = AA_RecordPageService.saveField(a.Id, 'aids-adaptations-difficulty-2__2', 'no', 'human');
        String loopMsg = rejection(a.Id, 'aids-adaptations-difficulty-2__2', 'maybe');
        Test.stopTest();

        System.assertEquals('england', [SELECT Value__c FROM AA_Answer__c WHERE Id = :country].Value__c, 'trimmed, and spelt as the catalogue code');
        System.assertEquals('["daytime-bed","daytime-washing"]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :days].Value__c,
            'the ticked codes, spelt as the catalogue spells them');
        System.assertEquals('format-large', [SELECT Value__c FROM AA_Answer__c WHERE Id = :formats].Value__c, 'a valid radio code is stored');
        AA_Answer__c entry = [SELECT Field_Id__c, Value__c FROM AA_Answer__c WHERE Id = :aid2];
        System.assertEquals('aids-adaptations-difficulty-2__2', entry.Field_Id__c, 'the entry keeps its own id');
        System.assertEquals('No', entry.Value__c, 'and the code as DWP spells it');
        System.assert(loopMsg != null && loopMsg.contains('is not an option for "' + labelOf('aids-adaptations-difficulty-2') + '".')
            && loopMsg.contains('Yes, No'), 'an off-list loop entry is refused against its base field: ' + loopMsg);
    }

    @isTest static void a_blank_value_still_clears_an_option_answer() {
        AA_Application__c a = makeApp('New');
        Id country = AA_RecordPageService.saveField(a.Id, 'residence-country', 'wales', 'human');
        Id days    = AA_RecordPageService.saveField(a.Id, 'day-difficulties', '["daytime-moving"]', 'human');

        Test.startTest();
        Id countryAgain = AA_RecordPageService.saveField(a.Id, 'residence-country', '', 'human');
        Id daysAgain    = AA_RecordPageService.saveField(a.Id, 'day-difficulties', '', 'human');
        Test.stopTest();

        System.assertEquals(country, countryAgain, 'the same row is cleared, not a new one written');
        System.assertEquals(days, daysAgain);
        System.assertEquals(null, [SELECT Value__c FROM AA_Answer__c WHERE Id = :country].Value__c, 'a blank radio answer clears it');
        System.assertEquals(null, [SELECT Value__c FROM AA_Answer__c WHERE Id = :days].Value__c,
            'the LWC saves an unticked list as blank, and that clears it');
        System.assertEquals(null, AA_RecordPageService.normaliseAnswer(a.Id, 'residence-country', null), 'null passes untouched');
        System.assertEquals('', AA_RecordPageService.normaliseAnswer(a.Id, 'care-needs-cause', '  '), 'whitespace is blank, not a malformed list');
    }

    // Whitespace alone ('   ', a tab, a newline) came back from normaliseAnswer
    // as the value to store, on every id. validateSave never stores it (free
    // text of only whitespace is an empty answer there), so it is a blank
    // answer here too, whatever rules the id has: an option, a format, a date
    // part, an entry over the cap.
    @isTest static void whitespace_alone_is_a_blank_answer() {
        for (String fid : new List<String>{
                'middle-name', 'residence-country', 'day-difficulties', 'care-needs-cause',
                'national-insurance', 'birth-date-day', 'health-conditions__21' }) {
            // The last three are no-break spaces and U+FEFF: String.isBlank
            // misses them and the org stores them as sent (review 2026-10-08).
            for (String blank : new List<String>{ '   ', '\t', '\n', ' \t\r\n ', ' ', '   ', '﻿' }) {
                System.assertEquals('', AA_RecordPageService.normaliseAnswer(fid, blank),
                    fid + ' takes ' + JSON.serialize(blank) + ' as a blank answer');
            }
        }
    }

    // A whitespace save clears the answer exactly as '' does. Two applications
    // with the same signed answers: one is cleared with '', the other with
    // spaces (a text id), a tab (a radio) and a newline (a tick-box list).
    // Both end the same: each row kept with no value, the declaration voided,
    // the mirrored middle name cleared and progress recomputed. (The org
    // already saved whitespace alone as null; saveField now sends '' itself.)
    @isTest static void whitespace_alone_clears_like_a_blank_value() {
        AA_Application__c viaBlank = makeApp('New');
        AA_Application__c viaSpace = makeApp('New');
        Set<Id> appIds = new Set<Id>{ viaBlank.Id, viaSpace.Id };
        List<List<String>> cases = new List<List<String>>{
            new List<String>{ 'middle-name',       'Anne',               '   ' },
            new List<String>{ 'residence-country', 'wales',              '\t' },
            new List<String>{ 'day-difficulties',  '["daytime-moving"]', '\n' }
        };
        Map<String, String> signed = new Map<String, String>{
            'decl' => '["agree"]', 'declname' => 'Margaret Smith',
            'decldate_day' => '8', 'decldate_month' => '10', 'decldate_year' => '2026'
        };
        List<AA_Answer__c> rows = new List<AA_Answer__c>();
        Set<String> caseIds = new Set<String>();
        for (Id appId : appIds) {
            for (List<String> c : cases) {
                rows.add(new AA_Answer__c(Application__c = appId, Field_Id__c = c[0], Value__c = c[1], Source__c = 'human'));
                caseIds.add(c[0]);
            }
            for (String fid : signed.keySet()) {
                rows.add(new AA_Answer__c(Application__c = appId, Field_Id__c = fid, Value__c = signed.get(fid), Source__c = 'human'));
            }
        }
        insert rows;
        for (AA_Application__c app : [SELECT Declaration_Complete__c, Middle_Name__c FROM AA_Application__c WHERE Id IN :appIds]) {
            System.assertEquals(true, app.Declaration_Complete__c, 'precondition: signed');
            System.assertEquals('Anne', app.Middle_Name__c, 'precondition: the middle name is mirrored to the application');
        }

        Test.startTest();
        Map<String, Id> savedTo = new Map<String, Id>();
        for (List<String> c : cases) {
            savedTo.put(viaBlank.Id + '|' + c[0], AA_RecordPageService.saveField(viaBlank.Id, c[0], '', 'human'));
            savedTo.put(viaSpace.Id + '|' + c[0], AA_RecordPageService.saveField(viaSpace.Id, c[0], c[2], 'human'));
        }
        Test.stopTest();

        Map<String, AA_Answer__c> stored = new Map<String, AA_Answer__c>();
        for (AA_Answer__c r : [SELECT Id, Application__c, Field_Id__c, Value__c FROM AA_Answer__c
                                WHERE Application__c IN :appIds AND Field_Id__c IN :caseIds]) {
            System.assert(!stored.containsKey(r.Application__c + '|' + r.Field_Id__c), 'one row per answer: ' + r.Field_Id__c);
            stored.put(r.Application__c + '|' + r.Field_Id__c, r);
        }
        for (List<String> c : cases) {
            for (Id appId : appIds) {
                AA_Answer__c r = stored.get(appId + '|' + c[0]);
                String how = appId == viaBlank.Id ? '\'\'' : JSON.serialize(c[2]);
                System.assertEquals(r.Id, savedTo.get(appId + '|' + c[0]), c[0] + ': ' + how + ' clears the same row, not a new one');
                System.assertEquals(null, r.Value__c, c[0] + ': ' + how + ' leaves no value');
            }
        }
        Map<Id, AA_Application__c> apps = new Map<Id, AA_Application__c>([
            SELECT Id, Declaration_Complete__c, Middle_Name__c, Notes__c, Progress_Filled__c, Progress_Total__c
              FROM AA_Application__c WHERE Id IN :appIds
        ]);
        AA_Application__c blankApp = apps.get(viaBlank.Id);
        AA_Application__c spaceApp = apps.get(viaSpace.Id);
        System.assertEquals(false, spaceApp.Declaration_Complete__c, 'a whitespace clear after signing voids the declaration');
        System.assertEquals(false, blankApp.Declaration_Complete__c, 'as a blank clear does');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c IN :appIds AND Field_Id__c IN :signed.keySet()],
            'the declaration rows are deleted on both');
        for (AA_Application__c app : apps.values()) {
            System.assert(app.Notes__c != null && app.Notes__c.contains('Declaration cleared') && app.Notes__c.contains('middle-name'),
                'ops can see why the declaration is pending again: ' + app.Notes__c);
            System.assertEquals(null, app.Middle_Name__c, 'the mirrored middle name is cleared, not set to whitespace');
        }
        System.assertEquals(blankApp.Progress_Filled__c, spaceApp.Progress_Filled__c, 'progress is recomputed as for a blank clear');
        System.assertEquals(blankApp.Progress_Total__c, spaceApp.Progress_Total__c);
    }

    // The org nulls spaces, tabs and newlines on its own but stores a no-break
    // space as sent, so only normaliseAnswer keeps it from reading as answered.
    @isTest static void a_no_break_space_alone_clears_the_answer() {
        AA_Application__c a = makeApp('New');
        AA_Answer__c row = new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'middle-name', Value__c = 'Anne', Source__c = 'human');
        insert row;

        Test.startTest();
        Id saved = AA_RecordPageService.saveField(a.Id, 'middle-name', ' ', 'human');
        Test.stopTest();

        System.assertEquals(row.Id, saved, 'the same row is cleared');
        System.assertEquals(null, [SELECT Value__c FROM AA_Answer__c WHERE Id = :row.Id].Value__c,
            'a no-break space alone leaves no value');
        System.assertEquals(null, [SELECT Middle_Name__c FROM AA_Application__c WHERE Id = :a.Id].Middle_Name__c,
            'the mirrored middle name is cleared');
    }

    @isTest static void care_needs_cause_takes_the_clients_own_conditions() {
        AA_Application__c a = makeApp('New');
        AA_RecordPageService.saveField(a.Id, 'health-conditions__1', 'Arthritis', 'human');
        AA_RecordPageService.saveField(a.Id, 'health-conditions-manual__2', 'Heart failure', 'human');
        AA_RecordPageService.saveField(a.Id, 'health-conditions-rows', '["Arthritis","Heart failure","Stroke"]', 'human');

        Test.startTest();
        Id cause = AA_RecordPageService.saveField(a.Id, 'care-needs-cause', '["arthritis", " heart   FAILURE ", "stroke"]', 'human');
        String unknown  = rejection(a.Id, 'care-needs-cause', '["Arthritis","Gout"]');
        String combined = rejection(a.Id, 'care-needs-cause', '["none-of-these","Arthritis"]');
        String empty    = rejection(a.Id, 'care-needs-cause', '[]');
        String scalar   = rejection(a.Id, 'care-needs-cause', 'Arthritis');
        Test.stopTest();

        System.assertEquals('["Arthritis","Heart failure","Stroke"]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :cause].Value__c,
            'names match ignoring case and spacing, and are stored as the client saved them');
        System.assert(unknown != null && unknown.contains('"Gout"') && !unknown.contains('"Arthritis"')
            && unknown.contains('Choose from: Arthritis, Heart failure, Stroke, or none-of-these on its own.'),
            'only the client\'s own conditions are offered, and only the stranger is named: ' + unknown);
        System.assert(combined != null && combined.startsWith('The answer to "' + labelOf('care-needs-cause')
            + '" cannot combine none-of-these with a condition'), combined);
        System.assert(empty != null && empty.startsWith('"' + labelOf('care-needs-cause') + '" needs at least one answer'), empty);
        System.assert(scalar != null && scalar.contains('as a list of the ticked options'), scalar);
    }

    @isTest static void care_needs_cause_with_no_condition_on_file_takes_any_name() {
        AA_Application__c a = makeApp('New');
        // A broken rows snapshot names no condition and must not break the save.
        AA_RecordPageService.saveField(a.Id, 'health-conditions-rows', '["Stroke"', 'human');
        Id cause = AA_RecordPageService.saveField(a.Id, 'care-needs-cause', '["Angina"]', 'human');
        System.assertEquals('["Angina"]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :cause].Value__c,
            'with no condition on file yet, a real answer is never refused (DWP checks it at fill time)');
        AA_RecordPageService.saveField(a.Id, 'care-needs-cause', '["NONE-OF-THESE"]', 'human');
        System.assertEquals('["none-of-these"]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :cause].Value__c);
        System.assertEquals('["Any condition"]', AA_RecordPageService.normaliseAnswer('care-needs-cause', '["Any condition"]'),
            'without an application there is nothing to hold the name to');
    }

    // Edge cases where validateSave and the record page must agree: an empty
    // tick-box list is accepted (the LWC saves blank instead), a "__<n>"
    // suffix on any option id is held to that id, and a blank or nested entry
    // never passes as a care-needs-cause condition.
    @isTest static void option_edge_cases_match_validate_save() {
        AA_Application__c a = makeApp('New');
        AA_RecordPageService.saveField(a.Id, 'health-conditions__1', 'Arthritis', 'human');

        Test.startTest();
        Id days = AA_RecordPageService.saveField(a.Id, 'day-difficulties', '[ ]', 'human');
        String suffixed = rejection(a.Id, 'residence-country__1', 'mars');
        String blank    = rejection(a.Id, 'care-needs-cause', '["Arthritis", " "]');
        String nested   = rejection(a.Id, 'care-needs-cause', '[["Arthritis"]]');
        Test.stopTest();

        System.assertEquals('[]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :days].Value__c, 'an empty list passes, as in validateSave');
        System.assert(suffixed != null && suffixed.contains('is not an option for "' + labelOf('residence-country') + '".'), suffixed);
        System.assert(blank != null && blank.contains('"(blank)"') && !blank.contains('"Arthritis"'), blank);
        System.assert(nested != null && nested.contains('"(blank)"'), nested);
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id
                                 AND Field_Id__c IN ('residence-country__1', 'care-needs-cause')],
            'nothing refused is stored');
    }

    // Everything aaApplicationData writes still saves: the declaration (decl
    // '["agree"]', declname, the decldate_* underscore parts handleToday
    // writes), the generic date editor's hyphen parts, the address lookup
    // picker ('1' = the first lookup result), loop entries, free text and ids
    // outside the catalogue.
    @isTest static void what_the_record_page_writes_still_saves() {
        AA_Application__c a = makeApp('New');
        Map<String, String> asSent = new Map<String, String>{
            'birth-date-day'                  => '15',
            'birth-date-month'                => '3',
            'birth-date-year'                 => '1940',
            'decldate_day'                    => '8',
            'declname'                        => 'Margaret Smith',
            'home-address-select'             => '1',
            'representative-address-select'   => '2 TURNBERRY, ANYTOWN',
            'health-conditions-start-date__2' => '2018',
            'treatment-surgery-information'   => 'Hip replacement in 2019',
            'health-conditions-rows'          => '["Arthritis"]',
            'not-in-the-catalogue'            => 'anything'
        };
        for (String fid : asSent.keySet()) {
            System.assertEquals(asSent.get(fid), AA_RecordPageService.normaliseAnswer(a.Id, fid, asSent.get(fid)),
                fid + ' is stored as sent, as before');
        }

        Test.startTest();
        AA_RecordPageService.saveField(a.Id, 'decl', '["agree"]', 'human');
        AA_RecordPageService.saveField(a.Id, 'declname', 'Margaret Smith', 'human');
        AA_RecordPageService.saveField(a.Id, 'decldate_day', '8', 'human');
        AA_RecordPageService.saveField(a.Id, 'decldate_month', '10', 'human');
        AA_RecordPageService.saveField(a.Id, 'decldate_year', '2026', 'human');
        Test.stopTest();

        System.assertEquals(true, [SELECT Declaration_Complete__c FROM AA_Application__c WHERE Id = :a.Id].Declaration_Complete__c,
            'the declaration still signs through saveField');
        System.assertEquals('["agree"]', [SELECT Value__c FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'decl'].Value__c);
        System.assertNotEquals(null, rejection(a.Id, 'decl', '["something-else"]'), 'decl is held to its one option, agree');
    }

    // The rules follow the catalogue's types: yesno and select are single
    // choices too, a select of postcode lookup results (*-address-select)
    // stays free text as in mary-validator, a radio without usable options is
    // free text (the LWC edits it as text), a tick-box field without options
    // takes any list, and the first definition of an id wins. Date parts are
    // the parts of a catalogue date only, and a field without a label is
    // named by its id.
    @isTest static void option_rules_follow_the_catalogue_types() {
        AA_RecordPageService.FIELD_RULE_CACHE = AA_RecordPageService.fieldRulesFrom(pagesOf(
            '{"PAGES":[{"key":"p1","part":"P","fields":['
            + '{"id":"q-yesno","type":"yesno"},'
            + '{"id":"q-select","type":"select","options":[["red","Red"],["blue","Blue"]]},'
            + '{"id":"q-bare-codes","type":"radio","options":["x","y"]},'
            + '{"id":"home-address-select","type":"select","options":[["2 TURNBERRY, ANYTOWN","2 TURNBERRY, ANYTOWN"]]},'
            + '{"id":"q-radio-no-options","type":"radio","options":[[null,null],["",""]]},'
            + '{"id":"q-ticks","type":"checkboxes","options":[["a","A"],["b","B"]]},'
            + '{"id":"q-open-ticks","type":"checkboxes","options":[]},'
            + '{"id":"q-when","type":"date","label":"When was it?"}'
            + ']},{"key":"p2","part":"P","fields":['
            + '{"id":"q-ticks","type":"radio","options":[["z","Z"]]},'
            + '{"id":"q-free","type":"text"}'
            + ']}]}'));

        System.assertEquals('yes', AA_RecordPageService.normaliseAnswer('q-yesno', 'YES'));
        System.assertEquals('blue', AA_RecordPageService.normaliseAnswer('q-select', ' Blue '));
        System.assertEquals('y', AA_RecordPageService.normaliseAnswer('q-bare-codes', 'Y'));
        System.assertEquals('1', AA_RecordPageService.normaliseAnswer('home-address-select', '1'), 'the first lookup result');
        System.assertEquals('14 Other Road', AA_RecordPageService.normaliseAnswer('home-address-select', '14 Other Road'), 'or the address text');
        System.assertEquals('anything', AA_RecordPageService.normaliseAnswer('q-radio-no-options', 'anything'));
        System.assertEquals('["b","a"]', AA_RecordPageService.normaliseAnswer('q-ticks__3', '["B","a"]'), 'first definition wins, loop suffix resolved');
        System.assertEquals('["anything"]', AA_RecordPageService.normaliseAnswer('q-open-ticks', '["anything"]'));
        System.assertEquals('free', AA_RecordPageService.normaliseAnswer('q-free', 'free'));
        System.assertEquals('07', AA_RecordPageService.normaliseAnswer('q-when-day', '07'), 'a part of a catalogue date');
        System.assertEquals('2026', AA_RecordPageService.normaliseAnswer('q-when_year', '2026'), 'the underscore parts too (decldate_*)');
        System.assertEquals('99', AA_RecordPageService.normaliseAnswer('q-free-day', '99'), 'a text field has no date parts');
        System.assertEquals('The month of "When was it?" must be a number from 1 to 12, not "13".',
            rejectionOf('q-when-month', '13'));
        System.assertEquals('"green" is not an option for "q-select". Choose one of: red, blue.', rejectionOf('q-select', 'green'),
            'a field without a label is named by its id');
        for (List<String> fv : new List<List<String>>{
            new List<String>{ 'q-yesno', 'maybe' },
            new List<String>{ 'q-select', 'green' },
            new List<String>{ 'q-ticks', '["z"]' },
            new List<String>{ 'q-ticks', '[null]' },
            new List<String>{ 'q-open-ticks', 'anything' }
        }) {
            System.assertNotEquals(null, rejectionOf(fv[0], fv[1]), fv[0] + '=' + fv[1] + ' must be refused');
        }
        System.assert(AA_RecordPageService.fieldRulesFrom(new List<Object>()).isEmpty(), 'AA_FlowEngine\'s empty fallback holds nothing');
        System.assert(AA_RecordPageService.fieldRulesFrom(null).isEmpty());
    }

    /** The message normaliseAnswer (no application) refused a value with, or null when it passed. */
    private static String rejectionOf(String fieldId, String value) {
        try {
            AA_RecordPageService.normaliseAnswer(fieldId, value);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    // ── entry numbers (validateSave MAX_LOOP_ENTRY, audit 2026-10-02 F30d) ──
    //
    // DWP's repeating blocks take up to 20 entries, and validateSave refuses
    // any other "__<n>". The record page offers entries 1 to 20 only, so a
    // direct caller could store an entry the fill can never type.

    @isTest static void entry_numbers_run_from_1_to_20() {
        AA_Application__c a = makeApp('New');
        // An entry 21 saved before the cap existed (Mary could, F30d).
        AA_Answer__c stray = new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'health-conditions__21', Value__c = 'Gout', Source__c = 'mary');
        insert stray;
        Map<String, String> refused = new Map<String, String>{
            'health-conditions__05'             => 'Angina',
            'health-conditions__abc'            => 'Angina',
            'health-conditions__'               => 'Angina',
            'health-conditions__100'            => 'Angina',
            'aids-adaptations-difficulty-2__21' => 'No'
        };

        Test.startTest();
        Id twentieth = AA_RecordPageService.saveField(a.Id, 'health-conditions__20', 'Asthma', 'human');
        String over  = rejection(a.Id, 'health-conditions__21', 'Angina');
        String zero  = rejection(a.Id, 'health-conditions__0', 'Angina');
        Map<String, String> others = new Map<String, String>();
        for (String fid : refused.keySet()) others.put(fid, rejection(a.Id, fid, refused.get(fid)));
        String storedBeforeClear = [SELECT Value__c FROM AA_Answer__c WHERE Id = :stray.Id].Value__c;
        Id cleared   = AA_RecordPageService.saveField(a.Id, 'health-conditions__21', '', 'human');
        Test.stopTest();

        String question = labelOf('health-conditions');
        System.assertEquals('Asthma', [SELECT Value__c FROM AA_Answer__c WHERE Id = :twentieth].Value__c, 'entry 20 is the last one DWP takes, and it saves');
        System.assertEquals('"' + question + '" takes up to 20 entries on the DWP form, so entry 21 cannot be saved. '
            + 'Keep the 20 that matter most.', over);
        System.assertEquals('Entries of "' + question + '" are numbered 1 to 20, so entry "0" cannot be saved.', zero);
        for (String fid : refused.keySet()) System.assertNotEquals(null, others.get(fid), fid + ' must be refused');
        Set<String> refusedIds = new Set<String>(refused.keySet());
        refusedIds.add('health-conditions__0');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c IN :refusedIds],
            'nothing refused is stored');
        System.assertEquals('Gout', storedBeforeClear, 'a refused save leaves the stored entry as it was');
        System.assertEquals(stray.Id, cleared, 'a blank still clears an entry saved before the cap, so the operator can remove it');
        System.assertEquals(null, [SELECT Value__c FROM AA_Answer__c WHERE Id = :stray.Id].Value__c);
    }

    // ── date parts (validateSave date_part ranges, audit 2026-10-02 F38) ──
    //
    // The parts the record page writes: "<stem>-day" / "-month" / "-year"
    // from the generic date editor, "decldate_day" / "_month" / "_year" from
    // the declaration date's editor and its "Today" button. A day of 32 or a
    // year of 19 was stored as sent.

    @isTest static void date_parts_are_range_checked_like_validate_save() {
        AA_Application__c a = makeApp('New');
        Integer thisYear = Date.today().year();
        List<List<String>> refused = new List<List<String>>{
            new List<String>{ 'birth-date-day', '0' },
            new List<String>{ 'birth-date-day', '3rd' },
            new List<String>{ 'birth-date-month', '0' },
            new List<String>{ 'birth-date-year', '48' },
            new List<String>{ 'birth-date-year', '01948' },
            new List<String>{ 'birth-date-year', '1899' },
            new List<String>{ 'difficulties-start-date-day', '32' },
            new List<String>{ 'decldate_day', '32' },
            new List<String>{ 'decldate_month', '13' },
            new List<String>{ 'decldate_year', '26' }
        };

        Test.startTest();
        String day32       = rejection(a.Id, 'birth-date-day', '32');
        String month13     = rejection(a.Id, 'birth-date-month', '13');
        String futureBirth = rejection(a.Id, 'birth-date-year', String.valueOf(thisYear + 1));
        String year2100    = rejection(a.Id, 'hospital-admission-date-year', '2100');
        List<String> others = new List<String>();
        for (List<String> fv : refused) others.add(rejection(a.Id, fv[0], fv[1]));
        Id day      = AA_RecordPageService.saveField(a.Id, 'birth-date-day', ' 08 ', 'human');
        Id month    = AA_RecordPageService.saveField(a.Id, 'birth-date-month', '3', 'human');
        Id year     = AA_RecordPageService.saveField(a.Id, 'birth-date-year', '1948', 'human');
        Id hospital = AA_RecordPageService.saveField(a.Id, 'hospital-admission-date-year', String.valueOf(thisYear), 'human');
        Id declDay  = AA_RecordPageService.saveField(a.Id, 'decldate_day', '08', 'human');
        // bed-day is a tick-box question of its own, not the day of a date.
        Id bedDay   = AA_RecordPageService.saveField(a.Id, 'bed-day', '["getting-into-bed"]', 'human');
        Id cleared  = AA_RecordPageService.saveField(a.Id, 'birth-date-month', '', 'human');
        Test.stopTest();

        String question = labelOf('birth-date');
        System.assertEquals('The day of "' + question + '" must be a number from 1 to 31, not "32".', day32);
        System.assertEquals('The month of "' + question + '" must be a number from 1 to 12, not "13".', month13);
        System.assertEquals('The year of "' + question + '" must be 4 digits from 1900 to ' + thisYear + ', not "' + (thisYear + 1) + '".',
            futureBirth, 'a date of birth is never in the future');
        for (Integer i = 0; i < refused.size(); i++) {
            System.assertNotEquals(null, others[i], refused[i][0] + '=' + refused[i][1] + ' must be refused');
            System.assert(!others[i].contains('—'), 'operator messages carry no em dash: ' + others[i]);
        }
        System.assertEquals('The year of "' + labelOf('hospital-admission-date') + '" must be 4 digits from 1900 to 2099, not "2100".',
            year2100, 'other dates run to 2099, as in validateSave');
        System.assertEquals('08', [SELECT Value__c FROM AA_Answer__c WHERE Id = :day].Value__c, 'a leading zero passes, and the part is trimmed');
        System.assertEquals('1948', [SELECT Value__c FROM AA_Answer__c WHERE Id = :year].Value__c);
        System.assertEquals(String.valueOf(thisYear), [SELECT Value__c FROM AA_Answer__c WHERE Id = :hospital].Value__c);
        System.assertEquals('08', [SELECT Value__c FROM AA_Answer__c WHERE Id = :declDay].Value__c, 'the declaration date part saves');
        System.assertEquals('["getting-into-bed"]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :bedDay].Value__c);
        System.assertEquals(month, cleared, 'clearing a part updates its row');
        System.assertEquals(null, [SELECT Value__c FROM AA_Answer__c WHERE Id = :month].Value__c, 'and a blank part clears it');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id
                                 AND Field_Id__c IN ('difficulties-start-date-day', 'decldate_month', 'decldate_year')],
            'nothing refused is stored');
    }

    // ── length limits (validateSave: DWP's own limit, then the column) ──
    //
    // An answer over DWP's limit saved and halted the live fill on that page
    // (audit 2026-10-02 F172), and one over 4000 characters reached the
    // insert and showed the operator a raw DmlException (E3, F176).

    @isTest static void answers_are_held_to_dwp_limits_and_the_column() {
        AA_Application__c a = makeApp('New');

        Test.startTest();
        String overDwp  = rejection(a.Id, 'treatment-surgery-information', 'x'.repeat(201));
        String overCare = rejection(a.Id, 'care-home-hospital-overnight-information', 'y'.repeat(501));
        Id atDwp        = AA_RecordPageService.saveField(a.Id, 'treatment-surgery-information', ' ' + 'x'.repeat(200) + '\n', 'human');
        Id atCare       = AA_RecordPageService.saveField(a.Id, 'care-home-hospital-overnight-information', 'y'.repeat(500), 'human');
        String overCol  = rejection(a.Id, 'place-of-work__1', 'z'.repeat(4001));
        String unknown  = rejection(a.Id, 'not-in-the-catalogue', 'z'.repeat(4001));
        Id atCol        = AA_RecordPageService.saveField(a.Id, 'place-of-work__1', 'z'.repeat(4000), 'human');
        Test.stopTest();

        System.assertEquals('The DWP form takes up to 200 characters for "' + labelOf('treatment-surgery-information')
            + '". This answer has 201 characters. Shorten it and save again.', overDwp);
        System.assert(overCare != null && overCare.contains('takes up to 500 characters') && overCare.contains('has 501 characters'), overCare);
        System.assertEquals(200, [SELECT Value__c FROM AA_Answer__c WHERE Id = :atDwp].Value__c.trim().length(),
            'the limit is counted without the surrounding spaces, as validateSave counts it');
        System.assertEquals(500, [SELECT Value__c FROM AA_Answer__c WHERE Id = :atCare].Value__c.length());
        System.assertEquals('Salesforce saves up to 4000 characters per answer. This answer to "' + labelOf('place-of-work')
            + '" has 4001 characters. Shorten it and save again.', overCol);
        System.assert(unknown != null && unknown.contains('This answer to "not-in-the-catalogue" has 4001 characters.'),
            'the column holds every answer, and an id outside the catalogue is named by its id: ' + unknown);
        System.assertEquals(4000, [SELECT Value__c FROM AA_Answer__c WHERE Id = :atCol].Value__c.length(), '4000 characters fit the column');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'not-in-the-catalogue'],
            'nothing refused is stored');
        for (String msg : new List<String>{ overDwp, overCare, overCol, unknown }) {
            System.assert(!msg.contains('—'), 'operator messages carry no em dash: ' + msg);
        }
    }

    // The same rules hold inside a repeating entry ("<part>__<n>", as the
    // date editor writes it for an entry), at the edges validateSave takes,
    // and for the unpadded parts the declaration's "Today" button writes.
    // A question that only ends in "-day" stays a question of its own.
    @isTest static void entry_parts_and_range_edges_match_validate_save() {
        String hospital = labelOf('hospital-admission-date');
        System.assertEquals('05', AA_RecordPageService.normaliseAnswer('hospital-admission-date-day__2', '05'));
        System.assertEquals('12', AA_RecordPageService.normaliseAnswer('hospital-admission-date-month__20', '12'));
        System.assertEquals('The day of "' + hospital + '" must be a number from 1 to 31, not "32".',
            rejectionOf('hospital-admission-date-day__2', '32'), 'a part inside an entry is range-checked too');
        System.assert(rejectionOf('hospital-admission-date-day__21', '5').contains('entry 21 cannot be saved'),
            'and its entry number is capped');
        System.assertEquals('1948', AA_RecordPageService.normaliseAnswer('birth-date-year', ' 1948 '));
        System.assertEquals('1900', AA_RecordPageService.normaliseAnswer('birth-date-year', '1900'));
        System.assertEquals('2099', AA_RecordPageService.normaliseAnswer('hospital-admission-date-year', '2099'));
        System.assertEquals('8', AA_RecordPageService.normaliseAnswer('decldate_day', '8'));
        System.assertEquals('10', AA_RecordPageService.normaliseAnswer('decldate_month', '10'));
        String thisYear = String.valueOf(Date.today().year());
        System.assertEquals(thisYear, AA_RecordPageService.normaliseAnswer('decldate_year', thisYear));
        System.assertEquals('yes', AA_RecordPageService.normaliseAnswer('return-bed-day', 'Yes'), 'a radio that ends in -day');
        System.assert(rejectionOf('treatment-surgery-information__2', 'x'.repeat(201)).contains('takes up to 200 characters'),
            'DWP\'s limit holds inside an entry');
    }

    // ── one parse of aaFlowConfig per save ───────────────────────────
    //
    // The answer rules read the catalogue through AA_FlowEngine.flowPages(),
    // the parse the AA_AnswerTrigger recompute uses, so a save parses the
    // ~200 KB resource once. The rules used to parse it a second time.

    @isTest static void a_save_parses_the_flow_catalogue_once() {
        AA_Application__c a = makeApp('New');

        Test.startTest();
        // Cold caches, as at the start of an operator's save.
        AA_FlowEngine.FLOW_CACHE = null;
        AA_FlowEngine.flowLoads = 0;
        AA_RecordPageService.FIELD_RULE_CACHE = null;
        AA_RecordPageService.saveField(a.Id, 'residence-country', 'wales', 'human');
        Integer perSave = AA_FlowEngine.flowLoads;
        // The rules alone, from cold: they load the catalogue through AA_FlowEngine.
        AA_FlowEngine.FLOW_CACHE = null;
        AA_FlowEngine.flowLoads = 0;
        AA_RecordPageService.FIELD_RULE_CACHE = null;
        String normalised = AA_RecordPageService.normaliseAnswer(a.Id, 'residence-country', 'Wales');
        Integer perRules = AA_FlowEngine.flowLoads;
        Test.stopTest();

        System.assertEquals(1, perSave, 'the answer rules and the answer trigger recompute share one parse of aaFlowConfig');
        System.assertEquals('wales', normalised);
        System.assertEquals(1, perRules, 'the answer rules read AA_FlowEngine\'s parse, not one of their own');
        System.assert(AA_FlowEngine.flowPages() === AA_FlowEngine.flowPages(), 'flowPages hands out the cached list, not a copy');
        System.assertEquals(1, AA_FlowEngine.flowLoads, 'and the transaction never parses it again');
    }

    // ── loop answers (audit 2026-10-02 F34/F49/F168) ─────────────────

    @isTest static void bare_loop_edit_is_refused_once_numbered_entries_exist() {
        AA_Application__c a = makeApp('New');
        AA_RecordPageService.saveField(a.Id, 'health-conditions__1', 'Arthritis', 'human');
        AA_RecordPageService.saveField(a.Id, 'health-conditions__1', 'Rheumatoid arthritis', 'human');

        for (String bareId : new List<String>{ 'health-conditions', 'health-conditions-start-date-year' }) {
            String msg = null;
            try { AA_RecordPageService.saveField(a.Id, bareId, 'x', 'human'); }
            catch (AuraHandledException e) { msg = e.getMessage(); }
            System.assertNotEquals(null, msg, bareId + ' would be ignored by the fill, so it must be refused');
            System.assert(msg.contains('numbered entry'), msg);
        }
        System.assertEquals('Rheumatoid arthritis',
            [SELECT Value__c FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'health-conditions__1'].Value__c,
            'numbered entries stay editable');

        // A different loop group is unaffected, and so is an app with no entries yet.
        AA_RecordPageService.saveField(a.Id, 'aids-adaptations-2', 'Walking frame', 'human');
        AA_Application__c fresh = makeApp('New');
        AA_RecordPageService.saveField(fresh.Id, 'health-conditions', 'Angina', 'human');
        System.assertEquals(1, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :fresh.Id AND Field_Id__c = 'health-conditions']);
    }

    // ── duplicates (audit 2026-10-02 F39) ────────────────────────────

    @isTest static void duplicates_newest_row_is_shown_and_updated() {
        AA_Application__c a = makeApp('New');
        // Answer_Key__c now makes new duplicates impossible; these two stand
        // for a legacy pair written before the key existed (blank keys).
        AA_ProgressCalculator.skipAnswerKeyForTest = true;
        AA_Answer__c older = new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'middle-name', Value__c = 'old', Source__c = 'human');
        insert older;
        AA_Answer__c newer = new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'middle-name', Value__c = 'new', Source__c = 'human');
        insert newer;
        AA_ProgressCalculator.skipAnswerKeyForTest = false;

        // The LWC keys by Field_Id__c and keeps the LAST row it sees.
        Map<String, AA_Answer__c> shown = new Map<String, AA_Answer__c>();
        for (AA_Answer__c r : AA_RecordPageService.getAnswers(a.Id)) shown.put(r.Field_Id__c, r);
        System.assertEquals(newer.Id, shown.get('middle-name').Id, 'the newest duplicate is the one the form shows');

        Id saved = AA_RecordPageService.saveField(a.Id, 'middle-name', 'edited', 'human');
        System.assertEquals(newer.Id, saved, 'the edit lands on the row readers treat as current');
        System.assertEquals('old', [SELECT Value__c FROM AA_Answer__c WHERE Id = :older.Id].Value__c);
    }

    @isTest static void saveField_defaults_source_to_human() {
        AA_Application__c a = makeApp('New');
        Id id = AA_RecordPageService.saveField(a.Id, 'national-insurance', 'AB123456C', '');
        System.assertEquals('human', [SELECT Source__c FROM AA_Answer__c WHERE Id = :id].Source__c, 'a blank source defaults to human');
        System.assertEquals('AB123456C', [SELECT Value__c FROM AA_Answer__c WHERE Id = :id].Value__c);
    }

    @isTest static void getAnswers_is_scoped_to_the_record_and_ordered_by_field_id() {
        AA_Application__c a = makeApp('New');
        AA_Application__c other = makeApp('New');
        insert new List<AA_Answer__c>{
            new AA_Answer__c(Application__c = a.Id,     Field_Id__c = 'zz-last',   Value__c = 'z', Source__c = 'human'),
            new AA_Answer__c(Application__c = a.Id,     Field_Id__c = 'aa-first',  Value__c = 'a', Source__c = 'human'),
            new AA_Answer__c(Application__c = other.Id, Field_Id__c = 'other-app', Value__c = 'o', Source__c = 'human')
        };

        List<AA_Answer__c> rows = AA_RecordPageService.getAnswers(a.Id);

        System.assertEquals(7, rows.size(), '5 seeded defaults + 2 inserted, nothing from another application');
        System.assertEquals('aa-first', rows[0].Field_Id__c, 'ordered by Field_Id__c ascending');
        System.assertEquals('zz-last',  rows[rows.size() - 1].Field_Id__c);
        for (AA_Answer__c r : rows) System.assertNotEquals('other-app', r.Field_Id__c, 'another application\'s answer leaked');
    }

    // ── getCallHistory ───────────────────────────────────────────────

    @isTest static void getCallHistory_newest_first_and_scoped_to_the_record() {
        AA_Application__c a = makeApp('New');
        AA_Application__c other = makeApp('New');
        Datetime older = Datetime.now().addHours(-3);
        Datetime newer = Datetime.now().addHours(-1);
        insert new List<AA_Call_Log__c>{
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = older, Status__c = 'completed', Direction__c = 'inbound', Source__c = 'Mary'),
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = newer, Status__c = 'no_answer', Direction__c = 'outbound', Source__c = 'Human', Rep_Name__c = 'Sean'),
            new AA_Call_Log__c(Application__c = other.Id, Started_At__c = newer, Status__c = 'completed', Direction__c = 'inbound', Source__c = 'Mary')
        };

        List<AA_Call_Log__c> rows = AA_RecordPageService.getCallHistory(a.Id);

        System.assertEquals(2, rows.size(), 'only this application\'s calls');
        System.assertEquals(newer, rows[0].Started_At__c, 'the newest call comes first');
        System.assertEquals('no_answer', rows[0].Status__c);
        System.assertEquals('outbound', rows[0].Direction__c);
        System.assertEquals(older, rows[1].Started_At__c);
        System.assertEquals('Sean', rows[0].Rep_Name__c, 'the rep is returned for the card');
        System.assertEquals(2, AA_RecordPageService.getCallHistoryCount(a.Id));
    }

    // 2026-10-29 audit: a placeholder that closed without a call is not shown
    // (nor counted); one still ringing is.
    @isTest static void getCallHistory_hides_closed_placeholders() {
        AA_Application__c a = makeApp('New');
        Datetime t = Datetime.now().addHours(-2);
        insert new List<AA_Call_Log__c>{
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t, Status__c = 'completed', Direction__c = 'outbound', Source__c = 'Mary'),
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t.addMinutes(30), Status__c = 'no_answer', Direction__c = 'inbound_known',
                Source__c = 'Mary', Personalization_Only__c = true),
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t.addMinutes(60), Status__c = 'in_progress', Direction__c = 'inbound_known',
                Source__c = 'Mary', Personalization_Only__c = true)
        };
        List<AA_Call_Log__c> rows = AA_RecordPageService.getCallHistory(a.Id);
        System.assertEquals(2, rows.size(), 'the closed placeholder is hidden');
        System.assertEquals('in_progress', rows[0].Status__c);
        System.assertEquals('completed', rows[1].Status__c);
        System.assertEquals(2, AA_RecordPageService.getCallHistoryCount(a.Id), 'count uses the same filter');
    }

    // ── changeStage + getStageHistory ────────────────────────────────

    @isTest static void changeStage_logs_each_real_transition_once_and_skips_noops() {
        AA_Application__c a = makeApp('New');

        Test.startTest();
        AA_RecordPageService.changeStage(a.Id, 'Awaiting First Call', 'first move');
        AA_RecordPageService.changeStage(a.Id, 'Awaiting First Call', 'same stage again'); // no-op
        AA_RecordPageService.changeStage(a.Id, 'Call In Progress', null);                  // blank note → default
        Test.stopTest();

        List<AA_Stage_Log__c> hist = AA_RecordPageService.getStageHistory(a.Id);
        System.assertEquals(2, hist.size(), 'two real transitions → two log rows; the no-op must log nothing');
        System.assert(hist[0].Changed_At__c >= hist[1].Changed_At__c, 'newest transition first');
        Map<String, AA_Stage_Log__c> byTo = new Map<String, AA_Stage_Log__c>();
        for (AA_Stage_Log__c l : hist) byTo.put(l.To_Stage__c, l);
        System.assertEquals('New', byTo.get('Awaiting First Call').From_Stage__c);
        System.assertEquals('first move', byTo.get('Awaiting First Call').Note__c, 'the note must travel to the trigger-written log');
        System.assertEquals(UserInfo.getName(), byTo.get('Awaiting First Call').Changed_By__r.Name, 'Changed_By__r.Name is selected for the timeline');
        System.assertEquals('Awaiting First Call', byTo.get('Call In Progress').From_Stage__c);
        System.assertEquals('Changed via record page', byTo.get('Call In Progress').Note__c, 'a blank note falls back to the record-page default');

        AA_Application__c after = [SELECT Stage__c, Stage_Changed_At__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('Call In Progress', after.Stage__c);
        System.assertNotEquals(null, after.Stage_Changed_At__c, 'Stage_Changed_At__c must be stamped');
    }

    @isTest static void changeStage_rejects_blank_stage_and_unknown_record() {
        AA_Application__c a = makeApp('New');
        Boolean blankThrew = false;
        try { AA_RecordPageService.changeStage(a.Id, ' ', 'n'); } catch (AuraHandledException e) { blankThrew = true; }
        System.assert(blankThrew, 'a blank target stage must be rejected');
        System.assertEquals('New', [SELECT Stage__c FROM AA_Application__c WHERE Id = :a.Id].Stage__c, 'a blank change leaves the stage untouched');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Stage_Log__c WHERE Application__c = :a.Id], 'nothing logged for a rejected change');

        AA_Application__c gone = makeApp('New');
        delete gone;
        Boolean missingThrew = false;
        try { AA_RecordPageService.changeStage(gone.Id, 'Awaiting First Call', 'n'); } catch (AuraHandledException e) { missingThrew = true; }
        System.assert(missingThrew, 'an unknown application must be rejected');
    }

    // ── getStages (path bar) ─────────────────────────────────────────

    @isTest static void getStages_has_one_ordered_metadata_row_per_stage_picklist_value() {
        Set<String> picklist = new Set<String>();
        for (Schema.PicklistEntry e : Schema.SObjectType.AA_Application__c.fields.Stage__c.getPicklistValues()) picklist.add(e.getValue());

        List<AA_Stage__mdt> stages = AA_RecordPageService.getStages();

        System.assertEquals(picklist.size(), stages.size(), 'one AA_Stage__mdt per Stage__c value — the path bar renders from the metadata');
        Set<String> labels = new Set<String>();
        Decimal prev = null;
        for (AA_Stage__mdt s : stages) {
            labels.add(s.MasterLabel);
            System.assert(prev == null || s.Order__c >= prev, 'stages must come back in Order__c ascending');
            prev = s.Order__c;
        }
        System.assertEquals(picklist, labels, 'every picklist value needs a matching AA_Stage__mdt MasterLabel');
        System.assertEquals('New', stages[0].MasterLabel, 'New is the first stage');
    }

    // ── getFlowConfig ────────────────────────────────────────────────

    @isTest static void getFlowConfig_returns_the_flow_json_with_pages() {
        String raw = AA_RecordPageService.getFlowConfig();
        Map<String, Object> cfg = (Map<String, Object>) JSON.deserializeUntyped(raw);
        System.assert(cfg.containsKey('PAGES'), 'aaFlowConfig must carry a PAGES array');
        List<Object> pages = (List<Object>) cfg.get('PAGES');
        System.assert(!pages.isEmpty(), 'the deployed aaFlowConfig must not be the empty fallback — the ApplicationData LWC would render nothing');
    }

    // ── getFiles / deleteFile ────────────────────────────────────────

    @isTest static void getFiles_lists_linked_documents_and_deleteFile_removes_them() {
        AA_Application__c a = makeApp('New');
        ContentVersion cv = new ContentVersion(
            Title = 'Test Doc', PathOnClient = 'Test Doc.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'), FirstPublishLocationId = a.Id
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        List<Map<String, Object>> files = AA_RecordPageService.getFiles(a.Id);
        System.assertEquals(1, files.size(), 'the linked document is listed');
        System.assertEquals(cv.ContentDocumentId, (Id) files[0].get('id'));
        System.assertEquals('Test Doc', (String) files[0].get('title'));
        System.assertEquals('PDF', (String) files[0].get('fileType'));
        System.assertEquals(cv.Id, (Id) files[0].get('versionId'), 'versionId is the latest published version');
        System.assertEquals(UserInfo.getUserId(), (Id) files[0].get('ownerId'));
        System.assertEquals(UserInfo.getName(), (String) files[0].get('ownerName'));
        System.assertNotEquals(null, files[0].get('size'));

        Boolean nullThrew = false;
        try { AA_RecordPageService.deleteFile(null); } catch (AuraHandledException e) { nullThrew = true; }
        System.assert(nullThrew, 'a null file id must be rejected');
        System.assertEquals(1, AA_RecordPageService.getFiles(a.Id).size(), 'a rejected delete leaves the file');

        AA_RecordPageService.deleteFile(cv.ContentDocumentId);
        System.assertEquals(0, AA_RecordPageService.getFiles(a.Id).size(), 'the file must be gone after deleteFile');

        Boolean goneThrew = false;
        try { AA_RecordPageService.deleteFile(cv.ContentDocumentId); } catch (AuraHandledException e) { goneThrew = true; }
        System.assert(goneThrew, 'deleting an already-deleted document must surface as AuraHandledException, not a raw DmlException');
    }

    // ── saveNotes + the clients-list descriptor ──────────────────────

    @isTest static void saveNotes_updates_notes_and_the_clients_list_descriptor_truncates() {
        AA_Application__c a = makeApp('New');

        AA_RecordPageService.saveNotes(a.Id, 'Short note');
        System.assertEquals('Short note', AA_RecordPageService.getApplication(a.Id).Notes__c, 'saveNotes must persist Notes__c');
        System.assertEquals('Short note', descriptorOf(a.Id), 'a note of 80 chars or fewer is the descriptor verbatim');

        String exactly80 = 'x'.repeat(80);
        AA_RecordPageService.saveNotes(a.Id, exactly80);
        System.assertEquals(exactly80, descriptorOf(a.Id), 'an 80-char note is not truncated');

        AA_RecordPageService.saveNotes(a.Id, 'y'.repeat(100));
        String d = descriptorOf(a.Id);
        System.assertEquals(80, d.length(), 'a long note is cut to 80 chars');
        System.assertEquals('y'.repeat(77) + '...', d, 'truncation keeps 77 chars plus an ellipsis');

        AA_RecordPageService.saveNotes(a.Id, '   ');
        System.assertEquals(null, descriptorOf(a.Id), 'a whitespace-only note yields no descriptor');
    }

    private static String descriptorOf(Id appId) {
        for (Map<String, Object> row : AA_RecordPageService.getClientsList('all', 50, 0)) {
            if ((Id) row.get('id') == appId) return (String) row.get('descriptor');
        }
        System.assert(false, 'application missing from the clients list');
        return null;
    }
}