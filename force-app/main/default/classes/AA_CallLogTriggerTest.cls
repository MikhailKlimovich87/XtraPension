/**
 * AA_CallLogTriggerTest — covers AA_CallLogTrigger + AA_LastContactUpdater
 * (audit #35: both were at 0% coverage — a hard per-trigger production-deploy
 * blocker, and the latest-wins mirror gate had zero assertions).
 */
@isTest
private class AA_CallLogTriggerTest {

    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'LC', Last_Name__c = 'Test' + System.now().getTime(),
            Stage__c = 'New', CurrencyIsoCode = 'GBP'
        );
        insert a;
        return a;
    }

    // Newest call mirrors; an OLDER call must not regress; a NEWER one advances.
    @isTest static void mirrors_newest_and_respects_latest_wins() {
        AA_Application__c a = makeApp();
        Datetime t0 = Datetime.now().addHours(-5);
        Datetime t1 = Datetime.now().addHours(-2);
        Datetime t2 = Datetime.now().addHours(-1);

        Test.startTest();
        insert new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t1,
            Status__c = 'completed', Direction__c = 'inbound', Source__c = 'Mary');
        insert new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t0,
            Status__c = 'completed', Direction__c = 'inbound', Source__c = 'Mary'); // older → ignored
        insert new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t2,
            Status__c = 'completed', Direction__c = 'inbound', Rep_Name__c = 'Sean Byrne'); // newer → wins
        Test.stopTest();

        AA_Application__c after = [
            SELECT Last_Contact_At__c, Last_Contact_Type__c, Last_Contact_Who__c, Last_Contact_Date__c
              FROM AA_Application__c WHERE Id = :a.Id
        ];
        System.assertEquals(t2, after.Last_Contact_At__c, 'newest call wins; older ignored');
        System.assertEquals('Phone Chat', after.Last_Contact_Type__c);
        System.assertEquals('Sean Byrne', after.Last_Contact_Who__c);
        System.assertEquals(t2.date(), after.Last_Contact_Date__c);
    }

    @isTest static void no_answer_for_outbound_no_answer() {
        AA_Application__c a = makeApp();
        Test.startTest();
        insert new AA_Call_Log__c(Application__c = a.Id, Started_At__c = Datetime.now(),
            Status__c = 'no_answer', Direction__c = 'outbound', Rep_Name__c = 'Grace');
        Test.stopTest();
        AA_Application__c after = [SELECT Last_Contact_Type__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('No Answer', after.Last_Contact_Type__c);
    }

    // after-update path: a late webhook bumping Started_At__c refreshes the card.
    @isTest static void update_bumps_last_contact() {
        AA_Application__c a = makeApp();
        AA_Call_Log__c cl = new AA_Call_Log__c(Application__c = a.Id,
            Started_At__c = Datetime.now().addHours(-1), Status__c = 'in_progress',
            Direction__c = 'inbound', Source__c = 'Mary');
        insert cl;
        Datetime newer = Datetime.now();
        Test.startTest();
        cl.Started_At__c = newer;
        cl.Status__c = 'completed';
        update cl; // fires after update
        Test.stopTest();
        AA_Application__c after = [SELECT Last_Contact_At__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(newer, after.Last_Contact_At__c);
    }

    // 2026-10-29 call-history audit: every case of the contact-type contract.
    @isTest static void derive_type_contract() {
        System.assertEquals('V/Mail Left', AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'no_answer', Voicemail_Left__c = true)),
            'Mary voicemail is V/Mail Left, not Phone Chat');
        System.assertEquals('No Answer', AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Human', Direction__c = 'outbound', Status__c = 'failed')));
        System.assertEquals('Phone Chat', AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'inbound_known', Status__c = 'completed')));
        System.assertEquals(null, AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'inbound_known', Status__c = 'completed', Personalization_Only__c = true)));
        System.assertEquals(null, AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'queued')));
        System.assertEquals(null, AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Mary', Direction__c = 'outbound', Status__c = 'in_progress')));
        System.assertEquals(null, AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Human', Direction__c = 'inbound', Status__c = 'no_answer')));
        System.assertEquals(null, AA_LastContactUpdater.deriveType(new AA_Call_Log__c(
            Source__c = 'Human', Direction__c = 'inbound', Status__c = 'completed', Voicemail_Left__c = true)),
            'a voicemail the client left us is not our contact');
        System.assertEquals(null, AA_LastContactUpdater.deriveType(new AA_Call_Log__c()), 'no status = still open');
        System.assertEquals('Grace', AA_LastContactUpdater.deriveWho(new AA_Call_Log__c(Source__c = 'Human', Rep_Name__c = 'Grace')));
        System.assertEquals('Mary', AA_LastContactUpdater.deriveWho(new AA_Call_Log__c(Source__c = 'Mary')));
    }

    // Placeholders, open calls and missed inbound calls never move the card.
    @isTest static void skips_placeholders_missed_inbound_and_open_calls() {
        AA_Application__c a = makeApp();
        Datetime t1 = Datetime.now().addHours(-3);
        insert new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t1, Status__c = 'completed',
            Direction__c = 'outbound', Source__c = 'Human', Rep_Name__c = 'Grace');
        Test.startTest();
        insert new List<AA_Call_Log__c>{
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addHours(1), Status__c = 'no_answer',
                Direction__c = 'inbound_known', Source__c = 'Mary', Personalization_Only__c = true),
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addHours(2), Status__c = 'no_answer',
                Direction__c = 'inbound', Source__c = 'Human', Rep_Name__c = 'Reception XtraPension'),
            new AA_Call_Log__c(Application__c = a.Id, Started_At__c = t1.addMinutes(150), Status__c = 'queued',
                Direction__c = 'outbound', Source__c = 'Mary')
        };
        Test.stopTest();
        AA_Application__c after = [SELECT Last_Contact_Type__c, Last_Contact_Who__c, Last_Contact_At__c FROM AA_Application__c WHERE Id = :a.Id];
        Datetime graceAt = [SELECT Started_At__c FROM AA_Call_Log__c WHERE Application__c = :a.Id AND Rep_Name__c = 'Grace'].Started_At__c;
        System.assertEquals(graceAt, after.Last_Contact_At__c, 'none of the later rows is a contact');
        System.assertEquals('Phone Chat', after.Last_Contact_Type__c);
        System.assertEquals('Grace', after.Last_Contact_Who__c);
    }

    // The gate is >, not >=: the same call closing later re-derives the type.
    @isTest static void same_call_closing_later_rederives() {
        AA_Application__c a = makeApp();
        AA_Call_Log__c cl = new AA_Call_Log__c(Application__c = a.Id, Started_At__c = Datetime.now().addMinutes(-30),
            Status__c = 'in_progress', Direction__c = 'outbound', Source__c = 'Mary');
        insert cl;
        System.assertEquals(null, [SELECT Last_Contact_At__c FROM AA_Application__c WHERE Id = :a.Id].Last_Contact_At__c,
            'an open call is not mirrored');
        Test.startTest();
        cl.Status__c = 'no_answer';
        cl.Voicemail_Left__c = true;
        update cl;
        AA_Application__c mid = [SELECT Last_Contact_Type__c, Last_Contact_Who__c, Last_Contact_At__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('V/Mail Left', mid.Last_Contact_Type__c);
        System.assertEquals('Mary', mid.Last_Contact_Who__c);
        System.assertEquals([SELECT Started_At__c FROM AA_Call_Log__c WHERE Id = :cl.Id].Started_At__c, mid.Last_Contact_At__c);
        cl.Status__c = 'completed';
        cl.Voicemail_Left__c = false;
        update cl;
        Test.stopTest();
        System.assertEquals('Phone Chat', [SELECT Last_Contact_Type__c FROM AA_Application__c WHERE Id = :a.Id].Last_Contact_Type__c);
    }

    // Bulk safety: 200 rows across 2 apps in one insert.
    @isTest static void bulk_two_apps_200_rows() {
        AA_Application__c a1 = makeApp();
        AA_Application__c a2 = makeApp();
        List<AA_Call_Log__c> rows = new List<AA_Call_Log__c>();
        Datetime base = Datetime.now().addDays(-1);
        for (Integer i = 0; i < 100; i++) {
            rows.add(new AA_Call_Log__c(Application__c = a1.Id, Started_At__c = base.addMinutes(i),
                Status__c = 'completed', Direction__c = 'inbound', Source__c = 'Mary'));
            rows.add(new AA_Call_Log__c(Application__c = a2.Id, Started_At__c = base.addMinutes(i),
                Status__c = 'completed', Direction__c = 'inbound', Source__c = 'Mary'));
        }
        Test.startTest();
        insert rows;
        Test.stopTest();
        AA_Application__c af1 = [SELECT Last_Contact_At__c FROM AA_Application__c WHERE Id = :a1.Id];
        AA_Application__c af2 = [SELECT Last_Contact_At__c FROM AA_Application__c WHERE Id = :a2.Id];
        System.assertNotEquals(null, af1.Last_Contact_At__c, 'app1 mirrored');
        System.assertNotEquals(null, af2.Last_Contact_At__c, 'app2 mirrored');
    }
}