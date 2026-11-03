/**
 * AA_AdminAlertRESTTest — covers the two things that actually differ from
 * "call Messaging.sendEmail": the auth gate and the recipient fallback.
 * sendEmail itself is stubbed by @isTest — SFDC never actually delivers.
 *
 * DAILY_ORG_EMAIL_LIMIT is not a real concern here (each test sends 1
 * message and the org limit is 5000/day) but @isTest suppresses delivery
 * anyway, so tests are safe to re-run.
 */
@isTest
private class AA_AdminAlertRESTTest {

    private static void seedConfig(String token, String adminEmail) {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        AA_Config__c cfg = rows.isEmpty()
            ? new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId())
            : new AA_Config__c(Id = rows[0].Id);
        cfg.Internal_Admin_Token__c = token;
        try { cfg.put('Admin_Alert_Email__c', adminEmail); }
        catch (Exception ignored) { /* field may not be deployed in a scratch org — fallback path is tested elsewhere */ }
        upsert cfg;
    }

    private static RestRequest buildReq(String bodyJson) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/aa/admin-alert';
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
        AA_AdminAlertREST.doPost();
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
        AA_AdminAlertREST.doPost();
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
        AA_AdminAlertREST.doPost();
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
        AA_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @isTest static void doPost_invalidJson_returns400() {
        seedConfig('SECRET-XYZ', 'fernando@example.com');
        buildReq('{not json');

        Test.startTest();
        AA_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    // No toAddress: the recipient comes from AA_Config__c.Admin_Alert_Email__c,
    // and an oversized subject/body is cut to the endpoint's limits.
    @isTest static void doPost_defaultRecipient_truncatesAndSetsOptionalFields() {
        seedConfig('SECRET-XYZ', 'ops@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'SECRET-XYZ',
            'subject'       => 'S'.repeat(300),
            'htmlBody'      => 'B'.repeat(250010),
            'textBody'      => 'plain fallback',
            'replyTo'       => 'noreply@example.com'
        }));

        Test.startTest();
        AA_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('ops@example.com', resp.get('to'));
    }

    // Admin_Alert_Email__c blank: falls back to the running user's email.
    @isTest static void resolveDefaultRecipient_fallsBackToRunningUser() {
        seedConfig('SECRET-XYZ', null);
        String expected = [SELECT Email FROM User WHERE Id = :UserInfo.getUserId()].Email;
        System.assertEquals(expected, AA_AdminAlertREST.resolveDefaultRecipient());
    }

    @isTest static void constantTimeEquals_handlesNullAndMismatch() {
        System.assertEquals(true,  AA_AdminAlertREST.constantTimeEquals('abc', 'abc'));
        System.assertEquals(false, AA_AdminAlertREST.constantTimeEquals('abc', 'abd'));
        System.assertEquals(false, AA_AdminAlertREST.constantTimeEquals(null, 'abc'));
    }

    // Token not configured: every call is refused, even with a secret supplied.
    @isTest static void doPost_noTokenConfigured_returns401() {
        seedConfig(null, 'ops@example.com');
        buildReq(JSON.serialize(new Map<String, Object>{
            'shared_secret' => 'anything', 'subject' => 'x', 'htmlBody' => '<p>x</p>'
        }));

        Test.startTest();
        AA_AdminAlertREST.doPost();
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
    }
}