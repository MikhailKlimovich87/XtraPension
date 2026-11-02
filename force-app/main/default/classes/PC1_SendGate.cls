/**
 * PC1_SendGate — PC1 must never message a real person from a sandbox.
 *
 * Fernando, 2026-09-28: "eu só não quero que saia email do pension credit pras
 * pessoas, coisas nada a ver."
 *
 * The hazard is not hypothetical. Production `clients@xtrapension.com` has been
 * forwarded into this sandbox for weeks, so sandbox records carry REAL client
 * email addresses and phone numbers. Anything that dispatches off those records
 * reaches an actual customer, and Salesforce stamps "Sandbox:" on the subject —
 * which is exactly how a real client received a claim reply on 2026-09-16
 * (see docs/INCIDENT-2026-09-28-sandbox-email-leak.md).
 *
 * This gate is FAIL-CLOSED in a sandbox: an address or number is blocked unless
 * it is explicitly allowlisted. Production is never gated — `isProduction()`
 * short-circuits before any allowlist work, so live clients are unaffected.
 *
 * Allowlist (sandbox only), any of:
 *   - any address at a domain in DEFAULT_SAFE_DOMAINS (our own staff)
 *   - anything listed in PC1_Config__c.Test_Send_Allowlist__c (comma/semicolon
 *     separated; entries may be a full address, a phone number, or "@domain")
 *
 * Blocking is not silent: callers record the suppression on
 * PC1_Message_Send_Log__c with Status__c='Suppressed', so a QA run still shows
 * what WOULD have gone out and to whom.
 */
public with sharing class PC1_SendGate {

    /** Staff domains that are always safe to message from a sandbox. */
    private static final Set<String> DEFAULT_SAFE_DOMAINS = new Set<String>{
        'xtrapension.com', 'tinderpoint.com', 'example.com'
    };

    @TestVisible private static Boolean sandboxOverride = null;   // tests only
    private static Boolean cachedIsSandbox = null;
    private static Set<String> cachedAllowlist = null;

    /** True when this org is NOT a sandbox — the gate is a no-op there. */
    public static Boolean isProduction() { return !isSandbox(); }

    @TestVisible
    public static Boolean isSandbox() {
        if (sandboxOverride != null) return sandboxOverride;
        // Apex tests never deliver anything: Messaging.sendEmail is suppressed and
        // callouts must be mocked. Gating them therefore buys no safety and only
        // breaks every existing test that asserts a 'Sent' status. Treat a test
        // run as ungated unless the test explicitly sets sandboxOverride to
        // exercise the gate itself (PC1_SendGateTest does exactly that).
        if (Test.isRunningTest()) return false;
        if (cachedIsSandbox == null) {
            try {
                cachedIsSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
            } catch (Exception e) {
                // Fail CLOSED: if we cannot tell, assume sandbox and block.
                // Wrongly blocking a production send is recoverable; wrongly
                // emailing a stranger from a test org is not.
                System.debug(LoggingLevel.ERROR, 'PC1_SendGate: could not read Organization — assuming sandbox. ' + e.getMessage());
                cachedIsSandbox = true;
            }
        }
        return cachedIsSandbox;
    }

    /** May we email this address from this org? */
    public static Boolean allowEmail(String address) {
        if (isProduction()) return true;
        if (String.isBlank(address)) return false;
        String a = address.trim().toLowerCase();
        if (allowlist().contains(a)) return true;
        Integer at = a.lastIndexOf('@');
        if (at < 0) return false;
        String domain = a.substring(at + 1);
        return DEFAULT_SAFE_DOMAINS.contains(domain) || allowlist().contains('@' + domain);
    }

    /** May we SMS this number from this org? */
    public static Boolean allowSms(String phone) {
        if (isProduction()) return true;
        if (String.isBlank(phone)) return false;
        return allowlist().contains(normalisePhone(phone));
    }

    /** Human-readable reason, for the send log. */
    public static String blockReason(String destination) {
        return 'Suppressed by PC1_SendGate: this is a SANDBOX and "' + destination
            + '" is not allowlisted. Add it to PC1_Config__c.Test_Send_Allowlist__c to test against it.';
    }

    /**
     * Digits only, with the international access prefix reconciled, so
     * "+353 86 123 4567" and "00353861234567" compare equal.
     *
     * Digits-alone was not enough: "+353…" strips to 353861234567 while
     * "00353…" strips to 00353861234567, so the same number failed to match
     * itself depending on which notation the allowlist happened to use.
     *
     * LIMITATION: a number written in NATIONAL format ("086 123 4567") does not
     * normalise to its international form — that needs a country code we do not
     * have here. Allowlist a number in the same notation the record carries.
     */
    private static String normalisePhone(String p) {
        if (String.isBlank(p)) return '';
        String digits = p.replaceAll('[^0-9]', '');
        if (digits.startsWith('00') && digits.length() > 2) digits = digits.substring(2);
        return digits;
    }

    private static Set<String> allowlist() {
        if (cachedAllowlist != null) return cachedAllowlist;
        cachedAllowlist = new Set<String>();
        String raw = null;
        try {
            PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
            if (cfg != null) {
                Object v = cfg.get('Test_Send_Allowlist__c');
                if (v != null) raw = String.valueOf(v);
            }
        } catch (Exception ignored) { /* field may not exist yet */ }
        if (String.isBlank(raw)) return cachedAllowlist;
        // Split on comma/semicolon ONLY, never on whitespace. A phone number is
        // routinely written "+353 86 123 4567", and splitting on spaces shredded it
        // into four useless tokens so the number never matched. Caught by
        // PC1_SendGateTest.allowlistedPhoneIgnoresFormatting before release.
        for (String part : raw.split('[,;]')) {
            String s = part.trim().toLowerCase();
            if (String.isBlank(s)) continue;
            cachedAllowlist.add(s);
            // A bare phone number is also stored digits-only so formatting
            // differences between the config and the record do not matter.
            if (!s.contains('@')) cachedAllowlist.add(normalisePhone(s));
        }
        return cachedAllowlist;
    }

    @TestVisible
    private static void resetCaches() {
        cachedIsSandbox = null;
        cachedAllowlist = null;
    }
}