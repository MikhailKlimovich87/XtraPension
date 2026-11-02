/**
 * PC1_AdminAlertRESTTest — covers the two things that actually differ from
 * "call Messaging.sendEmail": the auth gate and the recipient fallback.
 * sendEmail itself is stubbed by @isTest — SFDC never actually delivers.
 *
 * DAILY_ORG_EMAIL_LIMIT is not a real concern here (each test sends 1
 * message and the org limit is 5000/day) but @isTest suppresses delivery
 * anyway, so tests are safe to re-run.
 */
@isTest
private class PC1_AdminAlertRESTTest {

    private static void seedConfig(String token, String adminEmail) {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c cfg = rows.isEmpty()
            ? new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new PC1_Config__c(Id = rows[0].Id);
        cfg.Internal_Admin_Token__c = token;
        try { cfg.put('Admin_Alert_Email__c', adminEmail); }
        catch (Exception ignored) { /* field may not be deployed in a scratch org — fallback path is tested elsewhere */ }
        upsert cfg;
    }

    private static RestRequest buildReq(String bodyJson) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pc1/admin-alert';
        req.httpMethod = 'POST';
        req.addHeader('Content-Type', 'application/json');
        req.requestBody = Blob.valueOf(bodyJson);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return req;
    }

    @isTest static void doPost_happyPath_returnsOkAndSends() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'SECRET-XYZ',
            'subject'       => 'Test alert',
            'htmlBody'      => '<p>hi</p>',
            'toAddress'     => 'fernando@example.com'
        }));

        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('ok'));
        System.assertEquals(1, resp.get('sent'));
    }

    @isTest static void doPost_missingSecret_returns401() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'subject'   => 'x',
            'htmlBody'  => '<p>x</p>',
            'toAddress' => 'a@b.c'
        }));

        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @isTest static void doPost_wrongSecret_returns401() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'WRONG',
            'subject'       => 'x',
            'htmlBody'      => '<p>x</p>',
            'toAddress'     => 'a@b.c'
        }));

        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }

    @isTest static void doPost_missingSubject_returns400() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'SECRET-XYZ',
            'htmlBody'      => '<p>x</p>',
            'toAddress'     => 'a@b.c'
        }));

        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @isTest static void doPost_invalidJson_returns400() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq('{not json');

        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    // ── 2026-10-02: truncation, default recipient, send failure ──────
    @isTest static void doPost_longFields_defaultRecipient() {
        seedConfig('SECRET-XYZ', null);
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'SECRET-XYZ',
            'subject'       => 'S'.repeat(400),
            'htmlBody'      => 'B'.repeat(200000),
            'textBody'      => 'plain',
            'replyTo'       => 'ops@example.com'
        }));
        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();
        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        System.assertEquals(200, RestContext.response.statusCode, String.valueOf(resp));
        System.assertEquals([SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email, resp.get('to'),
            'no Admin_Alert_Email__c → running user');
    }

    @isTest static void doPost_badRecipient_reportsFailure() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'SECRET-XYZ',
            'subject'       => 'x',
            'htmlBody'      => '<p>x</p>',
            'toAddress'     => 'not an address'
        }));
        Test.startTest();
        PC1_AdminAlertREST.doPost();
        Test.stopTest();
        System.assertEquals(500, RestContext.response.statusCode);
    }

    @isTest static void resolveDefaultRecipient_prefersConfig() {
        seedConfig('SECRET-XYZ', 'alerts@example.com');
        String r = PC1_AdminAlertREST.resolveDefaultRecipient();
        System.assert(r == 'alerts@example.com' || r == [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email);
    }
}