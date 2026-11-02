/**
 * AA_IntakeAdminController — @AuraEnabled backend for the aaIntakeUsers LWC
 * (admin page "AA Intake Users"). Manages AA_Intake_User__c rows: list, create,
 * reset password, activate / deactivate, delete.
 *
 * Password handling is delegated: SF NEVER stores or receives back the plain
 * password. The LWC sends {username, password} into createUser / resetPassword,
 * this class forwards them to the Heroku endpoint
 *   POST /internal/intake/set-password
 * which bcrypts the password and writes the resulting hash back onto the
 * AA_Intake_User__c row via jsforce. The endpoint is authenticated by the shared
 * secret AA_Config__c.Internal_Admin_Token__c (matches INTERNAL_ADMIN_TOKEN
 * on the Heroku dyno), sent in the `x-internal-token` header.
 *
 * setActive + deleteUser touch the SF row directly. Audit 2026-10-02 F131:
 * deactivating (setActive false) and deleting now ALSO call
 *   POST /internal/intake/revoke
 * first, so any live intake session for that username is dropped at once
 * instead of surviving up to 12h. The callout runs BEFORE the DML (Apex forbids
 * a callout after uncommitted DML) and is best-effort: if Heroku is down the
 * SF change still lands and the dyno's renew-time Active__c re-check revokes
 * the session later.
 *
 * Wave 3 (owner decision 2026-10-02, ONE LOGIN PER SALES AGENT): each login
 * can be linked to the sales agent it books for (AA_Intake_User__c.
 * Sales_Agent__c). The Heroku intake stamps that agent on every Application
 * the login creates; the self-declared dropdown on the intake page is gone.
 * listSalesAgents / setSalesAgent and the optional createUser argument manage
 * the link. A value must be an active AA_Application__c.Sales_Agent__c
 * picklist value (that field is restricted, so anything else would make the
 * intake insert fail), and one agent may be linked to only one ACTIVE login,
 * so every application is attributed to exactly one person. The shared
 * 'sales'/'admin' logins stay usable with no agent linked.
 *
 * Remote Site Setting AA_Heroku_Autofill must whitelist the base URL (same
 * one used by AA_HerokuBridge). Callout base URL comes from
 * AA_Config__c.Heroku_Base_Url__c.
 */
