// Short Form Save with a question the form did not ask (17/11/2026, C00000): a Yes / No left unanswered comes as null
// and a checkbox cannot take null, so the Save failed with INVALID_TYPE_ON_FIELD_IN_RECORD. Now null keeps what the
// claim has.
@IsTest
private class XpClaimShortSaveNullTest {

    private static Integer people = 0;

    private static Basic__c claim(Map<String, Object> fields) {
        people++;
        Contact c = new Contact(LastName = 'Nullsave' + people, Email = 'null.save' + people + '@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'null.save' + people + '@example.com';
        for (String f : fields.keySet()) b.put(f, fields.get(f));
        insert b;
        return b;
    }

    private static void save(Id claimId, String track, String trackKey, Map<String, Object> trackBody) {
        Map<String, Object> client = new Map<String, Object>{ 'firstName' => 'Megan', 'email' => 'null.save@example.com', 'maritalStatus' => 'Married', 'everLivedUK' => true };
        String body = JSON.serialize(new Map<String, Object>{ 'applicationId' => claimId,
            'application' => new Map<String, Object>{ 'track' => track, 'client' => client, trackKey => trackBody } });
        BP_PortalUtils.autoSaveShort(new BP_RequestWrappers.ShortApplicationDataWrapper(body));
    }

    @IsTest
    static void trackBHusbandAliveSavesWithoutTheWidowQuestion() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B', 'Claimant_State_Pension__c' => true });
        Test.startTest();
        // husband alive: the form never asks "Are you getting a UK State Pension now from your husband?"
        save(b.Id, 'B', 'trackB', new Map<String, Object>{
            'husbandAlive' => 'Yes', 'husbandGettinStatePensionNow' => true, 'youGettinStatePensionNow' => null,
            'sameAddress' => true, 'husbandFirstName' => 'Bob', 'husbandSurname' => 'Smith', 'husbandHasNino' => 'Yes', 'husbandNino' => 'XY123456A' });
        Test.stopTest();
        Basic__c after = [SELECT Claimant_State_Pension__c, Partner_State_Pension__c, Partner_same_as_claimant__c, Partner_First_Name__c, Partner_Nino__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(true, after.Claimant_State_Pension__c, 'an unanswered question keeps what the claim has');
        System.assertEquals(true, after.Partner_State_Pension__c);
        System.assertEquals(true, after.Partner_same_as_claimant__c);
        System.assertEquals('Bob', after.Partner_First_Name__c, 'the rest of the Save goes in');
        System.assertEquals('XY123456A', after.Partner_Nino__c);
    }

    @IsTest
    static void trackBEveryYesNoUnansweredStillSaves() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B' });
        Test.startTest();
        save(b.Id, 'B', 'trackB', new Map<String, Object>{ 'husbandFirstName' => 'Bob' });
        Test.stopTest();
        Basic__c after = [SELECT Claimant_State_Pension__c, Partner_State_Pension__c, Partner_First_Name__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(false, after.Claimant_State_Pension__c);
        System.assertEquals(false, after.Partner_State_Pension__c);
        System.assertEquals('Bob', after.Partner_First_Name__c);
    }

    @IsTest
    static void trackBAnswersAreStillWritten() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B', 'Claimant_State_Pension__c' => true, 'Partner_State_Pension__c' => true });
        Test.startTest();
        save(b.Id, 'B', 'trackB', new Map<String, Object>{
            'husbandAlive' => 'No', 'youGettinStatePensionNow' => false, 'husbandGettinStatePensionNow' => false, 'sameAddress' => false });
        Test.stopTest();
        Basic__c after = [SELECT Claimant_State_Pension__c, Partner_State_Pension__c, Partner_same_as_claimant__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(false, after.Claimant_State_Pension__c, 'a No is written');
        System.assertEquals(false, after.Partner_State_Pension__c);
        System.assertEquals(false, after.Partner_same_as_claimant__c);
    }

    @IsTest
    static void trackCSameAddressUnansweredStillSaves() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'C' });
        Test.startTest();
        save(b.Id, 'C', 'trackC', new Map<String, Object>{ 'wifeHasNino' => 'Yes', 'wifeNino' => 'XY123456B' });
        Test.stopTest();
        System.assertEquals('XY123456B', [SELECT Partner_Nino__c FROM Basic__c WHERE Id = :b.Id].Partner_Nino__c);
    }
}