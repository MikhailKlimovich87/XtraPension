/**
 * Automatic "Last Contact" on the Application (Application__c) and the Claim (Basic__c).
 *
 * Contact_Type__c, Who__c, Date_Since_Contact__c and Last_Contact_Date__c used to be typed by hand.
 * They now follow what happened:
 *  - a Nuacom call (Call_Log__c, written by the automations server). Inbound: Answered = Phone Chat; a
 *    missed one does not count. Ours: not answered (No answer, Busy, Failed) = No Answer; answered and
 *    longer than 90 seconds = Phone Chat. A shorter one may be the client's voicemail, which the exchange
 *    also calls Answered: it counts once the call-voicemail-check flow has read it (Call_Check__c).
 *    Who = the agent.
 *  - an email a person sent from Salesforce (EmailMessage): Email Sent, Who = the sender. Emails written
 *    by the automations (jr@, XtraPension Admin, site guests, scheduled jobs and batches) and emails
 *    that only go to @xtrapension.com addresses do not count.
 *  - a WhatsApp a person sent: from a panel in Salesforce (LastContactController) or from Timelines
 *    (LastContactRest, reported by the automations server). Wapp Sent, Who = the person. SMS are automatic
 *    and do not count.
 *
 * Rule: an event replaces what is there only when it is newer than Last_Contact_At__c or, while that
 * is empty (records last touched by hand), when its day is on or after Date_Since_Contact__c.
 * Who__c gets the person's value in the picklist (full name, then first name, accents and case aside);
 * someone with no value leaves Who__c empty rather than another person's name next to the new date.
 *
 * System mode: the four fields are read-only for everyone, admins included. Never throws: a record that cannot be
 * saved (validation rule, lock) is skipped and logged; the email or the call is never rolled back.
 */
