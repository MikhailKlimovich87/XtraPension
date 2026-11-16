@IsTest
private class XpMissingInfoAutoTest {

    private static final Datetime NOW = System.now();
    private static Integer keys = 0;
    private static Integer contacts = 0;

    /** A paid claim made 2 hours ago with the bank BIC missing (one item the email asks). */
    private static Basic__c claim(Map<String, Object> fields) {
        // A second contact in one test gets its own name and email (the org's duplicate rule refuses the same one).
        contacts++;
        String n = contacts == 1 ? '' : String.valueOf(contacts);
        Contact c = new Contact(FirstName = 'John' + n, LastName = 'Snow' + n, Email = 'john.snow' + n + '@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = c.Email;
        b.First_Name__c = c.FirstName;
        b.Last_Name__c = c.LastName;
        b.Status__c = 'Form In Progress';
        b.Bank_BIC__c = null;
        for (String f : fields.keySet()) b.put(f, fields.get(f));
        insert b;
        Test.setCreatedDate(b.Id, NOW.addHours(-2));
        return b;
    }

    private static Call_Log__c call(Id claimId, Integer endedMinutesAgo, Integer talkSeconds, String outcome) {
        keys++;
        Call_Log__c c = new Call_Log__c(
            Claim__c = claimId, Call_Key__c = 'test-' + keys + '|' + claimId, Nuacom_Call_Id__c = 'test-' + keys,
            Direction__c = 'Outbound', Outcome__c = outcome,
            Started_At__c = NOW.addMinutes(-endedMinutesAgo).addSeconds(-talkSeconds), Ended_At__c = NOW.addMinutes(-endedMinutesAgo),
            Talk_Seconds__c = talkSeconds
        );
        insert c;
        return c;
    }

    private static Integer asked(Id claimId) {
        String mark = '%' + BP_MissingInfo.SUBJECT_MARK + '%';
        return [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :claimId AND Subject LIKE :mark];
    }

    private static XpMissingInfoAuto.Outcome only(List<XpMissingInfoAuto.Outcome> outcomes) {
        System.assertEquals(1, outcomes.size(), JSON.serialize(outcomes));
        return outcomes[0];
    }

    @IsTest
    static void sendsTwentyMinutesAfterTheCallSignedByTheValidationAgent() {
        Basic__c b = claim(new Map<String, Object>{ 'Contact__c' => null, 'Validation_Agent__c' => 'Sean B' });
        call(b.Id, 25, 900, 'Answered');
        Test.startTest();
        XpMissingInfoAuto.Outcome o = only(XpMissingInfoAuto.run(NOW, true));
        Test.stopTest();
        System.assert(o.result.startsWith('sent to john.snow@example.com'), o.result);
        System.assert(o.items > 0, 'items asked');
        EmailMessage m = [SELECT Subject, HtmlBody, FromAddress FROM EmailMessage WHERE RelatedToId = :b.Id];
        System.assert(m.Subject.contains(BP_MissingInfo.SUBJECT_MARK), m.Subject);
        System.assertEquals(BP_MissingInfo.CLIENTS_EMAIL, m.FromAddress);
        System.assert(m.HtmlBody.contains('BIC (SWIFT) code'), 'the missing item is asked');
        String agent = [SELECT Validation_Agent_Name__c FROM Basic__c WHERE Id = :b.Id].Validation_Agent_Name__c;
        if (agent == 'Sean') System.assert(m.HtmlBody.contains('Kind regards,<br/>Sean<br/>'), 'signed by the validation agent');
    }

    @IsTest
    static void sendsOncePerCall() {
        Basic__c b = claim(new Map<String, Object>{ 'Contact__c' => null });
        call(b.Id, 25, 900, 'Answered');
        Test.startTest();
        XpMissingInfoAuto.run(NOW, true);
        XpMissingInfoAuto.Outcome second = only(XpMissingInfoAuto.run(NOW.addMinutes(15), true));
        Test.stopTest();
        System.assert(second.result.startsWith('skipped: already asked'), second.result);
        System.assertEquals(1, asked(b.Id));
    }

    @IsTest
    static void skipsWhenTheAgentAlreadyAskedThatDay() {
        Basic__c b = claim(new Map<String, Object>{ 'Contact__c' => null });
        insert new EmailMessage(RelatedToId = b.Id, Subject = BP_MissingInfo.subject([SELECT Name FROM Basic__c WHERE Id = :b.Id]),
            FromAddress = BP_MissingInfo.CLIENTS_EMAIL, ToAddress = 'john.snow@example.com', Incoming = false, Status = '3',
            MessageDate = NOW.addHours(-5), TextBody = 'manual');
        call(b.Id, 25, 900, 'Answered');
        XpMissingInfoAuto.Outcome o = only(XpMissingInfoAuto.run(NOW, true));
        System.assert(o.result.startsWith('skipped: already asked'), o.result);
        System.assertEquals(1, asked(b.Id), 'nothing new');
    }

    @IsTest
    static void aRequestOlderThanADayDoesNotStopIt() {
        Basic__c b = claim(new Map<String, Object>{ 'Contact__c' => null });
        Test.setCreatedDate(b.Id, NOW.addDays(-3));
        insert new EmailMessage(RelatedToId = b.Id, Subject = BP_MissingInfo.subject([SELECT Name FROM Basic__c WHERE Id = :b.Id]),
            FromAddress = BP_MissingInfo.CLIENTS_EMAIL, ToAddress = 'john.snow@example.com', Incoming = false, Status = '3',
            MessageDate = NOW.addDays(-2), TextBody = 'manual');
        call(b.Id, 25, 900, 'Answered');
        Test.startTest();
        XpMissingInfoAuto.Outcome o = only(XpMissingInfoAuto.run(NOW, true));
        Test.stopTest();
        System.assert(o.result.startsWith('sent to'), o.result);
        System.assertEquals(2, asked(b.Id));
    }

    @IsTest
    static void waitsTwentyMinutesAndIgnoresShortUnansweredAndOldCalls() {
        Basic__c b = claim(new Map<String, Object>{});
        call(b.Id, 10, 900, 'Answered');     // ended 10 min ago: too soon
        call(b.Id, 30, 120, 'Answered');     // 2 minutes: too short
        call(b.Id, 30, 900, 'No answer');    // not answered
        call(b.Id, 200, 900, 'Answered');    // ended over 3 hours ago (and before the claim existed)
        System.assertEquals(0, XpMissingInfoAuto.run(NOW, true).size());
        System.assertEquals(0, asked(b.Id));
    }

    @IsTest
    static void aCallBeforeTheClientPaidIsStillSales() {
        Basic__c b = claim(new Map<String, Object>{});
        Test.setCreatedDate(b.Id, NOW.addMinutes(-30));
        call(b.Id, 60, 900, 'Answered');     // ended 60 min ago, the claim was made 30 min ago
        System.assertEquals(0, XpMissingInfoAuto.run(NOW, true).size());
    }

    @IsTest
    static void nothingGoesPastPendingClientOrWithoutAnEmail() {
        Basic__c checked = claim(new Map<String, Object>{ 'Status__c' => 'Agent Check' });
        call(checked.Id, 25, 900, 'Answered');
        Basic__c noEmail = claim(new Map<String, Object>{});
        noEmail.Email__c = null;
        update noEmail;
        call(noEmail.Id, 25, 900, 'Answered');
        Map<Id, String> results = new Map<Id, String>();
        for (XpMissingInfoAuto.Outcome o : XpMissingInfoAuto.run(NOW, true)) results.put(o.claimId, o.result);
        System.assertEquals('skipped: status Agent Check', results.get(checked.Id));
        System.assertEquals('skipped: no client email', results.get(noEmail.Id));
        System.assertEquals(0, asked(checked.Id) + asked(noEmail.Id));
    }

    @IsTest
    static void previewSendsNothing() {
        Basic__c b = claim(new Map<String, Object>{});
        call(b.Id, 25, 900, 'Answered');
        XpMissingInfoAuto.Outcome o = only(XpMissingInfoAuto.run(NOW, false));
        System.assertEquals('would send', o.result);
        System.assertEquals(0, asked(b.Id));
        System.assertEquals(0, Limits.getEmailInvocations());
        System.assertNotEquals(null, XpMissingInfoAuto.preview());
    }

    @IsTest
    static void withAContactTheEmailGoesThroughSalesforce() {
        Basic__c b = claim(new Map<String, Object>{ 'Friend_Email__c' => 'ann@example.com' });
        call(b.Id, 25, 900, 'Answered');
        Test.startTest();
        XpMissingInfoAuto.Outcome o = only(XpMissingInfoAuto.run(NOW, true));
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();
        System.assert(o.result.startsWith('sent to'), o.result);
        System.assertEquals(1, invocations);
    }

    @IsTest
    static void helperNotGivenStaysOutLikeInThePanel() {
        Basic__c b = claim(new Map<String, Object>{ 'Wants_Helper__c' => 'No' });
        List<BP_MissingInfo.Item> all = BP_MissingInfo.clientItems(BP_MissingInfo.check(BP_MissingInfo.load(b.Id)));
        for (BP_MissingInfo.Item i : XpMissingInfoAuto.startTicked(all)) System.assertNotEquals(false, i.askByDefault);
        Integer unticked = 0;
        for (BP_MissingInfo.Item i : all) if (i.askByDefault == false) unticked++;
        System.assertEquals(all.size() - unticked, XpMissingInfoAuto.startTicked(all).size());
    }

    @IsTest
    static void senderIsTheFirstName() {
        System.assertEquals('Sean', XpMissingInfoAuto.sender('Sean'));
        System.assertEquals('Ciara', XpMissingInfoAuto.sender(' Ciara Walsh '));
        System.assertEquals('The XtraPension team', XpMissingInfoAuto.sender(null));
    }

    @IsTest
    static void fourJobsEveryFifteenMinutes() {
        Test.startTest();
        List<Id> ids = XpMissingInfoAuto.schedule();
        Test.stopTest();
        System.assertEquals(4, ids.size());
        String name = XpMissingInfoAuto.JOB_PREFIX + '%';
        System.assertEquals(4, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :name]);
        System.assertEquals(4, XpMissingInfoAuto.unschedule());
    }

    @IsTest
    static void theJobRuns() {
        Test.startTest();
        System.schedule(XpMissingInfoAuto.JOB_PREFIX + ' test', '0 0 * * * ?', new XpMissingInfoAuto());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = :(XpMissingInfoAuto.JOB_PREFIX + ' test')]);
    }
}