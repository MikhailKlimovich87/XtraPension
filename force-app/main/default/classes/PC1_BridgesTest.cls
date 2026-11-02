/**
 * Tests for the Heroku bridges with no test until 2026-10-02:
 * PC1_MaryBridge (Call Now), PC1_SchedulerTickJob, PC1_FormMonitorScheduler
 * and PC1_MandateOverflowQueueable.
 */
@IsTest
private class PC1_BridgesTest {

    private class HerokuMock implements HttpCalloutMock {
        Integer status;
        HerokuMock(Integer status) { this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody('{"status":"dialing","ok":true,"mandate_id":"MD1","status":"pending_submission","mandate_pdf":{"ok":true}}');
            return r;
        }
    }

    private static void config(Boolean complete) {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c c = rows.isEmpty() ? new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId()) : new PC1_Config__c(Id = rows[0].Id);
        c.Heroku_Base_Url__c = complete ? 'https://example.herokuapp.com' : null;
        c.Heroku_Internal_Token__c = complete ? 'tok' : null;
        c.Internal_Admin_Token__c = 'tok';
        c.Auto_Create_DD_Mandate__c = false;
        upsert c;
    }

    private static PC1_Application__c makeApp(String stage) {
        PC1_Application__c a = new PC1_Application__c(First_Name__c = 'Br', Last_Name__c = 'Idge', Stage__c = stage,
            Phone__c = '+441234567890', Email__c = 'b@example.com', Address_Line1__c = '1 St', City__c = 'Leeds',
            Postcode__c = 'LS1 1AA', Bank_Sort_Code__c = '20-00-00', Bank_Account_Number__c = '55779911',
            Bank_Account_Holder__c = 'B IDGE', Bank_Verification_Status__c = 'Modulus Passed', DD_Terms_Read_By_Sales__c = true);
        insert a;
        return a;
    }

    // ── Call Now ─────────────────────────────────────────────────────

    @IsTest static void call_now_dials_in_collection_stages() {
        config(true);
        PC1_Application__c a = makeApp('Awaiting First Call');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(202));
        Test.startTest();
        System.assert(PC1_MaryBridge.callNow(a.Id).contains('dialing'));
        Test.stopTest();
    }

    @IsTest static void call_now_refused_after_submission() {
        config(true);
        PC1_Application__c a = makeApp('Awarded');
        Boolean threw = false;
        try { PC1_MaryBridge.callNow(a.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'post-award records must not be dialled (and pushed back to Data Complete)');
    }

    @IsTest static void call_now_errors() {
        PC1_Application__c a = makeApp('New');
        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_MaryBridge.callNow(null); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_MaryBridge.callNow(a.Id); } catch (AuraHandledException e) { t2 = true; }          // no config
        config(true);
        Test.setMock(HttpCalloutMock.class, new HerokuMock(409));
        try { PC1_MaryBridge.callNow(a.Id); } catch (AuraHandledException e) { t3 = true; }
        try { PC1_MaryBridge.callNow(UserInfo.getUserId()); } catch (Exception e) { t4 = true; }   // not an application
        System.assert(t1 && t2 && t3 && t4);
    }

    // ── Scheduler tick + form monitor ────────────────────────────────

    @IsTest static void scheduler_tick_sync_async_and_skip() {
        System.assert(PC1_SchedulerTickJob.fireOnce()[0].startsWith('skipped'));
        config(true);
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200));
        Test.startTest();
        System.assert(PC1_SchedulerTickJob.fireOnce()[0].startsWith('HTTP 200'));
        new PC1_SchedulerTickJob().execute(null);
        Test.stopTest();
    }

    @IsTest static void form_monitor_scheduler() {
        Test.setMock(HttpCalloutMock.class, new HerokuMock(202));
        Test.startTest();
        PC1_FormMonitorScheduler.firePostAsync();       // no token → logs and returns
        Test.stopTest();
        config(true);
        System.assertEquals('tok', PC1_FormMonitorScheduler.getHerokuToken());
    }

    @IsTest static void form_monitor_scheduler_posts() {
        config(true);
        Test.setMock(HttpCalloutMock.class, new HerokuMock(202));
        Test.startTest();
        new PC1_FormMonitorScheduler().execute(null);
        Test.stopTest();
    }

    // ── Mandate overflow queue ───────────────────────────────────────

    @IsTest static void overflow_queue_creates_and_chains() {
        config(true);
        PC1_Application__c a = makeApp('Awaiting First Call');
        PC1_Application__c b = makeApp('Awaiting First Call');
        Test.setMock(HttpCalloutMock.class, new HerokuMock(200));
        Test.startTest();
        new PC1_MandateOverflowQueueable(new List<Id>{ a.Id, b.Id }).execute(null);
        Test.stopTest();
        System.assertEquals('MD1', [SELECT DD_Mandate_Id__c FROM PC1_Application__c WHERE Id = :a.Id].DD_Mandate_Id__c);
        new PC1_MandateOverflowQueueable(null).execute(null);   // empty → no-op
    }
}