/**
 * AA_ProgressRecomputeBatchTest: the one-off recompute of the stored
 * "what is missing" figures (audit 2026-11-11 AA-APEX-9).
 */
@isTest
private class AA_ProgressRecomputeBatchTest {

    private static AA_Application__c app(String lastName, String stage) {
        return new AA_Application__c(
            First_Name__c = 'Batch', Last_Name__c = lastName, Phone__c = '+441234567890', Stage__c = stage);
    }

    @isTest static void recomputes_open_applications_and_leaves_closed_ones() {
        AA_Application__c open = app('Open', 'New');
        AA_Application__c closed = app('Closed', 'Closed - Paid');
        insert new List<AA_Application__c>{ open, closed };
        // Stand-in for figures computed by an older flow: nothing has touched
        // the answers since.
        Datetime stale = Datetime.now().addDays(-30);
        update new List<AA_Application__c>{
            new AA_Application__c(Id = open.Id, Progress_Total__c = 0, Progress_Last_Updated__c = stale),
            new AA_Application__c(Id = closed.Id, Progress_Total__c = 0, Progress_Last_Updated__c = stale)
        };

        Test.startTest();
        Database.executeBatch(new AA_ProgressRecomputeBatch(), 50);
        Test.stopTest();

        Map<Id, AA_Application__c> after = new Map<Id, AA_Application__c>([
            SELECT Id, Progress_Total__c, Progress_Last_Updated__c
              FROM AA_Application__c WHERE Id IN (:open.Id, :closed.Id)]);
        System.assert(after.get(open.Id).Progress_Total__c > 0, 'the open application is recomputed from the current flow');
        System.assert(after.get(open.Id).Progress_Last_Updated__c > stale.addDays(1), 'and stamped as recomputed now');
        System.assertEquals(0, after.get(closed.Id).Progress_Total__c, 'a closed case is left as it is');
        System.assert(AA_ProgressRecomputeBatch.CLOSED_STAGES.contains('Closed - Refused'));
    }
}