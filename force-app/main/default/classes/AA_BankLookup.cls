/**
 * AA_BankLookup — @AuraEnabled proxy the aaBankEditor LWC calls to run
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
public with sharing class AA_BankLookup {

    private static final String BASE_URL   = 'https://aa-autofill-14d501200453.herokuapp.com';
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
     * Provider-agnostic entrypoint used by aaBankEditor LWC. Calls the
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
        AA_Application__c patch = new AA_Application__c(
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
     *   - `status` restricted to the picklist enum. That alone does NOT stop
     *     a caller sending 'Modulus Passed' for digits that were never
     *     checked (audit 2026-10-02 F61), so when the sort code or account
     *     number change, the status is re-derived server-side (see
     *     saveVerification) instead of trusting the client.
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

    /** Prefix of the error the LWC recognises to ask for the live-mandate
     *  acknowledgement before re-saving (aaBankEditor). */
    public static final String LIVE_MANDATE_ERROR = 'LIVE_DD_MANDATE';

    /**
     * `acknowledgeLiveMandate` (audit 2026-10-02 F61/F108): changing the sort
     * code / account number while a Direct Debit is live does NOT move the
     * Direct Debit. GoCardless keeps collecting from the OLD account while the
     * record shows the new one. Such a save is refused with LIVE_MANDATE_ERROR
     * unless the operator has acknowledged it; an acknowledged save also opens
     * a Task saying how to move the Direct Debit.
     */
    @AuraEnabled
    public static void saveVerification(
        Id applicationId, String sortCode, String accountNumber,
        String accountHolder, String rollNumber, String bankName, String status,
        Boolean acknowledgeLiveMandate
    ) {
        if (applicationId == null) throw new AuraHandledException('Missing application id.');
        String cleanStatus = String.isBlank(status) ? 'Unverified' : status.trim();
        if (!ALLOWED_STATUSES.contains(cleanStatus)) throw new AuraHandledException('Unknown status: ' + cleanStatus);

        AA_Application__c existing = [
            SELECT Bank_Sort_Code__c, Bank_Account_Number__c, Bank_Account_Holder__c,
                   Bank_Roll_Number__c, Bank_Name__c, Bank_Verification_Status__c, Bank_Verified_At__c,
                   DD_Mandate_Id__c, DD_Mandate_Status__c
            FROM AA_Application__c WHERE Id = :applicationId LIMIT 1
        ];
        String newSort = keepIfBlank(sortCode,      existing.Bank_Sort_Code__c);
        String newAcct = keepIfBlank(accountNumber, existing.Bank_Account_Number__c);
        String newHolder = keepIfBlank(accountHolder, existing.Bank_Account_Holder__c);
        String newBankName = keepIfBlank(bankName, existing.Bank_Name__c);
        Boolean digitsChanged = digits(newSort) != digits(existing.Bank_Sort_Code__c)
            || digits(newAcct) != digits(existing.Bank_Account_Number__c);

        String mstat = existing.DD_Mandate_Status__c == null ? '' : existing.DD_Mandate_Status__c.toLowerCase();
        Boolean liveMandate = String.isNotBlank(existing.DD_Mandate_Id__c)
            && mstat != 'failed' && mstat != 'cancelled' && mstat != 'expired';
        if (digitsChanged && liveMandate && acknowledgeLiveMandate != true) {
            throw new AuraHandledException(LIVE_MANDATE_ERROR + ': a Direct Debit is set up on the current account. ' +
                'Saving new bank details does not move it: the fee would still be collected from the old account.');
        }

        // New digits: never trust a status the browser sends. Re-run the check
        // here (callout before any DML) and store what the server says. If the
        // check cannot run, store 'Unverified' so nobody relies on a stale green.
        if (digitsChanged && cleanStatus != 'Unverified') {
            try {
                Result r = verifyAccountViaEndpoint(newSort, newAcct, newHolder);
                cleanStatus = ALLOWED_STATUSES.contains(r.status) ? r.status : 'Unverified';
                if (String.isNotBlank(r.bankName)) newBankName = r.bankName;
                if (String.isNotBlank(r.canonicalSortCode)) newSort = r.canonicalSortCode;
            } catch (Exception e) {
                cleanStatus = 'Unverified';
            }
        }

        AA_Application__c patch = new AA_Application__c(
            Id = applicationId,
            Bank_Sort_Code__c        = newSort,
            Bank_Account_Number__c   = newAcct,
            Bank_Account_Holder__c   = newHolder,
            Bank_Roll_Number__c      = keepIfBlank(rollNumber,    existing.Bank_Roll_Number__c),
            Bank_Name__c             = newBankName,
            Bank_Verification_Status__c = cleanStatus
        );
        if (cleanStatus != 'Unverified' && (digitsChanged || cleanStatus != existing.Bank_Verification_Status__c)) {
            patch.Bank_Verified_At__c = Datetime.now();
        }
        update patch;

        if (digitsChanged && liveMandate) {
            insert new Task(
                WhatId       = applicationId,
                Subject      = 'Bank details changed while a Direct Debit is live',
                Description  = 'The sort code / account number on this record were changed, but the live Direct Debit (' +
                    existing.DD_Mandate_Id__c + ') still points at the OLD account, so any fee would be collected from there.\n\n' +
                    'To move it: cancel the old Direct Debit in the GoCardless dashboard, wait for the record to show it as ' +
                    'Cancelled, confirm with the client that they agree to a new Direct Debit, then click ' +
                    '"Create a new Direct Debit" on the Direct Debit card. Retry any cancelled fee instalment afterwards.',
                Status       = 'Open',
                Priority     = 'High',
                ActivityDate = Date.today()
            );
        }
    }

    private static String digits(String s) {
        return s == null ? '' : s.replaceAll('[^0-9]', '');
    }

    private static String keepIfBlank(String incoming, String prior) {
        return String.isBlank(incoming) ? prior : incoming.trim();
    }
    private static String getInternalToken() {
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
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