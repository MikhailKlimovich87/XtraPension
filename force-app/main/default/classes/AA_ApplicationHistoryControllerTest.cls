/**
 * AA_ApplicationHistoryControllerTest — backs the aaApplicationHistory card.
 *
 * Added 2026-10-02 (audit F157): the controller had 0% coverage. Apex tests
 * never produce field-history rows, so the query path is exercised for its
 * empty result and the row mapping (toRow) is exercised with in-memory
 * History records built through JSON.deserialize.
 */
@isTest
private class AA_ApplicationHistoryControllerTest {

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'History',
            Last_Name__c  = 'Test' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c      = '+441234567890',
            DOB__c        = Date.newInstance(1950, 6, 1),
            Postcode__c   = 'SW1A 1AA',
            Stage__c      = 'New'
        );
        insert a;
        return a;
    }

    @isTest static void nullRecordId_returnsEmpty() {
        System.assertEquals(0, AA_ApplicationHistoryController.getHistory(null, 5).size(), 'null id gives no rows');
        System.assertEquals(0, AA_ApplicationHistoryController.getHistoryCount(null), 'null id counts 0');
    }

    @isTest static void realRecord_queriesWithoutError() {
        AA_Application__c a = makeApp();
        Test.startTest();
        // maxRows <= 0 falls back to the default limit of 5.
        List<AA_ApplicationHistoryController.HistoryRow> rows = AA_ApplicationHistoryController.getHistory(a.Id, 0);
        Integer n = AA_ApplicationHistoryController.getHistoryCount(a.Id);
        Test.stopTest();
        // Field history is not written inside Apex tests; the contract under
        // test is "scoped query, no exception, count matches rows returned".
        System.assert(rows.size() <= 5, 'default limit is 5');
        System.assert(n >= rows.size(), 'count covers the rows returned');
    }

    @isTest static void toRow_mapsKnownFieldToFriendlyLabel() {
        AA_Application__History h = (AA_Application__History) JSON.deserialize(
            '{"attributes":{"type":"AA_Application__History"},"Field":"Stage__c"}',
            AA_Application__History.class);
        AA_ApplicationHistoryController.HistoryRow r = AA_ApplicationHistoryController.toRow(h);
        System.assertEquals('Stage', r.FieldLabel, 'Stage__c shows as Stage');
        System.assertEquals('Stage__c', r.FieldApiName, 'api name kept');
        System.assertEquals(null, r.OldValueDisplay, 'no old value');
        System.assertEquals(null, r.UserName, 'no user on an in-memory row');
    }

    @isTest static void toRow_unknownFieldFallsBackToApiName() {
        AA_Application__History h = (AA_Application__History) JSON.deserialize(
            '{"attributes":{"type":"AA_Application__History"},"Field":"Some_Other__c"}',
            AA_Application__History.class);
        AA_ApplicationHistoryController.HistoryRow r = AA_ApplicationHistoryController.toRow(h);
        System.assertEquals('Some_Other__c', r.FieldLabel, 'unknown field shows its API name');
    }
}