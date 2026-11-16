/**
 * XP AI for Claims panel. Relays the xpAiClaimsChat component to the XP AI for
 * Claims service (its own process, /xpai-claims/ on the automations VPS) through
 * the XP_AI_CLAIMS Named Credential (HTTP Basic, secret stored encrypted by
 * Salesforce). Same shape as XpAiController, kept apart so the main XP AI panel
 * is never touched by the Claims one. It only adds who is asking and refuses
 * any path the panel does not use.
 */
public with sharing class XpAiClaimsController {

    private static final Pattern ALLOWED = Pattern.compile(
        '^(POST /turn'
        + '|GET /turn/[0-9a-f-]{36}'
        + '|POST /reset'
        + '|GET /history(\\?recordId=[a-zA-Z0-9]{15,18})?'
        + '|GET /chats'
        + '|GET /context\\?recordId=[a-zA-Z0-9]{15,18}'
        + '|POST /feedback)$'
    );

    @AuraEnabled
    public static String send(String method, String path, String body) {
        if (!isAllowed(method, path)) {
            throw new AuraHandledException('Not allowed.');
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:XP_AI_CLAIMS' + path);
        req.setMethod(method);
        req.setTimeout(60000);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-XPAI-User', UserInfo.getUserId());
        req.setHeader('X-XPAI-Name', EncodingUtil.urlEncode(UserInfo.getName(), 'UTF-8'));
        if (method == 'POST') {
            req.setBody(String.isBlank(body) ? '{}' : body);
        }
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new AuraHandledException('XP AI for Claims is not reachable right now. Try again in a minute.');
        }
        if (res.getStatusCode() == 401) {
            throw new AuraHandledException('XP AI for Claims refused the connection. Tell Fernando.');
        }
        return res.getBody();
    }

    @TestVisible
    private static Boolean isAllowed(String method, String path) {
        if (String.isBlank(method) || String.isBlank(path)) {
            return false;
        }
        return ALLOWED.matcher(method + ' ' + path).matches();
    }
}