@IsTest
private class XpCallHistoryControllerTest {

    @TestSetup
    static void makeData() {
        // The controller runs in user mode: without the permission set the new fields are invisible even to an admin.
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'XP_Call_History'];
        User me = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(me) {
            if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :me.Id AND PermissionSetId = :ps.Id] == 0) {
                insert new PermissionSetAssignment(AssigneeId = me.Id, PermissionSetId = ps.Id);
            }
        }
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Id contactId = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1].Id;
        TestDataFactory.createApplication(contactId, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    // Permissions given in the setup only apply inside runAs.
    private static User me() {
        return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    }

    private static String myFirstName() {
        return UserInfo.getName().trim().split('\\s+')[0];
    }

    private static Call_Log__c call(Id appId, String key, Datetime at, String dir, String outcome, Integer talk) {
        return new Call_Log__c(
            Application__c = appId, Call_Key__c = key + '|' + appId, Nuacom_Call_Id__c = key,
            Started_At__c = at, Ended_At__c = at.addSeconds(talk + 20), Direction__c = dir, Outcome__c = outcome,
            Talk_Seconds__c = talk, Total_Seconds__c = talk + 20, Agent_Name__c = outcome == 'Missed' ? null : myFirstName(),
            Customer_Number__c = '+353870000000', Matched_On__c = 'Client phone', Has_Recording__c = talk > 0,
            Recording_URL__c = talk > 0 ? 'https://automations.xtrapension.com/c/0123456789abcdef0123456789abcdef' : null);
    }

    private class XpAiMock implements HttpCalloutMock {
        final Integer status;
        final String body;
        public String sent;
        XpAiMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            sent = req.getBody();
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    @IsTest
    static void transcribeAsksXpAiOnce() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Call_Log__c c = call(appId, 'svr16-core6-7.1', Datetime.now().addHours(-1), 'Outbound', 'Answered', 120);
        insert c;
        XpAiMock mock = new XpAiMock(202, '{"status":"started"}');
        Test.setMock(HttpCalloutMock.class, mock);
        System.runAs(me()) {
            Test.startTest();
            System.assertEquals('transcribing', XpCallHistoryController.requestTranscript(c.Id));
            Test.stopTest();
        }
        System.assert(mock.sent.contains('svr16-core6-7.1'), mock.sent);
        Call_Log__c after = [SELECT Transcript_Requested_By__c, Transcript_Status__c FROM Call_Log__c WHERE Id = :c.Id];
        System.assertEquals(UserInfo.getUserId(), after.Transcript_Requested_By__c);
        System.assertEquals(XpCallTranscriptService.TRANSCRIBING, after.Transcript_Status__c);

        mock.sent = null;
        System.runAs(me()) {
            System.assertEquals('transcribing', XpCallHistoryController.requestTranscript(c.Id));
            XpCallHistoryController.History h = XpCallHistoryController.getHistory(appId);
            System.assertEquals(true, h.calls[0].transcribing);
        }
        System.assertEquals(null, mock.sent, 'a second click does not transcribe it twice');
    }

    @IsTest
    static void theEmailComesWithXpAisPdfWhenTheTranscriptLands() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Call_Log__c c = call(appId, 'svr16-core6-8.1', Datetime.now().addHours(-1), 'Outbound', 'Answered', 120);
        c.Transcript_Requested_By__c = UserInfo.getUserId();
        c.Transcript_Status__c = XpCallTranscriptService.TRANSCRIBING;
        insert c;
        XpAiMock mock = new XpAiMock(200, '{"pdf":"JVBERi0xLjQ="}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        update new Call_Log__c(Id = c.Id, Transcript__c = '[00:00] Speaker A: Hello', Transcript_Summary__c = 'Spoke.');
        Test.stopTest();
        System.assertEquals(1, XpCallTranscriptService.emailsSent);
        System.assert(mock.sent.contains('Speaker A'), mock.sent);

        update new Call_Log__c(Id = c.Id, Transcript_Summary__c = 'Spoke again.');
        System.assertEquals(1, XpCallTranscriptService.emailsSent, 'saved again: no second email');
    }

    @IsTest
    static void aTranscriptOnTheCallGoesByEmailAtOnce() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Call_Log__c c = call(appId, 'svr16-core6-9.1', Datetime.now().addHours(-1), 'Inbound', 'Answered', 60);
        c.Transcript__c = '[00:00] Speaker A: Hello';
        insert c;
        Test.setMock(HttpCalloutMock.class, new XpAiMock(200, '{"pdf":"JVBERi0xLjQ="}'));
        System.runAs(me()) {
            Test.startTest();
            System.assertEquals('emailed', XpCallHistoryController.requestTranscript(c.Id));
            Test.stopTest();
        }
        System.assertEquals(1, XpCallTranscriptService.emailsSent);
    }

    @IsTest
    static void withoutThePdfTheTranscriptGoesInTheEmail() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Call_Log__c c = call(appId, 'svr16-core6-13.1', Datetime.now().addHours(-1), 'Inbound', 'Answered', 60);
        c.Transcript__c = '[00:00] Speaker A: Hello';
        insert c;
        Test.setMock(HttpCalloutMock.class, new XpAiMock(500, '{"error":"down"}'));
        Test.startTest();
        XpCallTranscriptService.emailTranscript(c.Id, UserInfo.getUserId());
        Test.stopTest();
        System.assertEquals(1, XpCallTranscriptService.emailsSent);

        String html = XpCallTranscriptService.transcriptHtml(new Call_Log__c(Transcript__c = '[00:00] Speaker A: 5 < 6 & more\nNo speaker here'));
        System.assert(html.contains('[00:00]</span> <b>Speaker A:</b> 5 &lt; 6 &amp; more</p>'), html);
        System.assert(html.contains('>No speaker here</p>'), html);
    }

    @IsTest
    static void aVoicemailIsNotSpeakingToTheClient() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Datetime now = Datetime.now();
        Call_Log__c talked = call(appId, 'svr16-core6-14.1', now.addHours(-5), 'Outbound', 'Answered', 300);
        Call_Log__c voicemail = call(appId, 'svr16-core6-15.1', now.addHours(-1), 'Outbound', 'Answered', 30);
        voicemail.Call_Check__c = 'Voicemail left';
        insert new List<Call_Log__c>{ talked, voicemail };
        System.runAs(me()) {
            XpCallHistoryController.History h = XpCallHistoryController.getHistory(appId);
            System.assertEquals(1, h.answered);
            System.assertEquals(1, h.notReached);
            System.assertEquals(300, h.lastTalkSeconds, 'the last time someone spoke to the client');
            System.assertEquals(1, h.triesSinceTalk);
            System.assertEquals(false, h.calls[0].spoke);
            System.assertEquals('Voicemail left', h.calls[0].check);
            System.assertEquals(true, h.calls[1].spoke);
        }
    }

    @IsTest
    static void aFailureTellsWhoAsked() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Call_Log__c c = call(appId, 'svr16-core6-9.1', Datetime.now().addHours(-1), 'Outbound', 'Answered', 60);
        c.Transcript_Requested_By__c = UserInfo.getUserId();
        c.Transcript_Status__c = XpCallTranscriptService.TRANSCRIBING;
        insert c;
        update new Call_Log__c(Id = c.Id, Transcript_Status__c = XpCallTranscriptService.FAILED_PREFIX + 'No recording.');
        System.assertEquals(1, XpCallTranscriptService.emailsSent);
        System.runAs(me()) {
            XpCallHistoryController.History h = XpCallHistoryController.getHistory(appId);
            System.assertEquals('No recording.', h.calls[0].transcriptProblem);
            System.assertEquals(false, h.calls[0].transcribing);
        }
    }

    @IsTest
    static void transcribeRefusesWhatItCannotDo() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Call_Log__c noAudio = call(appId, 'svr16-core6-10.1', Datetime.now().addHours(-1), 'Outbound', 'No answer', 0);
        Call_Log__c full = call(appId, 'svr16-core6-11.1', Datetime.now().addHours(-2), 'Outbound', 'Answered', 60);
        insert new List<Call_Log__c>{ noAudio, full };
        Test.setMock(HttpCalloutMock.class, new XpAiMock(429, '{"error":"The daily limit has been reached."}'));
        Integer refused = 0;
        System.runAs(me()) {
            Test.startTest();
            for (Id callLog : new List<Id>{ noAudio.Id, full.Id, UserInfo.getUserId() }) {
                try {
                    XpCallHistoryController.requestTranscript(callLog);
                } catch (AuraHandledException e) {
                    refused++;
                }
            }
            Test.stopTest();
        }
        System.assertEquals(3, refused);
        System.assertEquals(null, [SELECT Transcript_Status__c FROM Call_Log__c WHERE Id = :full.Id].Transcript_Status__c);
    }

    @IsTest
    static void buildsTheHistoryOfAnApplication() {
        Id appId = [SELECT Id FROM Application__c LIMIT 1].Id;
        Datetime now = Datetime.now();
        Datetime spoke = now.addHours(-3);
        Call_Log__c talked = call(appId, 'svr16-core6-1.1', spoke, 'Outbound', 'Answered', 300);
        talked.Transcript__c = '[00:00] Speaker A: Hello';
        talked.Transcript_Summary__c = 'Spoke about the reapply.';
        insert new List<Call_Log__c>{
            talked,
            call(appId, 'svr16-core6-2.1', now.addHours(-2), 'Outbound', 'No answer', 0),
            call(appId, 'svr16-core6-3.1', now.addHours(-1), 'Inbound', 'Missed', 15)
        };
        Task aboutTheCall = new Task(WhatId = appId, Subject = 'Spoke about the reapply', TaskSubtype = 'Call', Status = 'Completed');
        Task onItsOwn = new Task(WhatId = appId, Subject = 'Called from my mobile', TaskSubtype = 'Call', Status = 'Completed');
        insert new List<Task>{ aboutTheCall, onItsOwn };
        Test.setCreatedDate(aboutTheCall.Id, spoke.addMinutes(10));
        Test.setCreatedDate(onItsOwn.Id, now.addDays(-3));

        XpCallHistoryController.History h;
        Test.startTest();
        System.runAs(me()) { h = XpCallHistoryController.getHistory(appId); }
        Test.stopTest();

        System.assertEquals([SELECT Name FROM Application__c WHERE Id = :appId].Name, h.recordName);
        System.assertEquals(3, h.total);
        System.assertEquals(1, h.answered);
        System.assertEquals(1, h.missed);
        System.assertEquals(1, h.notReached);
        System.assertEquals(2, h.outbound);
        System.assertEquals(1, h.inbound);
        System.assertEquals(300, h.talkSeconds);
        System.assertEquals(1, h.triesSinceTalk, 'one outbound try after the last conversation');
        System.assertEquals(1, h.missedSinceTalk, 'the client rang once and nobody answered');
        System.assertEquals(myFirstName(), h.lastTalkAgent);
        System.assertEquals(3, h.calls.size());
        System.assertEquals('Missed', h.calls[0].outcome, 'newest first');
        System.assertEquals(1, h.calls[2].notes.size(), 'the note goes under the call it is about');
        System.assertEquals('Spoke about the reapply', h.calls[2].notes[0].subject);
        System.assertEquals(1, h.loneNotes.size(), 'a note with no call stays on its own');
        System.assert(h.calls[2].hasRecording);
        System.assert(h.calls[2].hasTranscript, 'the transcript comes with the call');
        System.assertEquals('Spoke about the reapply.', h.calls[2].transcriptSummary);
        System.assert(!h.calls[0].hasTranscript);
        System.assert(!h.truncated);
    }

    @IsTest
    static void aClaimWithNoCallsIsEmpty() {
        Id claimId = Id.valueOf(Basic__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        XpCallHistoryController.History h;
        System.runAs(me()) { h = XpCallHistoryController.getHistory(claimId); }
        System.assertEquals(0, h.total);
        System.assertEquals(0, h.calls.size());
        System.assertEquals(null, h.recordName, 'no such claim');
        System.assertEquals('Claim__c', XpCallHistoryController.lookupFieldFor(claimId));
    }

    @IsTest
    static void refusesOtherRecords() {
        Integer refused = 0;
        try { XpCallHistoryController.getHistory(UserInfo.getUserId()); } catch (AuraHandledException e) { refused++; }
        try { XpCallHistoryController.getHistory(null); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(2, refused);
    }

    @IsTest
    static void matchesNotesByPersonAndTime() {
        System.assertEquals('tomas', XpCallHistoryController.firstName('Tomás Coleman'));
        System.assertEquals('breege', XpCallHistoryController.firstName('  Breege '));
        System.assertEquals(null, XpCallHistoryController.firstName(' '));

        XpCallHistoryController.CallRow c = new XpCallHistoryController.CallRow();
        c.startedAt = Datetime.newInstanceGmt(2026, 10, 28, 10, 0, 0);
        c.endedAt = c.startedAt.addMinutes(6);
        c.agent = 'Breege';
        List<XpCallHistoryController.CallRow> calls = new List<XpCallHistoryController.CallRow>{ c };

        XpCallHistoryController.Note n = new XpCallHistoryController.Note();
        n.author = 'Breege Cowan';
        n.createdAt = c.endedAt.addMinutes(30);
        System.assertEquals(c, XpCallHistoryController.callFor(calls, n), 'half an hour after the call');
        n.createdAt = c.endedAt.addMinutes(120);
        System.assertEquals(null, XpCallHistoryController.callFor(calls, n), 'two hours later is another matter');
        n.createdAt = c.startedAt.addMinutes(2);
        n.author = 'Grace Smith';
        System.assertEquals(null, XpCallHistoryController.callFor(calls, n), 'someone else wrote it');
    }
}