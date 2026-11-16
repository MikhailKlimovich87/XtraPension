/**
 * WhatsApp panel on the claim (xpClaimsWhatsAppPanel). Same methods as the Sales
 * panel (XpWhatsAppController), but served by the XP AI for Claims service
 * through the XP_AI_CLAIMS Named Credential, so the Sales panel is never touched
 * by this one. The service resolves the phone from the claim: the client
 * (Phone__c) or the helper (Friend_Phone__c), as the panel says in "contact".
 * Every send carries who clicked it.
 */
public with sharing class XpClaimsWhatsAppController {

    @AuraEnabled
    public static Map<String, Object> getThread(Id claimId, String contact) {
        return call('/wa/thread', base(claimId, contact), 30000);
    }

    @AuraEnabled
    public static Map<String, Object> sendMessage(Id claimId, String contact, String messageBody) {
        if (String.isBlank(messageBody)) {
            throw new AuraHandledException('Message body is empty.');
        }
        Map<String, Object> body = base(claimId, contact);
        body.put('body', messageBody);
        return sent(claimId, call('/wa/send', body, 30000));
    }

    /** A file already on the claim (picked in the panel). */
    @AuraEnabled
    public static Map<String, Object> sendFileMessage(Id claimId, String contact, Id contentVersionId, String caption) {
        if (contentVersionId == null) {
            throw new AuraHandledException('Pick a file first.');
        }
        Map<String, Object> body = base(claimId, contact);
        body.put('contentVersionId', (String) contentVersionId);
        body.put('caption', caption);
        return sent(claimId, call('/wa/send-file', body, 120000));
    }

    /** A file picked on the computer, sent as base64. */
    @AuraEnabled
    public static Map<String, Object> sendFileFromBrowser(Id claimId, String contact, String filename, String mime, String base64Body, String caption) {
        if (String.isBlank(base64Body)) {
            throw new AuraHandledException('The file is empty.');
        }
        Map<String, Object> body = base(claimId, contact);
        body.put('filename', filename);
        body.put('mime', mime);
        body.put('base64Body', base64Body);
        body.put('caption', caption);
        return sent(claimId, call('/wa/send-file-inline', body, 120000));
    }

    /**
     * AI Reply: starts drafting the next message (never sends it). Whatever the
     * agent already typed in the box goes as the instruction. Poll getAiReply.
     */
    @AuraEnabled
    public static Map<String, Object> startAiReply(Id claimId, String contact, String instruction) {
        Map<String, Object> body = base(claimId, contact);
        body.put('hint', instruction);
        return call('/wa/ai-reply', body, 30000);
    }

    /** Rewrite: polishes the text in the box without changing what it says. Poll getAiReply. */
    @AuraEnabled
    public static Map<String, Object> startRewrite(Id claimId, String contact, String text) {
        if (String.isBlank(text)) {
            throw new AuraHandledException('Write something in the box first.');
        }
        Map<String, Object> body = base(claimId, contact);
        body.put('mode', 'rewrite');
        body.put('text', text);
        return call('/wa/ai-reply', body, 30000);
    }

    @AuraEnabled
    public static Map<String, Object> getAiReply(String jobId) {
        if (String.isBlank(jobId) || !Pattern.matches('[0-9a-f-]{36}', jobId)) {
            throw new AuraHandledException('Unknown request. Press AI Reply again.');
        }
        return call('/wa/ai-reply/' + jobId, new Map<String, Object>(), 30000);
    }

    /** Files linked to the claim, for the "From Salesforce Files" picker. */
    @AuraEnabled
    public static List<FileRow> listClaimFiles(Id claimId) {
        List<Id> docIds = new List<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :claimId
        ]) {
            docIds.add(cdl.ContentDocumentId);
        }
        List<FileRow> out = new List<FileRow>();
        if (docIds.isEmpty()) {
            return out;
        }
        for (ContentVersion cv : [
            SELECT Id, Title, PathOnClient, FileType, ContentSize, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
            ORDER BY CreatedDate DESC
        ]) {
            FileRow r = new FileRow();
            r.contentVersionId = cv.Id;
            r.title = cv.Title;
            r.filename = cv.PathOnClient;
            r.fileType = cv.FileType;
            r.size = cv.ContentSize;
            r.createdAt = cv.CreatedDate;
            out.add(r);
        }
        return out;
    }

    public class FileRow {
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String title;
        @AuraEnabled public String filename;
        @AuraEnabled public String fileType;
        @AuraEnabled public Integer size;
        @AuraEnabled public Datetime createdAt;
    }

    /** The claim and who is on the other end: the client unless the panel says helper. */
    /** The message is out: it is the Last Contact of whoever pressed Send. */
    private static Map<String, Object> sent(Id claimId, Map<String, Object> result) {
        LastContactController.whatsAppSent(claimId);
        return result;
    }

    private static Map<String, Object> base(Id claimId, String contact) {
        return new Map<String, Object>{
            'claimId' => (String) claimId,
            'contact' => contact == 'helper' ? 'helper' : 'client'
        };
    }

    private static Map<String, Object> call(String path, Map<String, Object> body, Integer timeoutMs) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:XP_AI_CLAIMS' + path);
        req.setMethod('POST');
        req.setTimeout(timeoutMs);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-XPAI-User', UserInfo.getUserId());
        req.setHeader('X-XPAI-Name', EncodingUtil.urlEncode(UserInfo.getName(), 'UTF-8'));
        req.setBody(JSON.serialize(body));
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new AuraHandledException('WhatsApp is not reachable right now. Try again in a minute.');
        }
        if (res.getStatusCode() == 401) {
            throw new AuraHandledException('WhatsApp service refused the connection. Tell Fernando.');
        }
        Map<String, Object> parsed = null;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        } catch (Exception e) {
            parsed = null;
        }
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            String msg = parsed != null && parsed.get('error') != null ? String.valueOf(parsed.get('error')) : 'HTTP ' + res.getStatusCode();
            throw new AuraHandledException(msg);
        }
        return parsed == null ? new Map<String, Object>() : parsed;
    }
}