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
}