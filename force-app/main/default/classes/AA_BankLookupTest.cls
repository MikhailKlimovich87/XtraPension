/**
 * AA_BankLookupTest — covers verifyAccount (via the Heroku /api/form/bank/verify
 * endpoint, with HttpCalloutMock) + verifyAndPersistAccount + saveVerification
 * (real DML) + input validation edges.
 *
 * 2026-09-02 (audit #34): rewritten to the live endpoint contract
 * {ok,status,bankName,acceptsDD,canonicalSortCode}. The old Data8 IsValid mock
 * shape ({"Status":{"Success":..},"Valid":..}) no longer matches — the endpoint
 * path (verifyAccountViaEndpoint) reads data.ok/status, so the stale mock made
 * both verify tests throw 'Unknown verify failure' and blocked every
 * RunLocalTests deploy.
 */
@isTest
private class AA_BankLookupTest {

    /** Mock for POST /api/form/bank/verify. */
    private class BankVerifyMock implements HttpCalloutMock {
        String body;
        Integer statusCode;
        BankVerifyMock(String b) { this.body = b; this.statusCode = 200; }
        BankVerifyMock(String b, Integer sc) { this.body = b; this.statusCode = sc; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(statusCode);
            r.setBody(body);
            return r;
        }
    }

    private static AA_Application__c makeApp() {
        return new AA_Application__c(
            First_Name__c = 'Bank', Last_Name__c = 'Test' + System.now().getTime(),
            Phone__c = '+441234567890', Stage__c = 'New'
        );
    }