public with sharing class AA_IntakeAdminController {

    public class UserRow {
        @AuraEnabled public String id;
        @AuraEnabled public String username;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Datetime lastLoginAt;
        @AuraEnabled public Integer failedLoginCount;
        @AuraEnabled public Datetime lockedAt;
        @AuraEnabled public String salesAgent;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserRow> listUsers() {
        // F131: listing usernames + lock state is admin-only too (it was the
        // one ungated method, callable by any user with class access).
        assertIntakeAdmin();
        List<AA_Intake_User__c> rows = [
            SELECT Id, Username__c, Role__c, Active__c,
                   Last_Login_At__c, Failed_Login_Count__c, Locked_At__c,
                   Sales_Agent__c
            FROM AA_Intake_User__c
            ORDER BY Active__c DESC, Username__c ASC
        ];
        List<UserRow> out = new List<UserRow>();
        for (AA_Intake_User__c r : rows) {
            UserRow u = new UserRow();
            u.id = r.Id;
            u.username = r.Username__c;
            u.role = r.Role__c;
            u.active = r.Active__c;
            u.lastLoginAt = r.Last_Login_At__c;
            u.failedLoginCount = (r.Failed_Login_Count__c == null)
                ? 0 : Integer.valueOf(r.Failed_Login_Count__c);
            u.lockedAt = r.Locked_At__c;
            u.salesAgent = r.Sales_Agent__c;
            out.add(u);
        }
        return out;
    }

    /** Authorization gate for the mutating intake-user operations. A full admin
     *  (ModifyAllData) always passes; otherwise the running user must hold the
     *  AA_Intake_Admin permission set. Blocks any AA_User from directly invoking
     *  these @AuraEnabled methods from the console (audit 2026-08-28). */
    private static void assertIntakeAdmin() {
        Integer n = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND (PermissionSet.Name = 'AA_Intake_Admin'
                   OR PermissionSet.PermissionsModifyAllData = true)
        ];
        if (n == 0) {
            throw new AuraHandledException('Not authorized — intake-admin permission required.');
        }
    }

    /**
     * Create a new AA_Intake_User__c and set its password on Heroku.
     * Heroku upserts by Username__c so we don't insert the row here — the
     * callout is the single source of truth for that write. Returns the
     * Heroku response body (JSON) or throws on failure.
     */
    /** Active AA_Application__c.Sales_Agent__c picklist values: the only names
     *  a login may be linked to (the field is restricted on the Application). */
    @AuraEnabled(cacheable=true)
    public static List<String> listSalesAgents() {
        assertIntakeAdmin();
        return listSalesAgentValues();
    }

    /**
     * Link (or, with a blank value, unlink) the sales agent an intake login
     * books for. Takes effect on that login's next intake submit; no re-login
     * needed (Heroku re-reads it on every submit).
     */
    @AuraEnabled
    public static void setSalesAgent(Id userId, String salesAgent) {
        assertIntakeAdmin();
        if (userId == null) throw new AuraHandledException('Missing user id.');
        String agent = normaliseAgent(salesAgent);
        if (agent != null) assertAgentFree(agent, userId);
        update new AA_Intake_User__c(Id = userId, Sales_Agent__c = agent);
    }

    /** Blank -> null; otherwise the exact picklist value (case-insensitive
     *  match), or an error naming the valid choices. */
    @TestVisible
    private static String normaliseAgent(String salesAgent) {
        if (String.isBlank(salesAgent)) return null;
        String wanted = salesAgent.trim();
        List<String> valid = listSalesAgentValues();
        for (String v : valid) {
            if (v.equalsIgnoreCase(wanted)) return v;
        }
        throw new AuraHandledException('"' + wanted + '" is not a sales agent. Choose one of: ' + String.join(valid, ', ') + '.');
    }

    private static List<String> listSalesAgentValues() {
        List<String> out = new List<String>();
        for (Schema.PicklistEntry pe : AA_Application__c.Sales_Agent__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) out.add(pe.getValue());
        }
        return out;
    }

    /** One login per sales agent: refuse when another ACTIVE login already
     *  books for this agent (inactive ones do not count, so a replacement
     *  login can be linked after the old one is deactivated). */
    private static void assertAgentFree(String agent, Id exceptUserId) {
        for (AA_Intake_User__c other : [
            SELECT Username__c FROM AA_Intake_User__c
            WHERE Sales_Agent__c = :agent AND Active__c = true AND Id != :exceptUserId
            LIMIT 1
        ]) {
            throw new AuraHandledException(agent + ' is already linked to the active login "' + other.Username__c
                + '". Unlink or deactivate that login first, so each application is credited to one person.');
        }
    }

    @AuraEnabled
    public static String createUser(String username, String password, String role, String salesAgent) {
        assertIntakeAdmin();
        String u = String.isBlank(username) ? '' : username.trim().toLowerCase();
        if (String.isBlank(u)) throw new AuraHandledException('Username is required.');
        if (String.isBlank(password)) throw new AuraHandledException('Password is required.');
        if (password.length() < 8) throw new AuraHandledException('Password must be at least 8 characters.');
        String r = String.isBlank(role) ? 'sales' : role.trim().toLowerCase();
        if (r != 'sales' && r != 'admin') throw new AuraHandledException('Role must be "sales" or "admin".');
        // Validate the agent BEFORE the callout: a bad value must not leave a
        // half-made login behind on Heroku's side.
        String agent = normaliseAgent(salesAgent);
        if (agent != null) assertAgentFree(agent, null);

        // Guard against duplicate username on the SF side (Heroku will upsert
        // anyway, but we prefer a clean error over an accidental password
        // reset for an existing row).
        for (AA_Intake_User__c ex : [SELECT Id FROM AA_Intake_User__c WHERE Username__c = :u LIMIT 1]) {
            throw new AuraHandledException('An intake user "' + u + '" already exists. Use Reset Password instead.');
        }
        String body = callSetPassword(u, password, r);
        // Heroku inserted the row in its own transaction, so it is visible
        // here. DML after a callout is allowed (the reverse is not).
        if (agent != null) {
            List<AA_Intake_User__c> created = [SELECT Id FROM AA_Intake_User__c WHERE Username__c = :u LIMIT 1];
            if (!created.isEmpty()) {
                update new AA_Intake_User__c(Id = created[0].Id, Sales_Agent__c = agent);
            } else {
                System.debug(LoggingLevel.WARN, 'AA_IntakeAdminController.createUser: row for ' + u + ' not found after set-password; sales agent not linked.');
            }
        }
        return body;
    }

    /**
     * Reset an existing user's password. Heroku bcrypts + writes the new hash
     * back to SF, and (per session store design) invalidates any live session
     * for this username so the reset takes effect immediately.
     */
    @AuraEnabled
    public static String resetPassword(Id userId, String password) {
        assertIntakeAdmin();
        if (userId == null) throw new AuraHandledException('Missing user id.');
        if (String.isBlank(password)) throw new AuraHandledException('Password is required.');
        if (password.length() < 8) throw new AuraHandledException('Password must be at least 8 characters.');
        AA_Intake_User__c row = [SELECT Id, Username__c, Role__c FROM AA_Intake_User__c WHERE Id = :userId LIMIT 1];
        return callSetPassword(row.Username__c, password, null);
    }

    @AuraEnabled
    public static void setActive(Id userId, Boolean active) {
        assertIntakeAdmin();
        if (userId == null) throw new AuraHandledException('Missing user id.');
        if (active == null) throw new AuraHandledException('Missing active flag.');
        if (active == true) {
            // One login per sales agent also on reactivation.
            for (AA_Intake_User__c u : [SELECT Sales_Agent__c FROM AA_Intake_User__c WHERE Id = :userId LIMIT 1]) {
                if (String.isNotBlank(u.Sales_Agent__c)) assertAgentFree(u.Sales_Agent__c, userId);
            }
        }
        if (active == false) {
            // F131: drop live sessions before the DML (callout-before-DML rule).
            for (AA_Intake_User__c u : [SELECT Username__c FROM AA_Intake_User__c WHERE Id = :userId LIMIT 1]) {
                callRevoke(u.Username__c);
            }
        }
        AA_Intake_User__c row = new AA_Intake_User__c(Id = userId, Active__c = active);
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
        assertIntakeAdmin();
        if (userId == null) throw new AuraHandledException('Missing user id.');
        List<AA_Intake_User__c> rows = [SELECT Id, Username__c FROM AA_Intake_User__c WHERE Id = :userId LIMIT 1];
        // F131: drop live sessions before the DML (callout-before-DML rule).
        for (AA_Intake_User__c u : rows) callRevoke(u.Username__c);
        delete rows;
    }

    /**
     * Best-effort session revoke on Heroku. Returns true when Heroku confirmed.
     * Never throws: a deactivation must not fail just because Heroku is down
     * or AA_Config__c is incomplete (see class header).
     */
    @TestVisible
    private static Boolean callRevoke(String username) {
        if (String.isBlank(username)) return false;
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Internal_Admin_Token__c);
        if (String.isBlank(base) || String.isBlank(token)) return false;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base.removeEnd('/') + '/internal/intake/revoke');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-internal-token', token);
        req.setBody(JSON.serialize(new Map<String, Object>{ 'username' => username }));
        req.setTimeout(10000);
        try {
            HttpResponse res = new Http().send(req);
            Integer status = res.getStatusCode();
            if (status < 200 || status >= 300) {
                System.debug(LoggingLevel.WARN, 'AA_IntakeAdminController.callRevoke HTTP ' + status + ': ' + res.getBody());
                return false;
            }
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AA_IntakeAdminController.callRevoke failed: ' + e.getMessage());
            return false;
        }
    }

    // ── HTTP callout ────────────────────────────────────────────────
    private static String callSetPassword(String username, String password, String role) {
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String base  = (cfg == null ? null : cfg.Heroku_Base_Url__c);
        String token = (cfg == null ? null : cfg.Internal_Admin_Token__c);
        if (String.isBlank(base) || String.isBlank(token)) {
            throw new AuraHandledException(
                'AA_Config__c is missing Heroku_Base_Url__c or Internal_Admin_Token__c — set them in Setup > Custom Settings > AA Config.'
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