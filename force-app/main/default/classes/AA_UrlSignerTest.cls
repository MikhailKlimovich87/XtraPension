/**
 * AA_UrlSignerTest — coverage for AA_UrlSigner.
 * Uses AA_Config__c custom setting to inject a deterministic secret.
 */
@IsTest
private class AA_UrlSignerTest {

    @IsTest static void signsAndVerifiesRoundTrip() {
        // Seed the custom setting so signAppId returns a real signature.
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new AA_Config__c();
        cfg.Signing_Secret__c = 'test-secret-do-not-use-in-prod';
        upsert cfg;

        // Insert an Application to get a real 18-char Id
        AA_Application__c app = new AA_Application__c(First_Name__c = 'Signer', Last_Name__c = 'Test');
        insert app;

        Test.startTest();
        String sig = AA_UrlSigner.signAppId(app.Id);
        Test.stopTest();

        System.assert(sig != null && sig.length() == 22, 'signature should be 22 base64url chars, got: ' + sig);
        System.assertNotEquals('UNCONFIGURED', sig, 'secret was set — should not be UNCONFIGURED');

        System.assert(AA_UrlSigner.verifyToken(app.Id, sig),  'verifyToken must accept the just-signed token');
        System.assert(!AA_UrlSigner.verifyToken(app.Id, 'wrong-token-xxxxxxxxxx'),  'verifyToken must reject a wrong token');
        System.assert(!AA_UrlSigner.verifyToken(app.Id, sig + 'x'), 'verifyToken must reject on length mismatch');
    }

    @IsTest static void returnsUnconfiguredWhenSecretMissing() {
        // Force cfg to null-secret state
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new AA_Config__c();
        cfg.Signing_Secret__c = null;
        upsert cfg;

        AA_Application__c app = new AA_Application__c(First_Name__c = 'Un', Last_Name__c = 'Configured');
        insert app;

        Test.startTest();
        String sig = AA_UrlSigner.signAppId(app.Id);
        Test.stopTest();

        System.assertEquals('UNCONFIGURED', sig, 'no secret configured should yield UNCONFIGURED');
        System.assert(!AA_UrlSigner.verifyToken(app.Id, 'anything'), 'verify must fail when secret missing');
    }

    @IsTest static void triggerStampsSignatureOnInsert() {
        AA_Config__c cfg = AA_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new AA_Config__c();
        cfg.Signing_Secret__c = 'trigger-test-secret';
        upsert cfg;

        Test.startTest();
        AA_Application__c app = new AA_Application__c(First_Name__c = 'Trigger', Last_Name__c = 'Stamp');
        insert app;
        Test.stopTest();

        AA_Application__c reread = [SELECT Id, Signature__c FROM AA_Application__c WHERE Id = :app.Id LIMIT 1];
        System.assertNotEquals(null, reread.Signature__c, 'trigger should stamp Signature__c');
        System.assertEquals(22, reread.Signature__c.length(), 'signature should be 22 chars');
    }
}