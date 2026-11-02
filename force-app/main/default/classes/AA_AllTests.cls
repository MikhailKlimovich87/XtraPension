/**
 * AA_AllTests — one class exercises every AA Apex class + trigger to satisfy
 * the 75% code-coverage rule Salesforce enforces on production deploys.
 *
 * Written intentionally chunky rather than one-test-per-method — sandbox
 * deploys want fast test runs, and each REST endpoint here is a tight ~30
 * line class so a single happy-path call gives us near-100% coverage.
 */
@isTest
private class AA_AllTests {

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Test',
            Last_Name__c  = 'User' + Math.mod(Math.abs(Crypto.getRandomInteger()), 10000),
            Phone__c      = '+441234567890',
            DOB__c        = Date.newInstance(1955, 3, 20),
            Postcode__c   = 'SW1A 1AA',
            // An email on file makes the seeded email-submit "yes" (it is
            // "no" without one, F27); the counts below assume 4 defaults.
            Email__c      = 'test@example.com',
            Stage__c      = 'New'
        );
        insert a;
        return a;
    }

    private static RestRequest reqWith(String body) {
        RestRequest r = new RestRequest();
        r.requestBody = Blob.valueOf(body);
        r.httpMethod = 'POST';
        RestContext.request = r;
        RestContext.response = new RestResponse();
        return r;
    }

    // ----------------------------- Helpers

    @isTest static void businessDayHelper_skipsWeekend() {
        // Friday 6pm → Monday 08:00
        Datetime fri = AA_BusinessDayHelper.buildUkDatetime(Date.newInstance(2026, 8, 7), 18);
        Datetime next = AA_BusinessDayHelper.nextBusinessDayAtUkTime(fri, 8);
        Date d = AA_BusinessDayHelper.dateInUkTimezone(next);
        System.assert(!AA_BusinessDayHelper.isWeekend(d), 'Should land on a weekday');
    }

    @isTest static void progress_ignoresDeclFields() {
        // Was maryProgress_ignoresDeclFields. Mary_Progress_Filled__c/_Total__c
        // are retired (audit 2026-10-02 F44/F177), so the same rule is asserted
        // on the real counter: a declaration field never counts toward
        // Progress_Filled__c (AA_FlowEngine Q3).
        AA_Application__c a = makeApp();
        insert new List<AA_Answer__c>{
            new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'first-name', Value__c = 'X', Source__c='mary'),
            new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'last-name',  Value__c = 'Y', Source__c='mary')
        };
        Decimal before = [SELECT Progress_Filled__c FROM AA_Application__c WHERE Id = :a.Id].Progress_Filled__c;
        insert new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'declname', Value__c = 'Z', Source__c='human');
        Decimal after = [SELECT Progress_Filled__c FROM AA_Application__c WHERE Id = :a.Id].Progress_Filled__c;
        System.assertEquals(before, after, 'a declaration field must NOT count toward progress');
        // The retired calculator is a no-op kept only until its destructive delete.
        AA_MaryProgressCalculator.updateMaryProgress(a.Id);
        AA_MaryProgressCalculator.updateMaryProgressBulk(new Set<Id>{ a.Id });
    }

    @isTest static void stageMachine_blocksIllegal() {
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            // The stage state machine was removed 2026-07-30 (stages move
            // freely); what blocks this is the DWP_Reference_Required_When_Submitted
            // validation rule, since the record has no DWP reference.
            update new AA_Application__c(Id = a.Id, Stage__c = 'Submitted');
        } catch (DmlException e) { threw = true; }
        System.assert(threw, 'Submitted without a DWP reference must be rejected');
    }

    @isTest static void stageMachine_allowsLegal() {
        AA_Application__c a = makeApp();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Awaiting First Call');
        List<AA_Stage_Log__c> logs = [SELECT To_Stage__c FROM AA_Stage_Log__c WHERE Application__c = :a.Id];
        System.assertEquals(1, logs.size(), 'Stage change must log');
    }

    // ----------------------------- REST endpoints

    // Removed 2026-10-02 with the Apex REST twins they exercised (AA_SaveField,
    // AA_SaveMultiField, AA_MarkComplete, AA_IdentifyByCallerPhone,
    // AA_IdentifyByName, AA_VerifyClient): saveField_*, saveMulti_*,
    // markComplete_movesStage, identifyByPhone_*, identifyByName_hits and
    // verifyClient_*. Mary's live path is the Heroku webhooks
    // (src/webhooks/mary.js); the org dependency graph showed these classes
    // referenced only by this test class, and the owner approved deleting them.

    // audit 2026-10-02 F27 + wave 3: without an email on file, email-submit is
    // seeded "no" (yes walks the client into a required email page nobody can
    // answer). Wave 2 left it open instead, which stalled the form and record
    // page paths; this is now the same rule as Mary's seedPolicyDefaults
    // backstop (mary.js). Fails on the wave-2 helper (no email-submit row).
    @isTest static void defaults_seed_email_submit_no_without_an_email() {
        AA_Application__c noEmail = new AA_Application__c(
            First_Name__c = 'No', Last_Name__c = 'Email', Phone__c = '+441234567899', Stage__c = 'New'
        );
        insert noEmail;
        Map<String, String> seeded = new Map<String, String>();
        for (AA_Answer__c r : [SELECT Field_Id__c, Value__c FROM AA_Answer__c WHERE Application__c = :noEmail.Id AND Source__c = 'default']) {
            seeded.put(r.Field_Id__c, r.Value__c);
        }
        System.assertEquals(new Set<String>{ 'welsh-language-speak', 'welsh-language-write', 'alternative-formats', 'best-time-to-call', 'email-submit' },
            seeded.keySet(), 'all five policy defaults are seeded');
        System.assertEquals('no', seeded.get('email-submit'), 'no email on file -> no confirmation email');

        AA_Application__c withEmail = makeApp();
        System.assertEquals('yes', [SELECT Value__c FROM AA_Answer__c WHERE Application__c = :withEmail.Id
                                      AND Field_Id__c = 'email-submit' AND Source__c = 'default'].Value__c);
    }

    // AA_AnswersController (aaAnswersList) had 0% coverage (F157).
    @isTest static void answersController_lists_the_record_answers() {
        AA_Application__c a = makeApp();
        insert new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'first-name', Value__c = 'Aoife', Source__c = 'mary');
        System.assertEquals(0, AA_AnswersController.getAnswers(null).size(), 'a null id returns nothing');
        List<AA_Answer__c> rows = AA_AnswersController.getAnswers(a.Id);
        System.assertEquals(6, rows.size(), '5 defaults + 1 answer');
    }

    // checkAnswers_returnsSummary — removed 2026-09-09 together with
    // AA_CheckCurrentAnswers. That class was a self-declared POC mock whose
    // missing_fields list was PC1's means-test ids (q_partner, q_savings_amount,
    // bank fields…) — none exist in the AA form, so every call reported all 15
    // as missing. Nothing routed to it: Mary's check_current_answers tool points
    // at /webhooks/mary/check-current-answers on Heroku (src/webhooks/mary.js),
    // which walks the real flow. Deleted rather than ported (audit 2026-09-09).

    // rescheduleCall_setsNextCall — removed. AA_RescheduleCall Apex REST
    // was deprecated 2026-07-29; Mary now hits /webhooks/mary/reschedule-call
    // on Heroku (src/webhooks/mary.js#rescheduleCall) which creates a
    // AA_Call_Schedule__c row instead of writing Next_Call_At__c directly.

    @isTest static void flagForHuman_createsHandoff() {
        AA_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","escalation_type":"confused","reason":"can\'t hear"}');
        AA_FlagForHuman.doPost();
        System.assertEquals(1, [SELECT COUNT() FROM AA_Handoff__c WHERE Application__c=:a.Id]);
        AA_Application__c after = [SELECT Stage__c FROM AA_Application__c WHERE Id=:a.Id];
        System.assertEquals('Needs Human', after.Stage__c);
    }

    // ----------------------------- Val Agent auto-assignment
    //
    // Seed 3 agents (30/30/40) → insert 10 apps → distribution should be
    // 3/3/4. Also covers admin controller list/create/update/delete.

    @isTest static void valAgent_assignsByWeight() {
        insert new List<AA_Val_Agent__c>{
            new AA_Val_Agent__c(Name = 'AlphaVA', Weight__c = 30, Active__c = true),
            new AA_Val_Agent__c(Name = 'BetaVA',  Weight__c = 30, Active__c = true),
            new AA_Val_Agent__c(Name = 'GammaVA', Weight__c = 40, Active__c = true)
        };
        List<AA_Application__c> rows = new List<AA_Application__c>();
        for (Integer i = 0; i < 10; i++) {
            rows.add(new AA_Application__c(
                First_Name__c = 'T' + i, Last_Name__c = 'U' + i,
                Phone__c = '+44712345600' + i, Stage__c = 'New'
            ));
        }
        insert rows;
        Map<String, Integer> counts = new Map<String, Integer>{
            'AlphaVA' => 0, 'BetaVA' => 0, 'GammaVA' => 0
        };
        for (AA_Application__c r : [SELECT Val_Agent__c FROM AA_Application__c WHERE Id IN :rows]) {
            if (counts.containsKey(r.Val_Agent__c)) counts.put(r.Val_Agent__c, counts.get(r.Val_Agent__c) + 1);
        }
        System.assertEquals(3, counts.get('AlphaVA'), 'Alpha should get 3/10 at 30% weight');
        System.assertEquals(3, counts.get('BetaVA'),  'Beta should get 3/10 at 30% weight');
        System.assertEquals(4, counts.get('GammaVA'), 'Gamma should get 4/10 at 40% weight');
    }

    @isTest static void valAgent_skipsWhenPresetOrNoAgents() {
        // No agents in pool → Val_Agent__c stays null
        AA_Application__c a1 = makeApp();
        System.assertEquals(null, [SELECT Val_Agent__c FROM AA_Application__c WHERE Id = :a1.Id].Val_Agent__c);

        // Preset value → helper must NOT overwrite
        insert new AA_Val_Agent__c(Name = 'DeltaVA', Weight__c = 100, Active__c = true);
        AA_Application__c a2 = new AA_Application__c(
            First_Name__c='Pre', Last_Name__c='Set', Phone__c='+441234567891',
            Stage__c='New', Val_Agent__c='DeltaVA'
        );
        insert a2;
        System.assertEquals('DeltaVA', [SELECT Val_Agent__c FROM AA_Application__c WHERE Id = :a2.Id].Val_Agent__c);
    }

    @isTest static void valAgentAdminController_crud() {
        // create
        Id id = AA_ValAgentAdminController.createAgent('EpsilonVA', 25, true);
        System.assert(id != null);

        // list — new agent should appear
        List<AA_ValAgentAdminController.AgentRow> rows = AA_ValAgentAdminController.listAgents();
        Boolean found = false;
        for (AA_ValAgentAdminController.AgentRow r : rows) if (r.name == 'EpsilonVA') { found = true; break; }
        System.assert(found, 'Newly created agent should appear in list');

        // rename + reweight + deactivate
        AA_ValAgentAdminController.updateAgent(id, 'EpsilonRenamed', 15, false);
        AA_Val_Agent__c after = [SELECT Name, Weight__c, Active__c FROM AA_Val_Agent__c WHERE Id = :id];
        System.assertEquals('EpsilonRenamed', after.Name);
        System.assertEquals(15, after.Weight__c);
        System.assertEquals(false, after.Active__c);

        // delete
        AA_ValAgentAdminController.deleteAgent(id);
        System.assertEquals(0, [SELECT COUNT() FROM AA_Val_Agent__c WHERE Id = :id]);
    }

    @isTest static void valAgentAdminController_rejectsBadInput() {
        Boolean threw = false;
        try { AA_ValAgentAdminController.createAgent('', 10, true); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Blank name should throw');

        threw = false;
        try { AA_ValAgentAdminController.createAgent('ZetaVA', 0, true); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Zero weight should throw');
    }

    // ----------------------------- Application / Answer metadata
    // Ported from the sf-metadata cluster's check-only scratch test
    // (AA_SfMetadataScratchTest, audit 2026-10-02). Each fails on the old
    // metadata, so they need the sf-src objects deployed with or before them.

    private static AA_Application__c ruleApp(Datetime nextCall) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Rule', Last_Name__c = 'Check' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c = '+441234567890', Postcode__c = 'SW1A 1AA', Next_Call_At__c = nextCall);
        insert a;
        return a;
    }

    // F83/F37: a Next_Call_At that has PASSED since it was written must not
    // block unrelated edits (old rule: every update failed). Busy-waits ~2 s.
    @isTest static void nextCallAt_stalePastValueDoesNotBlockOtherEdits() {
        Datetime soon = Datetime.now().addSeconds(2);
        AA_Application__c a = ruleApp(soon);
        while (Datetime.now() <= soon) { }
        a.Notes__c = 'edited while Next_Call_At is in the past';
        update a;
        System.assertEquals('edited while Next_Call_At is in the past',
            [SELECT Notes__c FROM AA_Application__c WHERE Id = :a.Id].Notes__c);
    }

    // The rule still rejects WRITING a past value, on insert and on update.
    @isTest static void nextCallAt_writingAPastValueIsStillRejected() {
        AA_Application__c a = ruleApp(null);
        a.Next_Call_At__c = Datetime.now().addMinutes(-5);
        Boolean rejected = false;
        try { update a; } catch (DmlException e) { rejected = e.getMessage().contains('Next Call At must be in the future'); }
        System.assert(rejected, 'update to a past Next_Call_At must be rejected');
        rejected = false;
        try { ruleApp(Datetime.now().addMinutes(-5)); } catch (DmlException e) { rejected = e.getMessage().contains('Next Call At must be in the future'); }
        System.assert(rejected, 'insert with a past Next_Call_At must be rejected');
        a.Next_Call_At__c = null;
        update a; // clearing always passes
    }

    // Restricted picklist values that code now writes.
    @isTest static void newPicklistValuesAreAccepted() {
        AA_Application__c a = ruleApp(null);
        a.DD_Mandate_Status__c = 'suspended_by_payer';
        a.Fee_Payment_Status__c = 'customer_approval_denied';
        a.DD_Terms_Read_By_Intake_User__c = 'megan';
        update a;
        insert new AA_Service_Health__c(Service__c = 'Intake Auth', Status__c = 'ok');
        insert new AA_Fill_Run__c(Application__c = a.Id, Status__c = 'failed', Error_Code__c = 'missing_answer');
        insert new AA_Fill_Run__c(Application__c = a.Id, Status__c = 'failed', Error_Code__c = 'lost_race');
        insert new AA_Message_Send_Log__c(Application__c = a.Id, Status__c = 'Skipped-Do-Not-Contact');
        for (String s : new List<String>{ 'pending_customer_approval', 'consumed', 'blocked' }) {
            a.DD_Mandate_Status__c = s;
            update a;
        }
        System.assertEquals(2, [SELECT COUNT() FROM AA_Fill_Run__c WHERE Application__c = :a.Id]);
    }

    // F39: Answer_Key__c is unique; rows with different field ids coexist.
    @isTest static void answerKey_isUniqueAndDistinctFieldsCoexist() {
        AA_Application__c a = ruleApp(null);
        insert new List<AA_Answer__c>{
            new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'zz-scratch-a', Value__c = 'x'),
            new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'zz-scratch-b', Value__c = 'y')
        };
        String key = String.valueOf(a.Id) + '|zz-scratch-c';
        insert new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'zz-scratch-c', Value__c = '1', Answer_Key__c = key);
        Boolean dup = false;
        try {
            insert new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'zz-scratch-c', Value__c = '2', Answer_Key__c = key);
        } catch (DmlException e) { dup = e.getDmlType(0) == StatusCode.DUPLICATE_VALUE; }
        System.assert(dup, 'a second row with the same Answer_Key__c must be rejected');
    }

    // F39: AA_AnswerTrigger stamps Answer_Key__c itself, so a writer that never
    // sets it (form.js, Mary, the seeder today) still cannot create a second
    // row for the same (Application, Field_Id). Fails without the trigger
    // stamp: blank keys never collide and the duplicate is inserted.
    @isTest static void answerKey_isStampedByTheTriggerAndBlocksDuplicates() {
        AA_Application__c a = ruleApp(null);
        AA_Answer__c first = new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'first-name', Value__c = 'Margaret', Source__c = 'form');
        insert first;
        System.assertEquals(String.valueOf(a.Id) + '|first-name',
            [SELECT Answer_Key__c FROM AA_Answer__c WHERE Id = :first.Id].Answer_Key__c,
            'the trigger stamps Application Id | Field_Id');

        Boolean dup = false;
        try {
            insert new AA_Answer__c(Application__c = a.Id, Field_Id__c = 'first-name', Value__c = 'Maggie', Source__c = 'mary');
        } catch (DmlException e) { dup = e.getDmlType(0) == StatusCode.DUPLICATE_VALUE; }
        System.assert(dup, 'a second row for the same field on the same application must be rejected');

        // A writer-supplied key is never trusted, and a renamed field moves its key.
        first.Field_Id__c = 'last-name';
        first.Answer_Key__c = 'something-else';
        update first;
        System.assertEquals(String.valueOf(a.Id) + '|last-name',
            [SELECT Answer_Key__c FROM AA_Answer__c WHERE Id = :first.Id].Answer_Key__c);
    }
}