/**
 * AA_FlowEngineTest — asserts what AA_FlowEngine WRITES, not just that it ran
 * (audit 2026-10-02 F45: no test checked Declaration_Complete__c or the
 * Progress_* outputs, so the '[]' declaration bug below went unnoticed).
 *
 * Declaration_Complete__c is the only gate AA_HerokuBridge checks before a DWP
 * fill. F151/F175: any non-empty decl value counted as signed, so an unticked
 * box stored as '[]' still flipped the flag; and with duplicate rows a stale
 * signed row could outvote a newer cleared one (F39). The first three tests
 * fail on the pre-fix engine.
 */
@isTest
private class AA_FlowEngineTest {

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Flow', Last_Name__c = 'Engine' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c = '+441234567890', Email__c = 'flow@example.com', Stage__c = 'New'
        );
        insert a;
        return a;
    }

    private static AA_Answer__c ans(Id appId, String fieldId, String value) {
        return new AA_Answer__c(Application__c = appId, Field_Id__c = fieldId, Value__c = value, Source__c = 'human');
    }

    private static List<AA_Answer__c> signedDeclaration(Id appId, String declValue) {
        return new List<AA_Answer__c>{
            ans(appId, 'decl', declValue),
            ans(appId, 'declname', 'Margaret Wilson'),
            ans(appId, 'decldate_day', '2'),
            ans(appId, 'decldate_month', '10'),
            ans(appId, 'decldate_year', '2026')
        };
    }

    private static Boolean declComplete(Id appId) {
        return [SELECT Declaration_Complete__c FROM AA_Application__c WHERE Id = :appId].Declaration_Complete__c;
    }

    @isTest static void declaration_needs_the_agree_box_ticked() {
        AA_Application__c a = makeApp();
        List<AA_Answer__c> rows = signedDeclaration(a.Id, '[]');

        Test.startTest();
        insert rows;
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id),
            'an unticked declaration box saved as [] must NOT count as signed');
    }

    @isTest static void unticking_the_box_clears_the_flag() {
        AA_Application__c a = makeApp();
        List<AA_Answer__c> rows = signedDeclaration(a.Id, '["agree"]');
        insert rows;
        System.assertEquals(true, declComplete(a.Id), 'agree + name + full date = signed');

        Test.startTest();
        rows[0].Value__c = '[]';
        update rows[0];
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id), 'unticking the box must clear Declaration_Complete__c');
    }

    // ── Fail closed on an unsign the Application update could not write ──
    // (audit 2026-10-02, wave-2 review of F37/F83). recomputeAndUpdate is a
    // partial update so a failing Application validation rule no longer loses
    // the answer; but an UNSIGN that does not land must not leave
    // Declaration_Complete__c = true behind an unticked box. No validation
    // rule can be relied on to block an update in a test org, so the
    // failAppUpdateForTest seam stands in for one.

    @isTest static void unsign_is_refused_when_the_application_update_fails() {
        AA_Application__c a = makeApp();
        List<AA_Answer__c> rows = signedDeclaration(a.Id, '["agree"]');
        insert rows;
        System.assertEquals(true, declComplete(a.Id), 'precondition: signed');

        AA_FlowEngine.failAppUpdateForTest.add(a.Id);
        Boolean refused = false;
        Test.startTest();
        try {
            rows[0].Value__c = '[]';
            update rows[0];
        } catch (DmlException e) {
            refused = e.getMessage().contains('declaration');
        }
        Test.stopTest();

        System.assert(refused, 'the unsign must fail loudly, not be dropped with only a log line');
        System.assertEquals('["agree"]', [SELECT Value__c FROM AA_Answer__c WHERE Id = :rows[0].Id].Value__c,
            'the answer row rolls back with it, so row and flag stay consistent');
        System.assertEquals(true, declComplete(a.Id), 'flag and answer agree (both still signed)');
    }

    @isTest static void a_failed_update_that_is_not_an_unsign_keeps_the_answer() {
        AA_Application__c signedApp = makeApp();
        insert signedDeclaration(signedApp.Id, '["agree"]');
        AA_Application__c freshApp = makeApp();
        AA_FlowEngine.failAppUpdateForTest.add(signedApp.Id);
        AA_FlowEngine.failAppUpdateForTest.add(freshApp.Id);

        Test.startTest();
        // An unrelated answer on a signed app: the flag does not move, so the
        // failed counter update is only logged. Source 'default' (a policy
        // pre-fill): an editor's answer would clear the signature instead
        // (owner decision 2026-10-02, see the declaration-void tests below).
        AA_Answer__c unrelated = ans(signedApp.Id, 'first-name', 'Margaret');
        unrelated.Source__c = 'default';
        insert unrelated;
        // Signing while the update fails: the flag stays false, already closed.
        insert signedDeclaration(freshApp.Id, '["agree"]');
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :signedApp.Id AND Field_Id__c = 'first-name']);
        System.assertEquals(true, declComplete(signedApp.Id));
        System.assertEquals(5, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :freshApp.Id AND Field_Id__c LIKE 'decl%']);
        System.assertEquals(false, declComplete(freshApp.Id), 'a sign that could not be written stays unsigned');
    }

    @isTest static void only_the_blocked_application_rows_fail_in_a_bulk_save() {
        AA_Application__c blocked = makeApp();
        AA_Application__c ok = makeApp();
        List<AA_Answer__c> b = signedDeclaration(blocked.Id, '["agree"]');
        List<AA_Answer__c> o = signedDeclaration(ok.Id, '["agree"]');
        insert b;
        insert o;
        AA_FlowEngine.failAppUpdateForTest.add(blocked.Id);

        b[0].Value__c = '[]';
        o[0].Value__c = '[]';
        Test.startTest();
        Database.SaveResult[] res = Database.update(new List<AA_Answer__c>{ b[0], o[0] }, false);
        Test.stopTest();

        System.assertEquals(false, res[0].isSuccess(), 'the blocked app unsign fails');
        System.assertEquals(true, res[1].isSuccess(), 'the other app is not dragged down with it');
        System.assertEquals(true, declComplete(blocked.Id));
        System.assertEquals(false, declComplete(ok.Id));
    }

    // Real validation-rule path, no seam. Next_Call_At_In_Future: with the
    // old formula (no ISCHANGED guard, still live in the org as of
    // 2026-10-02) a passed Next_Call_At__c blocks every Application update,
    // so the unsign must be refused; with the guarded formula the update goes
    // through and the flag must end false. Either way the flag never says
    // "signed" behind an unticked box. Busy-waits ~2 s.
    @isTest static void unsign_with_a_passed_next_call_never_leaves_the_flag_stale() {
        AA_Application__c a = makeApp();
        List<AA_Answer__c> rows = signedDeclaration(a.Id, '["agree"]');
        insert rows;
        Datetime soon = Datetime.now().addSeconds(2);
        update new AA_Application__c(Id = a.Id, Next_Call_At__c = soon);
        while (Datetime.now() <= soon) { }

        Boolean threw = false;
        try {
            rows[0].Value__c = '[]';
            update rows[0];
        } catch (DmlException e) {
            threw = true;
        }
        String stored = [SELECT Value__c FROM AA_Answer__c WHERE Id = :rows[0].Id].Value__c;
        if (threw) {
            System.assertEquals('["agree"]', stored, 'a refused unsign leaves the row signed');
            System.assertEquals(true, declComplete(a.Id));
        } else {
            System.assertEquals('[]', stored);
            System.assertEquals(false, declComplete(a.Id), 'a saved unsign must clear the flag');
        }
    }

    @isTest static void newest_duplicate_row_wins() {
        AA_Application__c a = makeApp();
        insert signedDeclaration(a.Id, '["agree"]');
        System.assertEquals(true, declComplete(a.Id), 'precondition: signed');

        Test.startTest();
        // A second, newer decl row (a duplicate from a save race) that is blank.
        // Answer_Key__c now blocks new duplicates, so this stands for a legacy
        // pair written before the key existed (the seam leaves its key blank;
        // the signed rows above got keys, and blank never collides).
        AA_ProgressCalculator.skipAnswerKeyForTest = true;
        insert ans(a.Id, 'decl', '');
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id),
            'the newest decl row is blank, so the declaration is not signed, whatever an older duplicate says');
    }

    @isTest static void incomplete_date_or_name_is_not_signed() {
        AA_Application__c a = makeApp();
        insert new List<AA_Answer__c>{
            ans(a.Id, 'decl', '["agree"]'),
            ans(a.Id, 'declname', '   '),
            ans(a.Id, 'decldate_day', '2'),
            ans(a.Id, 'decldate_month', '10')
        };
        System.assertEquals(false, declComplete(a.Id), 'a blank name and a missing year are not a signature');
    }

    @isTest static void isDeclarationSigned_unit() {
        System.assertEquals(false, AA_FlowEngine.isDeclarationSigned(null));
        Map<String, String> v = new Map<String, String>{
            'decl' => '["agree"]', 'declname' => 'A B',
            'decldate_day' => '1', 'decldate_month' => '1', 'decldate_year' => '2026'
        };
        System.assertEquals(true, AA_FlowEngine.isDeclarationSigned(v));
        v.put('decl', 'agree');
        System.assertEquals(false, AA_FlowEngine.isDeclarationSigned(v), 'only the JSON array the checkbox stores counts');
        v.put('decl', '["something-else"]');
        System.assertEquals(false, AA_FlowEngine.isDeclarationSigned(v));
    }

    @isTest static void progress_counters_are_written_and_path_is_served() {
        AA_Application__c a = makeApp();

        Test.startTest();
        insert ans(a.Id, 'first-name', 'Margaret');
        Test.stopTest();

        AA_Application__c after = [
            SELECT Progress_Filled__c, Progress_Total__c, Progress_Missing_Sections__c, Progress_Last_Updated__c
              FROM AA_Application__c WHERE Id = :a.Id
        ];
        System.assertNotEquals(null, after.Progress_Total__c, 'the answer trigger writes Progress_Total__c');
        System.assert(after.Progress_Filled__c <= after.Progress_Total__c, 'filled never exceeds total');
        System.assertNotEquals(null, after.Progress_Last_Updated__c);
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(after.Progress_Missing_Sections__c);
        System.assert(payload.containsKey('missing') && payload.containsKey('sections'), 'missing-sections JSON is well formed');

        Map<String, Object> path = AA_FlowEngine.getPathForRecord(a.Id);
        System.assertEquals(after.Progress_Total__c.intValue(), (Integer) path.get('total'), 'path tab and header agree on total');
        System.assertEquals(false, (Boolean) path.get('declarationComplete'));
        System.assertEquals(0, AA_FlowEngine.getPathForRecord(null).size(), 'a null record id returns an empty map');
    }

    // flowPages() hands AA_RecordPageService the catalogue compute() walks:
    // one query and parse of aaFlowConfig per transaction, and the cached
    // list itself, not a copy (a save used to parse the resource twice).
    @isTest static void flowPages_shares_the_one_parse_per_transaction() {
        AA_Application__c a = makeApp();
        AA_FlowEngine.FLOW_CACHE = null; // cold, as at the start of a transaction
        AA_FlowEngine.flowLoads = 0;

        List<Object> pages = AA_FlowEngine.flowPages();
        AA_FlowEngine.ProgressResult r = AA_FlowEngine.compute(a.Id);

        System.assert(!pages.isEmpty(), 'the deployed aaFlowConfig has pages');
        System.assert(pages === AA_FlowEngine.flowPages(), 'the cached list itself, not a copy');
        System.assert(r.total > 0, 'compute() walks the same catalogue');
        System.assertEquals(1, AA_FlowEngine.flowLoads, 'one load of aaFlowConfig for the whole transaction');
    }

    @isTest static void loop_entry_one_satisfies_the_bare_required_id() {
        AA_Application__c a = makeApp();
        insert ans(a.Id, 'health-conditions__1', 'Arthritis');
        AA_FlowEngine.ProgressResult r = AA_FlowEngine.compute(a.Id);
        // Only assertable when this persona reaches the conditions page.
        if (r.requiredFieldIds.contains('health-conditions')) {
            System.assert(r.filledFieldIds.contains('health-conditions'),
                'health-conditions__1 must count the bare health-conditions as filled (audit #40)');
        }
        System.assert(!r.missingFieldIds.contains('health-conditions'), 'never listed as missing when entry 1 exists');
    }

    // ── Declaration voids on change (owner decision, Fernando 2026-10-02) ──
    // An answer changed by the client (form), Mary or an operator (human)
    // after the declaration was signed clears the declaration, so the client
    // signs again before Fill on DWP. System writes, no-op saves and edits to
    // the declaration itself never clear it. Every test that expects a clear
    // fails without AA_ProgressCalculator.voidDeclarationOnChange (the flag
    // used to stay true, since the declaration rows were untouched).

    private static AA_Answer__c src(Id appId, String fieldId, String value, String source) {
        AA_Answer__c a = ans(appId, fieldId, value);
        a.Source__c = source;
        return a;
    }

    private static Integer declRowCount(Id appId) {
        return [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :appId
                 AND Field_Id__c IN ('decl','declname','decldate_day','decldate_month','decldate_year')];
    }

    /** App with one form answer, then a signed declaration. */
    private static AA_Answer__c signedAppWithAnswer(AA_Application__c a, String source) {
        AA_Answer__c first = src(a.Id, 'first-name', 'Margaret', source);
        insert first;
        insert signedDeclaration(a.Id, '["agree"]');
        System.assertEquals(true, declComplete(a.Id), 'precondition: signed');
        return first;
    }

    @isTest static void a_client_edit_after_signing_clears_the_declaration() {
        AA_Application__c a = makeApp();
        AA_Answer__c first = signedAppWithAnswer(a, 'form');

        Test.startTest();
        first.Value__c = 'Maggie';
        update first;
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id), 'the client must sign again');
        System.assertEquals(0, declRowCount(a.Id), 'the declaration rows are cleared, so the form shows it unsigned');
        System.assertEquals('Maggie', [SELECT Value__c FROM AA_Answer__c WHERE Id = :first.Id].Value__c, 'the edit itself is saved');
        String notes = [SELECT Notes__c FROM AA_Application__c WHERE Id = :a.Id].Notes__c;
        System.assert(notes != null && notes.contains('Declaration cleared') && notes.contains('first-name'),
            'ops can see why the declaration is pending again: ' + notes);
    }

    @isTest static void a_new_mary_answer_and_an_operator_edit_clear_it_too() {
        AA_Application__c byMary = makeApp();
        signedAppWithAnswer(byMary, 'form');
        AA_Application__c byOperator = makeApp();
        AA_Answer__c op = signedAppWithAnswer(byOperator, 'form');

        Test.startTest();
        insert src(byMary.Id, 'last-name', 'Wilson', 'mary');
        AA_RecordPageService.saveField(byOperator.Id, 'first-name', 'Peggy', 'human');
        Test.stopTest();

        System.assertEquals(false, declComplete(byMary.Id), 'Mary adding an answer after signing clears it');
        System.assertEquals(false, declComplete(byOperator.Id), 'an operator edit on the record page clears it');
        System.assertEquals('Peggy', [SELECT Value__c FROM AA_Answer__c WHERE Id = :op.Id].Value__c);
    }

    @isTest static void the_client_clearing_an_answer_clears_it() {
        AA_Application__c a = makeApp();
        AA_Answer__c first = signedAppWithAnswer(a, 'form');

        Test.startTest();
        delete first; // form.js clears an answer by deleting its row
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id));
        System.assertEquals(0, declRowCount(a.Id));
    }

    @isTest static void system_writes_do_not_clear_it() {
        AA_Application__c a = makeApp();
        AA_Answer__c seeded = signedAppWithAnswer(a, 'intake');

        Test.startTest();
        seeded.Value__c = 'Margaret Ann';
        update seeded; // still Source 'intake'
        // A policy default rewritten by the system (Mary's seedPolicyDefaults
        // backstop writes Source 'default').
        AA_Answer__c policy = [SELECT Id FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'welsh-language-speak'];
        policy.Value__c = 'welsh';
        policy.Source__c = 'default';
        update policy;
        insert src(a.Id, 'last-name', 'Wilson', 'intake');
        Test.stopTest();

        System.assertEquals(true, declComplete(a.Id), 'seeded, default and intake rows never clear a signature');
        System.assertEquals(5, declRowCount(a.Id));
    }

    @isTest static void a_no_op_save_does_not_clear_it() {
        AA_Application__c a = makeApp();
        AA_Answer__c first = signedAppWithAnswer(a, 'form');

        Test.startTest();
        first.Value__c = '  Margaret ';   // same value, whitespace aside
        first.Source__c = 'human';        // a different editor re-saving it
        update first;
        insert src(a.Id, 'middle-name', '', 'form'); // an empty insert is not an answer
        Test.stopTest();

        System.assertEquals(true, declComplete(a.Id), 'saving the same value is not a change');
        System.assertEquals(5, declRowCount(a.Id));
    }

    @isTest static void a_case_only_edit_is_a_change() {
        AA_Application__c a = makeApp();
        AA_Answer__c first = signedAppWithAnswer(a, 'form');

        Test.startTest();
        first.Value__c = 'MARGARET';
        update first;
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id), 'DWP would receive different text, so it is a change');
    }

    @isTest static void editing_the_declaration_itself_does_not_clear_it() {
        AA_Application__c a = makeApp();
        signedAppWithAnswer(a, 'form');
        AA_Answer__c name = [SELECT Id FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c = 'declname'];

        Test.startTest();
        name.Value__c = 'Margaret A Wilson';
        name.Source__c = 'form';
        update name;
        insert src(a.Id, 'health-conditions-rows', '["Arthritis"]', 'form'); // derived loop snapshot
        Test.stopTest();

        System.assertEquals(true, declComplete(a.Id), 'correcting the signature is not an answer change');
        System.assertEquals(5, declRowCount(a.Id));
    }

    @isTest static void an_edit_before_signing_leaves_partial_declaration_rows_alone() {
        AA_Application__c a = makeApp();
        insert new List<AA_Answer__c>{ ans(a.Id, 'decl', '["agree"]'), ans(a.Id, 'declname', 'Margaret Wilson') };
        System.assertEquals(false, declComplete(a.Id), 'precondition: not signed yet');

        Test.startTest();
        insert src(a.Id, 'first-name', 'Margaret', 'form');
        Test.stopTest();

        System.assertEquals(2, [SELECT COUNT() FROM AA_Answer__c WHERE Application__c = :a.Id AND Field_Id__c IN ('decl','declname')],
            'nothing was signed, so nothing is cleared');
    }

    @isTest static void tidying_a_legacy_duplicate_does_not_clear_it() {
        AA_Application__c a = makeApp();
        AA_ProgressCalculator.skipAnswerKeyForTest = true; // legacy pair, written before Answer_Key__c
        AA_Answer__c older = src(a.Id, 'first-name', 'Margaret', 'form');
        AA_Answer__c newer = src(a.Id, 'first-name', 'Margaret', 'form');
        insert older;
        insert newer;
        AA_ProgressCalculator.skipAnswerKeyForTest = false;
        insert signedDeclaration(a.Id, '["agree"]');
        System.assertEquals(true, declComplete(a.Id), 'precondition: signed');

        Test.startTest();
        delete older; // the twin still holds the same value
        Test.stopTest();

        System.assertEquals(true, declComplete(a.Id), 'the answer did not change, so the signature stands');
    }

    @isTest static void an_edit_is_refused_when_the_declaration_cannot_be_cleared() {
        AA_Application__c a = makeApp();
        AA_Answer__c first = signedAppWithAnswer(a, 'form');
        // The unsign write fails (stand-in for a validation rule), so the
        // declaration rows cannot be cleared either.
        AA_FlowEngine.failAppUpdateForTest.add(a.Id);

        Boolean refused = false;
        Test.startTest();
        try {
            first.Value__c = 'Maggie';
            update first;
        } catch (DmlException e) {
            refused = e.getMessage().contains('declaration');
        }
        Test.stopTest();

        System.assert(refused, 'the edit must not land under the old signature');
        System.assertEquals('Margaret', [SELECT Value__c FROM AA_Answer__c WHERE Id = :first.Id].Value__c);
        System.assertEquals(true, declComplete(a.Id));
        System.assertEquals(5, declRowCount(a.Id));
    }

    // Wave-4: the void had no stage scope, so a post-submission correction
    // deleted the only record of the signature DWP received. Fails without
    // AA_ProgressCalculator.FILED_STAGES.
    @isTest static void an_edit_after_the_claim_is_filed_keeps_the_declaration() {
        AA_Application__c awarded = makeApp();
        AA_Answer__c a1 = signedAppWithAnswer(awarded, 'form');
        AA_Application__c waiting = makeApp();
        AA_Answer__c a2 = signedAppWithAnswer(waiting, 'form');
        update new List<AA_Application__c>{
            new AA_Application__c(Id = awarded.Id, Stage__c = 'Awarded'),
            new AA_Application__c(Id = waiting.Id, Stage__c = 'Awaiting DWP Decision')
        };

        Test.startTest();
        AA_RecordPageService.saveField(awarded.Id, 'first-name', 'Peggy', 'human'); // operator correction
        insert src(waiting.Id, 'last-name', 'Wilson', 'mary');                       // Mary on an inbound call
        Test.stopTest();

        for (Id appId : new List<Id>{ awarded.Id, waiting.Id }) {
            System.assertEquals(true, declComplete(appId), 'the signature DWP received stays on record');
            System.assertEquals(5, declRowCount(appId));
            String notes = [SELECT Notes__c FROM AA_Application__c WHERE Id = :appId].Notes__c;
            System.assert(notes == null || !notes.contains('Declaration cleared'), 'no "sign again" note: ' + notes);
        }
        System.assertEquals('Peggy', [SELECT Value__c FROM AA_Answer__c WHERE Id = :a1.Id].Value__c, 'the edit itself is saved');
    }

    @isTest static void an_edit_before_submission_still_clears_it() {
        AA_Application__c a = makeApp();
        AA_Answer__c first = signedAppWithAnswer(a, 'form');
        update new AA_Application__c(Id = a.Id, Stage__c = 'Ready for Submit');

        Test.startTest();
        first.Value__c = 'Maggie';
        update first;
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id), 'nothing reached DWP yet, so the client signs again');
        System.assertEquals(0, declRowCount(a.Id));
    }

    // Integrator 2026-10-02: 'Awaiting Posted Pack Return' is PRE-submission
    // (the paper pack is with the client, nothing has reached DWP), so an
    // edit there still clears the declaration. It used to be in FILED_STAGES.
    @isTest static void an_edit_while_the_posted_pack_is_out_still_clears_it() {
        AA_Application__c a = makeApp();
        signedAppWithAnswer(a, 'form');
        update new AA_Application__c(Id = a.Id, Stage__c = 'Awaiting Posted Pack Return');

        Test.startTest();
        AA_RecordPageService.saveField(a.Id, 'first-name', 'Peggy', 'human');
        Test.stopTest();

        System.assertEquals(false, declComplete(a.Id), 'not filed yet, so the client signs again');
        System.assertEquals(0, declRowCount(a.Id));
        System.assert(!AA_ProgressCalculator.FILED_STAGES.contains('Awaiting Posted Pack Return'));
    }

    @isTest static void bulk_edit_clears_only_the_signed_application() {
        AA_Application__c signedApp = makeApp();
        AA_Answer__c s = signedAppWithAnswer(signedApp, 'form');
        AA_Application__c openApp = makeApp();
        AA_Answer__c o = src(openApp.Id, 'first-name', 'Arthur', 'form');
        insert o;

        s.Value__c = 'Maggie';
        o.Value__c = 'Art';
        Test.startTest();
        update new List<AA_Answer__c>{ s, o };
        Test.stopTest();

        System.assertEquals(false, declComplete(signedApp.Id));
        System.assertEquals(0, declRowCount(signedApp.Id));
        System.assertEquals('Art', [SELECT Value__c FROM AA_Answer__c WHERE Id = :o.Id].Value__c);
        System.assertEquals(null, [SELECT Notes__c FROM AA_Application__c WHERE Id = :openApp.Id].Notes__c,
            'an unsigned app gets no note');
    }

    @isTest static void missing_sections_json_always_parses_when_too_big() {
        // audit 2026-10-02 F47(a): the old cut-and-append produced invalid JSON.
        AA_FlowEngine.ProgressResult r = new AA_FlowEngine.ProgressResult();
        r.filled = 0;
        r.total = 400;
        r.missingFieldIds = new List<String>();
        r.labelById = new Map<String, String>();
        r.partByFieldId = new Map<String, String>();
        r.blockedReasonById = new Map<String, String>();
        r.missingParts = new List<String>{ 'Part 1' };
        for (Integer i = 0; i < 400; i++) {
            String id = 'field-' + i;
            r.missingFieldIds.add(id);
            r.labelById.put(id, 'A fairly long label with "quotes" for field number ' + i);
            r.partByFieldId.put(id, 'Part 1');
            r.blockedReasonById.put('blocked-' + i, 'Requires an answer to something ' + i);
        }
        AA_FlowEngine.missingJsonMax = 4000;

        String body = AA_FlowEngine.buildMissingSectionsJson(r);

        System.assert(body.length() <= 4000, 'stays under the cap: ' + body.length());
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        System.assertEquals(true, parsed.get('truncated'), 'the payload says it was shortened');
        System.assertEquals(400, (Integer) parsed.get('total'), 'the counts survive');
        System.assert(!((List<Object>) parsed.get('missing')).isEmpty(), 'some missing ids are kept');
    }
}