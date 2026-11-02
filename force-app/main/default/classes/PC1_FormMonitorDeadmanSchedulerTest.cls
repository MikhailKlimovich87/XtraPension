@isTest
private class PC1_FormMonitorDeadmanSchedulerTest {

    private static final String UNION = '__union__';

    private static PC1_Form_Snapshot__c snap(Datetime capturedAt, String personaKey, String status) {
        return new PC1_Form_Snapshot__c(
            Status__c       = status,
            Captured_At__c  = capturedAt,
            Persona_Key__c  = personaKey,
            Page_Count__c   = 49,
            Fields_Count__c = 66,
            Browser__c      = 'chromium',
            Duration_Ms__c  = 1000,
            Triggered_By__c = 'cron'
        );
    }
    /** A COMPLETE sweep: the per-persona rows plus the union row the worker writes last. */
    private static void completeSweep(Datetime at) {
        insert new List<PC1_Form_Snapshot__c>{
            snap(at, 'solo', 'success'),
            snap(at.addSeconds(60), 'partnered', 'success'),
            snap(at.addSeconds(120), UNION, 'success')
        };
    }

    @isTest static void notStale_whenRecentCompleteSweep() {
        completeSweep(Datetime.now());
        Test.startTest();
        Boolean stale = PC1_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(false, stale, 'a fresh complete sweep must not be stale');
    }

    @isTest static void stale_whenLastCompleteSweepOld() {
        completeSweep(Datetime.now().addHours(-48)); // older than the 26h threshold
        Test.startTest();
        Boolean stale = PC1_FormMonitorDeadmanScheduler.check(); // also exercises sendAlert
        Test.stopTest();
        System.assertEquals(true, stale, '48h-old sweep must be flagged stale');
    }

    @isTest static void stale_whenSweepDiedPartWay() {
        // THE REGRESSION THIS GUARDS: persona rows landed, then the worker was
        // killed (Heroku SIGTERM on deploy / dyno cycle) before the union row.
        // The old check accepted any successful row and reported healthy.
        insert new List<PC1_Form_Snapshot__c>{
            snap(Datetime.now(), 'solo', 'success'),
            snap(Datetime.now(), 'partnered', 'success'),
            snap(Datetime.now(), 'homeowner', 'success')
        };
        Test.startTest();
        Boolean stale = PC1_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale,
            'persona rows without the __union__ row mean the sweep never finished — must alert');
    }

    @isTest static void stale_whenUnionIsBlocked() {
        insert new List<PC1_Form_Snapshot__c>{
            snap(Datetime.now(), 'solo', 'success'),
            snap(Datetime.now(), UNION, 'blocked')
        };
        Test.startTest();
        Boolean stale = PC1_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'a blocked union is not a complete sweep');
    }

    @isTest static void stale_whenNoSuccessEver() {
        insert snap(Datetime.now(), UNION, 'blocked');
        Test.startTest();
        Boolean stale = PC1_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'no successful sweep ever must be stale');
    }

    @isTest static void recipientFallsBackToRunningUser() {
        Test.startTest();
        String to = PC1_FormMonitorDeadmanScheduler.resolveRecipient();
        Test.stopTest();
        System.assertNotEquals(null, to, 'must always resolve some recipient');
        System.assert(to.contains('@'), 'recipient must look like an email: ' + to);
    }

    @isTest static void scheduleAndExecute() {
        completeSweep(Datetime.now());
        Test.startTest();
        String jobId = System.schedule('PC1 Deadman Test', '0 0 12 * * ?', new PC1_FormMonitorDeadmanScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'schedulable registers');
    }
}