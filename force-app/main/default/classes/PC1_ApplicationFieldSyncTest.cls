/**
 * Tests for PC1_ApplicationFieldSync — both directions.
 *
 * Answers → parent was covered only indirectly by other classes. The
 * parent → answers mirror and the parent-side bank safety were added on
 * 2026-10-02 (audit C10): a bank or address edited on the record page used
 * to stay on the Application only, so DWP got the old values and the old
 * mandate kept being charged.
 */
@IsTest
private class PC1_ApplicationFieldSyncTest {

    private static PC1_Application__c makeApp() {
        List<PC1_Config__c> cfg = [SELECT Id FROM PC1_Config__c LIMIT 1];
        // No auto-mandate callouts from these tests.
        if (cfg.isEmpty()) insert new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId(), Auto_Create_DD_Mandate__c = false);
        else update new PC1_Config__c(Id = cfg[0].Id, Auto_Create_DD_Mandate__c = false);

        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Sync', Last_Name__c = 'Test', Stage__c = 'New', Email__c = 'sync@example.com',
            Address_Line1__c = '1 Old Road', Address_Line2__c = 'Flat 2', City__c = 'Leeds', Postcode__c = 'LS1 1AA',
            Bank_Sort_Code__c = '20-00-00', Bank_Account_Number__c = '55779911', Bank_Account_Holder__c = 'S TEST',
            Bank_Verification_Status__c = 'Modulus Passed');
        insert a;
        return a;
    }

    private static Map<String, String> answers(Id appId) {
        Map<String, String> m = new Map<String, String>();
        for (PC1_Answer__c r : [SELECT Field_Id__c, Value__c FROM PC1_Answer__c WHERE Application__c = :appId]) {
            m.put(r.Field_Id__c, r.Value__c);
        }
        return m;
    }

    @IsTest static void record_page_address_edit_reaches_answers() {
        PC1_Application__c a = makeApp();
        insert new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q7_line1', Value__c = '1 Old Road', Source__c = 'human');
        insert new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q7_line2', Value__c = 'Flat 2', Source__c = 'human');

        Test.startTest();
        update new PC1_Application__c(Id = a.Id, Address_Line1__c = '9 New Street', Address_Line2__c = null);
        Test.stopTest();

        Map<String, String> ans = answers(a.Id);
        System.assertEquals('9 New Street', ans.get('q7_line1'), 'DWP fill must see the new address');
        System.assert(!ans.containsKey('q7_line2'), 'cleared line 2 must not linger in answers');
        System.assertEquals('9 New Street', [SELECT Address_Line1__c FROM PC1_Application__c WHERE Id = :a.Id].Address_Line1__c,
            'and the next answer sync must not revert the parent');
    }

    @IsTest static void answer_save_still_updates_parent() {
        PC1_Application__c a = makeApp();
        Test.startTest();
        insert new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q7_town', Value__c = 'York', Source__c = 'mary');
        Test.stopTest();
        System.assertEquals('York', [SELECT City__c FROM PC1_Application__c WHERE Id = :a.Id].City__c);
    }

    @IsTest static void inline_bank_edit_resets_trust_and_parks_mandate() {
        PC1_Application__c a = makeApp();
        update new PC1_Application__c(Id = a.Id, DD_Mandate_Id__c = 'MD-LIVE', DD_Mandate_Status__c = 'active');

        Test.startTest();
        update new PC1_Application__c(Id = a.Id, Bank_Account_Number__c = '11223344');
        Test.stopTest();

        PC1_Application__c after = [SELECT Bank_Verification_Status__c, DD_Mandate_Status__c, DD_Mandate_Failure_Reason__c
                                      FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('Unverified', after.Bank_Verification_Status__c, 'old verdict does not cover new digits');
        System.assertEquals('cancelled', after.DD_Mandate_Status__c, 'old account must not be charged');
        System.assert(after.DD_Mandate_Failure_Reason__c.startsWith('Bank details changed'));
        System.assertEquals('11223344', answers(a.Id).get('q0_sp_account'), 'new account reaches DWP answers');
    }

    @IsTest static void bank_editor_verified_save_keeps_new_status() {
        PC1_Application__c a = makeApp();
        Test.startTest();
        // The bank editor writes new digits AND the fresh verdict together.
        update new PC1_Application__c(Id = a.Id, Bank_Account_Number__c = '11223344',
            Bank_Verification_Status__c = 'Name Verified');
        Test.stopTest();
        System.assertEquals('Name Verified',
            [SELECT Bank_Verification_Status__c FROM PC1_Application__c WHERE Id = :a.Id].Bank_Verification_Status__c);
        System.assertEquals('Name Verified', answers(a.Id).get('q_bank_verification_status'));
    }

    @IsTest static void dead_mandate_is_not_touched() {
        PC1_Application__c a = makeApp();
        update new PC1_Application__c(Id = a.Id, DD_Mandate_Id__c = 'MD-DEAD', DD_Mandate_Status__c = 'failed',
            DD_Mandate_Failure_Reason__c = 'bank_account_closed');
        update new PC1_Application__c(Id = a.Id, Bank_Sort_Code__c = '40-47-84');
        PC1_Application__c after = [SELECT DD_Mandate_Status__c, DD_Mandate_Failure_Reason__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('failed', after.DD_Mandate_Status__c);
        System.assertEquals('bank_account_closed', after.DD_Mandate_Failure_Reason__c, 'real failure reason kept');
    }

    @IsTest static void sync_overload_and_dob() {
        PC1_Application__c a = makeApp();
        insert new List<PC1_Answer__c>{
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q5_day', Value__c = '3', Source__c = 'human'),
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q5_month', Value__c = '4', Source__c = 'human'),
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q5_year', Value__c = '1950', Source__c = 'human'),
            new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q9_mobile', Value__c = '+447700900123', Source__c = 'human')
        };
        PC1_ApplicationFieldSync.syncFromAnswers(new Set<Id>{ a.Id });
        PC1_Application__c after = [SELECT DOB__c, Phone__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(Date.newInstance(1950, 4, 3), after.DOB__c);
        System.assertNotEquals(null, after.Phone__c);
    }
}