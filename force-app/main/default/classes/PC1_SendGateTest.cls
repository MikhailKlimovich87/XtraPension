@isTest
private class PC1_SendGateTest {

    private static void asSandbox() { PC1_SendGate.sandboxOverride = true;  PC1_SendGate.resetCaches(); }
    private static void asProduction() { PC1_SendGate.sandboxOverride = false; PC1_SendGate.resetCaches(); }

    private static void allowlist(String v) {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        cfg.put('Test_Send_Allowlist__c', v);
        upsert cfg;
        PC1_SendGate.resetCaches();
    }

    // ── the whole point: a stranger must not be messaged from a sandbox ──────

    @isTest static void sandboxBlocksRealClientEmail() {
        asSandbox();
        System.assertEquals(false, PC1_SendGate.allowEmail('brenworky@gmail.com'),
            'a real client address must be blocked in a sandbox');
        System.assertEquals(false, PC1_SendGate.allowEmail('mtr@lanigancurran.ie'));
        System.assertEquals(false, PC1_SendGate.allowEmail('someone@outlook.com'));
    }

    @isTest static void sandboxBlocksRealClientSms() {
        asSandbox();
        System.assertEquals(false, PC1_SendGate.allowSms('+353861234567'),
            'a real mobile must be blocked in a sandbox');
    }

    @isTest static void sandboxAllowsOwnStaff() {
        asSandbox();
        System.assertEquals(true, PC1_SendGate.allowEmail('fernando@xtrapension.com'));
        System.assertEquals(true, PC1_SendGate.allowEmail('ANYONE@XtraPension.com'), 'case-insensitive');
    }

    @isTest static void productionIsNeverGated() {
        asProduction();
        System.assertEquals(true, PC1_SendGate.allowEmail('brenworky@gmail.com'),
            'production must dispatch to real clients as normal');
        System.assertEquals(true, PC1_SendGate.allowSms('+353861234567'));
    }

    // ── allowlist ───────────────────────────────────────────────────────────

    @isTest static void allowlistedAddressPasses() {
        asSandbox();
        allowlist('tester@gmail.com, other@mail.com');
        System.assertEquals(true, PC1_SendGate.allowEmail('tester@gmail.com'));
        System.assertEquals(true, PC1_SendGate.allowEmail('  TESTER@gmail.com '), 'trimmed + lowercased');
        System.assertEquals(false, PC1_SendGate.allowEmail('stranger@gmail.com'),
            'allowlisting one gmail must NOT open the whole domain');
    }

    @isTest static void allowlistedDomainPasses() {
        asSandbox();
        allowlist('@succraft.com');
        System.assertEquals(true, PC1_SendGate.allowEmail('sergey.zhitkevich@succraft.com'));
        System.assertEquals(false, PC1_SendGate.allowEmail('someone@gmail.com'));
    }

    @isTest static void allowlistedPhoneIgnoresFormatting() {
        asSandbox();
        allowlist('+353 86 123 4567');
        System.assertEquals(true, PC1_SendGate.allowSms('00353861234567'), 'digits-only comparison');
        System.assertEquals(true, PC1_SendGate.allowSms('+353861234567'));
        System.assertEquals(false, PC1_SendGate.allowSms('+353869999999'));
    }

    // ── edges ───────────────────────────────────────────────────────────────

    @isTest static void blankAndMalformedAreBlocked() {
        asSandbox();
        System.assertEquals(false, PC1_SendGate.allowEmail(null));
        System.assertEquals(false, PC1_SendGate.allowEmail(''));
        System.assertEquals(false, PC1_SendGate.allowEmail('not-an-address'), 'no @ → blocked');
        System.assertEquals(false, PC1_SendGate.allowSms(null));
        System.assertEquals(false, PC1_SendGate.allowSms(''));
    }

    @isTest static void blockReasonNamesTheDestination() {
        String r = PC1_SendGate.blockReason('brenworky@gmail.com');
        System.assert(r.contains('brenworky@gmail.com'), 'reason must name the blocked destination');
        System.assert(r.contains('SANDBOX'), 'reason must say why');
    }

    @isTest static void orgLookupIsExercised() {
        // Clear the override: in a test run isSandbox() deliberately reports false
        // (see PC1_SendGate.isSandbox) so existing dispatcher tests are ungated.
        // What is asserted here is the invariant, not the value.
        PC1_SendGate.sandboxOverride = null;
        PC1_SendGate.resetCaches();
        Test.startTest();
        Boolean sb = PC1_SendGate.isSandbox();
        Test.stopTest();
        System.assertEquals(sb, !PC1_SendGate.isProduction(), 'isProduction must be the inverse');
    }
}