/**
 * The Transcribe button of the Call History panel (XpCallHistoryController.requestTranscript). XP AI transcribes
 * the call, with the same quota and store as asking it in chat, and writes the transcript on the Call Log rows of
 * that call. When it lands there, or when XP AI gives up, the person who asked gets an email. The PDF is XP AI's
 * own template, made for the email and never saved: in Salesforce only the text on the Call Log stays.
 *
 * Without sharing: the team can read Call Logs, not edit them.
 */
public without sharing class XpCallTranscriptService {

    public static final String TRANSCRIBING = 'Transcribing';
    public static final String FAILED_PREFIX = 'Failed: ';
    /** XP AI restarted in the middle of one: after this the button comes back. */
    private static final Integer STUCK_MINUTES = 15;
    private static final String SENDER = 'no-reply@xtrapension.com';
    private static final String TIME_ZONE = 'Europe/Dublin';
    // Brand: docs/guia_identidade_visual_xtrapension.md. The logo is the one the org's email templates use.
    private static final String TEAL = '#007D72';
    private static final String YELLOW = '#FFE100';
    private static final String RED = '#F22535';
    private static final String MUTED = '#6b7280';
    private static final String LOGO = 'https://cdn.prod.website-files.com/646b3f12df737f5a46034de5/648c412b02d7b62507507ce8_xtrapensionlogo.png';

    @TestVisible private static Integer emailsSent = 0;

    public static Boolean isTranscribing(String status, Datetime modifiedAt) {
        return status == TRANSCRIBING && modifiedAt != null && modifiedAt > Datetime.now().addMinutes(-STUCK_MINUTES);
    }

    /** What went wrong, for the panel; null when nothing did. */
    public static String problemOf(String status) {
        return status != null && status.startsWith(FAILED_PREFIX) ? status.removeStart(FAILED_PREFIX) : null;
    }

    public static void markRequested(Id callLogId, Id userId) {
        update new Call_Log__c(Id = callLogId, Transcript_Requested_By__c = userId, Transcript_Status__c = TRANSCRIBING);
    }

    /** POST to the XP AI service. Null when it cannot be reached. */
    public static HttpResponse callXpAi(String path, Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:XP_AI' + path);
        req.setMethod('POST');
        req.setTimeout(30000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-XPAI-User', UserInfo.getUserId());
        req.setHeader('X-XPAI-Name', EncodingUtil.urlEncode(UserInfo.getName(), 'UTF-8'));
        req.setBody(JSON.serialize(body));
        try {
            return new Http().send(req);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[CallTranscript] XP AI: ' + e.getMessage());
            return null;
        }
    }

    public static Map<String, Object> callDetails(Call_Log__c c) {
        return new Map<String, Object>{
            'callId' => c.Nuacom_Call_Id__c,
            'callLogId' => (String) c.Id,
            'startedAt' => c.Started_At__c == null ? null : c.Started_At__c.format('yyyy-MM-dd HH:mm:ss', TIME_ZONE),
            'direction' => c.Direction__c,
            'talkSeconds' => c.Talk_Seconds__c == null ? 0 : c.Talk_Seconds__c.intValue(),
            'clientNumber' => c.Customer_Number__c,
            'agent' => c.Agent_Name__c
        };
    }

    /** Call_Log__c after update. Never throws: these rows are written by the robots, and an email is not worth a lost call. */
    public static void onUpdate(List<Call_Log__c> rows, Map<Id, Call_Log__c> oldMap) {
        try {
            Set<Id> ready = new Set<Id>();
            Set<Id> failed = new Set<Id>();
            for (Call_Log__c c : rows) {
                if (c.Transcript_Requested_By__c == null) continue;
                Call_Log__c before = oldMap.get(c.Id);
                if (String.isNotBlank(c.Transcript__c) && String.isBlank(before.Transcript__c)) {
                    ready.add(c.Id);
                } else if (problemOf(c.Transcript_Status__c) != null && c.Transcript_Status__c != before.Transcript_Status__c) {
                    failed.add(c.Id);
                }
            }
            // A trigger cannot call XP AI for the PDF.
            if (!ready.isEmpty()) System.enqueueJob(new EmailJob(ready));
            if (failed.isEmpty()) return;
            List<Messaging.SingleEmailMessage> out = new List<Messaging.SingleEmailMessage>();
            for (Call_Log__c c : load(failed)) out.add(failureEmail(c));
            send(out);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[CallTranscript] ' + e.getMessage());
        }
    }

    public class EmailJob implements Queueable, Database.AllowsCallouts {
        final Set<Id> ids;
        EmailJob(Set<Id> ids) {
            this.ids = ids;
        }
        public void execute(QueueableContext ctx) {
            List<Messaging.SingleEmailMessage> out = new List<Messaging.SingleEmailMessage>();
            for (Call_Log__c c : load(ids)) out.add(transcriptEmail(c, c.Transcript_Requested_By__c));
            send(out);
        }
    }

    /** The button on a call that already has a transcript. */
    public static void emailTranscript(Id callLogId, Id userId) {
        send(new List<Messaging.SingleEmailMessage>{ transcriptEmail(load(new Set<Id>{ callLogId })[0], userId) });
    }

    private static List<Call_Log__c> load(Set<Id> ids) {
        return [
            SELECT Id, Application__c, Application__r.Name, Claim__c, Claim__r.Name, Started_At__c, Direction__c, Agent_Name__c,
                Nuacom_Call_Id__c, Talk_Seconds__c, Customer_Number__c,
                Transcript__c, Transcript_Summary__c, Transcript_Status__c, Transcript_Requested_By__c
            FROM Call_Log__c WHERE Id IN :ids
        ];
    }

    private static String recordName(Call_Log__c c) {
        return c.Application__c != null ? c.Application__r.Name : c.Claim__r.Name;
    }

    private static String callLine(Call_Log__c c) {
        String at = c.Started_At__c == null ? 'Date unknown' : c.Started_At__c.format('EEE, d MMM yyyy, HH:mm', TIME_ZONE);
        return at + ', ' + c.Direction__c + (String.isBlank(c.Agent_Name__c) ? '' : ', ' + c.Agent_Name__c);
    }

    private static String linkOf(Call_Log__c c) {
        return URL.getOrgDomainURL().toExternalForm() + '/' + (c.Application__c != null ? c.Application__c : c.Claim__c);
    }

    private static Messaging.SingleEmailMessage transcriptEmail(Call_Log__c c, Id userId) {
        Messaging.EmailFileAttachment pdf = pdfOf(c);
        String text = 'Here is the transcript you asked for' + (pdf != null ? ', in the attached PDF.' : '.') + '\n\n'
            + 'Client: ' + recordName(c) + '\n' + linkOf(c) + '\n' + 'Call: ' + callLine(c) + '\n\n';
        String html = details(c);
        if (String.isNotBlank(c.Transcript_Summary__c)) {
            text += 'SUMMARY\n' + c.Transcript_Summary__c + '\n\n';
            html += heading('Summary')
                + '<div style="background:#f0f8f7;border-left:3px solid ' + TEAL + ';padding:12px 14px;margin:0 0 16px;font-size:14px;line-height:1.5;">'
                + c.Transcript_Summary__c.escapeHtml4() + '</div>';
        }
        if (pdf != null) {
            html += '<p style="margin:0;font-size:13px;color:' + MUTED + ';">The full transcript is in the attached PDF.</p>';
        } else {
            text += 'TRANSCRIPT\n' + c.Transcript__c + '\n';
            html += heading('Transcript') + transcriptHtml(c);
        }
        Messaging.SingleEmailMessage m = message(userId, 'Call transcript: ' + recordName(c), text, frame('Call transcript', html));
        if (pdf != null) m.setFileAttachments(new List<Messaging.EmailFileAttachment>{ pdf });
        return m;
    }

    private static Messaging.SingleEmailMessage failureEmail(Call_Log__c c) {
        String reason = problemOf(c.Transcript_Status__c);
        String text = 'We could not transcribe this call.\n\n'
            + 'Client: ' + recordName(c) + '\n'
            + 'Call: ' + callLine(c) + '\n'
            + 'Reason: ' + reason + '\n\n'
            + 'You can press Transcribe again on the Call History.\n';
        String html = details(c)
            + '<div style="background:#fef2f2;border-left:3px solid ' + RED + ';padding:12px 14px;margin:0 0 16px;font-size:14px;line-height:1.5;">'
            + reason.escapeHtml4() + '</div>'
            + '<p style="margin:0;font-size:13px;color:' + MUTED + ';">You can press Transcribe again on the Call History.</p>';
        return message(c.Transcript_Requested_By__c, 'Call not transcribed: ' + recordName(c), text, frame('Call not transcribed', html));
    }

    /** Tables and inline styles: the only layout email clients agree on. */
    private static String frame(String title, String content) {
        return '<div style="background:#f3f4f6;padding:24px 12px;font-family:Arial,Helvetica,sans-serif;color:#262626;">'
            + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;background:#ffffff;border-top:4px solid ' + TEAL + ';">'
            + '<tr><td style="padding:24px 24px 0;"><img src="' + LOGO + '" alt="XtraPension" width="150" style="display:block;border:0;height:auto;"/></td></tr>'
            + '<tr><td style="padding:20px 24px 24px;">'
            + '<div style="margin:0 0 16px;font-size:20px;font-weight:bold;color:' + TEAL + ';">' + title + '</div>'
            + content
            + '</td></tr>'
            + '<tr><td style="padding:12px 24px;background:' + TEAL + ';color:#ffffff;font-size:12px;">XtraPension Call History</td></tr>'
            + '</table></div>';
    }

    private static String heading(String text) {
        return '<div style="margin:0 0 6px;font-size:13px;font-weight:bold;color:' + TEAL + ';">' + text + '</div>';
    }

    private static String details(Call_Log__c c) {
        String name = recordName(c).escapeHtml4();
        return '<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 16px;font-size:14px;line-height:1.6;">'
            + '<tr><td style="padding-right:16px;color:' + MUTED + ';">Client</td><td style="font-weight:bold;">' + name + '</td></tr>'
            + '<tr><td style="padding-right:16px;color:' + MUTED + ';">Call</td><td>' + callLine(c).escapeHtml4() + '</td></tr>'
            + '</table>'
            + '<a href="' + linkOf(c) + '" style="display:inline-block;margin:0 0 20px;padding:10px 18px;background:' + YELLOW
            + ';color:#000000;font-size:14px;font-weight:bold;text-decoration:none;border-radius:4px;">Open ' + name + ' in Salesforce</a>';
    }

    /** "[00:00] Speaker A: Hello", one paragraph per line, the time and the speaker set apart. */
    @TestVisible
    private static String transcriptHtml(Call_Log__c c) {
        List<String> out = new List<String>();
        for (String line : c.Transcript__c.split('\n')) {
            if (line.startsWith('[') && line.contains('] ') && line.contains(': ')) {
                out.add('<p style="margin:0 0 8px;font-size:14px;line-height:1.4;"><span style="color:' + MUTED + ';">'
                    + line.substringBefore('] ').escapeHtml4() + ']</span> <b>'
                    + line.substringAfter('] ').substringBefore(': ').escapeHtml4() + ':</b> '
                    + line.substringAfter(': ').escapeHtml4() + '</p>');
            } else {
                out.add('<p style="margin:0 0 8px;font-size:14px;line-height:1.4;">' + line.escapeHtml4() + '</p>');
            }
        }
        return String.join(out, '');
    }

    /** XP AI's PDF. Null when it does not come, and then the transcript goes in the body of the email. */
    private static Messaging.EmailFileAttachment pdfOf(Call_Log__c c) {
        try {
            Map<String, Object> body = callDetails(c);
            body.put('transcript', c.Transcript__c);
            body.put('summary', c.Transcript_Summary__c);
            HttpResponse res = callXpAi('/calls/transcript-pdf', body);
            if (res == null || res.getStatusCode() != 200) return null;
            String pdf = (String) ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('pdf');
            if (String.isBlank(pdf)) return null;
            Messaging.EmailFileAttachment file = new Messaging.EmailFileAttachment();
            file.setFileName('Transcript ' + recordName(c) + '.pdf');
            file.setContentType('application/pdf');
            file.setBody(EncodingUtil.base64Decode(pdf));
            return file;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, '[CallTranscript] PDF: ' + e.getMessage());
            return null;
        }
    }

    private static Messaging.SingleEmailMessage message(Id userId, String subject, String text, String html) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setTargetObjectId(userId);
        m.setSaveAsActivity(false);
        m.setUseSignature(false);
        m.setSubject(subject);
        m.setPlainTextBody(text);
        m.setHtmlBody(html);
        List<OrgWideEmailAddress> address = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :SENDER LIMIT 1];
        if (!address.isEmpty()) m.setOrgWideEmailAddressId(address[0].Id);
        return m;
    }

    private static void send(List<Messaging.SingleEmailMessage> emails) {
        if (emails.isEmpty()) return;
        Messaging.sendEmail(emails);
        emailsSent += emails.size();
    }
}