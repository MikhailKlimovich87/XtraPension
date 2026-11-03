/**
 * PC1_BankLookupTest — audit R6 M11 rewrite. Tests were still mocking the
 * retired direct-Data8 envelope (Status/Valid/FullBankName/Accepts*Direct
 * DebitTransactions) and seeding Data8_Key__c which the class no longer
 * reads. Any deploy with RunLocalTests failed.
 *
 * Post-rewrite the tests mirror the Heroku envelope actually consumed by
 * PC1_BankLookup.verifyAccountLegacy: {ok, status, bankName, acceptsDD,
 * canonicalSortCode, error?} with status ∈ Modulus Passed | Bank Does Not
 * Accept DD | Invalid Sort Code | Invalid Account Number | Bank
 * Verification Unavailable | Bank Confirmed | Verified (legacy). Auth is
 * the Internal_Admin_Token__c bearer.
 */
@isTest
private class PC1_BankLookupTest {

    /** Mock for the Heroku bank-verify endpoint envelope. */
    private class HerokuBankMock implements HttpCalloutMock {
        String body;
        Integer statusCode = 200;
        HerokuBankMock(String b) { this.body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(statusCode);
            r.setBody(body);
            return r;
        }
    }

    private static PC1_Application__c makeApp() {
        return new PC1_Application__c(
            First_Name__c = 'Bank', Last_Name__c = 'Test' + System.now().getTime(),
            Phone__c = '+441234567890', Stage__c = 'New'
        );
    }

    @isTest static void verify_modulus_passed_dd_capable() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new HerokuBankMock(
            '{"ok":true,"status":"Modulus Passed","bankName":"BARCLAYS BANK PLC",' +
            '"acceptsDD":true,"canonicalSortCode":"20-00-00"}'
        ));
        Test.startTest();
        PC1_BankLookup.Result r = PC1_BankLookup.verifyAccountLegacy('20-00-00', '55779911');
        Test.stopTest();
        System.assertEquals('Modulus Passed', r.status);
        System.assertEquals('BARCLAYS BANK PLC', r.bankName);
        System.assertEquals(true, r.acceptsDD);
    }

    @isTest static void verify_bank_does_not_accept_dd() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new HerokuBankMock(
            '{"ok":true,"status":"Bank Does Not Accept DD","bankName":"OBSCURE CU",' +
            '"acceptsDD":false,"canonicalSortCode":"20-00-00"}'
        ));
        Test.startTest();
        PC1_BankLookup.Result r = PC1_BankLookup.verifyAccountLegacy('200000', '55779911');
        Test.stopTest();
        System.assertEquals('Bank Does Not Accept DD', r.status);
        System.assertEquals(false, r.acceptsDD);
    }

    @isTest static void verify_invalid_sort_code() {
        upsertConfig();
        Test.setMock(HttpCalloutMock.class, new HerokuBankMock(
            '{"ok":false,"status":"Invalid Sort Code","bankName":"","acceptsDD":false,"error":"unknown_sort"}'
        ));
        Test.startTest();
        PC1_BankLookup.Result r = PC1_BankLookup.verifyAccountLegacy('99-99-99', '12345678');
        Test.stopTest();
        System.assertEquals('Invalid Sort Code', r.status);
    }

    @isTest static void verify_rejects_bad_sort_shape() {
        upsertConfig();
        Boolean threw = false;
        try { PC1_BankLookup.verifyAccountLegacy('abcdef', '12345678'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Non-digit sort must throw');
    }

    @isTest static void verify_rejects_bad_account_shape() {
        upsertConfig();
        Boolean threw = false;
        try { PC1_BankLookup.verifyAccountLegacy('200000', '12345'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Too-short account must throw');
    }

    @isTest static void save_and_reverify_preserves_bank_name() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        insert a;

        // First: full save
        PC1_BankLookup.saveVerification(
            a.Id, '20-00-00', '55779911', 'MR TEST', '', 'BARCLAYS BANK PLC', 'Modulus Passed'
        );
        PC1_Application__c after1 = [SELECT Bank_Name__c, Bank_Verification_Status__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('BARCLAYS BANK PLC', after1.Bank_Name__c);

        // Retry with blank bank name — MUST preserve the prior value.
        PC1_BankLookup.saveVerification(
            a.Id, '20-00-00', '55779911', 'MR TEST', '', '', 'Invalid Account Number'
        );
        PC1_Application__c after2 = [SELECT Bank_Name__c, Bank_Verification_Status__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('BARCLAYS BANK PLC', after2.Bank_Name__c, 'Bank name preserved on blank retry');
        System.assertEquals('Invalid Account Number', after2.Bank_Verification_Status__c);
    }

    @isTest static void save_rejects_bad_status() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        insert a;
        Boolean threw = false;
        try {
            PC1_BankLookup.saveVerification(a.Id, '20-00-00', '55779911', 'MR', '', '', 'Hacked');
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'Unknown status must throw');
    }

    /** Ensure PC1_Config__c org defaults has Internal_Admin_Token__c set —
     *  PC1_BankLookup uses THIS for the Heroku callout, not Data8_Key__c. */
    private static void upsertConfig() {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        if (rows.isEmpty()) {
            insert new PC1_Config__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Internal_Admin_Token__c = 'TEST-BEARER',
                Heroku_Base_Url__c = 'https://mock.local'
            );
        } else {
            update new PC1_Config__c(
                Id = rows[0].Id,
                Internal_Admin_Token__c = 'TEST-BEARER',
                Heroku_Base_Url__c = 'https://mock.local'
            );
        }
    }
}