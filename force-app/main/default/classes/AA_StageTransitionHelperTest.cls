/**
 * AA_StageTransitionHelperTest — stage audit log + the Pending-schedule
 * cancel that runs when an Application leaves the dialable stages.
 *
 * audit 2026-10-02 F84/F70: before cancelPendingSchedulesOnExit, moving an
 * app to Needs Human / Data Complete / Closed (by an operator, the client
 * form or the post-call handler) left its Pending AA_Call_Schedule__c row in
 * place. The tick never dials those stages, so the client still got the
 * morning "Mary will call you today" SMS, Next_Call_At__c went stale (and then
 * blocked every save under Next_Call_At_In_Future), and the reaper charged a
 * phantom miss. The first two tests fail without the fix.
 *
 * Also covers the 2026-10-02 owner decision that books Mary's first call
 * once a bank-deferred application reaches Awaiting First Call.
 */
@isTest
private class AA_StageTransitionHelperTest {

    private static AA_Application__c makeApp(String stage) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Stage', Last_Name__c = 'Helper' + Math.mod(Math.abs(Crypto.getRandomInteger()), 100000),
            Phone__c = '+441234567890', Stage__c = stage
        );
        insert a;
        return a;
    }

    private static AA_Call_Schedule__c pending(Id appId) {
        AA_Call_Schedule__c s = new AA_Call_Schedule__c(
            Application__c = appId, Scheduled_At__c = Datetime.now().addDays(2), Status__c = 'Pending'
        );
        insert s;
        return s;
    }

    private static AA_Call_Schedule__c reload(Id scheduleId) {
        return [SELECT Status__c, Cancelled_At__c, Cancel_Reason__c FROM AA_Call_Schedule__c WHERE Id = :scheduleId];
    }

    @isTest static void leaving_the_dialable_stages_cancels_the_pending_slot() {
        AA_Application__c a = makeApp('Partial Data');
        AA_Call_Schedule__c s = pending(a.Id);
        System.assertNotEquals(null, [SELECT Next_Call_At__c FROM AA_Application__c WHERE Id = :a.Id].Next_Call_At__c,
            'precondition: the Pending slot is mirrored onto the application');

        Test.startTest();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Needs Human');
        Test.stopTest();

        AA_Call_Schedule__c after = reload(s.Id);
        System.assertEquals('Cancelled', after.Status__c, 'a Needs Human app must not keep a Pending call');
        System.assertNotEquals(null, after.Cancelled_At__c, 'Cancelled_Needs_Timestamp is satisfied');
        System.assert(after.Cancel_Reason__c.contains('Needs Human'), after.Cancel_Reason__c);
        System.assertEquals(null, [SELECT Next_Call_At__c FROM AA_Application__c WHERE Id = :a.Id].Next_Call_At__c,
            'the mirror is cleared, so no stale Next_Call_At__c is left behind');
        System.assertEquals(1, [SELECT COUNT() FROM AA_Stage_Log__c WHERE Application__c = :a.Id],
            'the stage change itself is still logged once');
    }

    @isTest static void do_not_contact_cancels_the_pending_slot() {
        AA_Application__c a = makeApp('Awaiting First Call');
        AA_Call_Schedule__c s = pending(a.Id);

        Test.startTest();
        update new AA_Application__c(Id = a.Id, Do_Not_Contact__c = true);
        Test.stopTest();

        AA_Call_Schedule__c after = reload(s.Id);
        System.assertEquals('Cancelled', after.Status__c, 'a Do Not Contact client must not keep a Pending call');
        System.assertEquals('Marked Do Not Contact', after.Cancel_Reason__c);
    }

    @isTest static void moves_inside_the_dialable_stages_keep_the_slot() {
        AA_Application__c a = makeApp('Awaiting First Call');
        AA_Call_Schedule__c s = pending(a.Id);

        Test.startTest();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Call In Progress');
        update new AA_Application__c(Id = a.Id, Stage__c = 'Partial Data');
        Test.stopTest();

        System.assertEquals('Pending', reload(s.Id).Status__c,
            'a call cycle (Call In Progress -> Partial Data) must keep the follow-up slot');
        System.assertEquals(2, [SELECT COUNT() FROM AA_Stage_Log__c WHERE Application__c = :a.Id]);
    }

    @isTest static void bulk_update_cancels_only_the_apps_that_left() {
        AA_Application__c leaving = makeApp('Partial Data');
        AA_Application__c staying = makeApp('Partial Data');
        AA_Call_Schedule__c s1 = pending(leaving.Id);
        AA_Call_Schedule__c s2 = pending(staying.Id);

        Test.startTest();
        update new List<AA_Application__c>{
            new AA_Application__c(Id = leaving.Id, Stage__c = 'Data Complete'),
            new AA_Application__c(Id = staying.Id, Notes__c = 'just a note')
        };
        Test.stopTest();

        System.assertEquals('Cancelled', reload(s1.Id).Status__c, 'Data Complete is never dialled, so its slot is cancelled');
        System.assertEquals('Pending', reload(s2.Id).Status__c, 'an unrelated save must not touch the slot');
    }

    // ── Auto re-book Mary's first call (owner decision, Fernando 2026-10-02) ──
    // Moving a bank-deferred application to Awaiting First Call books Mary's
    // first call for the next UK business day at 10:00. The first test fails
    // without bookFirstCallAfterBankDetails (no Pending row is created).

    private static List<AA_Call_Schedule__c> pendingRows(Id appId) {
        return [SELECT Id, Scheduled_At__c, Status__c FROM AA_Call_Schedule__c
                 WHERE Application__c = :appId AND Status__c = 'Pending'];
    }

    @isTest static void bank_details_in_books_the_first_call_next_business_day_at_ten() {
        AA_Application__c a = makeApp('Awaiting Bank Details');

        Test.startTest();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Awaiting First Call');
        Test.stopTest();

        List<AA_Call_Schedule__c> rows = pendingRows(a.Id);
        System.assertEquals(1, rows.size(), 'Mary\'s first call is booked');
        Datetime slot = rows[0].Scheduled_At__c;
        System.assertEquals(10, AA_UkTime.hourUk(slot), 'at 10:00 UK');
        System.assertEquals('0', slot.format('m', 'Europe/London'));
        Date day = AA_UkTime.dateUk(slot);
        System.assert(day > AA_UkTime.dateUk(Datetime.now()), 'on a later day, never today: ' + day);
        System.assert(!AA_BusinessDayHelper.isWeekend(day), 'on a weekday: ' + day);
        System.assertEquals(slot, [SELECT Next_Call_At__c FROM AA_Application__c WHERE Id = :a.Id].Next_Call_At__c,
            'mirrored onto the application, so the tick dials it');
    }

    @isTest static void partial_data_also_counts_as_bank_details_in() {
        AA_Application__c a = makeApp('Awaiting Bank Details');
        Test.startTest();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Partial Data');
        Test.stopTest();
        System.assertEquals(1, pendingRows(a.Id).size());
    }

    @isTest static void no_booking_for_do_not_contact_or_other_moves() {
        AA_Application__c dnc = makeApp('Awaiting Bank Details');
        update new AA_Application__c(Id = dnc.Id, Do_Not_Contact__c = true);
        AA_Application__c done = makeApp('Awaiting Bank Details');
        AA_Application__c fresh = makeApp('New');

        Test.startTest();
        update new List<AA_Application__c>{
            new AA_Application__c(Id = dnc.Id, Stage__c = 'Awaiting First Call'),
            new AA_Application__c(Id = done.Id, Stage__c = 'Data Complete'),
            new AA_Application__c(Id = fresh.Id, Stage__c = 'Awaiting First Call')
        };
        Test.stopTest();

        System.assertEquals(0, pendingRows(dnc.Id).size(), 'Do Not Contact is respected');
        System.assertEquals(0, pendingRows(done.Id).size(), 'answers already in: no call needed');
        System.assertEquals(0, pendingRows(fresh.Id).size(), 'only a move OUT of Awaiting Bank Details books');
    }

    @isTest static void an_existing_future_slot_is_kept() {
        AA_Application__c a = makeApp('Awaiting Bank Details');
        AA_Call_Schedule__c s = pending(a.Id); // two days ahead

        Test.startTest();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Awaiting First Call');
        Test.stopTest();

        List<AA_Call_Schedule__c> rows = pendingRows(a.Id);
        System.assertEquals(1, rows.size());
        System.assertEquals(s.Id, rows[0].Id, 'the slot already booked stands');
    }

    // A slot whose time passed while the bank details were missing is stale:
    // it is cancelled and replaced, not dialled unannounced. Busy-waits ~2 s.
    @isTest static void a_lapsed_slot_is_replaced() {
        AA_Application__c a = makeApp('Awaiting Bank Details');
        Datetime soon = Datetime.now().addSeconds(2);
        AA_Call_Schedule__c old = new AA_Call_Schedule__c(Application__c = a.Id, Scheduled_At__c = soon, Status__c = 'Pending');
        insert old;
        while (Datetime.now() <= soon) { }

        Test.startTest();
        update new AA_Application__c(Id = a.Id, Stage__c = 'Awaiting First Call');
        Test.stopTest();

        AA_Call_Schedule__c after = reload(old.Id);
        System.assertEquals('Cancelled', after.Status__c);
        System.assert(after.Cancel_Reason__c.startsWith('Superseded'), after.Cancel_Reason__c);
        List<AA_Call_Schedule__c> rows = pendingRows(a.Id);
        System.assertEquals(1, rows.size(), 'a fresh slot replaces it');
        System.assert(rows[0].Scheduled_At__c > Datetime.now());
    }

    @isTest static void bulk_move_books_every_application() {
        List<AA_Application__c> apps = new List<AA_Application__c>();
        for (Integer i = 0; i < 12; i++) {
            apps.add(new AA_Application__c(First_Name__c = 'Bulk', Last_Name__c = 'Bank' + i,
                Phone__c = '+4412345678' + (10 + i), Stage__c = 'Awaiting Bank Details'));
        }
        insert apps;
        for (AA_Application__c a : apps) a.Stage__c = 'Awaiting First Call';

        Test.startTest();
        update apps;
        Test.stopTest();

        System.assertEquals(12, [SELECT COUNT() FROM AA_Call_Schedule__c WHERE Application__c IN :apps AND Status__c = 'Pending'],
            'one Queueable books all of them');
    }

    @isTest static void next_business_day_slot_skips_the_weekend() {
        // Friday 2 Oct 2026, 15:00 UK -> Monday 5 Oct 2026, 10:00 UK.
        Datetime fri = AA_BusinessDayHelper.buildUkDatetime(Date.newInstance(2026, 10, 2), 15);
        Datetime slot = AA_StageTransitionHelper.nextBusinessDaySlot(fri, 0);
        System.assertEquals(Date.newInstance(2026, 10, 5), AA_UkTime.dateUk(slot));
        System.assertEquals(10, AA_UkTime.hourUk(slot));
        // extraDays rolls one more day (used to step past a bank holiday):
        // Thursday 1 Oct -> Friday 2 Oct, one extra -> Saturday -> Monday 5 Oct.
        Datetime thu = AA_BusinessDayHelper.buildUkDatetime(Date.newInstance(2026, 10, 1), 15);
        System.assertEquals(Date.newInstance(2026, 10, 2), AA_UkTime.dateUk(AA_StageTransitionHelper.nextBusinessDaySlot(thu, 0)));
        System.assertEquals(Date.newInstance(2026, 10, 5), AA_UkTime.dateUk(AA_StageTransitionHelper.nextBusinessDaySlot(thu, 1)));
    }

    @isTest static void dialable_stage_set_matches_the_tick() {
        System.assertEquals(new Set<String>{ 'Awaiting First Call', 'Partial Data', 'Call In Progress' },
            AA_StageTransitionHelper.DIALABLE_STAGES,
            'keep in step with the scheduler tick filter in src/webhooks/scheduler.js');
    }
}