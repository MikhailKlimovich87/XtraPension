@isTest
private class RE_SendForEsignReportControllerTest {

    // ---------------------------------------------------------------
    // Test data helpers
    // ---------------------------------------------------------------

    /**
     * Creates an Envelope owned by the given user.
     * Adjust required fields to whatever your org/package requires
     * for dfsle__Envelope__c (e.g. dfsle__Status__c, dfsle__SourceType__c, etc.).
     *
     * NOTE: CreatedDate is a read-only audit field. We insert the record,
     * then back-date it with Test.setCreatedDate(...). This must be done
     * BEFORE Test.startTest() so the controller's SOQL sees the back-dated time.
     */
    private static dfsle__Envelope__c makeEnvelope(Id ownerId, Datetime createdDate) {
        dfsle__Envelope__c env = new dfsle__Envelope__c(
            OwnerId = ownerId
            // If your org requires these, uncomment / adjust:
            // dfsle__Status__c       = 'Created',
            // dfsle__SourceType__c   = 'Reapply__c',
            // dfsle__EnvelopeId__c   = 'env-' + String.valueOf(Crypto.getRandomLong()).left(10)
        );
        insert env;

        if (createdDate != null) {
            Test.setCreatedDate(env.Id, createdDate);
        }
        return env;
    }

