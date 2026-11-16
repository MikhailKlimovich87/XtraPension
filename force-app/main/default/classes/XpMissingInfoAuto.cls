/**
 * The Missing Info email by itself after a call with a client who already paid (Fernando, 13/11/2026).
 *
 * A claim (Basic__c) only exists once the client has paid the EUR 50 on the portal, so every claim here is a paying
 * client; before that it is still sales and nothing goes. Every 15 minutes (4 scheduled jobs, "XP Missing Info auto
 * :00 / :15 / :30 / :45") this looks at answered calls on a claim (Call_Log__c, written from Nuacom by the automations
 * server) of at least 5 minutes that ended between 20 minutes and 3 hours ago, after the claim was created. For each
 * claim it sends the same email the validation agent sends from the Missing Information panel: same rules and same
 * text (BP_MissingInfo), from clients@, helper in copy, logged on the claim. It asks what the panel starts ticked
 * ("Helper: none given" stays out unless the client wants a helper) and is signed by the claim's validation agent.
 * No AI: the list comes from the claim's fields.
 *
 * Nothing goes when: the claim is past Pending Client (Agent Check and later), it has no client email, nothing is
 * missing, or a missing-information email (manual or automatic) went out in the 24 hours before the call ended or
 * since. The last rule also makes it once per call, because the automatic email is sent after the call.
 *
 * In practice the email goes 20 to 40 minutes after the call: long calls reach Salesforce on the server's "late" pass.
 * Stop it: XpMissingInfoAuto.unschedule() (the deploy script's --unschedule). See salesforce/missing-info-auto/README.md.
 */
