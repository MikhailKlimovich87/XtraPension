@IsTest
private class LastContactServiceTest {

    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1].Id;
        TestDataFactory.createApplication(contactId, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
        BP_TestDataFactory.createBasic(contactId, true);
    }

    static Id appId() { return [SELECT Id FROM Application__c LIMIT 1].Id; }
    static Id claimId() { return [SELECT Id FROM Basic__c LIMIT 1].Id; }

    static Application__c app() {
        return [SELECT Contact_Type__c, Who__c, Date_Since_Contact__c, Last_Contact_Date__c, Last_Contact_At__c FROM Application__c LIMIT 1];
    }
    static Basic__c claim() {
        return [SELECT Contact_Type__c, Who__c, Date_Since_Contact__c, Last_Contact_Date__c, Last_Contact_At__c FROM Basic__c LIMIT 1];
    }

    /** A Senior Agent (the profile the four fields are read-only for). Inserted as the running user: no mixed DML. */
    static User agent(String first, String last) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Senior Agent' LIMIT 1];
        String key = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            FirstName = first, LastName = last, Alias = ('lc' + key).left(8), Email = 'lastcontact' + key + '@example.com',
            Username = 'lastcontact.' + key + '@example.com.xptest', ProfileId = p.Id, TimeZoneSidKey = 'Europe/Dublin',
            LocaleSidKey = 'en_IE_EURO', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        System.runAs(new User(Id = UserInfo.getUserId())) { insert u; }
        return u;
    }

    static Call_Log__c call(Id recordId, String key, Datetime at, String dir, String outcome, String agentName) {
        Boolean isClaim = recordId.getSObjectType() == Basic__c.SObjectType;
        return new Call_Log__c(
            Application__c = isClaim ? null : recordId, Claim__c = isClaim ? recordId : null,
            Call_Key__c = key + '|' + recordId, Nuacom_Call_Id__c = key,
            Started_At__c = at, Ended_At__c = at.addMinutes(3), Direction__c = dir, Outcome__c = outcome,
            Agent_Name__c = agentName, Customer_Number__c = '+353870000000', Matched_On__c = 'Client phone');
    }

    static EmailMessage email(Id recordId, String toAddress, String status) {
        return new EmailMessage(
            RelatedToId = recordId, Incoming = false, Status = status, Subject = 'Your application',
            TextBody = 'Hello', FromAddress = 'clients@xtrapension.com', ToAddress = toAddress, MessageDate = Datetime.now());
    }

    static LastContactService.ContactEvent ev(Id recordId, String type, String person, Datetime at) {
        return new LastContactService.ContactEvent(recordId, type, person, at);
    }

    // ------------------------------------------------------------------ rules

    @IsTest
    static void mapsCallsToContactTypes() {
        System.assertEquals('Phone Chat', LastContactService.typeForCall('Outbound', 'Answered', 300, null), 'long enough to be a conversation');
        System.assertEquals('Phone Chat', LastContactService.typeForCall('Inbound', 'Answered', 20, null), 'the client rang us');
        System.assertEquals('No Answer', LastContactService.typeForCall('Outbound', 'No answer', 0, null));
        System.assertEquals('No Answer', LastContactService.typeForCall('Outbound', 'Busy', 0, null));
        System.assertEquals('No Answer', LastContactService.typeForCall('Outbound', 'Failed', 0, 'No conversation'));
        System.assertEquals(null, LastContactService.typeForCall('Inbound', 'Missed', 0, null), 'a missed call is not a contact');
        System.assertEquals(null, LastContactService.typeForCall('Inbound', 'No answer', 0, null));
        System.assertEquals(null, LastContactService.typeForCall('Outbound', 'Answered', 30, null), 'it may be a voicemail: wait for the flow');
        System.assertEquals('Phone Chat', LastContactService.typeForCall('Outbound', 'Answered', 30, 'Conversation'));
        System.assertEquals('V/Mail Left', LastContactService.typeForCall('Outbound', 'Answered', 30, 'Voicemail left'));
        System.assertEquals('No Answer', LastContactService.typeForCall('Outbound', 'Answered', 30, 'Voicemail, no message'));
        System.assertEquals('No Answer', LastContactService.typeForCall('Outbound', 'Answered', 30, 'No conversation'));
        System.assertEquals('V/Mail Left', LastContactService.typeForCall('Outbound', 'Answered', 20, 'Not checked'), 'no recording to read');
        System.assertEquals('Phone Chat', LastContactService.typeForCall('Outbound', 'Answered', 50, 'Not checked'));
    }

    @IsTest
    static void aShortCallCountsOnceItHasBeenRead() {
        Id a = appId();
        Id fakeId = Id.valueOf(Call_Log__c.SObjectType.getDescribe().getKeyPrefix() + '000000000002');
        Datetime t = Datetime.now().addMinutes(-30);
        Call_Log__c first = call(a, 'svr-9.1', t, 'Outbound', 'Answered', 'Ciara');
        first.Id = fakeId;
        first.Talk_Seconds__c = 30;
        System.assertEquals(0, LastContactService.eventsFromCalls(new List<Call_Log__c>{ first }, null).size(), 'it may be a voicemail');

        Call_Log__c read = first.clone(true, true);
        read.Call_Check__c = 'Voicemail left';
        LastContactService.apply(LastContactService.eventsFromCalls(new List<Call_Log__c>{ read }, new Map<Id, Call_Log__c>{ fakeId => first }));
        Application__c x = app();
        System.assertEquals('V/Mail Left', x.Contact_Type__c);
        System.assertEquals('Ciara', x.Who__c);

        Call_Log__c corrected = read.clone(true, true);
        corrected.Call_Check__c = 'No conversation';
        LastContactService.apply(LastContactService.eventsFromCalls(new List<Call_Log__c>{ corrected }, new Map<Id, Call_Log__c>{ fakeId => read }));
        System.assertEquals('No Answer', app().Contact_Type__c, 'the same call, read again: a record labelled before the flow gets corrected');
    }

    @IsTest
    static void findsThePersonInTheList() {
        Map<String, String> values = new Map<String, String>();
        for (String v : new List<String>{ 'Becky', 'Sean Byrne', 'Sean Bedford', 'Tomas', 'MaryClaire', 'Old Sales Acct (Megan/Tomas/Sean)' }) values.put(LastContactService.normalize(v), v);
        System.assertEquals('Sean Byrne', LastContactService.whoValue('Sean Byrne', values), 'full name first');
        System.assertEquals('Sean Bedford', LastContactService.whoValue('Sean Bedford', values));
        System.assertEquals('Sean Bedford', LastContactService.whoValue('Sean', values), 'the Nuacom "Sean" extension');
        System.assertEquals('Old Sales Acct (Megan/Tomas/Sean)', LastContactService.whoValue('Sales XtraPension', values), 'the old shared sales@ user');
        System.assertEquals('Becky', LastContactService.whoValue('Becky McAllister', values), 'then the first name');
        System.assertEquals('Tomas', LastContactService.whoValue('Tomás Coleman', values), 'accents do not count');
        System.assertEquals('MaryClaire', LastContactService.whoValue('  maryclaire   Mchatton ', values), 'nor case and spaces');
        System.assertEquals(null, LastContactService.whoValue('Zelda Nobody', values), 'not in the list');
        System.assertEquals(null, LastContactService.whoValue(' ', values));
        System.assertEquals(null, LastContactService.whoValue(null, values));
    }

    @IsTest
    static void onlyANewerEventWins() {
        Datetime t = Datetime.newInstanceGmt(2026, 10, 20, 10, 0, 0);
        Date day = LastContactService.dayOf(t);
        LastContactService.ContactEvent e = ev(appId(), 'Phone Chat', 'Breege', t);
        System.assert(LastContactService.wins(e, null, null, null), 'nothing there yet');
        System.assert(LastContactService.wins(e, null, day, 'Phone Chat'), 'same day as the date typed by hand');
        System.assert(!LastContactService.wins(e, null, day, 'Wapp Sent'), 'a WhatsApp typed by hand stays on its day');
        System.assert(!LastContactService.wins(e, null, day, 'SMS Sent'), 'an SMS typed by hand stays on its day');
        System.assert(LastContactService.wins(e, null, day.addDays(-1), 'Wapp Sent'), 'but not on a later day');
        System.assert(!LastContactService.wins(e, null, day.addDays(1), null), 'the date typed by hand is later');
        System.assert(LastContactService.wins(e, t.addMinutes(-1), day.addDays(5), null), 'with Last Contact At set, the time decides');
        System.assert(!LastContactService.wins(e, t, null, null), 'the same time is not newer');
        e.sameEventAgain = true;
        System.assert(LastContactService.wins(e, t, null, null), 'unless it is the same call saved again');
        System.assert(!LastContactService.wins(e, t.addMinutes(1), null, null));
        e.manual = true;
        System.assert(LastContactService.wins(e, t.addDays(1), null, null), 'a button always wins');
        System.assertEquals(Date.newInstance(2026, 10, 21), LastContactService.dayOf(Datetime.newInstanceGmt(2026, 10, 20, 23, 30, 0)), 'Irish day (summer time)');
    }

    @IsTest
    static void newestEventOfEachRecord() {
        Id a = appId();
        Datetime t = Datetime.now().addDays(-1);
        List<LastContactService.ContactEvent> events = new List<LastContactService.ContactEvent>{
            ev(a, 'Phone Chat', 'Breege', t), ev(a, 'Email Sent', 'Becky', t.addHours(1)), ev(a, 'V/Mail Left', 'Ciara', t.addMinutes(30)),
            ev(UserInfo.getUserId(), 'Phone Chat', 'Breege', t), ev(a, null, 'Breege', t.addHours(2)), null
        };
        Map<Id, LastContactService.ContactEvent> newest = LastContactService.newestByRecord(events);
        System.assertEquals(1, newest.size(), 'only Applications and Claims, only complete events');
        System.assertEquals('Becky', newest.get(a).person);
    }

    // ------------------------------------------------------------------ calls

    @IsTest
    static void callsUpdateTheApplicationAndTheClaim() {
        Id a = appId();
        Id c = claimId();
        Datetime base = Datetime.now().addDays(-2);
        Test.startTest();
        insert new List<Call_Log__c>{
            call(a, 'svr-1.1', base, 'Outbound', 'Answered', 'Breege'),
            call(a, 'svr-2.1', base.addHours(1), 'Outbound', 'No answer', 'Sean'),
            call(a, 'svr-3.1', base.addHours(2), 'Inbound', 'Missed', null),
            call(c, 'svr-4.1', base.addHours(3), 'Inbound', 'Answered', 'Tomás Coleman')
        };
        Test.stopTest();

        Application__c x = app();
        System.assertEquals('No Answer', x.Contact_Type__c, 'the newest call that counts; the missed one does not');
        System.assertEquals('Sean Bedford', x.Who__c);
        System.assertEquals(LastContactService.dayOf(base.addHours(1)), x.Date_Since_Contact__c, 'the day of the call, not today');
        System.assertEquals(x.Date_Since_Contact__c, x.Last_Contact_Date__c);
        System.assertEquals(base.addHours(1).getTime() / 1000, x.Last_Contact_At__c.getTime() / 1000);

        Basic__c y = claim();
        System.assertEquals('Phone Chat', y.Contact_Type__c);
        System.assertEquals('Tomas', y.Who__c);
        System.assertEquals(LastContactService.dayOf(base.addHours(3)), y.Date_Since_Contact__c);
    }

    @IsTest
    static void anOlderCallChangesNothing() {
        Id a = appId();
        Datetime last = Datetime.now().addHours(-1);
        update new Application__c(Id = a, Contact_Type__c = 'Email Sent', Who__c = 'Becky', Date_Since_Contact__c = Date.today(), Last_Contact_At__c = last);
        Test.startTest();
        insert call(a, 'svr-5.1', last.addHours(-5), 'Outbound', 'Answered', 'Breege');
        Test.stopTest();
        Application__c x = app();
        System.assertEquals('Email Sent', x.Contact_Type__c);
        System.assertEquals('Becky', x.Who__c);
        System.assertEquals(last.getTime() / 1000, x.Last_Contact_At__c.getTime() / 1000);
    }

    @IsTest
    static void aCallSavedAgainWithAnotherOutcome() {
        Id a = appId();
        Id fakeId = Id.valueOf(Call_Log__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Datetime t = Datetime.now().addMinutes(-30);
        Call_Log__c first = call(a, 'svr-6.1', t, 'Outbound', 'No answer', 'Ciara');
        first.Id = fakeId;
        LastContactService.apply(LastContactService.eventsFromCalls(new List<Call_Log__c>{ first }, null));
        System.assertEquals('No Answer', app().Contact_Type__c);

        Call_Log__c same = first.clone(true, true);
        System.assertEquals(0, LastContactService.eventsFromCalls(new List<Call_Log__c>{ same }, new Map<Id, Call_Log__c>{ fakeId => first }).size(), 'saved again unchanged: nothing to do');

        Call_Log__c answered = first.clone(true, true);
        answered.Outcome__c = 'Answered';
        LastContactService.Result r = LastContactService.apply(LastContactService.eventsFromCalls(new List<Call_Log__c>{ answered }, new Map<Id, Call_Log__c>{ fakeId => first }));
        System.assertEquals(1, r.applied);
        System.assertEquals('Phone Chat', app().Contact_Type__c, 'the motor corrected the outcome');
    }

    @IsTest
    static void aDateTypedByHandStillCounts() {
        Id a = appId();
        update new Application__c(Id = a, Date_Since_Contact__c = Date.today());
        LastContactService.Result r = LastContactService.apply(new List<LastContactService.ContactEvent>{ ev(a, 'Phone Chat', 'Breege', Datetime.now().addDays(-3)) });
        System.assertEquals(1, r.older, 'older than the date typed by hand');
        System.assertEquals(null, app().Contact_Type__c);
        r = LastContactService.apply(new List<LastContactService.ContactEvent>{ ev(a, 'Phone Chat', 'Breege', Datetime.now()) });
        System.assertEquals(1, r.applied);
        System.assertEquals('Breege', app().Who__c);
    }

    // ----------------------------------------------------------------- emails

    @IsTest
    static void anEmailFromAPersonCounts() {
        Id a = appId();
        User megan = agent('Megan', 'Lctest');
        // Applied in a Queueable (never inside the agent's email send): stopTest runs it.
        Test.startTest();
        System.runAs(megan) { insert email(a, 'client@example.com', '3'); }
        Test.stopTest();
        Application__c x = app();
        System.assertEquals('Email Sent', x.Contact_Type__c);
        System.assertEquals('Megan', x.Who__c, 'first name: Megan Lctest');
        System.assertEquals(Date.today(), x.Date_Since_Contact__c);
        System.assertNotEquals(null, x.Last_Contact_At__c);
    }

    @IsTest
    static void draftsColleaguesAndAutomationsDoNotCount() {
        Id a = appId();
        User hannah = agent('Hannah', 'Lctest');
        System.runAs(hannah) {
            insert new List<EmailMessage>{
                email(a, 'client@example.com', '5'),
                email(a, 'Breege <breege@xtrapension.com>; grace@xtrapension.com', '3')
            };
            EmailMessage fromClient = email(a, 'clients@xtrapension.com', '3');
            fromClient.Incoming = true;
            insert fromClient;
        }
        System.assertEquals(null, app().Contact_Type__c, 'a draft, a note to colleagues, an email from the client');

        System.assert(LastContactService.onlyInternal('breege@xtrapension.com', null, 'Grace <GRACE@XtraPension.com>'));
        System.assert(!LastContactService.onlyInternal('breege@xtrapension.com', 'client@example.com', null));
        System.assert(!LastContactService.onlyInternal(null, ' ', null), 'no address at all: counts');
        System.assert(LastContactService.isPerson('Standard', 'becky@xtrapension.com'));
        System.assert(!LastContactService.isPerson('Standard', 'JR@xtrapension.com'), 'the automations server');
        System.assert(!LastContactService.isPerson('Standard', 'xtrapension.admin@xtrapension.com'), 'the scheduled jobs');
        System.assert(!LastContactService.isPerson('Guest', 'stripe_webhooks@example.com'), 'a site guest (Stripe)');
    }

    @IsTest
    static void aDraftCountsWhenItIsSent() {
        Id a = appId();
        Id msgId = Id.valueOf(EmailMessage.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        String payload = '{"attributes":{"type":"EmailMessage"},"Id":"' + msgId + '","RelatedToId":"' + a + '","Incoming":false,"Status":"3",'
            + '"ToAddress":"client@example.com","CreatedById":"' + agent('Vince', 'Lctest').Id + '","MessageDate":"' + Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') + '"}';
        EmailMessage sent = (EmailMessage) System.JSON.deserialize(payload, EmailMessage.class);
        EmailMessage draft = sent.clone(true, true);
        draft.Status = '5';
        EmailMessage stillSent = sent.clone(true, true);
        System.assertEquals(1, LastContactService.eventsFromEmails(new List<EmailMessage>{ sent }, new Map<Id, EmailMessage>{ msgId => draft }).size());
        System.assertEquals(0, LastContactService.eventsFromEmails(new List<EmailMessage>{ sent }, new Map<Id, EmailMessage>{ msgId => stillSent }).size(), 'already counted when it was sent');
        System.assertEquals('Vince', LastContactService.apply(LastContactService.eventsFromEmails(new List<EmailMessage>{ sent }, null)).who.get(a));
    }

    @IsTest
    static void aFullTransactionWaitsInTheQueue() {
        Id a = appId();
        User megan = agent('Megan', 'Lctest');
        LastContactService.noRoomForTest = true;
        Test.startTest();
        System.runAs(megan) { insert email(a, 'client@example.com', '3'); }
        System.assertEquals(null, app().Contact_Type__c, 'not yet: queued');
        Test.stopTest();
        System.assertEquals('Email Sent', app().Contact_Type__c);
    }

    // --------------------------------------------------------------- WhatsApp

    @IsTest
    static void aWhatsAppFromTheInboxCountsAndTheNewestWins() {
        Id a = appId();
        LastContactRest.Item newest = new LastContactRest.Item();
        newest.recordId = a;
        newest.person = 'Monica XtraPension';
        newest.sentAt = Datetime.now().addMinutes(-5);
        LastContactRest.Item older = new LastContactRest.Item();
        older.recordId = a;
        older.person = 'Becky McAllister';
        older.sentAt = Datetime.now().addHours(-1);
        LastContactRest.Answer r = LastContactRest.report(new List<LastContactRest.Item>{ newest, older });
        System.assertEquals(1, r.applied);
        System.assertEquals(0, r.failed);
        Application__c x = app();
        System.assertEquals('Wapp Sent', x.Contact_Type__c);
        System.assertEquals('Monica', x.Who__c);
        System.assertEquals(newest.sentAt, x.Last_Contact_At__c);

        LastContactRest.Answer again = LastContactRest.report(new List<LastContactRest.Item>{ older });
        System.assertEquals(1, again.older, 'older than what is there');
        System.assertEquals(0, LastContactRest.report(null).applied);
    }

    @IsTest
    static void aPanelSendStampsTheUserAndNow() {
        Id a = appId();
        Id c = claimId();
        User vince = agent('Vince', 'Lctest');
        System.runAs(vince) {
            LastContactController.whatsAppSent(a);
            LastContactController.whatsAppSent(c);
        }
        Application__c x = app();
        System.assertEquals('Wapp Sent', x.Contact_Type__c);
        System.assertEquals('Vince', x.Who__c);
        System.assertEquals(Date.today(), x.Date_Since_Contact__c);
        System.assertEquals(Date.today(), x.Last_Contact_Date__c);
        Basic__c y = claim();
        System.assertEquals('Wapp Sent', y.Contact_Type__c);
        System.assertEquals('Vince', y.Who__c);
    }

    @IsTest
    static void someoneNotInTheListLeavesWhoEmpty() {
        Id a = appId();
        update new Application__c(Id = a, Who__c = 'Becky', Contact_Type__c = 'Phone Chat');
        User zelda = agent('Zelda', 'Nobody');
        System.runAs(zelda) { LastContactController.whatsAppSent(a); }
        Application__c x = app();
        System.assertEquals('Wapp Sent', x.Contact_Type__c);
        System.assertEquals(null, x.Who__c, 'never someone else next to the new date');
    }

    @IsTest
    static void aPanelSendOnAnythingElseChangesNothing() {
        LastContactController.whatsAppSent(UserInfo.getUserId());
        LastContactController.whatsAppSent(null);
        LastContactController.whatsAppSent(Id.valueOf(Application__c.SObjectType.getDescribe().getKeyPrefix() + '000000000009'));
        System.assertEquals(null, app().Contact_Type__c);
    }

    @IsTest
    static void aRecordThatCannotBeSavedNeverThrows() {
        Id a = appId();
        // A value the restricted picklist refuses: the update fails the way a validation rule or a lock would.
        LastContactService.whoForTest = 'Not In The List';
        LastContactService.Result r = LastContactService.apply(new List<LastContactService.ContactEvent>{ ev(a, 'Phone Chat', 'Breege', Datetime.now()) });
        System.assertEquals(0, r.applied);
        System.assertEquals(1, r.failures.size());

        User megan = agent('Megan', 'Lctest');
        System.runAs(megan) { insert email(a, 'client@example.com', '3'); }
        System.assertEquals(1, [SELECT COUNT() FROM EmailMessage WHERE RelatedToId = :a AND CreatedById = :megan.Id], 'the email is saved all the same');
        System.assertEquals(null, app().Contact_Type__c);

        System.runAs(megan) { LastContactController.whatsAppSent(a); }
        System.assertEquals(null, app().Contact_Type__c, 'the message went out all the same');
    }
}