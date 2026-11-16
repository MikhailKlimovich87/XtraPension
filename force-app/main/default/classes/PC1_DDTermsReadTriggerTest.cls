/**
 * PC1_DDTermsReadTriggerTest — covers PC1_DDTermsReadTrigger:
 *   1. false → true stamps When/Who with current user + now
 *   2. true → false nulls both stamps
 */
@isTest
private class PC1_DDTermsReadTriggerTest {

    private static PC1_Application__c makeApp() {
        // Required minimums per PC1_ApplicationTrigger + validation rules.
        return new PC1_Application__c(
            First_Name__c = 'DDTerms',
            Last_Name__c  = 'Test' + System.now().getTime(),
            Phone__c      = '+441234567890',
            Stage__c      = 'New'
        );
    }

    @isTest static void flipTrue_stamps_when_and_who() {
        PC1_Application__c a = makeApp();
        insert a;

        a.DD_Terms_Read_By_Sales__c = true;
        Test.startTest();
        update a;
        Test.stopTest();

        PC1_Application__c after = [
            SELECT DD_Terms_Read_By_Sales__c,
                   DD_Terms_Read_At__c,
                   DD_Terms_Read_By__c
              FROM PC1_Application__c WHERE Id = :a.Id
        ];
        System.assertEquals(true, after.DD_Terms_Read_By_Sales__c);
        System.assertNotEquals(null, after.DD_Terms_Read_At__c, 'When must be stamped on flip true');
        System.assertEquals(UserInfo.getUserId(), after.DD_Terms_Read_By__c, 'Who must be current user');
    }

    @isTest static void flipFalse_clears_when_and_who() {
        PC1_Application__c a = makeApp();
        insert a;

        // First flip true so we have stamps to clear.
        a.DD_Terms_Read_By_Sales__c = true;
        update a;
        PC1_Application__c pre = [
            SELECT DD_Terms_Read_At__c, DD_Terms_Read_By__c
              FROM PC1_Application__c WHERE Id = :a.Id
        ];
        System.assertNotEquals(null, pre.DD_Terms_Read_At__c, 'precondition: When stamped');
        System.assertNotEquals(null, pre.DD_Terms_Read_By__c, 'precondition: Who stamped');

        // Now flip back — trigger must null both stamps.
        a.DD_Terms_Read_By_Sales__c = false;
        Test.startTest();
        update a;
        Test.stopTest();

        PC1_Application__c after = [
            SELECT DD_Terms_Read_By_Sales__c,
                   DD_Terms_Read_At__c,
                   DD_Terms_Read_By__c
              FROM PC1_Application__c WHERE Id = :a.Id
        ];
        System.assertEquals(false, after.DD_Terms_Read_By_Sales__c);
        System.assertEquals(null, after.DD_Terms_Read_At__c, 'When must be cleared on flip false');
        System.assertEquals(null, after.DD_Terms_Read_By__c, 'Who must be cleared on flip false');
    }

    // Audit 2026-11-11 PC-APEX-15: intake inserts through the one integration
    // user; the trail must be able to name the agent who read the terms.
    @isTest static void suppliedReader_isKept_onInsert_andOnUpdate() {
        List<User> others = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1];
        if (others.isEmpty()) return;   // single-user org: nothing to tell apart
        Id agent = others[0].Id;

        PC1_Application__c onInsert = makeApp();
        onInsert.DD_Terms_Read_By_Sales__c = true;
        onInsert.DD_Terms_Read_By__c = agent;
        insert onInsert;
        PC1_Application__c a1 = [SELECT DD_Terms_Read_At__c, DD_Terms_Read_By__c FROM PC1_Application__c WHERE Id = :onInsert.Id];
        System.assertEquals(agent, a1.DD_Terms_Read_By__c, 'the reader named by the caller is kept (was overwritten)');
        System.assertNotEquals(null, a1.DD_Terms_Read_At__c);

        PC1_Application__c onUpdate = makeApp();
        insert onUpdate;
        update new PC1_Application__c(Id = onUpdate.Id, DD_Terms_Read_By_Sales__c = true, DD_Terms_Read_By__c = agent);
        System.assertEquals(agent,
            [SELECT DD_Terms_Read_By__c FROM PC1_Application__c WHERE Id = :onUpdate.Id].DD_Terms_Read_By__c);
    }
}