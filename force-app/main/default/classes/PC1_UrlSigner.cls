/**
 * PC1_UrlSigner — mirrors src/lib/signer.js on the Node side.
 *
 * Produces a 22-char base64url slice of HMAC-SHA256(appId, secret) so the
 * Signature__c custom field on PC1_Application__c can be baked into the
 * Client_Form_URL__c formula as `?t=<sig>`. The Heroku dyno then re-computes
 * the same signature and rejects any URL where they don't match.
 *
 * Secret source: Custom Setting PC1_Config__c.Signing_Secret__c on the org's
 * default record. Must match Heroku's PC1_URL_SIGNING_SECRET env var byte-for-
 * byte or every client-form link will 401.
 *
 * NOT for authentication — only ties a URL to an Application Id. Anyone with
 * the link opens the form (that's the intent — the client received it from
 * XtraPension via email/SMS).
 */
public with sharing class PC1_UrlSigner {

    /** Base64url slice length — must match src/lib/signer.js. */
    private static final Integer SIG_LEN = 22;

    /** Fallback string used when the secret is not configured, so the trigger
     *  never blocks record creation — the URL formula just renders a link that
     *  will 401 until Fernando sets PC1_Config__c.Signing_Secret__c in Setup. */
    private static final String UNCONFIGURED = 'UNCONFIGURED';

    /** Cached across an execution context — avoids repeated SOQL. */
    private static String cachedSecret;

    private static String getSecret() {
        if (cachedSecret != null) return cachedSecret;
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
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
     * Called from PC1_ApplicationTrigger (after insert / after update when
     * Signature__c is blank). Bulk-safe: builds a single update DML list.
     */
    public static void stampSignatures(List<PC1_Application__c> apps) {
        if (apps == null || apps.isEmpty()) return;
        List<PC1_Application__c> toUpdate = new List<PC1_Application__c>();
        for (PC1_Application__c a : apps) {
            if (a.Id == null) continue;
            // Only stamp when missing so re-fires don't churn the record.
            if (String.isNotBlank(a.Signature__c) && a.Signature__c != UNCONFIGURED) continue;
            toUpdate.add(new PC1_Application__c(Id = a.Id, Signature__c = signAppId(a.Id)));
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }

    // ── /files/* links (call recordings + transcripts) ───────────────────

    /** The Heroku proxy routes whose ?t= is a file token. */
    private static final Pattern FILE_URL = Pattern.compile(
        '^(.*/files/(?:transcript|recording|nuacom-recording)/)([^/?#]+)(\\?[^#]*)?$');

    /**
     * Mirrors signKey() in src/webhooks/files.js byte for byte:
     * base64url(HMAC-SHA256('file:' + key, secret)) without padding, first 22
     * chars. The 'file:' prefix (audit R5 H10, 2026-08-29) keeps a file token
     * from ever verifying as a form token. Returns null when the secret is not
     * configured. files.js reads FILES_URL_SIGNING_SECRET first and falls back
     * to PC1_URL_SIGNING_SECRET; Signing_Secret__c must equal whichever of the
     * two Heroku actually uses (today: PC1_URL_SIGNING_SECRET, the other is unset).
     */
    public static String signFileKey(String key) {
        if (String.isBlank(key)) return null;
        String secret = getSecret();
        if (String.isBlank(secret)) return null;
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf('file:' + key), Blob.valueOf(secret));
        String url = EncodingUtil.base64Encode(mac).replace('+', '-').replace('/', '_').replace('=', '');
        return url.length() > SIG_LEN ? url.substring(0, SIG_LEN) : url;
    }

    /**
     * Rebuild the ?t= of a stored /files/transcript|recording|nuacom-recording
     * link with the current file token. The tokens frozen into
     * PC1_Call_Log__c when the row was written stop working whenever the
     * signing scheme changes (2026-08-29 added the 'file:' prefix and every
     * older link returned 401), so the record page signs at render time.
     * Any other URL, a blank one or an unconfigured secret comes back as is;
     * other query parameters are kept.
     */
    public static String resignFileUrl(String url) {
        if (String.isBlank(url)) return url;
        Matcher m = FILE_URL.matcher(url);
        if (!m.matches()) return url;
        String encodedKey = m.group(2);
        String sig;
        try {
            sig = signFileKey(EncodingUtil.urlDecode(encodedKey, 'UTF-8'));
        } catch (Exception e) {
            return url; // malformed %-escape: leave the stored link untouched
        }
        if (sig == null) return url;
        List<String> params = new List<String>();
        String query = m.group(3);
        if (query != null && query.length() > 1) {
            for (String part : query.substring(1).split('&')) {
                if (String.isBlank(part) || part == 't' || part.startsWith('t=')) continue;
                params.add(part);
            }
        }
        params.add('t=' + sig);
        return m.group(1) + encodedKey + '?' + String.join(params, '&');
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