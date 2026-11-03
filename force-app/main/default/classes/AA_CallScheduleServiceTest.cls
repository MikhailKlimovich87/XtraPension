/**
 * AA_CallScheduleServiceTest — covers the aaCallSchedule LWC's Apex surface,
 * in particular the UK call-hours gate on createSchedule (review 2026-09-11):
 * a slot the Heroku tick would never dial must be refused at write time with
 * a message the operator can act on, not booked and silently missed.
 *
 * Datetimes are built in Europe/London via AA_BusinessDayHelper so the
 * assertions hold whether the running user sits in GMT, BST or elsewhere —
 * the gate is about UK wall-clock, not the user's timezone.
 */
@isTest
private class AA_CallScheduleServiceTest {

    // 'Awaiting First Call': createSchedule now refuses stages the Heroku tick
    // never dials (audit F84), and 'New' is one of them.
    private static AA_Application__c makeApp() {
        return makeApp('Awaiting First Call', false);
    }

    private static AA_Application__c makeApp(String stage, Boolean dnc) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c     = 'Sched',
            Last_Name__c      = 'Test' + System.now().getTime(),
            Phone__c          = '+447700900123',   // Ofcom-reserved drama range
            Stage__c          = stage,
            Do_Not_Contact__c = dnc,
            CurrencyIsoCode   = 'GBP'
        );
        insert a;
        return a;
    }

    /**
     * First Mon–Fri, non-bank-holiday UK day after `fromDt`, at hourUk:00 UK.
     * AA_BusinessDayHelper skips weekends only, so roll past bank holidays too
     * — otherwise a run on 24 Dec would hand the happy path Christmas Day.
     */
    private static Datetime nextCallableDayAt(Datetime fromDt, Integer hourUk) {
        Datetime d = AA_BusinessDayHelper.nextBusinessDayAtUkTime(fromDt, hourUk);
        Integer guard = 0;
        while (AA_CallScheduleService.UK_BANK_HOLIDAYS.contains(d.format('yyyy-MM-dd', 'Europe/London')) && guard < 10) {
            d = AA_BusinessDayHelper.nextBusinessDayAtUkTime(d, hourUk);
            guard++;
        }
        return d;
    }

    /** `dateUk` at HH:MM UK wall-clock, as the UTC Datetime SF stores. */
    private static Datetime ukAt(Date dateUk, Integer hh, Integer mm) {
        return AA_BusinessDayHelper.buildUkDatetime(dateUk, hh).addMinutes(mm);
    }

    /** Next Saturday or Sunday (UK date) after today. */
    private static Date nextWeekendDay() {
        Date d = AA_UkTime.dateUk(Datetime.now()).addDays(1);
        Integer guard = 0;
        while (!AA_BusinessDayHelper.isWeekend(d) && guard < 8) { d = d.addDays(1); guard++; }
        return d;
    }

    @isTest static void gateAcceptsWeekdayInsideHoursAndRejectsEdges() {
        Date d = AA_UkTime.dateUk(nextCallableDayAt(Datetime.now(), 10));
        System.assert(AA_CallScheduleService.isWithinUkCallHours(ukAt(d, 7, 0)),    '07:00 UK is the first callable minute');
        System.assert(AA_CallScheduleService.isWithinUkCallHours(ukAt(d, 12, 15)),  'midday is callable');
        System.assert(AA_CallScheduleService.isWithinUkCallHours(ukAt(d, 17, 29)),  '17:29 UK is still callable');
        System.assert(!AA_CallScheduleService.isWithinUkCallHours(ukAt(d, 6, 59)),  '06:59 UK is before opening');
        System.assert(!AA_CallScheduleService.isWithinUkCallHours(ukAt(d, 17, 30)), '17:30 UK is already closed (exclusive bound, as in retry.js)');
        System.assert(!AA_CallScheduleService.isWithinUkCallHours(ukAt(d, 20, 0)),  '20:00 UK is an evening slot');
    }

    @isTest static void gateRejectsWeekendsAndBankHolidays() {
        Date weekend = nextWeekendDay();
        System.assert(AA_BusinessDayHelper.isWeekend(weekend), 'test setup: found a weekend day');
        System.assert(!AA_CallScheduleService.isWithinUkCallHours(ukAt(weekend, 10, 0)), 'Saturday/Sunday 10:00 UK is not callable');
        // 2027-12-27 is a Monday (Christmas Day substitute) — a weekday, but a bank holiday.
        System.assert(!AA_CallScheduleService.isWithinUkCallHours(ukAt(Date.newInstance(2027, 12, 27), 10, 0)),
            'a weekday bank holiday is not callable');
        // Audit F96: the list stopped at 2027, so Mon 2028-01-03 (New Year
        // substitute) read as callable.
        System.assert(!AA_CallScheduleService.isWithinUkCallHours(ukAt(Date.newInstance(2028, 1, 3), 10, 0)),
            '2028 bank holidays are covered');
    }

    @isTest static void createScheduleInsideHoursBooksPendingAndMirrors() {
        AA_Application__c a = makeApp();
        Datetime slot = nextCallableDayAt(Datetime.now(), 10);
        Test.startTest();
        Id rowId = AA_CallScheduleService.createSchedule(a.Id, slot);
        Test.stopTest();
        AA_Call_Schedule__c row = [SELECT Status__c, Scheduled_At__c FROM AA_Call_Schedule__c WHERE Id = :rowId];
        System.assertEquals('Pending', row.Status__c);
        System.assertEquals(slot, row.Scheduled_At__c);
        AA_Application__c got = [SELECT Next_Call_At__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(slot, got.Next_Call_At__c, 'trigger mirrors the Pending slot into Next_Call_At__c');
        System.assertEquals(rowId, AA_CallScheduleService.getActivePending(a.Id).Id);
        System.assertEquals(1, AA_CallScheduleService.getScheduleHistory(a.Id, 10).size());
    }

    @isTest static void createScheduleEveningSlotIsRefusedWithReadableError() {
        AA_Application__c a = makeApp();
        Datetime evening = ukAt(AA_UkTime.dateUk(nextCallableDayAt(Datetime.now(), 10)), 18, 30);
        String msg = null;
        Test.startTest();
        try {
            AA_CallScheduleService.createSchedule(a.Id, evening);
        } catch (AuraHandledException e) {
            msg = e.getMessage();
        }
        Test.stopTest();
        System.assertNotEquals(null, msg, 'an 18:30 UK slot must be refused');
        System.assert(msg.contains('07:00-17:30'), 'the error names the call window: ' + msg);
        System.assert(msg.contains('18:30'), 'the error echoes the requested UK time: ' + msg);
        System.assertEquals(0, [SELECT COUNT() FROM AA_Call_Schedule__c WHERE Application__c = :a.Id],
            'nothing is booked for a slot the tick would never dial');
        System.assertEquals(null, [SELECT Next_Call_At__c FROM AA_Application__c WHERE Id = :a.Id].Next_Call_At__c,
            'no mirror either — a phantom Next_Call_At__c is what the reaper turned into a miss');
    }

    @isTest static void createScheduleWeekendSlotIsRefused() {
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            AA_CallScheduleService.createSchedule(a.Id, ukAt(nextWeekendDay(), 10, 0));
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'a weekend slot must be refused');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Call_Schedule__c WHERE Application__c = :a.Id]);
    }

    @isTest static void createScheduleRequiresBothArguments() {
        Boolean threwApp = false;
        Boolean threwWhen = false;
        try { AA_CallScheduleService.createSchedule(null, Datetime.now().addDays(1)); }
        catch (AuraHandledException e) { threwApp = true; }
        try { AA_CallScheduleService.createSchedule(makeApp().Id, null); }
        catch (AuraHandledException e) { threwWhen = true; }
        System.assert(threwApp, 'applicationId is required');
        System.assert(threwWhen, 'scheduledAt is required');
    }

    @isTest static void secondPendingIsRefusedByTrigger() {
        AA_Application__c a = makeApp();
        Datetime slot = nextCallableDayAt(Datetime.now(), 10);
        AA_CallScheduleService.createSchedule(a.Id, slot);
        Boolean threw = false;
        try {
            AA_CallScheduleService.createSchedule(a.Id, slot.addMinutes(30));
        } catch (AuraHandledException e) {
            // DML path re-throws without setMessage, so the text is not
            // assertable here; the guard is AA_CallScheduleTrigger's — the
            // row count below proves it held.
            threw = true;
        }
        System.assert(threw, 'one Pending per application');
        System.assertEquals(1, [SELECT COUNT() FROM AA_Call_Schedule__c WHERE Application__c = :a.Id AND Status__c = 'Pending']);
    }

    @isTest static void cancelScheduleFlipsPendingAndRefusesNonPending() {
        AA_Application__c a = makeApp();
        Id rowId = AA_CallScheduleService.createSchedule(a.Id, nextCallableDayAt(Datetime.now(), 10));
        Test.startTest();
        AA_CallScheduleService.cancelSchedule(rowId, 'Client asked to stop');
        Test.stopTest();
        AA_Call_Schedule__c row = [SELECT Status__c, Cancelled_At__c, Cancel_Reason__c FROM AA_Call_Schedule__c WHERE Id = :rowId];
        System.assertEquals('Cancelled', row.Status__c);
        System.assertNotEquals(null, row.Cancelled_At__c);
        System.assertEquals('Client asked to stop', row.Cancel_Reason__c);
        System.assertEquals(null, AA_CallScheduleService.getActivePending(a.Id), 'no Pending left');
        System.assertEquals(null, [SELECT Next_Call_At__c FROM AA_Application__c WHERE Id = :a.Id].Next_Call_At__c,
            'mirror cleared once the Pending row is gone');
        Boolean threw = false;
        try { AA_CallScheduleService.cancelSchedule(rowId, 'again'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'only Pending rows can be cancelled');
    }

    // Audit F84: a Do Not Contact client must never get a Pending row.
    @isTest static void createScheduleRefusesDoNotContact() {
        AA_Application__c a = makeApp('Partial Data', true);
        String msg = null;
        try {
            AA_CallScheduleService.createSchedule(a.Id, nextCallableDayAt(Datetime.now(), 10));
        } catch (AuraHandledException e) {
            msg = e.getMessage();
        }
        System.assertNotEquals(null, msg, 'a DNC app must be refused');
        System.assert(msg.contains('Do Not Contact'), 'the error says why: ' + msg);
        System.assertEquals(0, [SELECT COUNT() FROM AA_Call_Schedule__c WHERE Application__c = :a.Id]);
    }

    // Audit F84: a stage the tick never dials (here Data Complete) must not
    // be booked; the row would only feed the reminder SMS and lock the app.
    @isTest static void createScheduleRefusesUndialableStage() {
        AA_Application__c a = makeApp('Data Complete', false);
        String msg = null;
        try {
            AA_CallScheduleService.createSchedule(a.Id, nextCallableDayAt(Datetime.now(), 10));
        } catch (AuraHandledException e) {
            msg = e.getMessage();
        }
        System.assertNotEquals(null, msg, 'a Data Complete app must be refused');
        System.assert(msg.contains('Data Complete'), 'the error names the stage: ' + msg);
        System.assertEquals(0, [SELECT COUNT() FROM AA_Call_Schedule__c WHERE Application__c = :a.Id]);
    }

    @isTest static void createScheduleAllowsPartialData() {
        AA_Application__c a = makeApp('Partial Data', false);
        Id rowId = AA_CallScheduleService.createSchedule(a.Id, nextCallableDayAt(Datetime.now(), 11));
        System.assertNotEquals(null, rowId, 'Partial Data is dialable');
    }

    @isTest static void readsTolerateNullApplication() {
        System.assertEquals(null, AA_CallScheduleService.getActivePending(null));
        System.assertEquals(0, AA_CallScheduleService.getScheduleHistory(null, 5).size());
    }
}