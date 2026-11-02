/**
 * PC1_InboundEmailHandler — universal client-reply router.
 * Receives forwarded emails from clients@xtrapension.com (Gmail auto-forward
 * ALL inbound to this Email Service) and routes each one to the correct
 * app record by matching the sender address against every known product's
 * Email__c / Helper_Email__c field. Unmatched mails still land as
 * EmailMessage rows with RelatedToId=null so a human can triage.
 *
 * Routing priority (first match wins):
 *   1. Thread match — In-Reply-To / References → EmailMessage.MessageIdentifier
 *      (works for any product because outbound dispatchers all stamp it)
 *   2. Sender match — PC1_Application (Email__c OR Helper_Email__c)
 *   3. Sender match — AA_Application  (Email__c OR Helper_Email__c)
 *   4. Sender match — Application     (Email__c, State Pension)
 *   5. Unmatched → EmailMessage with RelatedToId=null (triage queue)
 */
global class PC1_InboundEmailHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope env
    ) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        try {
            processEmail(email, env);
            result.success = true;
        } catch (Exception e) {
            // Persist to DLQ so replies aren't lost silently (audit C3).
            // Best-effort insert — if the DLQ itself fails we still return
            // success=true (SF would otherwise bounce the sender's email).
            try {
                insert new PC1_Inbound_Email_DLQ__c(
                    From_Address__c = truncateTo(email.fromAddress, 255),
                    Subject__c      = truncateTo(email.subject, 255),
                    Error_Message__c = truncateTo(e.getMessage() + '\n' + e.getStackTraceString(), 32000),
                    Headers__c      = truncateTo(serialiseHeaders(email.headers), 32000),
                    Body_Text__c    = truncateTo(email.plainTextBody, 32000)
                );
            } catch (Exception dlqErr) {
                System.debug(LoggingLevel.ERROR, 'PC1_InboundEmailHandler: DLQ insert failed: ' + dlqErr.getMessage());
            }
            System.debug(LoggingLevel.ERROR, 'PC1_InboundEmailHandler failure: ' + e.getMessage() + '\n' + e.getStackTraceString());
            result.success = true;
            result.message = 'Handled with warnings: ' + e.getMessage();
        }
        return result;
    }

    /**
     * HMRC printing-house detector — REQUIRES sender in gov.uk/hmrc.gov.uk
     * to avoid killing legit client emails that quote an HMRC letter (C2).
     * Also strips HTML before searching so HTML-only HMRC mails still match (H19).
     */
    @TestVisible
    private static Boolean isHmrcPrintingHouseReply(Messaging.InboundEmail email) {
        if (email == null) return false;
        String sender = String.isBlank(email.fromAddress) ? '' : email.fromAddress.toLowerCase();
        Boolean fromGovUk = sender.endsWith('@gov.uk') || sender.endsWith('.gov.uk') || sender.contains('@hmrc.');
        if (!fromGovUk) return false;
        String body = String.isNotBlank(email.plainTextBody)
            ? email.plainTextBody
            : stripHtml(email.htmlBody);
        if (String.isBlank(body)) return false;
        return body.contains('AppID:') && body.contains('Tracking No:');
    }

    @TestVisible
    private static String stripHtml(String html) {
        if (String.isBlank(html)) return null;
        // Cheap tag-strip — enough for keyword lookup. Not a sanitizer.
        return html.replaceAll('<[^>]+>', ' ').replaceAll('&nbsp;', ' ');
    }

    @TestVisible
    private static String serialiseHeaders(List<Messaging.InboundEmail.Header> hs) {
        if (hs == null || hs.isEmpty()) return null;
        List<String> out = new List<String>();
        for (Messaging.InboundEmail.Header h : hs) {
            if (h != null && String.isNotBlank(h.name)) out.add(h.name + ': ' + h.value);
        }
        return String.join(out, '\n');
    }

    /** Split out for unit testing without needing the Messaging fixtures. */
    @TestVisible
    private static void processEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope env) {
        // ── 0) Skip HMRC printing-house replies — those belong to
        //     XtraPensionEmailServiceHandler which parses AppID + Tracking No.
        //     Defense-in-depth in case Gmail filters overlap.
        //     Sender gate REQUIRED — a client forwarding an HMRC letter with
        //     'AppID:'/'Tracking No:' in the quoted body would otherwise be
        //     silently dropped (audit C2). ──
        if (isHmrcPrintingHouseReply(email)) {
            System.debug(LoggingLevel.INFO, 'PC1_InboundEmailHandler: skipping HMRC printing-house reply — owned by XtraPensionEmailServiceHandler.');
            return;
        }

        // ── 0a) Noise gate (2026-09-03 sandbox storage audit) — silently drop
        //     mail from own-org / robot senders. These are outbound copies
        //     that Gmail-side forwarding loops back into the service address:
        //     receipts, DocuSign notifications, Slack relay traffic, bounces.
        //     They arrive with no valid PC1 sender so they'd all land in the
        //     null-Related triage queue anyway, dragging PDFs into storage. ──
        String fromLc = String.isBlank(email.fromAddress) ? '' : email.fromAddress.toLowerCase();
        if (fromLc.endsWith('@xtrapension.com')
                || fromLc.startsWith('mailer-daemon@')
                || fromLc.endsWith('.slack.com')
                || fromLc.contains('@eumail.docusign.net')
                || fromLc.contains('@docusign.net')) {
            System.debug(LoggingLevel.INFO, 'PC1_InboundEmailHandler: noise-gate drop from=' + fromLc);
            return;
        }

        // ── 1) Find the parent EmailMessage via In-Reply-To / References ──
        Id relatedToId = null;
        String inReplyTo = extractHeader(email, 'In-Reply-To');
        String referencesHdr = extractHeader(email, 'References');
        Set<String> candidateMsgIds = new Set<String>();
        if (String.isNotBlank(inReplyTo))    candidateMsgIds.addAll(splitMessageIds(inReplyTo));
        if (String.isNotBlank(referencesHdr)) candidateMsgIds.addAll(splitMessageIds(referencesHdr));

        if (!candidateMsgIds.isEmpty()) {
            List<EmailMessage> parents = [
                SELECT Id, RelatedToId, ThreadIdentifier
                FROM EmailMessage
                WHERE MessageIdentifier IN :candidateMsgIds
                ORDER BY MessageDate DESC
                LIMIT 1
            ];
            if (!parents.isEmpty() && parents[0].RelatedToId != null) {
                relatedToId = parents[0].RelatedToId;
            }
        }

        // ── 1b) Subject reference token — support-desk style [PC-00042] set
        //     by dispatcher (C1 fix). Cheaper and more reliable than
        //     MessageIdentifier, since SF doesn't expose Message-Id setter
        //     on SingleEmailMessage and the header we stamp never reaches
        //     the SMTP wire.
        if (relatedToId == null && String.isNotBlank(email.subject)) {
            relatedToId = routeBySubjectToken(email.subject);
        }

        // ── 2) Fallback: match sender email against every product's Email/Helper fields ──
        if (relatedToId == null && String.isNotBlank(email.fromAddress)) {
            relatedToId = routeBySenderEmail(email.fromAddress);
        }

        // ── 3) Create the EmailMessage row ──
        EmailMessage em = new EmailMessage();
        em.Incoming = true;
        em.Status = '0';                         // '0' = New (unread)
        em.Subject = safeSubject(email.subject);
        em.FromAddress = email.fromAddress;
        em.FromName = email.fromName;
        em.ToAddress = joinList(email.toAddresses);
        em.CcAddress = joinList(email.ccAddresses);
        em.HtmlBody = String.isNotBlank(email.htmlBody) ? email.htmlBody : null;
        em.TextBody = String.isNotBlank(email.plainTextBody) ? email.plainTextBody : null;
        em.MessageDate = Datetime.now();
        em.MessageIdentifier = truncateTo(extractHeader(email, 'Message-Id'), 255);
        em.ThreadIdentifier = truncateTo(extractHeader(email, 'Thread-Index'), 255);
        em.RelatedToId = relatedToId;
        // HasAttachment is auto-derived by the platform based on child
        // ContentDocumentLinks — read-only on insert (SF error otherwise).
        insert em;

        // ── 4) EmailMessageRelation for FromAddress (drives the timeline avatar) ──
        try {
            insert new EmailMessageRelation(
                EmailMessageId  = em.Id,
                RelationAddress = email.fromAddress,
                RelationType    = 'FromAddress'
            );
            for (String toAddr : safeList(email.toAddresses)) {
                insert new EmailMessageRelation(
                    EmailMessageId  = em.Id,
                    RelationAddress = toAddr,
                    RelationType    = 'ToAddress'
                );
            }
        } catch (DmlException e) {
            System.debug(LoggingLevel.WARN, 'EMR insert warning: ' + e.getMessage());
        }

        // ── 5) Attachments — persist ONLY when routed to a real record
        //     (2026-09-03 sandbox storage audit: 3,439 unrouted mails
        //     dragged ~107MB of PDFs into file storage). Unrouted mail
        //     keeps a metadata-only EM row for triage; the original
        //     attachment is still in the Gmail inbox if a human re-parents.
        //     Also bounded: max 10 files, 25MB total per email. ──
        if (email.binaryAttachments != null && !email.binaryAttachments.isEmpty()
                && relatedToId != null) {
            final Integer MAX_ATT = 10;
            final Long MAX_TOTAL_BYTES = 25L * 1024 * 1024;
            List<ContentVersion> cvs = new List<ContentVersion>();
            Long total = 0;
            for (Messaging.InboundEmail.BinaryAttachment att : email.binaryAttachments) {
                if (cvs.size() >= MAX_ATT || att.body == null) break;
                total += att.body.size();
                if (total > MAX_TOTAL_BYTES) break;
                cvs.add(new ContentVersion(
                    Title = att.fileName,
                    PathOnClient = att.fileName,
                    VersionData = att.body,
                    FirstPublishLocationId = em.Id
                ));
            }
            if (!cvs.isEmpty()) insert cvs;
        }
    }

    /**
     * Parse the [AppName-nonce] token from subject and VERIFY the nonce
     * matches an EmailMessage we sent. Prevents subject-token spoofing:
     * an attacker sending 'Subject: [PC00031] update bank' from any email
     * won't have the 16-hex nonce we generated per outbound message, so
     * the query returns 0 rows and RelatedToId stays null.
     *
     * Legacy: subjects without a nonce (or with an unverified nonce) are
     * IGNORED and the handler falls through to sender-match, which does
     * gate on the sender being a known client.
     */
    @TestVisible
    private static Id routeBySubjectToken(String subject) {
        if (String.isBlank(subject)) return null;
        Pattern p = Pattern.compile('\\[[A-Z]{1,4}[- ]?\\d{3,10}-([a-f0-9]{16})\\]');
        Matcher m = p.matcher(subject);
        if (!m.find()) return null;
        String nonce = m.group(1);
        // Query the mirror EmailMessage created by PC1_MessageDispatcher — its
        // MessageIdentifier suffix is the same nonce. Copy its RelatedToId.
        String nonceLike = '%-' + nonce + '@xtrapension.com';
        List<EmailMessage> parents = [
            SELECT RelatedToId FROM EmailMessage
            WHERE MessageIdentifier LIKE :nonceLike
              AND RelatedToId != null
            ORDER BY MessageDate DESC
            LIMIT 1
        ];
        return parents.isEmpty() ? null : parents[0].RelatedToId;
    }

    /**
     * Universal sender→record router. Priority order matters — PC1 is our
     * newest, highest-touch product so we check it first; ties within a
     * product are broken by LastModifiedDate DESC so the freshest
     * conversation wins (a client can have multiple apps over years).
     * All queries are safe against blank input because the caller gated it.
     */
    @TestVisible
    private static Id routeBySenderEmail(String fromAddress) {
        // 1) PC1
        List<PC1_Application__c> pc1 = [
            SELECT Id FROM PC1_Application__c
            WHERE Email__c = :fromAddress OR Helper_Email__c = :fromAddress
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        if (!pc1.isEmpty()) return pc1[0].Id;

        // 2) AA (Attendance Allowance) — object may not exist in every org
        try {
            List<SObject> aa = Database.query(
                'SELECT Id FROM AA_Application__c ' +
                'WHERE Email__c = :fromAddress OR Helper_Email__c = :fromAddress ' +
                'ORDER BY LastModifiedDate DESC LIMIT 1'
            );
            if (!aa.isEmpty()) return (Id) aa[0].get('Id');
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'AA_Application__c lookup skipped: ' + e.getMessage());
        }

        // 3) Application (State Pension / legacy)
        try {
            List<SObject> sp = Database.query(
                'SELECT Id FROM Application__c ' +
                'WHERE Email__c = :fromAddress ' +
                'ORDER BY LastModifiedDate DESC LIMIT 1'
            );
            if (!sp.isEmpty()) return (Id) sp[0].get('Id');
        } catch (Exception e) {
            System.debug(LoggingLevel.INFO, 'Application__c lookup skipped: ' + e.getMessage());
        }

        return null;
    }

    // ── helpers ─────────────────────────────────────────────────────────
    @TestVisible private static String extractHeader(Messaging.InboundEmail email, String name) {
        if (email.headers == null) return null;
        for (Messaging.InboundEmail.Header h : email.headers) {
            if (h != null && h.name != null && h.name.equalsIgnoreCase(name)) return h.value;
        }
        return null;
    }
    @TestVisible private static Set<String> splitMessageIds(String raw) {
        Set<String> out = new Set<String>();
        if (String.isBlank(raw)) return out;
        // Message-Ids in headers look like: <a@b.com> <c@d.com>
        for (String tok : raw.split('\\s+|,')) {
            String s = tok.trim();
            if (s.startsWith('<') && s.endsWith('>')) s = s.substring(1, s.length() - 1);
            if (String.isNotBlank(s)) out.add(s);
        }
        return out;
    }
    private static String safeSubject(String s) {
        return String.isBlank(s) ? '(no subject)' : (s.length() > 3000 ? s.substring(0, 3000) : s);
    }
    private static String truncateTo(String s, Integer max) {
        if (String.isBlank(s)) return null;
        return s.length() > max ? s.substring(0, max) : s;
    }
    private static String joinList(List<String> lst) {
        if (lst == null || lst.isEmpty()) return null;
        return String.join(lst, '; ');
    }
    private static List<String> safeList(List<String> lst) {
        return lst == null ? new List<String>() : lst;
    }
}