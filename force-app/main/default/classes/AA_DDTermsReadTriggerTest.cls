/**
 * AA_DDTermsReadTriggerTest — covers AA_DDTermsReadTrigger:
 *   1. false → true stamps When/Who with current user + now
 *   2. true → false nulls both stamps
 *   3. a reader supplied in the same DML is kept (audit 2026-10-02 F118)
 */
@isTest
private class AA_DDTermsReadTriggerTest {

    private static AA_Application__c makeApp() {
        // Required minimums per AA_ApplicationTrigger + validation rules.
        return new AA_Application__c(
            First_Name__c = 'DDTerms',
            Last_Name__c  = 'Test' + System.now().getTime(),
            Phone__c      = '+441234567890',
            Stage__c      = 'New'
        );
    }

    @isTest static void flipTrue_stamps_when_and_who() {
        AA_Application__c a = makeApp();
        insert a;

        a.DD_Terms_Read_By_Sales__c = true;
        Test.startTest();
        update a;
        Test.stopTest();

        AA_Application__c after = [
            SELECT DD_Terms_Read_By_Sales__c,
                   DD_Terms_Read_At__c,
                   DD_Terms_Read_By__c
              FROM AA_Application__c WHERE Id = :a.Id
        ];
        System.assertEquals(true, after.DD_Terms_Read_By_Sales__c);
        System.assertNotEquals(null, after.DD_Terms_Read_At__c, 'When must be stamped on flip true');
        System.assertEquals(UserInfo.getUserId(), after.DD_Terms_Read_By__c, 'Who must be current user');
    }

    @isTest static void flipFalse_clears_when_and_who() {
        AA_Application__c a = makeApp();
        insert a;

        // First flip true so we have stamps to clear.
        a.DD_Terms_Read_By_Sales__c = true;
        update a;
        AA_Application__c pre = [
            SELECT DD_Terms_Read_At__c, DD_Terms_Read_By__c
              FROM AA_Application__c WHERE Id = :a.Id
        ];
        System.assertNotEquals(null, pre.DD_Terms_Read_At__c, 'precondition: When stamped');
        System.assertNotEquals(null, pre.DD_Terms_Read_By__c, 'precondition: Who stamped');

        // Now flip back — trigger must null both stamps.
        a.DD_Terms_Read_By_Sales__c = false;
        Test.startTest();
        update a;
        Test.stopTest();

        AA_Application__c after = [
            SELECT DD_Terms_Read_By_Sales__c,
                   DD_Terms_Read_At__c,
                   DD_Terms_Read_By__c
              FROM AA_Application__c WHERE Id = :a.Id
        ];
        System.assertEquals(false, after.DD_Terms_Read_By_Sales__c);
        System.assertEquals(null, after.DD_Terms_Read_At__c, 'When must be cleared on flip false');
        System.assertEquals(null, after.DD_Terms_Read_By__c, 'Who must be cleared on flip false');
    }

    // audit 2026-10-02 F118: intake writes as the integration user; when it
    // names the agent who read the terms, that value must survive the stamp.
    @isTest static void flipTrue_keepsSuppliedReader() {
        AA_Application__c a = makeApp();
        insert a;
        Id otherUser = [SELECT Id FROM User WHERE IsActive = true AND Id != :UserInfo.getUserId() LIMIT 1].Id;
        a.DD_Terms_Read_By_Sales__c = true;
        a.DD_Terms_Read_By__c = otherUser;
        update a;
        AA_Application__c after = [SELECT DD_Terms_Read_At__c, DD_Terms_Read_By__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(otherUser, after.DD_Terms_Read_By__c, 'caller-supplied reader kept');
        System.assertNotEquals(null, after.DD_Terms_Read_At__c);
    }
}