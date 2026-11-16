/**
 * Call History panel (xpCallHistory) on the Application and on the Claim.
 *
 * Two sources, shown as one timeline:
 *  - Call_Log__c: every Nuacom call with the client, written by the automations
 *    server (nuacom-to-salesforce), with who made or took it and the recording.
 *  - the call notes the team logs as Tasks (TaskSubtype = Call). Each note is
 *    attached to the call it is about when there is one: same person, written
 *    between 15 minutes before the call and 90 minutes after it ended. A note
 *    with no such call (a mobile, or before March 2024) stays on its own.
 *
 * Runs in user mode: someone without access to the record or the object sees nothing.
 */
public with sharing class XpCallHistoryController {

    @TestVisible private static final Integer MAX_CALLS = 1000;
    private static final Integer MAX_NOTES = 500;
    private static final Long NOTE_BEFORE_MS = 15L * 60 * 1000;
    private static final Long NOTE_AFTER_MS = 90L * 60 * 1000;
    /** Answered on the exchange, but nobody spoke to the client: a voicemail picks up too (call-voicemail-check flow). */
    private static final Set<String> NOT_SPOKEN = new Set<String>{ 'Voicemail left', 'Voicemail, no message', 'No conversation' };

    public class CallRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public Datetime endedAt;
        @AuraEnabled public String direction;
        @AuraEnabled public String outcome;
        @AuraEnabled public Integer talkSeconds;
        @AuraEnabled public Integer totalSeconds;
        @AuraEnabled public String agent;
        @AuraEnabled public String extension;
        @AuraEnabled public String clientNumber;
        @AuraEnabled public String callerIdName;
        @AuraEnabled public String line;
        @AuraEnabled public String queue;
        @AuraEnabled public String rang;
        @AuraEnabled public String matchedOn;
        @AuraEnabled public Boolean hasRecording;
        @AuraEnabled public String recordingUrl;
        @AuraEnabled public Boolean transferred;
        @AuraEnabled public String nuacomNote;
        @AuraEnabled public Boolean hasTranscript;
        @AuraEnabled public String transcript;
        @AuraEnabled public String transcriptSummary;
        @AuraEnabled public Datetime transcribedAt;
        @AuraEnabled public String check;
        @AuraEnabled public Boolean spoke;
        @AuraEnabled public Boolean transcribing;
        @AuraEnabled public String transcriptProblem;
        @AuraEnabled public List<Note> notes = new List<Note>();
    }

    public class Note {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public String description;
        @AuraEnabled public String author;
        @AuraEnabled public Datetime createdAt;
    }

    public class History {
        @AuraEnabled public String recordName;
        @AuraEnabled public List<CallRow> calls = new List<CallRow>();
        @AuraEnabled public List<Note> loneNotes = new List<Note>();
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer answered = 0;
        @AuraEnabled public Integer inbound = 0;
        @AuraEnabled public Integer outbound = 0;
        @AuraEnabled public Integer missed = 0;
        @AuraEnabled public Integer notReached = 0;
        @AuraEnabled public Integer talkSeconds = 0;
        @AuraEnabled public Datetime firstCallAt;
        @AuraEnabled public Datetime lastCallAt;
        @AuraEnabled public Datetime lastTalkAt;
        @AuraEnabled public String lastTalkAgent;
        @AuraEnabled public Integer lastTalkSeconds;
        @AuraEnabled public Integer triesSinceTalk = 0;
        @AuraEnabled public Integer missedSinceTalk = 0;
        @AuraEnabled public Boolean truncated = false;
    }

    /** The lookup on Call_Log__c for this kind of record. Anything else is refused. */
    @TestVisible
    private static String lookupFieldFor(Id recordId) {
        if (recordId == null) throw new AuraHandledException('No record.');
        Schema.SObjectType t = recordId.getSObjectType();
        if (t == Application__c.SObjectType) return 'Application__c';
        if (t == Basic__c.SObjectType) return 'Claim__c';
        throw new AuraHandledException('Call History works on Applications and Claims only.');
    }

    @AuraEnabled(cacheable=true)
    public static History getHistory(Id recordId) {
        String field = lookupFieldFor(recordId);
        Map<String, Object> binds = new Map<String, Object>{ 'rid' => recordId };
        History h = new History();

        // For the title of the full page (View all).
        String objectName = recordId.getSObjectType().getDescribe().getName();
        List<SObject> rec = Database.queryWithBinds('SELECT Name FROM ' + objectName + ' WHERE Id = :rid', binds, AccessLevel.USER_MODE);
        h.recordName = rec.isEmpty() ? null : (String) rec[0].get('Name');

        // Counts over every call, not just the ones loaded below.
        String agg = 'SELECT Direction__c dir, Outcome__c outcome, Call_Check__c happened, COUNT(Id) n, SUM(Talk_Seconds__c) talk, MIN(Started_At__c) firstAt, MAX(Started_At__c) lastAt'
            + ' FROM Call_Log__c WHERE ' + field + ' = :rid GROUP BY Direction__c, Outcome__c, Call_Check__c';
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(agg, binds, AccessLevel.USER_MODE)) {
            Integer n = (Integer) ar.get('n');
            String dir = (String) ar.get('dir');
            String outcome = (String) ar.get('outcome');
            h.total += n;
            if (dir == 'Inbound') h.inbound += n;
            if (dir == 'Outbound') h.outbound += n;
            if (spoke(outcome, (String) ar.get('happened'))) {
                h.answered += n;
                Decimal talk = (Decimal) ar.get('talk');
                h.talkSeconds += talk == null ? 0 : talk.intValue();
            } else if (outcome == 'Missed') {
                h.missed += n;
            } else {
                h.notReached += n;
            }
            h.firstCallAt = earliest(h.firstCallAt, (Datetime) ar.get('firstAt'));
            h.lastCallAt = latest(h.lastCallAt, (Datetime) ar.get('lastAt'));
        }
        if (h.total == 0 && !hasNotes(recordId)) return h;

        String soql = 'SELECT Id, Name, Started_At__c, Ended_At__c, Direction__c, Outcome__c, Talk_Seconds__c, Total_Seconds__c,'
            + ' Agent_Name__c, Agent_Extension__c, Customer_Number__c, Caller_ID_Name__c, XP_Line__c, Queue__c, Rang_Extension__c,'
            + ' Matched_On__c, Has_Recording__c, Recording_URL__c, Transferred__c, Note__c,'
            + ' Transcript__c, Transcript_Summary__c, Transcribed_At__c, Transcript_Status__c, Call_Check__c, LastModifiedDate'
            + ' FROM Call_Log__c WHERE ' + field + ' = :rid ORDER BY Started_At__c DESC NULLS LAST LIMIT ' + MAX_CALLS;
        for (Call_Log__c c : (List<Call_Log__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            h.calls.add(toRow(c));
        }
        h.truncated = h.total > h.calls.size();

        for (CallRow c : h.calls) {
            if (c.spoke) {
                h.lastTalkAt = c.startedAt;
                h.lastTalkAgent = c.agent;
                h.lastTalkSeconds = c.talkSeconds;
                break;
            }
            if (c.direction == 'Outbound') h.triesSinceTalk++;
            if (c.outcome == 'Missed') h.missedSinceTalk++;
        }

        attachNotes(h, recordId);
        return h;
    }

    /**
     * The Transcribe button. A transcript already on the call goes to the person's email at once. Otherwise XP AI
     * transcribes it in the background and XpCallTranscriptService emails the person when it lands.
     * Returns 'emailed' or 'transcribing'.
     */
    @AuraEnabled
    public static String requestTranscript(Id callLogId) {
        List<Call_Log__c> rows = [
            SELECT Id, Nuacom_Call_Id__c, Started_At__c, Direction__c, Talk_Seconds__c, Customer_Number__c, Agent_Name__c,
                Has_Recording__c, Transcript__c, Transcript_Status__c, LastModifiedDate
            FROM Call_Log__c WHERE Id = :callLogId WITH USER_MODE
        ];
        if (rows.isEmpty()) throw new AuraHandledException('This call is not available.');
        Call_Log__c c = rows[0];
        if (String.isNotBlank(c.Transcript__c)) {
            XpCallTranscriptService.emailTranscript(c.Id, UserInfo.getUserId());
            return 'emailed';
        }
        if (c.Has_Recording__c != true) throw new AuraHandledException('This call has no recording to transcribe.');
        if (!XpCallTranscriptService.isTranscribing(c.Transcript_Status__c, c.LastModifiedDate)) {
            askXpAi(c);
            XpCallTranscriptService.markRequested(c.Id, UserInfo.getUserId());
        }
        return 'transcribing';
    }

    private static void askXpAi(Call_Log__c c) {
        HttpResponse res = XpCallTranscriptService.callXpAi('/calls/transcribe', XpCallTranscriptService.callDetails(c));
        if (res == null) throw new AuraHandledException('Transcription is not reachable right now. Try again in a minute.');
        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) return;
        String message = 'The transcription could not start. Try again in a minute.';
        try {
            Object error = ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('error');
            if (error != null) message = String.valueOf(error);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, '[CallHistory] transcribe answered ' + res.getStatusCode());
        }
        throw new AuraHandledException(message);
    }

    private static Boolean hasNotes(Id recordId) {
        return ![SELECT Id FROM Task WHERE WhatId = :recordId AND TaskSubtype = 'Call' WITH USER_MODE LIMIT 1].isEmpty();
    }

    private static Boolean spoke(String outcome, String happened) {
        return outcome == 'Answered' && !NOT_SPOKEN.contains(happened);
    }

    private static CallRow toRow(Call_Log__c c) {
        CallRow r = new CallRow();
        r.id = c.Id;
        r.name = c.Name;
        r.startedAt = c.Started_At__c;
        r.endedAt = c.Ended_At__c;
        r.direction = c.Direction__c;
        r.outcome = c.Outcome__c;
        r.talkSeconds = c.Talk_Seconds__c == null ? 0 : c.Talk_Seconds__c.intValue();
        r.totalSeconds = c.Total_Seconds__c == null ? 0 : c.Total_Seconds__c.intValue();
        r.agent = c.Agent_Name__c;
        r.extension = c.Agent_Extension__c;
        r.clientNumber = c.Customer_Number__c;
        r.callerIdName = c.Caller_ID_Name__c;
        r.line = c.XP_Line__c;
        r.queue = c.Queue__c;
        r.rang = c.Rang_Extension__c;
        r.matchedOn = c.Matched_On__c;
        r.hasRecording = c.Has_Recording__c == true && String.isNotBlank(c.Recording_URL__c);
        r.recordingUrl = r.hasRecording ? c.Recording_URL__c : null;
        r.transferred = c.Transferred__c == true;
        r.nuacomNote = c.Note__c;
        r.hasTranscript = String.isNotBlank(c.Transcript__c);
        r.transcript = c.Transcript__c;
        r.check = c.Call_Check__c;
        r.spoke = spoke(c.Outcome__c, c.Call_Check__c);
        r.transcribing = !r.hasTranscript && XpCallTranscriptService.isTranscribing(c.Transcript_Status__c, c.LastModifiedDate);
        r.transcriptProblem = r.hasTranscript ? null : XpCallTranscriptService.problemOf(c.Transcript_Status__c);
        r.transcriptSummary = c.Transcript_Summary__c;
        r.transcribedAt = c.Transcribed_At__c;
        return r;
    }

    /** Each logged-call Task goes under the call it is about, or stays on its own. */
    private static void attachNotes(History h, Id recordId) {
        List<Task> tasks = [
            SELECT Id, Subject, Description, CreatedDate, CreatedBy.Name
              FROM Task
             WHERE WhatId = :recordId AND TaskSubtype = 'Call'
             WITH USER_MODE
             ORDER BY CreatedDate DESC
             LIMIT :MAX_NOTES
        ];
        for (Task t : tasks) {
            Note n = new Note();
            n.id = t.Id;
            n.subject = t.Subject;
            n.description = t.Description;
            n.author = t.CreatedBy?.Name;
            n.createdAt = t.CreatedDate;
            CallRow call = callFor(h.calls, n);
            if (call != null) call.notes.add(n);
            else h.loneNotes.add(n);
        }
    }

    @TestVisible
    private static CallRow callFor(List<CallRow> calls, Note n) {
        String who = firstName(n.author);
        if (String.isBlank(who) || n.createdAt == null) return null;
        Long at = n.createdAt.getTime();
        CallRow best;
        Long bestGap;
        for (CallRow c : calls) {
            if (c.startedAt == null || firstName(c.agent) != who) continue;
            Long opens = c.startedAt.getTime() - NOTE_BEFORE_MS;
            Long ends = (c.endedAt == null ? c.startedAt : c.endedAt).getTime();
            if (at < opens || at > ends + NOTE_AFTER_MS) continue;
            Long gap = Math.abs(at - ends);
            if (best == null || gap < bestGap) {
                best = c;
                bestGap = gap;
            }
        }
        return best;
    }

    /** "Breege Cowan" and "Breege" are the same person; accents and case do not count. */
    @TestVisible
    private static String firstName(String full) {
        if (String.isBlank(full)) return null;
        String first = full.trim().split('\\s+')[0].toLowerCase();
        return first.replaceAll('[áàâã]', 'a').replaceAll('[éê]', 'e').replaceAll('[íî]', 'i').replaceAll('[óôõ]', 'o').replaceAll('[úû]', 'u');
    }

    private static Datetime earliest(Datetime a, Datetime b) {
        if (a == null) return b;
        if (b == null) return a;
        return a < b ? a : b;
    }

    private static Datetime latest(Datetime a, Datetime b) {
        if (a == null) return b;
        if (b == null) return a;
        return a > b ? a : b;
    }
}