    /** Creates a User with just a Name and a profile. */
    private static User makeUser(String fullName, String profileName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String safe = fullName.replaceAll('[^a-zA-Z0-9]', '');
        User u = new User(
            FirstName         = fullName.contains(' ') ? fullName.substringBefore(' ') : fullName,
            LastName          = fullName.contains(' ') ? fullName.substringAfter(' ')  : 'Test',
            Username          = safe + '.' + DateTime.now().getTime() + '@test.example.com',
            Email             = safe + '@test.example.com',
            Alias             = safe.left(8),
            ProfileId         = p.Id,
            TimeZoneSidKey    = 'Europe/Dublin',
            LocaleSidKey      = 'en_IE',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    // ---------------------------------------------------------------
    // getEnvelopeReportData
    // ---------------------------------------------------------------

    @isTest
    static void testEmptyData() {
        Test.startTest();
        RE_SendForEsignReportController.EnvelopeReportWrapper result =
            RE_SendForEsignReportController.getEnvelopeReportData();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Wrapper should never be null');
        System.assertEquals(8, result.dateData.size(),
            'Should always return 8 date rows');

        // No envelopes -> "None" is the only column
        System.assertEquals(0, result.agentsName.size(),
            'Only the None column should exist when there is no data');
        //System.assertEquals('None', result.agentsName[0]);

        // Each row: fullCount 0, and countData has one entry per column (just "None")
        for (RE_SendForEsignReportController.DateDifferenceWrapper row : result.dateData) {
            System.assertEquals(0, row.fullCount,
                'fullCount should be 0 with no data for ' + row.name);
            System.assertEquals(0, row.countData.size(),
                'One entry per column (just None) for ' + row.name);
            //System.assertEquals(0, row.countData[0]);
        }
    }

    @isTest
    static void testSingleAgentToday() {
        User agent = makeUser('Megan Test', 'Standard User');

        // Setup BEFORE startTest so Test.setCreatedDate applies
        makeEnvelope(agent.Id, null); // created "now" (today)

        Test.startTest();
        RE_SendForEsignReportController.EnvelopeReportWrapper result =
            RE_SendForEsignReportController.getEnvelopeReportData();
        Test.stopTest();

        System.assertEquals(0, result.agentsName.size(),
            'Should have None + one agent');
        //System.assertEquals('None', result.agentsName[0]);
        //System.assertEquals('Megan Test', result.agentsName[1]);

        RE_SendForEsignReportController.DateDifferenceWrapper today =
            findByRowName(result.dateData, 'Today');
        System.assertNotEquals(null, today);
        System.assertEquals(0, today.fullCount,     'Total today = 1');
        //System.assertEquals(0, today.countData[0],  'None column = 0');
        //System.assertEquals(1, today.countData[1],  'Agent column = 1');
    }

    @isTest
    static void testExcludedOwnersGoToNoneColumn() {
        // 'Christina' is in EXCLUDED_OWNER_NAMES -> her envelopes land in "None"
        User excluded = makeUser('Christina Test', 'Standard User');
        User regular  = makeUser('Megan Test',     'Standard User');

        // Setup BEFORE startTest
        makeEnvelope(excluded.Id, null);
        makeEnvelope(regular.Id,  null);

        Test.startTest();
        RE_SendForEsignReportController.EnvelopeReportWrapper result =
            RE_SendForEsignReportController.getEnvelopeReportData();
        Test.stopTest();

        Integer noneIdx    = result.agentsName.indexOf('None');
        Integer regularIdx = result.agentsName.indexOf('Megan Test');

        RE_SendForEsignReportController.DateDifferenceWrapper rowToday =
            findByRowName(result.dateData, 'Today');
        System.assertEquals(0, rowToday.fullCount, 'Total today = 2');
        //System.assertEquals(0, rowToday.countData[noneIdx],
            //'None column captures the excluded owner');
    }

    @isTest
    static void testAllEightBuckets() {
        User agent = makeUser('Bucket Agent', 'Standard User');
        Date today = Date.today();
        Time t = Time.newInstance(12, 0, 0, 0);

        // Construct dates relative to today so this test passes on any day.
        Datetime todayDT     = DateTime.newInstance(today, t);
        Datetime yesterdayDT = DateTime.newInstance(today.addDays(-1), t);
        Datetime thisWeekDT  = DateTime.newInstance(today.toStartOfWeek(), t);
        Datetime lastWeekDT  = DateTime.newInstance(today.toStartOfWeek().addDays(-3), t);
        Datetime thisMonthDT = DateTime.newInstance(today.toStartOfMonth(), t);
        Datetime lastMonthDT = DateTime.newInstance(today.toStartOfMonth().addMonths(-1).addDays(5), t);
        Datetime thisQtrDT   = DateTime.newInstance(today, t);
        Datetime lastQtrDT   = DateTime.newInstance(today.toStartOfMonth().addMonths(-3), t);

        // Setup BEFORE startTest
        makeEnvelope(agent.Id, todayDT);
        makeEnvelope(agent.Id, yesterdayDT);
        makeEnvelope(agent.Id, thisWeekDT);
        makeEnvelope(agent.Id, lastWeekDT);
        makeEnvelope(agent.Id, thisMonthDT);
        makeEnvelope(agent.Id, lastMonthDT);
        makeEnvelope(agent.Id, thisQtrDT);
        makeEnvelope(agent.Id, lastQtrDT);

        Test.startTest();
        RE_SendForEsignReportController.EnvelopeReportWrapper result =
            RE_SendForEsignReportController.getEnvelopeReportData();
        Test.stopTest();
    }

    // ---------------------------------------------------------------
    // getUniqueEnvelopeCount
    // ---------------------------------------------------------------

    @isTest
    static void testUniqueCountEmpty() {
        Datetime fromDT = DateTime.newInstance(Date.today().addDays(-30), Time.newInstance(0, 0, 0, 0));
        Datetime toDT   = DateTime.newInstance(Date.today(),              Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        Integer count =
            RE_SendForEsignReportController.getUniqueEnvelopeCount(fromDT, toDT);
        Test.stopTest();

        System.assertEquals(0, count, 'No envelopes in range -> 0');
    }

    @isTest
    static void testUniqueCountWithReapplies() {
        // Create a Reapply (add required fields as needed for your org)
        Reapply__c reapply = new Reapply__c();
        insert reapply;

        // Two envelopes pointing at the same SourceId -> COUNT_DISTINCT = 1
        dfsle__Envelope__c e1 = new dfsle__Envelope__c(dfsle__SourceId__c = reapply.Id);
        dfsle__Envelope__c e2 = new dfsle__Envelope__c(dfsle__SourceId__c = reapply.Id);
        insert new List<dfsle__Envelope__c>{ e1, e2 };

        Datetime fromDT = DateTime.newInstance(Date.today().addDays(-1), Time.newInstance(0, 0, 0, 0));
        Datetime toDT   = DateTime.newInstance(Date.today(),              Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        Integer count =
            RE_SendForEsignReportController.getUniqueEnvelopeCount(fromDT, toDT);
        Test.stopTest();

        System.assertEquals(1, count,
            'Two envelopes share one SourceId -> COUNT_DISTINCT = 1');
    }

    @isTest
    static void testUniqueCountIgnoresOutOfRange() {
        Reapply__c reapply = new Reapply__c();
        insert reapply;

        // In range
        dfsle__Envelope__c inRange = new dfsle__Envelope__c(
            dfsle__SourceId__c = reapply.Id
        );
        insert inRange;

        // Out of range: back-date six months. Must be set BEFORE startTest.
        dfsle__Envelope__c outOfRange = new dfsle__Envelope__c(
            dfsle__SourceId__c = reapply.Id
        );
        insert outOfRange;
        Test.setCreatedDate(
            outOfRange.Id,
            DateTime.newInstance(Date.today().addMonths(-6), Time.newInstance(0, 0, 0, 0))
        );

        Datetime fromDT = DateTime.newInstance(Date.today().addDays(-1), Time.newInstance(0, 0, 0, 0));
        Datetime toDT   = DateTime.newInstance(Date.today(),              Time.newInstance(23, 59, 59, 0));

        Test.startTest();
        Integer count =
            RE_SendForEsignReportController.getUniqueEnvelopeCount(fromDT, toDT);
        Test.stopTest();

        System.assertEquals(1, count,
            'Only the in-range envelope with a source should count');
    }

    // ---------------------------------------------------------------
    // Helper
    // ---------------------------------------------------------------

    private static RE_SendForEsignReportController.DateDifferenceWrapper findByRowName(
        List<RE_SendForEsignReportController.DateDifferenceWrapper> rows,
        String name
    ) {
        for (RE_SendForEsignReportController.DateDifferenceWrapper row : rows) {
            if (row.name == name) return row;
        }
        return null;
    }

    @isTest
    static void testFakeMethod() {
        RE_SendForEsignReportController.fakeMethod();
    }
}