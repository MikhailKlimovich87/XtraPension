/**
 * PC1_BankLookup — @AuraEnabled proxy the pc1BankEditor LWC calls to run
 * UK bank account verification against XtraPension's own Heroku endpoint
 * (`POST /api/form/bank/verify`). Server-side call keeps the underlying
 * provider key out of the browser and lets us swap providers without
 * touching the LWC.
 *
 * (2026-08-17) — endpoint contract:
 *   Request  : { sortCode, accountNumber, accountHolderName? }
 *   Response : { ok, status, bankName, acceptsDD, canonicalSortCode, error? }
 *   status ∈  Modulus Passed | Invalid Sort Code |
 *             Invalid Account Number | Bank Does Not Accept DD
 *
 * verifyAndPersistAccount() persists the outcome to Bank_Verification_Status__c
 * on the parent Application when called from read mode, so the badge in the
 * LWC reflects the latest server-side truth without a separate save round-trip.
 *
 * (2026-08-17 refactor) — the Tier 2 verbal-confirm flow was removed. Name
 * confirmation now happens on the sales-agent side via the DD Terms LWC
 * that reads terms back to the client; those fields live on a different
 * bundle. This class only handles modulus verify + persistence.
 */
public with sharing class PC1_BankLookup {

    private static final String BASE_URL   = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com';
    private static final String VERIFY_PATH = '/api/form/bank/verify';
    private static final Integer TIMEOUT_MS = 8000;

    /** Shape the LWC binds against. Keep field names stable — the LWC
     *  destructures on them. */
    public class Result {
        @AuraEnabled public Boolean verified;             // shortcut: modulus ok AND accepts DD
        @AuraEnabled public String  status;               // see enum above
        @AuraEnabled public String  bankName;
        @AuraEnabled public String  canonicalSortCode;    // "XX-XX-XX"
        @AuraEnabled public Boolean acceptsDirectDebit;   // alias kept for legacy readers
        @AuraEnabled public Boolean acceptsDD;            // new endpoint field name
    }

    /**
     * Provider-agnostic entrypoint used by pc1BankEditor LWC. Calls the
     * internal Heroku endpoint and maps the response.
     *
     * `name` is optional — the offline modulus check does not consume it,
     * but the endpoint accepts it so we can start pre-populating CoP name
     * matches in the future without changing this signature.
     * `accountType` is accepted for signature compatibility with the old
     * Data8 path; the new endpoint ignores it.
     */
    @AuraEnabled
    public static Result verifyAccount(String sortCode, String accountNumber, String name, String accountType) {
        return verifyAccountViaEndpoint(sortCode, accountNumber, name);
    }

    /** Legacy 2-arg signature — some flows still bind to this. */
    @AuraEnabled
    public static Result verifyAccountLegacy(String sortCode, String accountNumber) {
        return verifyAccount(sortCode, accountNumber, null, 'PERSONAL');
    }

    /**
     * Read-mode helper — verify + persist Bank_Verification_Status__c and
     * Bank_Name__c on the parent Application in one round-trip. Used when
     * the agent clicks Verify Account from the LWC read view (no draft
     * to edit; result should show up in the badge immediately). Draft/
     * edit mode still uses the pair verifyAccount() + saveVerification().
     */
    @AuraEnabled
    public static Result verifyAndPersistAccount(Id applicationId, String sortCode, String accountNumber, String accountHolder) {
        if (applicationId == null) throw new AuraHandledException('Missing application id.');
        Result r = verifyAccount(sortCode, accountNumber, accountHolder, 'PERSONAL');
        PC1_Application__c patch = new PC1_Application__c(
            Id = applicationId,
            Bank_Verification_Status__c = r.status
        );
        if (String.isNotBlank(r.bankName)) patch.Bank_Name__c = r.bankName;
        if (String.isNotBlank(r.canonicalSortCode)) patch.Bank_Sort_Code__c = r.canonicalSortCode;
        if (r.status != 'Unverified') patch.Bank_Verified_At__c = Datetime.now();
        update patch;
        return r;
    }

    private static Result verifyAccountViaEndpoint(String sortCode, String accountNumber, String accountHolderName) {
        // Local input hygiene BEFORE calling out — cheap validation avoids
        // wasted HTTP and gives the LWC a friendly error message fast.
        String rawSort = sortCode == null ? '' : sortCode.replaceAll('[- ]', '');
        String rawAcct = accountNumber == null ? '' : accountNumber.trim();
        if (!Pattern.matches('^\\d{6}$', rawSort))    throw new AuraHandledException('Sort code must be 6 digits.');
        if (!Pattern.matches('^\\d{6,10}$', rawAcct)) throw new AuraHandledException('Account number must be 6–10 digits.');

        Map<String, Object> reqBody = new Map<String, Object>{
            'sortCode'      => rawSort,
            'accountNumber' => rawAcct
        };
        if (String.isNotBlank(accountHolderName)) {
            reqBody.put('accountHolderName', accountHolderName.trim());
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + VERIFY_PATH);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        // Server-to-server bearer — the endpoint validates against the
        // Internal_Admin_Token__c value baked into the Heroku env. Blank
        // token → skip header (dev orgs without config); endpoint may
        // reject with 401 in that case, surfaced as AuraHandledException.
        String tok = getInternalToken();
        if (String.isNotBlank(tok)) req.setHeader('Authorization', 'Bearer ' + tok);
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(reqBody));

        HttpResponse resp;
        try {
            resp = new Http().send(req);
        } catch (Exception e) {
            throw new AuraHandledException('Bank verify endpoint unreachable: ' + e.getMessage());
        }
        if (resp.getStatusCode() < 200 || resp.getStatusCode() >= 300) {
            throw new AuraHandledException('Bank verify HTTP ' + resp.getStatusCode()
                + ' — ' + safeBody(resp));
        }

        Map<String, Object> data;
        try { data = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody()); }
        catch (Exception e) { throw new AuraHandledException('Bank verify returned non-JSON'); }

        Boolean ok = data.get('ok') == true;
        String  status = str(data.get('status'));
        String  err    = str(data.get('error'));

        // Endpoint can return ok=false with a human-friendly status
        // (e.g. "Invalid Sort Code") — that's a valid outcome we want to
        // surface, not throw. Only throw when there's no status at all.
        if (!ok && String.isBlank(status)) {
            throw new AuraHandledException(String.isBlank(err) ? 'Unknown verify failure' : err);
        }

        Result r = new Result();
        r.status            = String.isBlank(status) ? 'Invalid' : status;
        r.bankName          = str(data.get('bankName'));
        r.canonicalSortCode = str(data.get('canonicalSortCode'));
        Object accDd = data.get('acceptsDD');
        r.acceptsDD           = (accDd == null) ? null : Boolean.valueOf(accDd);
        r.acceptsDirectDebit  = r.acceptsDD;
        r.verified            = (r.status == 'Modulus Passed' && r.acceptsDD == true);
        return r;
    }

    /** Persist verification. Guard rails:
     *   - Blank input for a field is treated as "keep prior value" so
     *     the LWC doesn't accidentally null Bank_Name__c on a retry.
     *   - `status` restricted to the picklist enum — attackers can't
     *     stamp 'Modulus Passed' without a real verifyAccount round-trip.
     *
     *  'Verbally Confirmed' removed (2026-08-17) — the verbal-confirm flow is
     *  gone; picklist value is being deactivated by the schema agent.
     *  'Bank Verification Unavailable' added (2026-08-18) — surfaced when
     *  Data8 is down / rate-limited / credits exhausted; sales cannot proceed
     *  but the digits haven't been rejected, so the record keeps them and can
     *  simply re-verify. */
    private static final Set<String> ALLOWED_STATUSES = new Set<String>{
        'Unverified',
        // offline-modulus contract
        'Modulus Passed',
        'Invalid Sort Code', 'Invalid Account Number', 'Bank Does Not Accept DD',
        // Data8 fail-closed outcome (2026-08-18) — treat as retry, not a reject.
        'Bank Verification Unavailable',
        // legacy values kept for backwards compat during rollout
        'Verified', 'Bank Confirmed', 'Not Confirmed',
        'Not DD-capable', 'Invalid',
        'Name Verified', 'Name Close Match', 'Name Mismatch'
    };

    /** Statuses that unlock a Direct Debit mandate, plus the legacy 'Verified'. */
    private static final Set<String> GREEN_STATUSES = new Set<String>{
        'Modulus Passed', 'Bank Confirmed', 'Name Verified', 'Name Close Match', 'Verified'
    };
    /** Verdicts about the account HOLDER: they do not survive a change of holder. */
    private static final Set<String> NAME_STATUSES = new Set<String>{ 'Name Verified', 'Name Close Match' };

    /**
     * Audit 2026-11-11 PC-APEX-8 / PC-SFUI-12 (port of AA F61). The status
     * comes from the browser, and the allow-list alone did not stop a caller
     * storing 'Bank Confirmed' for digits nobody checked (a green status then
     * unlocks a GoCardless mandate). A green status is now only stored as
     * sent when it claims nothing new: same digits, same holder for a name
     * verdict, same status as already on the record. Otherwise the check is
     * run again HERE (callout before any DML) and what the server says is
     * stored; if the check cannot run, 'Unverified'.
     */
    @AuraEnabled
    public static void saveVerification(
        Id applicationId, String sortCode, String accountNumber,
        String accountHolder, String rollNumber, String bankName, String status
    ) {
        if (applicationId == null) throw new AuraHandledException('Missing application id.');
        String cleanStatus = String.isBlank(status) ? 'Unverified' : status.trim();
        if (!ALLOWED_STATUSES.contains(cleanStatus)) throw new AuraHandledException('Unknown status: ' + cleanStatus);

        PC1_Application__c existing = [
            SELECT Bank_Sort_Code__c, Bank_Account_Number__c, Bank_Account_Holder__c,
                   Bank_Roll_Number__c, Bank_Name__c, Bank_Verification_Status__c, Bank_Verified_At__c
            FROM PC1_Application__c WHERE Id = :applicationId LIMIT 1
        ];
        String newSort   = keepIfBlank(sortCode,      existing.Bank_Sort_Code__c);
        String newAcct   = keepIfBlank(accountNumber, existing.Bank_Account_Number__c);
        String newHolder = keepIfBlank(accountHolder, existing.Bank_Account_Holder__c);
        Boolean digitsChanged = digits(newSort) != digits(existing.Bank_Sort_Code__c)
            || digits(newAcct) != digits(existing.Bank_Account_Number__c);
        Boolean holderChanged = squash(newHolder) != squash(existing.Bank_Account_Holder__c);

        // Another account: the old bank's name must not stay under the new
        // digits, so it is written as sent, blank included. A roll number is
        // typed by the agent, so an empty one always clears it (null = the
        // caller did not send it).
        String newBankName = digitsChanged ? blankToNull(bankName) : keepIfBlank(bankName, existing.Bank_Name__c);
        String newRoll     = rollNumber == null ? existing.Bank_Roll_Number__c : blankToNull(rollNumber);

        Boolean claimsSomethingNew = digitsChanged
            || (holderChanged && NAME_STATUSES.contains(cleanStatus))
            || cleanStatus != existing.Bank_Verification_Status__c;
        if (GREEN_STATUSES.contains(cleanStatus) && claimsSomethingNew) {
            try {
                Result r = verifyAccountViaEndpoint(newSort, newAcct, newHolder);
                cleanStatus = ALLOWED_STATUSES.contains(r.status) ? r.status : 'Unverified';
                if (String.isNotBlank(r.bankName)) newBankName = r.bankName;
                if (String.isNotBlank(r.canonicalSortCode)) newSort = r.canonicalSortCode;
            } catch (Exception e) {
                cleanStatus = 'Unverified';
            }
        }

        PC1_Application__c patch = new PC1_Application__c(
            Id = applicationId,
            Bank_Sort_Code__c        = newSort,
            Bank_Account_Number__c   = newAcct,
            Bank_Account_Holder__c   = newHolder,
            Bank_Roll_Number__c      = newRoll,
            Bank_Name__c             = newBankName,
            Bank_Verification_Status__c = cleanStatus
        );
        if (cleanStatus != 'Unverified' && (digitsChanged || cleanStatus != existing.Bank_Verification_Status__c)) {
            patch.Bank_Verified_At__c = Datetime.now();
        }
        update patch;
    }

    private static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }
    /** Case- and spacing-insensitive form of a holder name, for "did it change". */
    private static String squash(String s) {
        return s == null ? '' : s.trim().toLowerCase().replaceAll('\\s+', ' ');
    }
    private static String blankToNull(String s) {
        return String.isBlank(s) ? null : s.trim();
    }
    private static String keepIfBlank(String incoming, String prior) {
        return String.isBlank(incoming) ? prior : incoming.trim();
    }
    private static String getInternalToken() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        return (cfg != null && String.isNotBlank(cfg.Internal_Admin_Token__c))
            ? cfg.Internal_Admin_Token__c.trim() : null;
    }
    private static String safeBody(HttpResponse r) {
        try {
            String b = r.getBody();
            return b == null ? '' : (b.length() > 200 ? b.substring(0, 200) : b);
        } catch (Exception e) { return ''; }
    }
    private static String str(Object o) { return o == null ? '' : String.valueOf(o).trim(); }
}