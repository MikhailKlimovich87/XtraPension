// "Minded Kids in UK 1978-2010?" = No with no child sent (18/11/2026): the children the long form saved before go, so
// the BR1 notes (Q53) and the Client Summary stop printing a child under a No. A child added on the Claim page stays,
// and so does everything when the answer is Yes or not sent.
@IsTest
private class XpClaimMindedKidsNoTest {

    private static Integer people = 0;

    private static Basic__c claim() {
        people++;
        Contact c = new Contact(LastName = 'Kids' + people, Email = 'minded.kids' + people + '@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'minded.kids' + people + '@example.com';
        b.Claimant_Minded_Kids__c = true;
        insert b;
        insert new List<Claimant_Child__c>{
            new Claimant_Child__c(Basic__c = b.Id, Name = 'Form child', Saved_By_Form__c = true),
            new Claimant_Child__c(Basic__c = b.Id, Name = 'Claim page child')
        };
        return b;
    }

    // What the form sends: the claimant section with its defaults, plus the test's values
    private static Map<String, Object> claimant(Map<String, Object> values) {
        Map<String, Object> all = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new BP_RequestWrappers.ApplicationFullWrapper()));
        Map<String, Object> base = (Map<String, Object>) all.get('claimant');
        base.putAll(values);
        return base;
    }

    private static BP_RequestWrappers.ApplicationDetailsDataWrapper payload(Id claimId, Map<String, Object> claimant, Boolean partial) {
        Map<String, Object> body = new Map<String, Object>{
            'applicationId' => claimId, 'currentStep' => 9, 'isAgentForm' => true,
            'isAutoSave' => partial, 'isPartial' => partial, 'application' => new Map<String, Object>{ 'claimant' => claimant }
        };
        return new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(body));
    }

    private static List<String> names(Id claimId) {
        List<String> out = new List<String>();
        for (Claimant_Child__c row : [SELECT Name FROM Claimant_Child__c WHERE Basic__c = :claimId ORDER BY Name]) out.add(row.Name);
        return out;
    }

    @IsTest
    static void autosaveWithNoRemovesTheFormsChildren() {
        Basic__c b = claim();
        Test.startTest();
        BP_PortalUtils.autoSave(payload(b.Id, claimant(new Map<String, Object>{ 'mindedKids' => false, 'children' => new List<Object>() }), true));
        Test.stopTest();
        System.assertEquals(new List<String>{ 'Claim page child' }, names(b.Id), 'the form\'s child goes, the Claim page\'s stays');
        System.assertEquals(false, [SELECT Claimant_Minded_Kids__c FROM Basic__c WHERE Id = :b.Id].Claimant_Minded_Kids__c);
    }

    @IsTest
    static void sendWithNoRemovesTheFormsChildren() {
        Basic__c b = claim();
        // one blank row, as the form sends an untouched list
        Map<String, Object> c = claimant(new Map<String, Object>{ 'mindedKids' => false,
            'children' => new List<Object>{ new Map<String, Object>{ 'name' => '', 'dob' => null } } });
        BP_PortalUtils.deleteListsBeingReplaced(payload(b.Id, c, false));
        System.assertEquals(new List<String>{ 'Claim page child' }, names(b.Id));
    }

    @IsTest
    static void yesWithAnEmptyListKeepsEveryChild() {
        Basic__c b = claim();
        Map<String, Object> c = claimant(new Map<String, Object>{ 'mindedKids' => true, 'children' => new List<Object>() });
        BP_PortalUtils.saveListsFromAutosave(payload(b.Id, c, true));
        BP_PortalUtils.deleteListsBeingReplaced(payload(b.Id, c, false));
        System.assertEquals(2, names(b.Id).size(), 'a list sent empty keeps what Salesforce has');
    }

    @IsTest
    static void noAnswerSentKeepsEveryChild() {
        Basic__c b = claim();
        Map<String, Object> c = new Map<String, Object>{ 'firstName' => 'Ann' };
        BP_PortalUtils.saveListsFromAutosave(payload(b.Id, c, true));
        BP_PortalUtils.deleteListsBeingReplaced(payload(b.Id, c, false));
        System.assertEquals(2, names(b.Id).size());
    }

    @IsTest
    static void aChildSentIsSavedAsBefore() {
        Basic__c b = claim();
        // No with a child still in the list: the list wins, as before
        Map<String, Object> c = claimant(new Map<String, Object>{ 'mindedKids' => false,
            'children' => new List<Object>{ new Map<String, Object>{ 'name' => 'New child', 'dob' => '1985-03-01T00:00:00.000Z' } } });
        BP_PortalUtils.saveListsFromAutosave(payload(b.Id, c, true));
        System.assertEquals(new List<String>{ 'Claim page child', 'New child' }, names(b.Id));
    }
}