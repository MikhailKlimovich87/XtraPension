global class ClientSupportEmailServiceHandler implements Messaging.InboundEmailHandler {
    global final String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String subject = email.subject;
        if (email.fromAddress == 'dse@eumail.docusign.net' || email.fromAddress == 'clients@xtrapension.com') {
            result.success = false;
            return result;
        }
        Messaging.InboundEmail.BinaryAttachment[] emailAttachments = email.binaryAttachments;
        Email_Message_Status__c newStatus = new Email_Message_Status__c();
        insert newStatus;
        EmailMessage emailMessage = new EmailMessage();
        emailMessage.status = '3';
        emailMessage.fromAddress = email.fromAddress;
        emailMessage.fromName = email.fromName;
        emailMessage.ToAddress = ORG_WIDE_EMAIL_ADDRESS;
        emailMessage.Subject = String.isBlank(subject) ? 'Empty' : subject;
        emailMessage.HtmlBody = email.htmlBody != null && email.htmlBody.length() >= 131072 ? email.htmlBody.substring(0, 131072) : email.htmlBody;
        emailMessage.TextBody = email.plainTextBody != null && email.plainTextBody.length() >= 131072 ? email.plainTextBody.substring(0, 131072) : email.plainTextBody;
        emailMessage.Has_Attachment__c = emailAttachments != null ? true : false;
        emailMessage.Email_Message_Status__c = newStatus.Id;

        // Legacy Application__c match — resolved OUTSIDE the try so the existing
        // ~866-record flow behaves exactly as before. `bestWhen` lets the AA/PC1
        // matches below override ONLY when a strictly newer active record exists
        // (a dual-enrolled client's reply belongs on the active record, not the
        // stale legacy one — audit 2026-08-28).
        Datetime bestWhen = null;
        if (email.fromAddress != null) {
            List<Application__c> applications = [
                SELECT Id, Email__c, LastModifiedDate
                FROM Application__c
                WHERE Email__c = :email.fromAddress
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            if (!applications.isEmpty()) {
                emailMessage.relatedToId    = applications[0].Id;
                emailMessage.Application__c = applications[0].Id;
                bestWhen = applications[0].LastModifiedDate;
            }
        }
        // ── Multi-project routing across the shared clients@ mailbox ──────
        // Route to the MOST RECENTLY MODIFIED matching record; a pure-legacy
        // sender only matches Application__c so that flow is unchanged. Wrapped
        // in try/catch — on failure the legacy match (set above) still stands.
        try {
            if (String.isNotBlank(email.fromAddress)) {
                // PC1 — override the legacy match only if strictly newer.
                for (PC1_Application__c p : [
                        SELECT Id, LastModifiedDate FROM PC1_Application__c
                        WHERE Email__c = :email.fromAddress
                        ORDER BY LastModifiedDate DESC LIMIT 1]) {
                    if (bestWhen == null || p.LastModifiedDate > bestWhen) {
                        emailMessage.RelatedToId = p.Id;
                        emailMessage.Application__c = null;
                        emailMessage.Is_PC1_Application__c = true;
                        emailMessage.Is_AA_Application__c = false;
                        emailMessage.Incoming = true;
                        bestWhen = p.LastModifiedDate;
                    }
                }
                // AA — override if strictly newer than the current best.
                for (AA_Application__c aa : [
                        SELECT Id, LastModifiedDate FROM AA_Application__c
                        WHERE Email__c = :email.fromAddress
                        ORDER BY LastModifiedDate DESC LIMIT 1]) {
                    if (bestWhen == null || aa.LastModifiedDate > bestWhen) {
                        emailMessage.RelatedToId = aa.Id;
                        emailMessage.Application__c = null;
                        emailMessage.Is_AA_Application__c = true;
                        emailMessage.Is_PC1_Application__c = false;
                        emailMessage.Incoming = true;
                        bestWhen = aa.LastModifiedDate;
                    }
                }
                // Helper_Email__c — the dispatcher CCs the helper on every email,
                // so a reply from the helper's own address should reach the app.
                // Only when nothing matched the sender's own address.
                if (emailMessage.RelatedToId == null) {
                    for (AA_Application__c aa : [
                            SELECT Id FROM AA_Application__c
                            WHERE Helper_Email__c = :email.fromAddress
                            ORDER BY LastModifiedDate DESC LIMIT 1]) {
                        emailMessage.RelatedToId = aa.Id;
                        emailMessage.Is_AA_Application__c = true;
                        emailMessage.Incoming = true;
                    }
                }
                if (emailMessage.RelatedToId == null) {
                    for (PC1_Application__c p : [
                            SELECT Id FROM PC1_Application__c
                            WHERE Helper_Email__c = :email.fromAddress
                            ORDER BY LastModifiedDate DESC LIMIT 1]) {
                        emailMessage.RelatedToId = p.Id;
                        emailMessage.Is_PC1_Application__c = true;
                        emailMessage.Incoming = true;
                    }
                }
            }
            // Thread fallback via In-Reply-To/References. NB: only matches when a
            // PRIOR inbound EmailMessage stored that Message-Id — the dispatcher
            // mirror uses a SYNTHETIC MessageIdentifier that never equals an
            // outbound email's real Message-Id, so this does NOT thread replies
            // to dispatcher-sent emails (those rely on the sender/Helper match
            // above). Kept for inbound→inbound chains (audit 2026-08-28).
            if (emailMessage.RelatedToId == null) {
                Set<String> refIds = extractRefIds(email);
                if (!refIds.isEmpty()) {
                    List<EmailMessage> parents = [
                        SELECT RelatedToId, Application__c,
                               Is_PC1_Application__c, Is_AA_Application__c
                        FROM EmailMessage
                        WHERE MessageIdentifier IN :refIds AND RelatedToId != null
                        ORDER BY MessageDate DESC LIMIT 1];
                    if (!parents.isEmpty()) {
                        emailMessage.RelatedToId           = parents[0].RelatedToId;
                        emailMessage.Application__c        = parents[0].Application__c;
                        emailMessage.Is_PC1_Application__c = parents[0].Is_PC1_Application__c;
                        emailMessage.Is_AA_Application__c  = parents[0].Is_AA_Application__c;
                        if (parents[0].Is_PC1_Application__c || parents[0].Is_AA_Application__c) {
                            emailMessage.Incoming = true;
                        }
                    }
                }
            }
        } catch (Exception routingEx) {
            // Surface a durable-ish signal (result.message + ERROR log) instead
            // of a silent WARN — an FLS/deploy regression that disables routing
            // must be visible, not swallowed (the pattern that hid the AES bug).
            // The legacy Application__c match (set before the try) still stands.
            result.message = 'Multi-project routing error: ' + routingEx.getMessage();
            System.debug(LoggingLevel.ERROR,
                'ClientSupportEmailServiceHandler routing error: ' + routingEx.getMessage());
        }


        if (emailMessage != null) {
            insert emailMessage;
        }
        // Attachment ingestion — guarded (audit 2026-08-28): only persist when
        // the message matched a record, and bound count + total bytes so an
        // unauthenticated sender to the public clients@ address can't fill File
        // Storage or drop arbitrary files onto the org.
        if (emailAttachments != null && emailMessage != null && emailMessage.RelatedToId != null) {
            final Integer MAX_ATT = 10;
            final Long MAX_TOTAL_BYTES = 25L * 1024 * 1024;
            List<ContentVersion> attachContVersions = new List<ContentVersion>();
            Long totalBytes = 0;
            for (Messaging.InboundEmail.BinaryAttachment attachment : emailAttachments) {
                if (attachContVersions.size() >= MAX_ATT || attachment.body == null) continue;
                totalBytes += attachment.body.size();
                if (totalBytes > MAX_TOTAL_BYTES) break;
                ContentVersion conVer = new ContentVersion();
                conVer.ContentLocation = 'S';
                conVer.PathOnClient = attachment.fileName;
                conVer.Title = attachment.fileName;
                conVer.VersionData = attachment.body;
                attachContVersions.add(conVer);
            }
            if (!attachContVersions.isEmpty()) insert attachContVersions;
            Set<Id> contVersIds = new Set<Id>();
            for (ContentVersion version : attachContVersions) {
	            contVersIds.add(version.id);
            }
            List<ContentVersion> contVersAfterInsert = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :contVersIds
            ];
            Set<Id> contDocIds = new Set<Id>();
            for (ContentVersion version : contVersAfterInsert) {
                contDocIds.add(version.ContentDocumentId);
            }
            List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
            for (Id conDocId : contDocIds) {
                ContentDocumentLink conDocLink = new ContentDocumentLink();
                conDocLink.LinkedEntityId = emailMessage.Id;
                conDocLink.ContentDocumentId = conDocId;
                conDocLink.shareType = 'V';
                conDocLink.Visibility = 'AllUsers';
                newLinks.add(conDocLink);
            }
            if (!newLinks.isEmpty()) {
                insert newLinks;
            }
        }
        result.success = true;
        return result;
    }

    // Added 2026-08-27 — parse In-Reply-To / References into a set of Message-Ids.
    private static Set<String> extractRefIds(Messaging.InboundEmail email) {
        Set<String> out = new Set<String>();
        if (email == null || email.headers == null) return out;
        for (Messaging.InboundEmail.Header h : email.headers) {
            if (h == null || h.name == null) continue;
            if (h.name.equalsIgnoreCase('In-Reply-To') || h.name.equalsIgnoreCase('References')) {
                if (String.isNotBlank(h.value)) {
                    for (String tok : h.value.split('\\s+|,')) {
                        String s = tok.trim();
                        if (s.startsWith('<') && s.endsWith('>')) s = s.substring(1, s.length() - 1);
                        if (String.isNotBlank(s)) out.add(s);
                    }
                }
            }
        }
        return out;
    }
}