public without sharing class XpMissingInfoAuto implements Schedulable {

    public static final Integer WAIT_MINUTES = 20;
    public static final Integer MIN_TALK_SECONDS = 300;
    public static final Integer LOOK_BACK_HOURS = 3;
    public static final Integer RECENT_EMAIL_HOURS = 24;
    // Messaging.sendEmail can be called 10 times per transaction; the rest goes on the next run.
    public static final Integer MAX_PER_RUN = 10;
    public static final String JOB_PREFIX = 'XP Missing Info auto';
    public static final Set<String> STATUSES = new Set<String>{ 'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client' };

    public class Outcome {
        public String claim;
        public Id claimId;
        public Datetime callEnded;
        public String result;
        public Integer items;
    }

    public void execute(SchedulableContext sc) {
        run(System.now(), true);
    }

    /** What a run would do now, without sending (the deploy script's --preview). */
    public static List<Outcome> preview() {
        return run(System.now(), false);
    }

    public static List<Outcome> run(Datetime now, Boolean send) {
        List<Outcome> out = new List<Outcome>();
        Datetime endedBefore = now.addMinutes(-WAIT_MINUTES);
        Datetime endedAfter = now.addHours(-LOOK_BACK_HOURS);

        // The latest qualifying call of each claim (ascending, so the last one wins).
        Map<Id, Call_Log__c> lastCall = new Map<Id, Call_Log__c>();
        for (Call_Log__c c : [
            SELECT Claim__c, Ended_At__c, Talk_Seconds__c, Claim__r.CreatedDate
            FROM Call_Log__c
            WHERE Claim__c != null AND Outcome__c = 'Answered' AND Talk_Seconds__c >= :MIN_TALK_SECONDS
              AND Ended_At__c <= :endedBefore AND Ended_At__c >= :endedAfter
            ORDER BY Ended_At__c ASC
        ]) {
            // A call that ended before the claim existed was a sales call (the number's history comes in when the claim is made).
            if (c.Ended_At__c <= c.Claim__r.CreatedDate) continue;
            lastCall.put(c.Claim__c, c);
        }
        if (lastCall.isEmpty()) return out;

        Datetime oldest = now.addHours(-LOOK_BACK_HOURS - RECENT_EMAIL_HOURS);
        String mark = '%' + BP_MissingInfo.SUBJECT_MARK + '%';
        Map<Id, Datetime> lastAsked = new Map<Id, Datetime>();
        for (EmailMessage m : [
            SELECT RelatedToId, MessageDate FROM EmailMessage
            WHERE RelatedToId IN :lastCall.keySet() AND Incoming = false AND Subject LIKE :mark AND MessageDate >= :oldest
        ]) {
            Datetime seen = lastAsked.get(m.RelatedToId);
            if (seen == null || m.MessageDate > seen) lastAsked.put(m.RelatedToId, m.MessageDate);
        }

        Map<Id, Basic__c> claims = new Map<Id, Basic__c>([
            SELECT Id, Name, Status__c, Email__c, Validation_Agent_Name__c FROM Basic__c WHERE Id IN :lastCall.keySet()
        ]);
        List<OrgWideEmailAddress> owea = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :BP_MissingInfo.CLIENTS_EMAIL LIMIT 1];

        Integer sent = 0;
        for (Id claimId : lastCall.keySet()) {
            Basic__c head = claims.get(claimId);
            Call_Log__c call = lastCall.get(claimId);
            Outcome o = new Outcome();
            o.claimId = claimId;
            o.claim = head == null ? null : head.Name;
            o.callEnded = call.Ended_At__c;
            out.add(o);
            if (head == null) { o.result = 'claim not found'; continue; }
            if (!STATUSES.contains(head.Status__c)) { o.result = 'skipped: status ' + head.Status__c; continue; }
            if (String.isBlank(head.Email__c)) { o.result = 'skipped: no client email'; continue; }
            Datetime asked = lastAsked.get(claimId);
            if (asked != null && asked >= call.Ended_At__c.addHours(-RECENT_EMAIL_HOURS)) {
                o.result = 'skipped: already asked ' + asked.formatGmt('dd/MM HH:mm') + ' UTC';
                continue;
            }
            if (sent >= MAX_PER_RUN) { o.result = 'next run (10 emails per run)'; continue; }
            try {
                Basic__c b = BP_MissingInfo.load(claimId);
                List<BP_MissingInfo.Item> items = startTicked(BP_MissingInfo.clientItems(BP_MissingInfo.check(b)));
                o.items = items.size();
                if (items.isEmpty()) { o.result = 'skipped: nothing missing'; continue; }
                if (!send) { o.result = 'would send'; continue; }
                deliver(b, items, sender(head.Validation_Agent_Name__c), owea.isEmpty() ? null : owea[0].Id);
                sent++;
                o.result = 'sent to ' + b.Email__c;
            } catch (Exception e) {
                // One bad claim must not stop the others (an exception here would cancel every email of the run).
                o.result = 'failed: ' + e.getMessage();
                System.debug(LoggingLevel.ERROR, 'XpMissingInfoAuto ' + o.claim + ': ' + e.getMessage());
            }
        }
        return out;
    }

    /** The items the panel starts ticked: what the agent would send without unticking anything. */
    @TestVisible
    private static List<BP_MissingInfo.Item> startTicked(List<BP_MissingInfo.Item> items) {
        List<BP_MissingInfo.Item> out = new List<BP_MissingInfo.Item>();
        for (BP_MissingInfo.Item i : items) {
            if (i.askByDefault != false) out.add(i);
        }
        return out;
    }

    /** The validation agent's first name, as the client knows them from the welcome email. */
    @TestVisible
    private static String sender(String validationAgentName) {
        if (String.isBlank(validationAgentName)) return 'The XtraPension team';
        return validationAgentName.trim().split('\\s+')[0];
    }

    /** Same email as BP_MissingInfo.sendAsking (the panel's Send), with the sender given. */
    private static void deliver(Basic__c b, List<BP_MissingInfo.Item> items, String sender, Id oweaId) {
        String subject = BP_MissingInfo.subject(b);
        String htmlBody = BP_MissingInfo.html(b, items, null, sender);
        String textBody = BP_MissingInfo.text(b, items, null, sender);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(textBody);
        if (oweaId != null) mail.setOrgWideEmailAddressId(oweaId);
        String cc = ccAddress(b);
        if (cc != null) mail.setCcAddresses(new List<String>{ cc });

        // With a contact the email is saved on the claim by Salesforce; without one it is logged below.
        Boolean logged = false;
        if (b.Contact__c != null) {
            List<Contact> contacts = [SELECT Email FROM Contact WHERE Id = :b.Contact__c LIMIT 1];
            mail.setTargetObjectId(b.Contact__c);
            mail.setWhatId(b.Id);
            mail.setSaveAsActivity(true);
            Boolean sameAddress = !contacts.isEmpty() && contacts[0].Email != null && contacts[0].Email.equalsIgnoreCase(b.Email__c);
            if (!sameAddress) {
                mail.setTreatTargetObjectAsRecipient(false);
                mail.setToAddresses(new List<String>{ b.Email__c });
            }
            logged = true;
        } else {
            mail.setToAddresses(new List<String>{ b.Email__c });
        }
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        if (!logged) {
            insert new EmailMessage(
                RelatedToId = b.Id, Subject = subject, HtmlBody = htmlBody, TextBody = textBody,
                ToAddress = b.Email__c, CcAddress = cc, FromAddress = BP_MissingInfo.CLIENTS_EMAIL, FromName = 'XtraPension',
                Incoming = false, Status = '3', MessageDate = System.now()
            );
        }
    }

    // Same rule as BP_MissingInfo.ccAddress (private there): the helper in copy when they have an email that is not the client's.
    private static String ccAddress(Basic__c b) {
        if (String.isBlank(b.Friend_Email__c)) return null;
        String cc = b.Friend_Email__c.trim();
        return cc.equalsIgnoreCase(String.isBlank(b.Email__c) ? '' : b.Email__c.trim()) ? null : cc;
    }

    // ------------------------------------------------------------------ the 4 jobs

    public static List<Id> schedule() {
        List<Id> ids = new List<Id>();
        for (Integer minute : new List<Integer>{ 0, 15, 30, 45 }) {
            String name = JOB_PREFIX + ' :' + String.valueOf(minute).leftPad(2, '0');
            ids.add(System.schedule(name, '0 ' + minute + ' * * * ?', new XpMissingInfoAuto()));
        }
        return ids;
    }

    public static Integer unschedule() {
        Integer n = 0;
        String name = JOB_PREFIX + '%';
        for (CronTrigger t : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :name]) {
            System.abortJob(t.Id);
            n++;
        }
        return n;
    }
}