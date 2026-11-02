/**
 * AA_UrlSigner — mirrors src/lib/signer.js on the Node side.
 *
 * Produces a 22-char base64url slice of HMAC-SHA256(appId, secret) so the
 * Signature__c custom field on AA_Application__c can be baked into the
 * Client_Form_URL__c formula as `?t=<sig>`. The Heroku dyno then re-computes
 * the same signature and rejects any URL where they don't match.
 *
 * Secret source: Custom Setting AA_Config__c.Signing_Secret__c on the org's
 * default record. Must match Heroku's AA_URL_SIGNING_SECRET env var byte-for-
 * byte or every client-form link will 401.
 *
 * NOT for authentication — only ties a URL to an Application Id. Anyone with
 * the link opens the form (that's the intent — the client received it from
 * XtraPension via email/SMS).
 */
public with sharing class AA_UrlSigner {

    /** Base64url slice length — must match src/lib/signer.js. */
    private static final Integer SIG_LEN = 22;

    /** Fallback string used when the secret is not configured, so the trigger
     *  never blocks record creation — the URL formula just renders a link that
     *  will 401 until Fernando sets AA_Config__c.Signing_Secret__c in Setup. */
    private static final String UNCONFIGURED = 'UNCONFIGURED';

    /** Cached across an execution context — avoids repeated SOQL. */
    private static String cachedSecret;

    private static String getSecret() {
        if (cachedSecret != null) return cachedSecret;
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        String s = (cfg != null && cfg.Signing_Secret__c != null) ? cfg.Signing_Secret__c.trim() : '';
        cachedSecret = s;
        return s;
    }

    /** Deterministic signature for an Application Id. Returns UNCONFIGURED
     *  when the shared secret hasn't been set yet — the trigger still stamps
     *  a value so the formula field has something non-null to concatenate. */
    public static String signAppId(Id appId) {
        if (appId == null) return UNCONFIGURED;
        String secret = getSecret();
        if (String.isBlank(secret)) return UNCONFIGURED;
        // Truncate to 15-char case-sensitive Id — that's what the
        // Client_Form_URL__c formula bakes into the URL (SF formulas render Id
        // as 15-char). Node re-computes on the 15-char from the URL, so both
        // sides must HMAC the same 15-char string or every token 401s.
        String idStr = String.valueOf(appId);
        if (idStr.length() > 15) idStr = idStr.substring(0, 15);
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(idStr), Blob.valueOf(secret));
        String b64 = EncodingUtil.base64Encode(mac);
        // base64 -> base64url + strip padding + slice to SIG_LEN
        String url = b64.replace('+', '-').replace('/', '_').replace('=', '');
        return url.length() > SIG_LEN ? url.substring(0, SIG_LEN) : url;
    }

    /** Trigger-friendly overload for bulk stamping. */
    public static String signAppId(String appIdStr) {
        return signAppId((Id) appIdStr);
    }

    /**
     * Called from AA_ApplicationTrigger (after insert / after update when
     * Signature__c is blank). Bulk-safe: builds a single update DML list.
     */
    public static void stampSignatures(List<AA_Application__c> apps) {
        if (apps == null || apps.isEmpty()) return;
        List<AA_Application__c> toUpdate = new List<AA_Application__c>();
        for (AA_Application__c a : apps) {
            if (a.Id == null) continue;
            // Only stamp when missing so re-fires don't churn the record.
            if (String.isNotBlank(a.Signature__c) && a.Signature__c != UNCONFIGURED) continue;
            toUpdate.add(new AA_Application__c(Id = a.Id, Signature__c = signAppId(a.Id)));
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    /**
     * Verify a token against an Application Id. Constant-time comparison via
     * Apex's XOR-length loop (no built-in constant-time compare, but SIG_LEN
     * is fixed so early exit on length mismatch is safe).
     */
    public static Boolean verifyToken(Id appId, String token) {
        if (appId == null || String.isBlank(token)) return false;
        String expected = signAppId(appId);
        if (expected == UNCONFIGURED) return false;
        if (token.length() != expected.length()) return false;
        Integer diff = 0;
        for (Integer i = 0; i < expected.length(); i++) {
            diff |= (expected.charAt(i) ^ token.charAt(i));
        }
        return diff == 0;
    }
}