/**
 * PC1_AllTests — one class exercises every PC1 Apex class + trigger to satisfy
 * the 75% code-coverage rule Salesforce enforces on production deploys.
 *
 * Written intentionally chunky rather than one-test-per-method — sandbox
 * deploys want fast test runs, and each REST endpoint here is a tight ~30
 * line class so a single happy-path call gives us near-100% coverage.
 */
@isTest
private class PC1_AllTests {

    private static PC1_Application__c makeApp() {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Test',
            Last_Name__c  = 'User' + Math.mod(Math.abs(Crypto.getRandomInteger()), 10000),
            Phone__c      = '+441234567890',
            DOB__c        = Date.newInstance(1955, 3, 20),
            Postcode__c   = 'SW1A 1AA',
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
        Datetime fri = PC1_BusinessDayHelper.buildUkDatetime(Date.newInstance(2026, 8, 7), 18);
        Datetime next = PC1_BusinessDayHelper.nextBusinessDayAtUkTime(fri, 8);
        Date d = PC1_BusinessDayHelper.dateInUkTimezone(next);
        System.assert(!PC1_BusinessDayHelper.isWeekend(d), 'Should land on a weekday');
    }

    @isTest static void maryProgress_ignoresDeclFields() {
        PC1_Application__c a = makeApp();
        // The defaults seeded on insert (PC1_DefaultAnswersHelper) count. Read
        // from the org instead of a fixed number: the list grew from 4 to 8 with
        // the form changes of October 2026 and the old "6" broke every deploy
        // that ran this class (2026-10-29).
        Integer seeded = [SELECT COUNT() FROM PC1_Answer__c WHERE Application__c = :a.Id];
        insert new List<PC1_Answer__c>{
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q_first_name', Value__c = 'X', Source__c='mary'),
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q_last_name',  Value__c = 'Y', Source__c='mary'),
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'declname',     Value__c = 'Z', Source__c='human')
        };
        PC1_MaryProgressCalculator.updateMaryProgress(a.Id);
        PC1_Application__c after = [SELECT Mary_Progress_Filled__c FROM PC1_Application__c WHERE Id = :a.Id];
        // Seeded defaults + the 2 mary answers here. Declname does NOT count.
        // CRIT-3 (2026-07-29): pre-DefaultAnswersHelper this was 2.
        System.assert(seeded > 0, 'defaults are seeded on insert');
        System.assertEquals(seeded + 2, after.Mary_Progress_Filled__c, 'decl field must NOT count; defaults DO count');
    }

    @isTest static void stageMachine_blocksIllegal() {
        PC1_Application__c a = makeApp();
        Boolean threw = false;
        try {
            update new PC1_Application__c(Id = a.Id, Stage__c = 'Submitted');   // New → Submitted illegal
        } catch (DmlException e) { threw = true; }
        System.assert(threw, 'Trigger must block New→Submitted');
    }

    @isTest static void stageMachine_allowsLegal() {
        PC1_Application__c a = makeApp();
        update new PC1_Application__c(Id = a.Id, Stage__c = 'Awaiting First Call');
        List<PC1_Stage_Log__c> logs = [SELECT To_Stage__c FROM PC1_Stage_Log__c WHERE Application__c = :a.Id];
        System.assertEquals(1, logs.size(), 'Stage change must log');
    }

    // ----------------------------- REST endpoints

    @isTest static void saveField_creates_then_updates() {
        PC1_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","field_id":"q_first_name","value":"Aoife"}');
        PC1_SaveField.doPost();
        System.assertEquals(200, RestContext.response.statusCode == null ? 200 : RestContext.response.statusCode);
        // Filter out the 4 default-seeded rows (Source__c='default') so this
        // test asserts what SaveField itself wrote.
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Answer__c WHERE Application__c = :a.Id AND Source__c != 'default']);
        // Second call same field → update in place
        reqWith('{"application_id":"' + a.Id + '","field_id":"q_first_name","value":"Aoife-updated"}');
        PC1_SaveField.doPost();
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Answer__c WHERE Application__c = :a.Id AND Source__c != 'default']);
    }

    @isTest static void saveMulti_batches() {
        PC1_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","answers":[{"field_id":"q_ni","value":"AB123456C"},{"field_id":"q_bank","value":"AIB"}]}');
        PC1_SaveMultiField.doPost();
        // Ignore default-seeded rows (4 always present on new app).
        System.assertEquals(2, [SELECT COUNT() FROM PC1_Answer__c WHERE Application__c = :a.Id AND Source__c != 'default']);
    }

    @isTest static void checkAnswers_returnsSummary() {
        PC1_Application__c a = makeApp();
        insert new PC1_Answer__c(Application__c=a.Id, Field_Id__c='q_first_name', Value__c='X', Source__c='mary');
        reqWith('{"application_id":"' + a.Id + '"}');
        PC1_CheckCurrentAnswers.doPost();
        String body = RestContext.response.responseBody.toString();
        System.assert(body.contains('missing_fields'), 'missing_fields must be in response');
    }

    // rescheduleCall_setsNextCall — removed. PC1_RescheduleCall Apex REST
    // was deprecated 2026-07-29; Mary now hits /webhooks/mary/reschedule-call
    // on Heroku (src/webhooks/mary.js#rescheduleCall) which creates a
    // PC1_Call_Schedule__c row instead of writing Next_Call_At__c directly.

    @isTest static void flagForHuman_createsHandoff() {
        PC1_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","escalation_type":"confused","reason":"can\'t hear"}');
        PC1_FlagForHuman.doPost();
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Handoff__c WHERE Application__c=:a.Id]);
        PC1_Application__c after = [SELECT Stage__c FROM PC1_Application__c WHERE Id=:a.Id];
        System.assertEquals('Needs Human', after.Stage__c);
    }

    @isTest static void markComplete_movesStage() {
        PC1_Application__c a = makeApp();
        update new PC1_Application__c(Id=a.Id, Stage__c='Awaiting First Call');
        update new PC1_Application__c(Id=a.Id, Stage__c='Call In Progress');
        update new PC1_Application__c(Id=a.Id, Stage__c='Partial Data');
        reqWith('{"application_id":"' + a.Id + '","note":"done"}');
        PC1_MarkComplete.doPost();
        PC1_Application__c after = [SELECT Stage__c FROM PC1_Application__c WHERE Id=:a.Id];
        System.assertEquals('Data Complete', after.Stage__c);
    }

    @isTest static void identifyByPhone_hits() {
        PC1_Application__c a = makeApp();
        reqWith('{"phone":"' + a.Phone__c + '"}');
        PC1_IdentifyByCallerPhone.doPost();
        System.assert(RestContext.response.responseBody.toString().contains('matches'));
    }

    @isTest static void identifyByPhone_notFound() {
        reqWith('{"phone":"+9999"}');
        PC1_IdentifyByCallerPhone.doPost();
        System.assert(RestContext.response.responseBody.toString().contains('not_found'));
    }

    @isTest static void identifyByName_hits() {
        PC1_Application__c a = makeApp();
        reqWith('{"first_name":"' + a.First_Name__c + '","last_name":"' + a.Last_Name__c + '"}');
        PC1_IdentifyByName.doPost();
        System.assert(RestContext.response.responseBody.toString().contains('matches'));
    }

    @isTest static void verifyClient_verified() {
        PC1_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","dob":"1955-03-20","postcode":"SW1A 1AA"}');
        PC1_VerifyClient.doPost();
        System.assert(RestContext.response.responseBody.toString().contains('verified'));
    }

    @isTest static void verifyClient_mismatch() {
        PC1_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","dob":"2000-01-01","postcode":"XX1"}');
        PC1_VerifyClient.doPost();
        System.assert(RestContext.response.responseBody.toString().contains('mismatch'));
    }

    @isTest static void verifyClient_insufficient() {
        PC1_Application__c a = makeApp();
        reqWith('{"application_id":"' + a.Id + '","dob":"1955-03-20"}');
        PC1_VerifyClient.doPost();
        System.assert(RestContext.response.responseBody.toString().contains('insufficient'));
    }

    // ----------------------------- Val Agent auto-assignment
    //
    // Seed 3 agents (30/30/40) → insert 10 apps → distribution should be
    // 3/3/4. Also covers admin controller list/create/update/delete.

    @isTest static void valAgent_assignsByWeight() {
        insert new List<PC1_Val_Agent__c>{
            new PC1_Val_Agent__c(Name = 'AlphaVA', Weight__c = 30, Active__c = true),
            new PC1_Val_Agent__c(Name = 'BetaVA',  Weight__c = 30, Active__c = true),
            new PC1_Val_Agent__c(Name = 'GammaVA', Weight__c = 40, Active__c = true)
        };
        List<PC1_Application__c> rows = new List<PC1_Application__c>();
        for (Integer i = 0; i < 10; i++) {
            rows.add(new PC1_Application__c(
                First_Name__c = 'T' + i, Last_Name__c = 'U' + i,
                Phone__c = '+44712345600' + i, Stage__c = 'New'
            ));
        }
        insert rows;
        Map<String, Integer> counts = new Map<String, Integer>{
            'AlphaVA' => 0, 'BetaVA' => 0, 'GammaVA' => 0
        };
        for (PC1_Application__c r : [SELECT Val_Agent__c FROM PC1_Application__c WHERE Id IN :rows]) {
            if (counts.containsKey(r.Val_Agent__c)) counts.put(r.Val_Agent__c, counts.get(r.Val_Agent__c) + 1);
        }
        System.assertEquals(3, counts.get('AlphaVA'), 'Alpha should get 3/10 at 30% weight');
        System.assertEquals(3, counts.get('BetaVA'),  'Beta should get 3/10 at 30% weight');
        System.assertEquals(4, counts.get('GammaVA'), 'Gamma should get 4/10 at 40% weight');
    }

    @isTest static void valAgent_skipsWhenPresetOrNoAgents() {
        // No agents in pool → Val_Agent__c stays null
        PC1_Application__c a1 = makeApp();
        System.assertEquals(null, [SELECT Val_Agent__c FROM PC1_Application__c WHERE Id = :a1.Id].Val_Agent__c);

        // Preset value → helper must NOT overwrite
        insert new PC1_Val_Agent__c(Name = 'DeltaVA', Weight__c = 100, Active__c = true);
        PC1_Application__c a2 = new PC1_Application__c(
            First_Name__c='Pre', Last_Name__c='Set', Phone__c='+441234567891',
            Stage__c='New', Val_Agent__c='DeltaVA'
        );
        insert a2;
        System.assertEquals('DeltaVA', [SELECT Val_Agent__c FROM PC1_Application__c WHERE Id = :a2.Id].Val_Agent__c);
    }

    @isTest static void valAgentAdminController_crud() {
        // create
        Id id = PC1_ValAgentAdminController.createAgent('EpsilonVA', 25, true);
        System.assert(id != null);

        // list — new agent should appear
        List<PC1_ValAgentAdminController.AgentRow> rows = PC1_ValAgentAdminController.listAgents();
        Boolean found = false;
        for (PC1_ValAgentAdminController.AgentRow r : rows) if (r.name == 'EpsilonVA') { found = true; break; }
        System.assert(found, 'Newly created agent should appear in list');

        // rename + reweight + deactivate
        PC1_ValAgentAdminController.updateAgent(id, 'EpsilonRenamed', 15, false);
        PC1_Val_Agent__c after = [SELECT Name, Weight__c, Active__c FROM PC1_Val_Agent__c WHERE Id = :id];
        System.assertEquals('EpsilonRenamed', after.Name);
        System.assertEquals(15, after.Weight__c);
        System.assertEquals(false, after.Active__c);

        // delete
        PC1_ValAgentAdminController.deleteAgent(id);
        System.assertEquals(0, [SELECT COUNT() FROM PC1_Val_Agent__c WHERE Id = :id]);
    }

    @isTest static void valAgentAdminController_rejectsBadInput() {
        Boolean threw = false;
        try { PC1_ValAgentAdminController.createAgent('', 10, true); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Blank name should throw');

        threw = false;
        try { PC1_ValAgentAdminController.createAgent('ZetaVA', 0, true); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Zero weight should throw');
    }
}