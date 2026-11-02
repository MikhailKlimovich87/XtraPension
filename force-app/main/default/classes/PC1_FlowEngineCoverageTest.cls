/**
 * PC1_FlowEngine on realistic answer sets (2026-10-02): the shares loop,
 * the partner gate, skip-if-answered pages, the "start = no" exit and the
 * record-page path wrapper. Existing tests only walked minimal answers, so
 * those branches were never executed (class sat at 72-74%).
 */
@IsTest
private class PC1_FlowEngineCoverageTest {

    private static Id appWith(Map<String, String> answers) {
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'Fl', Last_Name__c = 'Ow', Stage__c = 'Partial Data');
        insert a;
        List<PC1_Answer__c> rows = new List<PC1_Answer__c>();
        for (String k : answers.keySet()) {
            rows.add(new PC1_Answer__c(Application__c = a.Id, Field_Id__c = k, Value__c = answers.get(k), Source__c = 'human'));
        }
        insert rows;
        return a.Id;
    }

    @IsTest static void rich_path_with_partner_and_shares_loop() {
        Id appId = appWith(new Map<String, String>{
            'start' => 'yes', 'q0_country' => 'england', 'q14' => 'yeslivetogether',
            'q105' => '["shares","bank"]', 'addshares_1' => 'yes', 'addshares_2' => 'no',
            's1_shares_company' => 'Acme', 'q3' => 'Fl', 'q2' => 'Ow',
            'decl' => 'yes', 'declname' => 'Fl Ow', 'decldate_day' => '1', 'decldate_month' => '10', 'decldate_year' => '2026'
        });
        Test.startTest();
        Map<String, Object> path = PC1_FlowEngine.getPathForRecord(appId);
        Test.stopTest();
        List<String> required = (List<String>) path.get('requiredFieldIds');
        System.assert(required.size() > 10, 'a full path is computed: ' + required.size());
        System.assert(((List<String>) path.get('partsCovered')).size() > 1);
        Boolean sawLoop = false, sawPartner = false;
        for (String id : required) {
            if (id.startsWith('s1_') || id.startsWith('addshares_')) sawLoop = true;
            if (id == 'q23' || id.startsWith('q0_partner')) sawPartner = true;
        }
        System.assert(sawLoop, 'shares loop instantiated with prefixed ids');
        System.assert(sawPartner, 'partner pages included when living together');
        System.assertNotEquals(null, path.get('declarationComplete'));
    }

    @IsTest static void single_no_partner_and_start_no() {
        Id single = appWith(new Map<String, String>{ 'start' => 'yes', 'q14' => 'no', 'q105' => '["none"]' });
        Id notStarted = appWith(new Map<String, String>{ 'start' => 'no' });
        Map<Id, PC1_FlowEngine.ProgressResult> res = PC1_FlowEngine.compute(new Set<Id>{ single, notStarted });
        System.assert(res.get(single).total > res.get(notStarted).total, 'start = no stops after the intro pages');
        for (String id : res.get(single).requiredFieldIds) {
            System.assert(id != 'q23', 'no partner pages for a single claimant');
        }
        PC1_FlowEngine.recomputeAndUpdate(new Set<Id>{ single, notStarted });
        System.assertNotEquals(null, [SELECT Progress_Total__c FROM PC1_Application__c WHERE Id = :single].Progress_Total__c);
    }

    @IsTest static void empty_inputs() {
        System.assertEquals(0, PC1_FlowEngine.getPathForRecord(null).size());
        System.assertEquals(0, PC1_FlowEngine.compute(new Set<Id>()).size());
        System.assertEquals(0, PC1_FlowEngine.compute((Set<Id>) null).size());
    }
}