/**
 * The Missing Info email by itself after a call with a client who already paid (Fernando, 13/11/2026).
 *
 * A claim (Basic__c) only exists once the client has paid the EUR 50 on the portal, so every claim here is a paying
 * client; before that it is still sales and nothing goes. Every 15 minutes (4 scheduled jobs, "XP Missing Info auto
 * :00 / :15 / :30 / :45") this looks at answered calls on a claim (Call_Log__c, written from Nuacom by the automations
 * server) of at least 5 minutes that ended between 20 minutes and 6 hours ago, after the claim was created. For each
 * claim it sends the same email the validation agent sends from the Missing Information panel: same rules and same
 * list (BP_MissingInfo), from clients@, helper in copy, logged on the claim. It asks what the panel starts ticked
 * ("Helper: none given" stays out unless the client wants a helper) and is signed by the claim's validation agent.
 * No AI: the list comes from the claim's fields.
 *
 * John, 16/11/2026 ("can we be sure we're asking for exactly the right info if automated?"):
 * - it waits until nobody has touched the claim (or its countries, employers and children) for 30 minutes, so what the
 *   agent types after the call is in before the list is made and the client is not asked for what they just said;
 * - when the client worked in the UK it adds John's "any proof of UK employment if available" line.
 * The email's wording is BP_MissingInfo's, with John's edits of 16/11/2026 (salesforce/missing-info-wording): that
 * package goes to production first, the tests here fail on the old "Thank you for filling in your claim form." opening.
 *
 * Nothing goes when: the claim is past Pending Client (Agent Check and later), it has no client email, nothing is
 * missing, or a missing-information email (manual or automatic) went out in the 24 hours before the call ended or
 * since. The last rule also makes it once per call, because the automatic email is sent after the call.
 *
 * In practice the email goes about an hour after the call: long calls reach Salesforce on the server's "late" pass 20
 * to 40 minutes after they end, and that touches the claim (Last Contact), so the 30 quiet minutes start then.
 * Stop it: XpMissingInfoAuto.unschedule() (the deploy script's --unschedule). See salesforce/missing-info-auto/README.md.
 */
public without sharing class XpMissingInfoAuto implements Schedulable {

    public static final Integer WAIT_MINUTES = 20;
    public static final Integer MIN_TALK_SECONDS = 300;
    // 6 hours: room for the 30 quiet minutes after an agent who keeps editing the claim after the call.
    public static final Integer LOOK_BACK_HOURS = 6;
    public static final Integer QUIET_MINUTES = 30;
    public static final Integer RECENT_EMAIL_HOURS = 24;
    // Messaging.sendEmail can be called 10 times per transaction; the rest goes on the next run.
    public static final Integer MAX_PER_RUN = 10;
    public static final String JOB_PREFIX = 'XP Missing Info auto';
    // The names schedule() and unschedule() work with. A test sets its own: the org's real jobs are visible to a test,
    // and scheduling a second job under the same name fails ("already scheduled"), which broke the test in production.
    @TestVisible private static String jobPrefix = JOB_PREFIX;
    public static final Set<String> STATUSES = new Set<String>{ 'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client' };
    public static final String PROOF = 'If you have anything that shows you worked in the UK, such as old payslips, a P60 or P45, or letters from '
        + 'an employer or HMRC, please send us a photo of it too. It is not essential, but it helps.';
    // Tests set it below 0 so the records they have just made count as quiet.
    @TestVisible private static Integer quietMinutes = QUIET_MINUTES;

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

        // The latest edit to the claim or its rows (the agent typing what the client said on the call).
        Map<Id, Basic__c> claims = new Map<Id, Basic__c>([
            SELECT Id, Name, Status__c, Email__c, Validation_Agent_Name__c, LastModifiedDate,
                   (SELECT LastModifiedDate FROM ClaimantCountrieslived__r ORDER BY LastModifiedDate DESC LIMIT 1),
                   (SELECT LastModifiedDate FROM Claimant_Companies__r ORDER BY LastModifiedDate DESC LIMIT 1),
                   (SELECT LastModifiedDate FROM Clamant_Children__r ORDER BY LastModifiedDate DESC LIMIT 1)
            FROM Basic__c WHERE Id IN :lastCall.keySet()
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
            Datetime edited = lastEdit(head);
            if (edited > now.addMinutes(-quietMinutes)) {
                o.result = 'waiting: claim edited ' + edited.formatGmt('dd/MM HH:mm') + ' UTC, goes ' + quietMinutes + ' min after the last edit';
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

    /** The last time the claim, or one of its countries, employers or children, was saved. */
    private static Datetime lastEdit(Basic__c head) {
        Datetime last = head.LastModifiedDate;
        List<SObject> rows = new List<SObject>();
        rows.addAll((List<SObject>) head.ClaimantCountrieslived__r);
        rows.addAll((List<SObject>) head.Claimant_Companies__r);
        rows.addAll((List<SObject>) head.Clamant_Children__r);
        for (SObject r : rows) {
            Datetime d = (Datetime) r.get('LastModifiedDate');
            if (d != null && (last == null || d > last)) last = d;
        }
        return last;
    }

    /**
     * The panel's email plus, when the client worked in the UK, the proof line before "You can simply reply".
     * [0] html, [1] text. A test checks the line is in, so a new panel wording cannot drop it silently.
     */
    public static List<String> bodies(Basic__c b, List<BP_MissingInfo.Item> items, String sender) {
        String htmlBody = BP_MissingInfo.html(b, items, null, sender);
        String textBody = BP_MissingInfo.text(b, items, null, sender);
        if (b.Claimant_Ever_Worked_UK__c == true) {
            String reply = 'You can simply reply to this email';
            htmlBody = htmlBody.replace('<p style="margin:18px 0 14px 0;">' + reply,
                '<p style="margin:18px 0 14px 0;">' + PROOF.escapeHtml4() + '</p><p style="margin:0 0 14px 0;">' + reply);
            textBody = textBody.replace('\n' + reply, '\n' + PROOF + '\n\n' + reply);
        }
        return new List<String>{ htmlBody, textBody };
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

    /** Same email as BP_MissingInfo.sendAsking (the panel's Send), with the sender given and the changes of bodies(). */
    private static void deliver(Basic__c b, List<BP_MissingInfo.Item> items, String sender, Id oweaId) {
        String subject = BP_MissingInfo.subject(b);
        List<String> body = bodies(b, items, sender);
        String htmlBody = body[0];
        String textBody = body[1];
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
            String name = jobPrefix + ' :' + String.valueOf(minute).leftPad(2, '0');
            ids.add(System.schedule(name, '0 ' + minute + ' * * * ?', new XpMissingInfoAuto()));
        }
        return ids;
    }

    public static Integer unschedule() {
        Integer n = 0;
        String name = jobPrefix + '%';
        for (CronTrigger t : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :name]) {
            System.abortJob(t.Id);
            n++;
        }
        return n;
    }
}