public without sharing class LastContactService {

    public static final String PHONE_CHAT = 'Phone Chat';
    public static final String EMAIL_SENT = 'Email Sent';
    public static final String VMAIL_LEFT = 'V/Mail Left';
    public static final String NO_ANSWER = 'No Answer';
    /** Up to this long, an answered call of ours may be a voicemail: of 37 at random in October 2026, 33 were not a conversation. */
    @TestVisible static final Integer CHECKED_UP_TO_SECONDS = 90;
    /** When the recording could not be read: this short is more likely a machine than a person. */
    @TestVisible static final Integer LIKELY_VOICEMAIL_SECONDS = 25;
    public static final String SMS_SENT = 'SMS Sent';
    public static final String WAPP_SENT = 'Wapp Sent';

    /** The business day of an event is the day in Ireland (org time zone, every user's time zone). */
    @TestVisible static final String TIME_ZONE = 'Europe/Dublin';
    static final String DRAFT = '5';
    /** Users that send emails on their own (the automations server and the admin user of the scheduled jobs). */
    @TestVisible static final Set<String> AUTOMATION_USERNAMES = new Set<String>{ 'jr@xtrapension.com', 'xtrapension.admin@xtrapension.com' };
    /** An email only to these domains is a note to a colleague, not a contact with the client. */
    @TestVisible static final Set<String> INTERNAL_DOMAINS = new Set<String>{ 'xtrapension.com' };
    /**
     * Nuacom names the extension "Sean" (ext 17): that is Sean Bedford; Sean Byrne's is "Sean Byrne" (call notes, 29/10/2026).
     * The shared sales@ user, inactive now, was the account of Megan, Tomas and Sean (Fernando, 30/10/2026).
     */
    @TestVisible static final Map<String, String> ALIASES = new Map<String, String>{
        'sean' => 'Sean Bedford',
        'sales xtrapension' => 'Old Sales Acct (Megan/Tomas/Sean)'
    };
    static final List<Schema.SObjectType> TYPES = new List<Schema.SObjectType>{ Application__c.SObjectType, Basic__c.SObjectType };

    /** True while this class saves records: an email or a call that this save causes is not a new contact. */
    @TestVisible static Boolean applying = false;
    @TestVisible static Boolean noRoomForTest = false;
    @TestVisible static String whoForTest;
    static Map<Schema.SObjectType, Map<String, String>> whoValuesCache = new Map<Schema.SObjectType, Map<String, String>>();

    public class ContactEvent {
        public Id recordId;
        public String contactType;
        public String person;
        public Datetime at;
        /** The same call saved again (another outcome): the same time is enough. */
        public Boolean sameEventAgain = false;
        /** Sent from a panel this very moment: always wins. */
        public Boolean manual = false;
        public ContactEvent(Id recordId, String contactType, String person, Datetime at) {
            this.recordId = recordId;
            this.contactType = contactType;
            this.person = person;
            this.at = at;
        }
    }

    public class Result {
        public Integer considered = 0;
        public Integer applied = 0;
        public Integer older = 0;
        public Map<Id, String> who = new Map<Id, String>();
        public Map<Id, String> failures = new Map<Id, String>();
        public Set<String> unknownPeople = new Set<String>();
    }

    // ---------------------------------------------------------------- triggers

    /** Call_Log__c after insert / after update. Runs in a Queueable: the motor's upsert never waits for or depends on it. */
    public static void onCalls(List<Call_Log__c> rows, Map<Id, Call_Log__c> oldMap) {
        try {
            submit(eventsFromCalls(rows, oldMap), true);
        } catch (Exception e) {
            log('calls', e);
        }
    }

    /**
     * EmailMessage after insert / after update (a draft that gets sent). Also in a Queueable: the update of
     * the Application runs the devs' triggers and flows, and a limit hit there cannot be caught — it would
     * fail the agent's email. The card shows it a few seconds later instead.
     */
    public static void onEmails(List<EmailMessage> rows, Map<Id, EmailMessage> oldMap) {
        try {
            submit(eventsFromEmails(rows, oldMap), true);
        } catch (Exception e) {
            log('emails', e);
        }
    }

    // ------------------------------------------------------------------ events

    /** Contact type for a call, or null when the call does not count. */
    public static String typeForCall(String direction, String outcome, Decimal talkSeconds, String check) {
        if (direction != 'Outbound') return outcome == 'Answered' ? PHONE_CHAT : null;
        if (outcome == 'No answer' || outcome == 'Busy' || outcome == 'Failed') return NO_ANSWER;
        if (outcome != 'Answered') return null;
        if (talkSeconds == null || talkSeconds > CHECKED_UP_TO_SECONDS) return PHONE_CHAT;
        switch on check {
            when null { return null; }
            when 'Conversation' { return PHONE_CHAT; }
            when 'Voicemail left' { return VMAIL_LEFT; }
            when 'Voicemail, no message', 'No conversation' { return NO_ANSWER; }
            when else { return talkSeconds <= LIKELY_VOICEMAIL_SECONDS ? VMAIL_LEFT : PHONE_CHAT; }
        }
    }

    public static List<ContactEvent> eventsFromCalls(List<Call_Log__c> rows, Map<Id, Call_Log__c> oldMap) {
        List<ContactEvent> out = new List<ContactEvent>();
        for (Call_Log__c c : rows) {
            Call_Log__c before = oldMap == null ? null : oldMap.get(c.Id);
            if (before != null && !callChanged(before, c)) continue;
            String type = typeForCall(c.Direction__c, c.Outcome__c, c.Talk_Seconds__c, c.Call_Check__c);
            Datetime at = c.Started_At__c != null ? c.Started_At__c : c.Ended_At__c;
            if (type == null || at == null) continue;
            for (Id recordId : new List<Id>{ c.Application__c, c.Claim__c }) {
                if (recordId == null) continue;
                ContactEvent e = new ContactEvent(recordId, type, c.Agent_Name__c, at);
                e.sameEventAgain = before != null;
                out.add(e);
            }
        }
        return out;
    }

    static Boolean callChanged(Call_Log__c a, Call_Log__c b) {
        return a.Outcome__c != b.Outcome__c || a.Direction__c != b.Direction__c || a.Agent_Name__c != b.Agent_Name__c
            || a.Call_Check__c != b.Call_Check__c
            || a.Started_At__c != b.Started_At__c || a.Application__c != b.Application__c || a.Claim__c != b.Claim__c;
    }

    public static List<ContactEvent> eventsFromEmails(List<EmailMessage> rows, Map<Id, EmailMessage> oldMap) {
        List<ContactEvent> out = new List<ContactEvent>();
        // A person does not send from a batch or a scheduled job: those are the automations.
        if (System.isBatch() || System.isFuture() || System.isQueueable() || System.isScheduled()) return out;
        List<EmailMessage> candidates = new List<EmailMessage>();
        Set<Id> creators = new Set<Id>();
        for (EmailMessage m : rows) {
            EmailMessage before = oldMap == null ? null : oldMap.get(m.Id);
            if (before != null && before.Status != DRAFT) continue;
            if (m.Incoming == true || m.Status == DRAFT || m.RelatedToId == null || !isOurs(m.RelatedToId)) continue;
            if (onlyInternal(m.ToAddress, m.CcAddress, m.BccAddress)) continue;
            candidates.add(m);
            creators.add(m.CreatedById);
        }
        if (candidates.isEmpty()) return out;
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name, Username, UserType FROM User WHERE Id IN :creators]);
        for (EmailMessage m : candidates) {
            User u = users.get(m.CreatedById);
            if (u == null || !isPerson(u.UserType, u.Username)) continue;
            Datetime at = m.MessageDate != null ? m.MessageDate : (m.CreatedDate != null ? m.CreatedDate : Datetime.now());
            out.add(new ContactEvent(m.RelatedToId, EMAIL_SENT, u.Name, at));
        }
        return out;
    }

    public static Boolean isOurs(Id recordId) {
        if (recordId == null) return false;
        Schema.SObjectType t = recordId.getSObjectType();
        return t == Application__c.SObjectType || t == Basic__c.SObjectType;
    }

    @TestVisible
    static Boolean isPerson(String userType, String username) {
        return userType == 'Standard' && username != null && !AUTOMATION_USERNAMES.contains(username.toLowerCase());
    }

    @TestVisible
    static Boolean onlyInternal(String toAddress, String ccAddress, String bccAddress) {
        Integer seen = 0;
        for (String part : new List<String>{ toAddress, ccAddress, bccAddress }) {
            if (String.isBlank(part)) continue;
            for (String a : part.split('[;,\\s]+')) {
                if (!a.contains('@')) continue;
                seen++;
                String domain = a.substringAfterLast('@').toLowerCase().replaceAll('[^a-z0-9.\\-]', '');
                if (!INTERNAL_DOMAINS.contains(domain)) return false;
            }
        }
        return seen > 0;
    }

    // ------------------------------------------------------------------- apply

    /** Applies now when there is room in this transaction, otherwise (or when asked) in a Queueable. */
    public static void submit(List<ContactEvent> events, Boolean preferAsync) {
        if (events == null || events.isEmpty() || applying) return;
        Boolean room = hasHeadroom(events.size());
        if ((preferAsync || !room) && canEnqueue()) {
            System.enqueueJob(new Job(events));
        } else if (room) {
            apply(events);
        } else {
            System.debug(LoggingLevel.WARN, '[LastContact] no room to update ' + events.size() + ' event(s) in this transaction; skipped.');
        }
    }

    public class Job implements Queueable {
        final List<ContactEvent> events;
        public Job(List<ContactEvent> events) {
            this.events = events;
        }
        public void execute(QueueableContext ctx) {
            apply(events);
        }
    }

    @TestVisible
    static Boolean hasHeadroom(Integer events) {
        if (noRoomForTest) return false;
        return Limits.getQueries() + 30 <= Limits.getLimitQueries()
            && Limits.getDmlStatements() + 15 <= Limits.getLimitDmlStatements()
            && Limits.getDmlRows() + 3 * events + 200 <= Limits.getLimitDmlRows()
            && Limits.getCpuTime() * 2 < Limits.getLimitCpuTime();
    }

    static Boolean canEnqueue() {
        return Limits.getQueueableJobs() < Limits.getLimitQueueableJobs();
    }

    /** One update per record: the newest event of each record, when it wins over what is there. Never throws. */
    public static Result apply(List<ContactEvent> events) {
        Result r = new Result();
        try {
            Map<Id, ContactEvent> newest = newestByRecord(events);
            r.considered = newest.size();
            if (newest.isEmpty()) return r;
            List<SObject> updates = new List<SObject>();
            Map<Id, Date> days = new Map<Id, Date>();
            for (Schema.SObjectType t : TYPES) {
                Set<Id> ids = idsOf(newest.keySet(), t);
                if (ids.isEmpty()) continue;
                Map<String, String> values = whoValues(t);
                String soql = 'SELECT Id, Contact_Type__c, Date_Since_Contact__c, Last_Contact_At__c FROM ' + t.getDescribe().getName() + ' WHERE Id IN :ids';
                for (SObject rec : Database.query(soql)) {
                    ContactEvent e = newest.get(rec.Id);
                    if (!wins(e, (Datetime) rec.get('Last_Contact_At__c'), (Date) rec.get('Date_Since_Contact__c'), (String) rec.get('Contact_Type__c'))) {
                        r.older++;
                        continue;
                    }
                    String who = whoForTest != null ? whoForTest : whoValue(e.person, values);
                    if (who == null) {
                        r.unknownPeople.add(String.valueOf(e.person));
                        System.debug(LoggingLevel.WARN, '[LastContact] no Last Contact value for "' + e.person + '": Who__c left empty on ' + rec.Id);
                    }
                    Date day = dayOf(e.at);
                    SObject u = t.newSObject(rec.Id);
                    u.put('Contact_Type__c', e.contactType);
                    u.put('Who__c', who);
                    u.put('Date_Since_Contact__c', day);
                    u.put('Last_Contact_Date__c', day);
                    u.put('Last_Contact_At__c', e.at);
                    updates.add(u);
                    days.put(rec.Id, day);
                    r.who.put(rec.Id, who);
                }
            }
            Set<Id> saved = save(updates, r);
            keepDays(saved, days);
        } catch (Exception e) {
            log('apply', e);
        }
        return r;
    }

    @TestVisible
    static Map<Id, ContactEvent> newestByRecord(List<ContactEvent> events) {
        Map<Id, ContactEvent> newest = new Map<Id, ContactEvent>();
        for (ContactEvent e : events) {
            if (e == null || e.recordId == null || e.at == null || String.isBlank(e.contactType) || !isOurs(e.recordId)) continue;
            ContactEvent have = newest.get(e.recordId);
            if (have == null || e.manual || (!have.manual && e.at >= have.at)) newest.put(e.recordId, e);
        }
        return newest;
    }

    /**
     * Newer than Last_Contact_At__c; while that is empty, on or after the day typed in Date_Since_Contact__c —
     * except that a WhatsApp or SMS typed by hand stays on its own day: it has no time and we cannot see those
     * channels, so a call or an email of the same day may well have come before it (Fernando, 29/10/2026).
     */
    @TestVisible
    static Boolean wins(ContactEvent e, Datetime lastAt, Date lastDay, String lastType) {
        if (e.manual) return true;
        if (lastAt != null) return e.at > lastAt || (e.sameEventAgain && e.at == lastAt);
        if (lastDay == null) return true;
        Date day = dayOf(e.at);
        if (day == lastDay && (lastType == WAPP_SENT || lastType == SMS_SENT)) return false;
        return day >= lastDay;
    }

    static Set<Id> save(List<SObject> updates, Result r) {
        Set<Id> saved = new Set<Id>();
        if (updates.isEmpty()) return saved;
        List<Database.SaveResult> results;
        applying = true;
        try {
            results = Database.update(updates, false);
        } finally {
            applying = false;
        }
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                saved.add(updates[i].Id);
            } else {
                String msg = messageOf(results[i].getErrors());
                r.failures.put(updates[i].Id, msg);
                System.debug(LoggingLevel.WARN, '[LastContact] not saved ' + updates[i].Id + ': ' + msg);
            }
        }
        r.applied = saved.size();
        return saved;
    }

    /**
     * ApplicationTrigger (devs' code, left as it is) stamps Date_Since_Contact__c = today whenever Who__c or
     * Contact_Type__c changes. A call or an email from an earlier day gets its own day back. Only runs for
     * records whose day is not today, so a contact happening now costs nothing extra.
     */
    static void keepDays(Set<Id> saved, Map<Id, Date> days) {
        Set<Id> check = new Set<Id>();
        for (Id rid : saved) if (days.get(rid) != Date.today()) check.add(rid);
        if (check.isEmpty()) return;
        List<SObject> fixes = new List<SObject>();
        for (Schema.SObjectType t : TYPES) {
            Set<Id> ids = idsOf(check, t);
            if (ids.isEmpty()) continue;
            String soql = 'SELECT Id, Date_Since_Contact__c, Last_Contact_Date__c FROM ' + t.getDescribe().getName() + ' WHERE Id IN :ids';
            for (SObject rec : Database.query(soql)) {
                Date want = days.get(rec.Id);
                if ((Date) rec.get('Date_Since_Contact__c') == want && (Date) rec.get('Last_Contact_Date__c') == want) continue;
                SObject f = t.newSObject(rec.Id);
                f.put('Date_Since_Contact__c', want);
                f.put('Last_Contact_Date__c', want);
                fixes.add(f);
            }
        }
        if (fixes.isEmpty()) return;
        applying = true;
        try {
            for (Database.SaveResult sr : Database.update(fixes, false)) {
                if (!sr.isSuccess()) System.debug(LoggingLevel.WARN, '[LastContact] day not kept on ' + sr.getId() + ': ' + messageOf(sr.getErrors()));
            }
        } finally {
            applying = false;
        }
    }

    // ------------------------------------------------------------------ people

    /** Normalized value -> picklist value of Who__c on this object (active values). */
    static Map<String, String> whoValues(Schema.SObjectType t) {
        Map<String, String> values = whoValuesCache.get(t);
        if (values != null) return values;
        values = new Map<String, String>();
        Schema.DescribeFieldResult f = t.getDescribe().fields.getMap().get('Who__c').getDescribe();
        for (Schema.PicklistEntry p : f.getPicklistValues()) {
            if (p.isActive()) values.put(normalize(p.getValue()), p.getValue());
        }
        whoValuesCache.put(t, values);
        return values;
    }

    /** Full name first ("Sean Byrne"), then a known alias, then the first name ("Becky McAllister" -> Becky). */
    @TestVisible
    static String whoValue(String person, Map<String, String> values) {
        String full = normalize(person);
        if (String.isBlank(full)) return null;
        if (values.containsKey(full)) return values.get(full);
        String alias = ALIASES.get(full);
        if (alias != null && values.containsKey(normalize(alias))) return values.get(normalize(alias));
        return values.get(full.split(' ')[0]);
    }

    @TestVisible
    static String normalize(String s) {
        if (s == null) return null;
        return s.trim().toLowerCase().replaceAll('\\s+', ' ')
            .replaceAll('[áàâãäå]', 'a').replaceAll('[éèêë]', 'e').replaceAll('[íìîï]', 'i')
            .replaceAll('[óòôõö]', 'o').replaceAll('[úùûü]', 'u').replaceAll('ç', 'c').replaceAll('ñ', 'n');
    }

    // ----------------------------------------------------------------- helpers

    public static Date dayOf(Datetime at) {
        return Date.valueOf(at.format('yyyy-MM-dd', TIME_ZONE));
    }

    static Set<Id> idsOf(Set<Id> ids, Schema.SObjectType t) {
        Set<Id> out = new Set<Id>();
        for (Id rid : ids) if (rid.getSObjectType() == t) out.add(rid);
        return out;
    }

    static String messageOf(List<Database.Error> errors) {
        List<String> parts = new List<String>();
        for (Database.Error e : errors) parts.add(e.getMessage());
        return String.join(parts, '; ');
    }

    static void log(String context, Exception e) {
        System.debug(LoggingLevel.ERROR, '[LastContact] ' + context + ': ' + e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
    }
}