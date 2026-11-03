/**
 * AA_MandateEligibility — one-liner helper used by
 * AA_MandateAutoCreateTrigger to decide when to enqueue the auto-mandate
 * Queueable. Extracted from the trigger so we can unit-test the rule set
 * without spinning up the async job runner and so future axes (client
 * refusal, expired mandates, dead-lettered retries) grow here rather than
 * cluttering trigger code.
 */
public with sharing class AA_MandateEligibility {

    /** Bank statuses we treat as "verified enough" to open a Direct Debit
     *  agreement. Extended 2026-08-18 for the Data8 CoP-shaped return values:
     *    - 'Modulus Passed'   : legacy free-modulus path (no holder name).
     *    - 'Bank Confirmed'   : Data8 confirmed the account is live, no
     *                            name-match verdict available (current path).
     *    - 'Name Verified'    : real CoP provider says exact name match.
     *    - 'Name Close Match' : real CoP provider says partial name match —
     *                            sales already confirmed with client. */
    public static final Set<String> VERIFIED_STATUSES = new Set<String>{
        'Modulus Passed', 'Bank Confirmed', 'Name Verified', 'Name Close Match'
    };

    public static Boolean isEligible(AA_Application__c a) {
        if (a == null) return false;
        if (!VERIFIED_STATUSES.contains(String.valueOf(a.Bank_Verification_Status__c))) return false;
        if (a.DD_Terms_Read_By_Sales__c != true) return false;
        if (String.isNotBlank(a.DD_Mandate_Id__c)) return false;
        return true;
    }
}