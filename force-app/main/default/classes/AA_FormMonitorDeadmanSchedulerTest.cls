@isTest
private class AA_FormMonitorDeadmanSchedulerTest {

    private static AA_Form_Snapshot__c snap(String status, Datetime capturedAt) {
        return new AA_Form_Snapshot__c(
            Status__c       = status,
            Captured_At__c  = capturedAt,
            Page_Count__c   = 45,
            Fields_Count__c = 58,
            Browser__c      = 'chromium',
            Duration_Ms__c  = 1000,
            Triggered_By__c = 'cron'
        );
    }

    private static AA_Form_Snapshot__c snap(Datetime capturedAt) {
        return snap('success', capturedAt);
    }

    @isTest static void notStale_whenRecentSuccess() {
        insert snap(Datetime.now());
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(false, stale, 'a fresh success walk must not be stale');
        System.assertEquals(null, AA_FormMonitorDeadmanScheduler.lastReason, 'no alert reason when nothing is wrong');
    }

    @isTest static void stale_whenLastSuccessOld() {
        insert snap(Datetime.now().addHours(-48)); // older than the 26h threshold
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check(); // also exercises sendAlert
        Test.stopTest();
        System.assertEquals(true, stale, '48h-old walk must be flagged stale');
        System.assertEquals('NO_RUN', AA_FormMonitorDeadmanScheduler.lastReason,
            'the only walk is 48h old, so nothing ran in 26h: the pipeline is dead');
    }

    @isTest static void stale_whenNoSuccessEver() {
        // only a BLOCKED snapshot exists → walks run, none ever succeeded
        insert snap('blocked', Datetime.now());
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'no successful walk ever must be stale');
        System.assertEquals('NO_SUCCESS', AA_FormMonitorDeadmanScheduler.lastReason,
            'a fresh blocked walk proves the pipeline fires, so this is NO_SUCCESS, not NO_RUN');
    }

    /**
     * Regression for 2026-09-16. One transient DWP blip made the morning walk come
     * back 'blocked'. The worker emailed its own walk-failed alert immediately; this
     * job then sent a SECOND email at 11:00 about the same event, pointing at the
     * scheduler and the endpoint, which were both healthy. A single blocked run with
     * a success inside NO_SUCCESS_HOURS must stay silent here.
     */
    @isTest static void silent_whenOneBlockedRunFollowsARecentSuccess() {
        insert new List<AA_Form_Snapshot__c>{
            snap('success', Datetime.now().addHours(-31)),   // exactly the gap that fired
            snap('blocked', Datetime.now().addHours(-7))
        };
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(false, stale,
            'a blocked walk already alerted by itself; a 31h success gap must not send a duplicate');
        System.assertEquals(null, AA_FormMonitorDeadmanScheduler.lastReason, 'no alert reason expected');
    }

    @isTest static void errorRowCountsAsARun() {
        // An 'error' row is written when the worker crashes. It still proves the
        // scheduler fired and the endpoint answered, so it must not read as NO_RUN.
        insert new List<AA_Form_Snapshot__c>{
            snap('success', Datetime.now().addHours(-40)),
            snap('error',   Datetime.now().addHours(-2))
        };
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(false, stale, 'a recent error row is a run, and the success is inside 72h');
    }

    @isTest static void noRun_whenEveryWalkIsOlderThanTheStaleWindow() {
        // Walks of every status exist, but none in the last 26h: the pipeline stopped.
        insert new List<AA_Form_Snapshot__c>{
            snap('success', Datetime.now().addHours(-30)),
            snap('blocked', Datetime.now().addHours(-29))
        };
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'nothing ran in 26h must alert');
        System.assertEquals('NO_RUN', AA_FormMonitorDeadmanScheduler.lastReason,
            'no walk of any status in 26h is the dead-pipeline case');
    }

    @isTest static void noSuccess_whenWalksKeepFailingPastTheBackstop() {
        // The walker runs daily but has not succeeded for over 72h. The worker should
        // have been alerting each day; this is the backstop in case those emails are
        // not arriving.
        insert new List<AA_Form_Snapshot__c>{
            snap('success', Datetime.now().addHours(-80)),
            snap('blocked', Datetime.now().addHours(-3))
        };
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'no success in 80h must alert even though walks are running');
        System.assertEquals('NO_SUCCESS', AA_FormMonitorDeadmanScheduler.lastReason,
            'recent runs exist, so the reason must be NO_SUCCESS, not NO_RUN');
    }

    @isTest static void noRun_takesPriorityOverNoSuccess() {
        // Both conditions true at once: nothing ran in 26h AND no success in 72h. The
        // dead pipeline is the root cause, so that is what the reader must be told.
        insert snap('success', Datetime.now().addHours(-100));
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'must alert');
        System.assertEquals('NO_RUN', AA_FormMonitorDeadmanScheduler.lastReason,
            'when nothing runs at all, point at the pipeline, not at the walker');
    }

    @isTest static void noRun_whenTableIsEmpty() {
        Test.startTest();
        Boolean stale = AA_FormMonitorDeadmanScheduler.check();
        Test.stopTest();
        System.assertEquals(true, stale, 'no snapshot ever must alert');
        System.assertEquals('NO_RUN', AA_FormMonitorDeadmanScheduler.lastReason, 'an empty table means nothing has ever run');
    }

    @isTest static void scheduleAndExecute() {
        insert snap(Datetime.now());
        Test.startTest();
        String jobId = System.schedule('AA Deadman Test', '0 0 12 * * ?', new AA_FormMonitorDeadmanScheduler());
        Test.stopTest();
        System.assert(jobId != null, 'schedulable registers');
    }
}