    // ── verify: modulus passed + DD-capable → verified ──────────────
    @isTest static void verify_valid_dd_capable() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock(
            '{"ok":true,"status":"Modulus Passed","bankName":"BARCLAYS BANK PLC",' +
            '"canonicalSortCode":"20-00-00","acceptsDD":true}'
        ));
        Test.startTest();
        AA_BankLookup.Result r = AA_BankLookup.verifyAccountLegacy('20-00-00', '55779911');
        Test.stopTest();
        System.assertEquals(true, r.verified, 'Modulus Passed + acceptsDD → verified');
        System.assertEquals('Modulus Passed', r.status);
        System.assertEquals('BARCLAYS BANK PLC', r.bankName);
        System.assertEquals(true, r.acceptsDD);
    }

    // ── verify: real account but not DD-capable → not verified ──────
    @isTest static void verify_valid_not_dd_capable() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock(
            '{"ok":false,"status":"Bank Does Not Accept DD","bankName":"BARCLAYS BANK PLC",' +
            '"canonicalSortCode":"20-00-00","acceptsDD":false}'
        ));
        Test.startTest();
        AA_BankLookup.Result r = AA_BankLookup.verifyAccountLegacy('200000', '55779911');
        Test.stopTest();
        System.assertEquals(false, r.verified, 'not DD-capable → not verified');
        System.assertEquals('Bank Does Not Accept DD', r.status);
    }

    // ── verify: endpoint ok=false + a human status is NOT a throw ───
    @isTest static void verify_invalid_sort_surfaced_not_thrown() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock(
            '{"ok":false,"status":"Invalid Sort Code","bankName":"","acceptsDD":false}'
        ));
        Test.startTest();
        AA_BankLookup.Result r = AA_BankLookup.verifyAccountLegacy('20-00-01', '55779911');
        Test.stopTest();
        System.assertEquals(false, r.verified);
        System.assertEquals('Invalid Sort Code', r.status);
    }

    // ── verify: HTTP error → AuraHandledException ───────────────────
    @isTest static void verify_http_error_throws() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock('{"error":"boom"}', 500));
        Boolean threw = false;
        Test.startTest();
        try { AA_BankLookup.verifyAccountLegacy('200000', '55779911'); }
        catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'Non-2xx must throw AuraHandledException');
    }

    // ── verifyAndPersistAccount: persists status/name/verified-at ───
    @isTest static void verifyAndPersist_persists_outcome() {
        upsertConfig();
        AA_Application__c a = makeApp();
        insert a;
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock(
            '{"ok":true,"status":"Modulus Passed","bankName":"BARCLAYS BANK PLC",' +
            '"canonicalSortCode":"20-00-00","acceptsDD":true}'
        ));
        Test.startTest();
        AA_BankLookup.verifyAndPersistAccount(a.Id, '20-00-00', '55779911', 'MR TEST');
        Test.stopTest();
        AA_Application__c after = [
            SELECT Bank_Verification_Status__c, Bank_Name__c, Bank_Verified_At__c, Bank_Sort_Code__c
              FROM AA_Application__c WHERE Id = :a.Id
        ];
        System.assertEquals('Modulus Passed', after.Bank_Verification_Status__c);
        System.assertEquals('BARCLAYS BANK PLC', after.Bank_Name__c);
        System.assertNotEquals(null, after.Bank_Verified_At__c, 'verified-at stamped for a real status');
    }

    // ── input validation (throws before any callout) ────────────────
    @isTest static void verify_rejects_bad_sort() {
        upsertConfig();
        Boolean threw = false;
        try { AA_BankLookup.verifyAccountLegacy('abcdef', '12345678'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Non-digit sort must throw');
    }

    @isTest static void verify_rejects_bad_account() {
        upsertConfig();
        Boolean threw = false;
        try { AA_BankLookup.verifyAccountLegacy('200000', '12345'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Too-short account must throw');
    }

    // ── saveVerification DML ────────────────────────────────────────
    @isTest static void save_and_reverify_preserves_bank_name() {
        upsertConfig();
        AA_Application__c a = makeApp();
        insert a;

        // New digits → the server re-checks them (mocked) before storing a status.
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock(
            '{"ok":true,"status":"Modulus Passed","bankName":"BARCLAYS BANK PLC",' +
            '"canonicalSortCode":"20-00-00","acceptsDD":true}'
        ));
        Test.startTest();   // DML above, callout below: separate them
        AA_BankLookup.saveVerification(
            a.Id, '20-00-00', '55779911', 'MR TEST', '', 'BARCLAYS BANK PLC', 'Modulus Passed', null
        );
        AA_Application__c after1 = [SELECT Bank_Name__c, Bank_Verification_Status__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('BARCLAYS BANK PLC', after1.Bank_Name__c);
        System.assertEquals('Modulus Passed', after1.Bank_Verification_Status__c);

        // Retry with blank bank name — MUST preserve the prior value.
        AA_BankLookup.saveVerification(
            a.Id, '20-00-00', '55779911', 'MR TEST', '', '', 'Invalid', null
        );
        AA_Application__c after2 = [SELECT Bank_Name__c, Bank_Verification_Status__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('BARCLAYS BANK PLC', after2.Bank_Name__c, 'Bank name preserved on blank retry');
        System.assertEquals('Invalid', after2.Bank_Verification_Status__c);
        Test.stopTest();
    }

    @isTest static void save_rejects_bad_status() {
        upsertConfig();
        AA_Application__c a = makeApp();
        insert a;
        Boolean threw = false;
        try {
            AA_BankLookup.saveVerification(a.Id, '20-00-00', '55779911', 'MR', '', '', 'Hacked', null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Unknown status must throw');
    }

    // audit 2026-10-02 F61: a green status sent by the browser for NEW digits
    // is not trusted; the server's own check decides.
    @isTest static void save_newDigits_greenStatusFromClient_isRechecked() {
        upsertConfig();
        AA_Application__c a = makeApp();
        insert a;
        Test.setMock(HttpCalloutMock.class, new BankVerifyMock(
            '{"ok":false,"status":"Invalid Account Number","bankName":"","acceptsDD":false}'
        ));
        Test.startTest();
        AA_BankLookup.saveVerification(a.Id, '20-00-00', '11111111', 'MR TEST', '', '', 'Modulus Passed', null);
        Test.stopTest();
        AA_Application__c after = [SELECT Bank_Verification_Status__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('Invalid Account Number', after.Bank_Verification_Status__c);
    }

    // audit 2026-10-02 F61/F108: new digits while a Direct Debit is live are
    // refused until acknowledged; the acknowledged save opens a Task.
    @isTest static void save_newDigits_liveMandate_needsAcknowledgement() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Sort_Code__c = '20-00-00';
        a.Bank_Account_Number__c = '55779911';
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Mandate_Id__c = 'MD-LIVE';
        a.DD_Mandate_Status__c = 'active';
        insert a;
        Boolean threw = false;
        try {
            AA_BankLookup.saveVerification(a.Id, '40-00-00', '12345678', 'MR TEST', '', '', 'Unverified', null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'must refuse until the live Direct Debit is acknowledged');
        System.assertEquals('55779911', [SELECT Bank_Account_Number__c FROM AA_Application__c WHERE Id = :a.Id].Bank_Account_Number__c);

        AA_BankLookup.saveVerification(a.Id, '40-00-00', '12345678', 'MR TEST', '', '', 'Unverified', true);
        System.assertEquals('12345678', [SELECT Bank_Account_Number__c FROM AA_Application__c WHERE Id = :a.Id].Bank_Account_Number__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :a.Id AND Subject LIKE 'Bank details changed%']);
    }

    // Holder-name-only edits keep the verification (it checks digits only).
    @isTest static void save_holderOnly_keepsStatus_noCallout() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Sort_Code__c = '20-00-00';
        a.Bank_Account_Number__c = '55779911';
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Mandate_Id__c = 'MD-LIVE';
        a.DD_Mandate_Status__c = 'active';
        insert a;
        // No mock: a callout here would fail the test.
        AA_BankLookup.saveVerification(a.Id, '20-00-00', '55779911', 'MRS NEW NAME', '', '', 'Modulus Passed', null);
        AA_Application__c after = [SELECT Bank_Verification_Status__c, Bank_Account_Holder__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('Modulus Passed', after.Bank_Verification_Status__c);
        System.assertEquals('MRS NEW NAME', after.Bank_Account_Holder__c);
    }

    /** Ensure an AA_Config__c org-default row exists. The verify callout is
     *  mocked, so no real token is needed — this just avoids a null-config path. */
    private static void upsertConfig() {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        if (rows.isEmpty()) {
            insert new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId(), Internal_Admin_Token__c = 'TEST-TOKEN');
        } else {
            update new AA_Config__c(Id = rows[0].Id, Internal_Admin_Token__c = 'TEST-TOKEN');
        }
    }
}