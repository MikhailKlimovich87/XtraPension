/**
 * A Canadian bank account, as the Claims code needs it (Canada launch, 16/11/2026).
 *
 * A Canadian account has no IBAN. It is three numbers: the institution number (3 digits, the bank), the transit number
 * (5 digits, the branch) and the account number. The Full Form keeps the first two together in Bank_Sort_Code__c as
 * "003-12345" (institution, then transit). They are needed apart in three places:
 *  - DWP's "Direct Payment request to Canada" (IPC1394 Canada): bank number = 0 + institution, and the transit number;
 *  - GoCardless pre-authorized debit: bank_code = institution, branch_code = transit;
 *  - the pre-authorized debit agreement the client signs.
 *
 * lookup() is the "Get Bank Info" of Canada: GoCardless says whether the institution and transit exist and names the
 * bank (Ireland asks Data8, Australia has its table of BSBs).
 */
public with sharing class XpCanadaBank {

    public class Parts {
        public String institution;
        public String transit;
    }

    /**
     * Institution and transit out of what was typed, or null when it is not a Canadian pair.
     * Read: "003-12345" and "00312345" (institution first, how the form saves it), "12345-003" (the order printed on a
     * cheque: transit first) and "000312345" / "0003-12345" (the electronic form: zero, institution, transit).
     */
    public static Parts parts(String typed) {
        if (String.isBlank(typed)) return null;
        String t = typed.trim();
        String digits = t.replaceAll('[^0-9]', '');
        Parts p = new Parts();
        if (Pattern.matches('^\\d{5}\\D+\\d{3}$', t)) {
            p.transit = digits.left(5);
            p.institution = digits.right(3);
            return p;
        }
        if (digits.length() == 9 && digits.startsWith('0')) digits = digits.substring(1);
        if (digits.length() != 8) return null;
        p.institution = digits.left(3);
        p.transit = digits.right(5);
        return p;
    }

    /** The account number with no spaces, dashes or slashes (DWP and GoCardless both want it bare). */
    public static String accountNumber(String typed) {
        return typed == null ? null : typed.replaceAll('[^0-9A-Za-z]', '');
    }

    // BIC of the banks that hold most accounts, by institution number. GoCardless rarely returns one for Canada, and
    // DWP's Canada form has a BIC box. Any other bank: the BIC stays as typed (it is optional).
    private static final Map<String, String> BIC = new Map<String, String>{
        '001' => 'BOFMCAM2',     // Bank of Montreal
        '002' => 'NOSCCATT',     // Scotiabank
        '003' => 'ROYCCAT2',     // Royal Bank of Canada
        '004' => 'TDOMCATTTOR',  // Toronto-Dominion
        '006' => 'BNDCCAMMINT',  // National Bank of Canada
        '010' => 'CIBCCATT',     // CIBC
        '815' => 'CCDQCAMM'      // Desjardins
    };

    public class Lookup {
        public Boolean found = false;    // the institution and transit exist and the account number has a valid length
        public String bankName;
        public String bic;
        public Boolean canDebit = false; // GoCardless can take a pre-authorized debit from it
        public String message;           // when not found: what is wrong, for the person typing
    }

    /** Asks GoCardless about a Canadian account. Nothing is created there. */
    public static Lookup lookup(String sortCode, String account) {
        Lookup out = new Lookup();
        Parts p = parts(sortCode);
        String acct = accountNumber(account);
        if (p == null) {
            out.message = 'Institution number (3 digits) and transit number (5 digits) needed, like 003-12345.';
            return out;
        }
        if (String.isBlank(acct)) {
            out.message = 'Account number missing.';
            return out;
        }
        Map<String, Object> body = new Map<String, Object>{ 'bank_details_lookups' => new Map<String, Object>{
            'country_code' => 'CA', 'bank_code' => p.institution, 'branch_code' => p.transit, 'account_number' => acct } };
        GocardlessApiHandler.GocardlessAPIResponseWrapper res;
        try {
            res = GocardlessApiHandler.requestGocardlessApi('bank_details_lookups', 'POST', body, true);
        } catch (Exception e) {
            out.message = 'The bank check is not answering right now. The numbers are kept as typed.';
            return out;
        }
        Map<String, Object> root = new Map<String, Object>();
        try {
            if (String.isNotBlank(res.responseBody)) root = (Map<String, Object>) JSON.deserializeUntyped(res.responseBody);
        } catch (Exception e) {
            root = new Map<String, Object>();
        }
        if (res.statusCode == 200 && root.get('bank_details_lookups') != null) {
            Map<String, Object> found = (Map<String, Object>) root.get('bank_details_lookups');
            out.found = true;
            out.bankName = properCase((String) found.get('bank_name'));
            out.bic = String.isNotBlank((String) found.get('bic')) ? (String) found.get('bic') : BIC.get(p.institution);
            List<Object> schemes = (List<Object>) found.get('available_debit_schemes');
            out.canDebit = schemes != null && schemes.contains('pad');
            return out;
        }
        List<String> problems = new List<String>();
        Boolean accountWrong = false;
        Map<String, Object> err = (Map<String, Object>) root.get('error');
        if (err != null && err.get('errors') != null) {
            for (Object o : (List<Object>) err.get('errors')) {
                Map<String, Object> one = (Map<String, Object>) o;
                String field = (String) one.get('field');
                if (field == 'branch_code' || field == 'bank_code') {
                    problems.add('institution number ' + p.institution + ' with transit number ' + p.transit + ' is not a bank branch we can find');
                } else if (field == 'account_number') {
                    accountWrong = true;
                } else {
                    problems.add(field + ' ' + one.get('message'));
                }
            }
        }
        // With an account number of the wrong length GoCardless also rejects the branch, even a real one: say only that
        if (accountWrong) problems = new List<String>{ 'the account number should be 7 to 12 digits' };
        out.message = problems.isEmpty()
            ? 'The bank check is not answering right now. The numbers are kept as typed.'
            : 'Please check the bank details: ' + String.join(problems, '; ') + '.';
        return out;
    }

    // "ROYAL BANK OF CANADA" -> "Royal Bank of Canada"
    @TestVisible
    private static String properCase(String name) {
        if (String.isBlank(name)) return name;
        List<String> out = new List<String>();
        for (String w : name.trim().toLowerCase().split('\\s+')) {
            if (!out.isEmpty() && (new Set<String>{ 'of', 'and', 'the', 'du', 'de', 'des' }).contains(w)) {
                out.add(w);
                continue;
            }
            List<String> bits = new List<String>();
            for (String bit : w.split('-')) bits.add(bit.capitalize());   // "toronto-dominion" -> "Toronto-Dominion"
            out.add(String.join(bits, '-'));
        }
        return String.join(out, ' ');
    }
}