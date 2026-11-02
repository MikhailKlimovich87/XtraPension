/**
 * PC1_UrlSignerTest — coverage for PC1_UrlSigner.
 * Uses PC1_Config__c custom setting to inject a deterministic secret.
 */
@IsTest
private class PC1_UrlSignerTest {

    @IsTest static void signsAndVerifiesRoundTrip() {
        // Seed the custom setting so signAppId returns a real signature.
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = 'test-secret-do-not-use-in-prod';
        upsert cfg;

        // Insert an Application to get a real 18-char Id
        PC1_Application__c app = new PC1_Application__c(First_Name__c = 'Signer', Last_Name__c = 'Test');
        insert app;

        Test.startTest();
        String sig = PC1_UrlSigner.signAppId(app.Id);
        Test.stopTest();

        System.assert(sig != null && sig.length() == 22, 'signature should be 22 base64url chars, got: ' + sig);
        System.assertNotEquals('UNCONFIGURED', sig, 'secret was set — should not be UNCONFIGURED');

        System.assert(PC1_UrlSigner.verifyToken(app.Id, sig),  'verifyToken must accept the just-signed token');
        System.assert(!PC1_UrlSigner.verifyToken(app.Id, 'wrong-token-xxxxxxxxxx'),  'verifyToken must reject a wrong token');
        System.assert(!PC1_UrlSigner.verifyToken(app.Id, sig + 'x'), 'verifyToken must reject on length mismatch');
    }

    @IsTest static void returnsUnconfiguredWhenSecretMissing() {
        // Force cfg to null-secret state
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = null;
        upsert cfg;

        PC1_Application__c app = new PC1_Application__c(First_Name__c = 'Un', Last_Name__c = 'Configured');
        insert app;

        Test.startTest();
        String sig = PC1_UrlSigner.signAppId(app.Id);
        Test.stopTest();

        System.assertEquals('UNCONFIGURED', sig, 'no secret configured should yield UNCONFIGURED');
        System.assert(!PC1_UrlSigner.verifyToken(app.Id, 'anything'), 'verify must fail when secret missing');
    }

    // Known vectors computed in Node with signKey() from src/webhooks/files.js
    // and the same dummy secret (2026-10-29):
    //   PC1_URL_SIGNING_SECRET=pc1-files-test-secret-2026 node -e \
    //     "console.log(require('./src/webhooks/files').signKey('<key>'))"
    @IsTest static void fileKeyMatchesNodeSignKeyByteForByte() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = 'pc1-files-test-secret-2026';
        upsert cfg;

        System.assertEquals('4PbAEnJD14mCKx9VZRc-TV', PC1_UrlSigner.signFileKey('conv_0123456789abcdefghij'),
            'ElevenLabs conversation token must equal files.js signKey()');
        System.assertEquals('09sM3kuSibxHiTSb6DEoSQ', PC1_UrlSigner.signFileKey('svr16-core6-1730203200.4567'),
            'Nuacom call_id token must equal files.js signKey()');
        System.assertEquals(null, PC1_UrlSigner.signFileKey(null));
        System.assertEquals(null, PC1_UrlSigner.signFileKey(''));
    }

    @IsTest static void resignFileUrlReplacesStaleTokens() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = 'pc1-files-test-secret-2026';
        upsert cfg;
        String base = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com/files/';

        System.assertEquals(base + 'transcript/conv_0123456789abcdefghij?t=4PbAEnJD14mCKx9VZRc-TV',
            PC1_UrlSigner.resignFileUrl(base + 'transcript/conv_0123456789abcdefghij?t=OLDTOKENOLDTOKENOLDTOK'));
        System.assertEquals(base + 'recording/conv_0123456789abcdefghij?t=4PbAEnJD14mCKx9VZRc-TV',
            PC1_UrlSigner.resignFileUrl(base + 'recording/conv_0123456789abcdefghij'), 'unsigned link gets a token');
        System.assertEquals(base + 'nuacom-recording/svr16-core6-1730203200.4567?t=09sM3kuSibxHiTSb6DEoSQ',
            PC1_UrlSigner.resignFileUrl(base + 'nuacom-recording/svr16-core6-1730203200.4567?t=stale'));
        System.assertEquals(base + 'transcript/conv_0123456789abcdefghij?format=json&t=4PbAEnJD14mCKx9VZRc-TV',
            PC1_UrlSigner.resignFileUrl(base + 'transcript/conv_0123456789abcdefghij?format=json&t=stale'),
            'other query parameters are kept');
        System.assertEquals('https://example.com/other?t=x', PC1_UrlSigner.resignFileUrl('https://example.com/other?t=x'),
            'non-/files/ links are left alone');
        System.assertEquals(null, PC1_UrlSigner.resignFileUrl(null));
    }

    @IsTest static void resignFileUrlLeavesLinkWhenSecretMissing() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = null;
        upsert cfg;
        String url = 'https://pc1-autofill-0c5c5df96de7.herokuapp.com/files/recording/conv_x?t=abc';
        System.assertEquals(url, PC1_UrlSigner.resignFileUrl(url));
    }

    @IsTest static void triggerStampsSignatureOnInsert() {
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        if (cfg == null || cfg.Id == null) cfg = new PC1_Config__c();
        cfg.Signing_Secret__c = 'trigger-test-secret';
        upsert cfg;

        Test.startTest();
        PC1_Application__c app = new PC1_Application__c(First_Name__c = 'Trigger', Last_Name__c = 'Stamp');
        insert app;
        Test.stopTest();

        PC1_Application__c reread = [SELECT Id, Signature__c FROM PC1_Application__c WHERE Id = :app.Id LIMIT 1];
        System.assertNotEquals(null, reread.Signature__c, 'trigger should stamp Signature__c');
        System.assertEquals(22, reread.Signature__c.length(), 'signature should be 22 chars');
    }
}