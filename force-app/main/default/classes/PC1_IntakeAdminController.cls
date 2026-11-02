/**
 * PC1_IntakeAdminController — @AuraEnabled backend for the pc1IntakeUsers LWC
 * (admin page "PC Intake Users"). Manages Intake_User__c rows: list, create,
 * reset password, activate / deactivate, delete.
 *
 * Password handling is delegated: SF NEVER stores or receives back the plain
 * password. The LWC sends {username, password} into createUser / resetPassword,
 * this class forwards them to the Heroku endpoint
 *   POST /internal/intake/set-password
 * which bcrypts the password and writes the resulting hash back onto the
 * Intake_User__c row via jsforce. The endpoint is authenticated by the shared
 * secret PC1_Config__c.Internal_Admin_Token__c (matches INTERNAL_ADMIN_TOKEN
 * on the Heroku dyno), sent in the `x-internal-token` header.
 *
 * setActive + deleteUser touch the SF row directly — no callout needed.
 *
 * Remote Site Setting PC1_Heroku_Autofill must whitelist the base URL (same
 * one used by PC1_HerokuBridge). Callout base URL comes from
 * PC1_Config__c.Heroku_Base_Url__c.
 */
public with sharing class PC1_IntakeAdminController {

    public class UserRow {
        @AuraEnabled public String id;
        @AuraEnabled public String username;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Datetime lastLoginAt;
        @AuraEnabled public Integer failedLoginCount;
        @AuraEnabled public Datetime lockedAt;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserRow> listUsers() {
        List<Intake_User__c> rows = [
            SELECT Id, Username__c, Role__c, Active__c,
                   Last_Login_At__c, Failed_Login_Count__c, Locked_At__c
            FROM Intake_User__c
            ORDER BY Active__c DESC, Username__c ASC
        ];
        List<UserRow> out = new List<UserRow>();
        for (Intake_User__c r : rows) {
            UserRow u = new UserRow();
            u.id = r.Id;
            u.username = r.Username__c;
            u.role = r.Role__c;
            u.active = r.Active__c;
            u.lastLoginAt = r.Last_Login_At__c;
            u.failedLoginCount = (r.Failed_Login_Count__c == null)
                ? 0 : Integer.valueOf(r.Failed_Login_Count__c);
            u.lockedAt = r.Locked_At__c;
            out.add(u);
        }
        return out;
    }

    /**
     * Create a new Intake_User__c and set its password on Heroku.
     * Heroku upserts by Username__c so we don't insert the row here — the
     * callout is the single source of truth for that write. Returns the
     * Heroku response body (JSON) or throws on failure.
     */
    @AuraEnabled
    public static String createUser(String username, String password, String role) {
        String u = String.isBlank(username) ? '' : username.trim().toLowerCase();
        if (String.isBlank(u)) throw new AuraHandledException('Username is required.');
        if (String.isBlank(password)) throw new AuraHandledException('Password is required.');
        if (password.length() < 8) throw new AuraHandledException('Password must be at least 8 characters.');
        String r = String.isBlank(role) ? 'sales' : role.trim().toLowerCase();
        if (r != 'sales' && r != 'admin') throw new AuraHandledException('Role must be "sales" or "admin".');

        // Guard against duplicate username on the SF side (Heroku will upsert
        // anyway, but we prefer a clean error over an accidental password
        // reset for an existing row).
        for (Intake_User__c ex : [SELECT Id FROM Intake_User__c WHERE Username__c = :u LIMIT 1]) {
            throw new AuraHandledException('An intake user "' + u + '" already exists. Use Reset Password instead.');
        }
        return callSetPassword(u, password, r);
    }

    /**
     * Reset an existing user's password. Heroku bcrypts + writes the new hash
     * back to SF, and (per session store design) invalidates any live session
     * for this username so the reset takes effect immediately.
     */
    @AuraEnabled
    public static String resetPassword(Id userId, String password) {
        if (userId == null) throw new AuraHandledException('Missing user id.');
        if (String.isBlank(password)) throw new AuraHandledException('Password is required.');
        if (password.length() < 8) throw new AuraHandledException('Password must be at least 8 characters.');
        Intake_User__c row = [SELECT Id, Username__c, Role__c FROM Intake_User__c WHERE Id = :userId LIMIT 1];
        return callSetPassword(row.Username__c, password, null);
    }

    @AuraEnabled
    public static void setActive(Id userId, Boolean active) {
        if (userId == null) throw new AuraHandledException('Missing user id.');
        if (active == null) throw new AuraHandledException('Missing active flag.');
        Intake_User__c row = [SELECT Id, Username__c FROM Intake_User__c WHERE Id = :userId LIMIT 1];
        // Audit R7-H5 fix: revoke callout MUST run BEFORE the DML — Apex
        // forbids callout after DML in the same tx ('uncommitted work
        // pending' CalloutException, previously swallowed to debug so the
        // session was NEVER revoked). Worst case here is
        // revoked-but-still-active for a millisecond — safe direction.
        if (active == false) {
            try { callRevokeSessions(row.Username__c); }
            catch (Exception e) {
                // Real failure now — surface to admin so they retry or force logout.
                throw new AuraHandledException('Session revoke callout failed: ' + e.getMessage() + '. User NOT deactivated to avoid split-brain — retry.');
            }
        }
        row.Active__c = active;
        // Clearing lock when reactivating is a nice-to-have; when deactivating
        // we leave counters alone so the audit trail sticks.
        if (active == true) {
            row.Failed_Login_Count__c = 0;
            row.Locked_At__c = null;
        }
        update row;
    }

    @AuraEnabled
    public static void deleteUser(Id userId) {
        if (userId == null) throw new AuraHandledException('Missing user id.');
        Intake_User__c row = [SELECT Id, Username__c FROM Intake_User__c WHERE Id = :userId LIMIT 1];
        String username = row.Username__c;
        // Audit R7-H5 fix: revoke BEFORE delete (same reason as setActive).
        try { callRevokeSessions(username); }
        catch (Exception e) {
            throw new AuraHandledException('Session revoke callout failed: ' + e.getMessage() + '. User NOT deleted to avoid split-brain — retry.');
        }
        delete row;
    }

    /** Heroku callout to invalidate live sessions for a username.
     *  Bearer INTERNAL_ADMIN_TOKEN, mirrors callSetPassword. */
    private static void callRevokeSessions(String username) {
        if (String.isBlank(username)) return;
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Internal_Admin_Token__c);
        // Audit R8-M6 fix: previously return'd silently if config blank —
        // deactivations 'succeeded' at LWC but no revoke ran. THROW so the
        // outer AuraHandledException surfaces the config gap to admin.
        if (String.isBlank(base) || String.isBlank(token)) {
            throw new AuraHandledException(
                'PC1_Config__c is missing Heroku_Base_Url__c or Internal_Admin_Token__c — ' +
                'session revocation cannot run. Set them in Setup > Custom Settings > PC1 Config, then retry.'
            );
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base.removeEnd('/') + '/internal/intake/revoke-sessions');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setBody(JSON.serialize(new Map<String, Object>{ 'username' => username }));
        req.setTimeout(10000);
        HttpResponse res = new Http().send(req);
        // Audit R8-H1 fix: was `new Http().send(req);` — discarded response.
        // A 401 (token rotated in Heroku but stale in PC1_Config__c) or
        // any non-2xx failed silently, so the outer setActive/deleteUser
        // proceeded and the departed rep's session stayed alive. Mirror
        // callSetPassword and throw on non-2xx.
        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new AuraHandledException(
                'Heroku revoke-sessions returned HTTP ' + status + ': ' + res.getBody()
            );
        }
    }

    // ── HTTP callout ────────────────────────────────────────────────
    private static String callSetPassword(String username, String password, String role) {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Internal_Admin_Token__c);
        if (String.isBlank(base) || String.isBlank(token)) {
            throw new AuraHandledException(
                'PC1_Config__c is missing Heroku_Base_Url__c or Internal_Admin_Token__c — set them in Setup > Custom Settings > PC1 Config.'
            );
        }
        String url = base.removeEnd('/') + '/internal/intake/set-password';

        Map<String, Object> body = new Map<String, Object>{
            'username' => username,
            'password' => password
        };
        if (String.isNotBlank(role)) body.put('role', role);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-internal-token', token);
        req.setBody(JSON.serialize(body));
        req.setTimeout(30000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new AuraHandledException('Callout to Heroku failed: ' + e.getMessage());
        }
        Integer status = res.getStatusCode();
        String responseBody = res.getBody();
        if (status < 200 || status >= 300) {
            throw new AuraHandledException('Heroku returned HTTP ' + status + ': ' + responseBody);
        }
        return responseBody;
    }
}