/**
 * AA_GoCardlessControllerTest — covers the four Aura-enabled methods on
 * AA_GoCardlessController + the auto-create trigger + eligibility helper.
 *
 * Callouts are stubbed with a routing HttpCalloutMock so we can drive both
 * endpoints (create-mandate + charge-fee) from a single mock and toggle the
 * success/failure body on demand.
 *
 * Guard-rail tests deliberately DO NOT set a mock — they should throw
 * before any HTTP is issued.
 */
@isTest
private class AA_GoCardlessControllerTest {

    // -----------------------------------------------------------------
    // Mock
    // -----------------------------------------------------------------
    /** Routes on the endpoint suffix so a single mock covers both endpoints. */
    private class GcMock implements HttpCalloutMock {
        public Integer status = 200;
        public String  mandateBody;
        public String  chargeBody;
        public String  lastMandateRequest;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            String url = req.getEndpoint();
            if (url.endsWith('/internal/gocardless/create-mandate')) {
                lastMandateRequest = req.getBody();
                r.setBody(mandateBody);
            } else if (url.endsWith('/internal/gocardless/charge-fee')) {
                r.setBody(chargeBody);
            } else {
                r.setStatusCode(404);
                r.setBody('{"ok":false,"error":"unknown endpoint"}');
            }
            return r;
        }
    }

    private static GcMock successMock() {
        GcMock m = new GcMock();
        // mandate_pdf.ok gates DD_Mandate_Id__c stamping (controller rule 2026-08-18):
        // without it pdfOk=false and the id never lands, so the mock must include it.
        m.mandateBody = '{"ok":true,"mandate_id":"MD0001","customer_id":"CU0001","status":"pending_submission","mandate_pdf":{"ok":true}}';
        // No charge_date: Heroku echoes the requested one, and a fixed (past)
        // date here would now trip the scheduler's "collected EARLIER than the
        // notice" guard (wave-2 W3).
        m.chargeBody  = '{"ok":true,"payment_id":"PM0001","status":"pending_submission"}';
        return m;
    }
    private static GcMock failMock() {
        GcMock m = new GcMock();
        m.mandateBody = '{"ok":false,"error":"gocardless_rejected"}';
        m.chargeBody  = '{"ok":false,"error":"insufficient_permissions"}';
        return m;
    }

    // -----------------------------------------------------------------
    // Fixtures
    // -----------------------------------------------------------------
    private static void upsertConfig() {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        AA_Config__c cfg;
        if (rows.isEmpty()) {
            cfg = new AA_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        } else {
            cfg = new AA_Config__c(Id = rows[0].Id);
        }
        cfg.Internal_Admin_Token__c = 'TEST-TOKEN';
        cfg.Auto_Create_DD_Mandate__c = true;
        upsert cfg;
    }

    private static void disableAutoCreate() {
        List<AA_Config__c> rows = [SELECT Id FROM AA_Config__c LIMIT 1];
        update new AA_Config__c(Id = rows[0].Id, Auto_Create_DD_Mandate__c = false);
    }

    /** Base intake row — ready to have bank + terms toggled by each test. */
    private static AA_Application__c makeApp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'GC',
            Last_Name__c  = 'Test' + System.now().getTime(),
            Email__c      = 'gc.test@example.com',
            Phone__c      = '+441234567890',
            Address_Line1__c = '1 High Street',
            City__c       = 'London',
            Postcode__c   = 'SW1A 1AA',
            Bank_Sort_Code__c      = '20-00-00',
            Bank_Account_Number__c = '55779911',
            Bank_Account_Holder__c = 'MR GC TEST',
            Bank_Verification_Status__c = 'Unverified',
            DD_Terms_Read_By_Sales__c   = false,
            Stage__c      = 'New'
        );
        insert a;
        return a;
    }

    // -----------------------------------------------------------------
    // createMandateForApplication — happy path + idempotent
    // -----------------------------------------------------------------
    @isTest static void createMandate_happyPath() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        Test.setMock(HttpCalloutMock.class, successMock());
        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('MD0001', res.get('mandate_id'));
        System.assertEquals('pending_submission', res.get('status'));

        AA_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c
                                    FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0001', after.DD_Mandate_Id__c);
        System.assertEquals('pending_submission', after.DD_Mandate_Status__c);
        System.assertNotEquals(null, after.DD_Mandate_Created_At__c);
    }

    @isTest static void createMandate_idempotent_shortCircuits() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-EXISTING';
        a.DD_Mandate_Status__c        = 'active';
        update a;

        // No mock set — if we tried to call out this would raise
        // "HttpCalloutMock must be set" and the test would fail.
        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('MD-EXISTING', res.get('mandate_id'));
        System.assertEquals(true, res.get('existed'));
    }

    // A dead mandate (failed/cancelled/expired) must NOT short-circuit — the
    // rep corrects the digits and re-creates; a fresh mandate is minted (#19).
    @isTest static void createMandate_deadMandate_recreates() {
        upsertConfig();
        disableAutoCreate();   // isolate: only our explicit call should hit GC
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-DEAD';
        a.DD_Mandate_Status__c        = 'failed';   // dead → must recreate
        update a;

        GcMock mock = successMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('MD0001', res.get('mandate_id'));
        System.assertNotEquals(true, res.get('existed'),
            'a dead mandate must recreate, not return existed:true');
        AA_Application__c after = [SELECT DD_Mandate_Id__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0001', after.DD_Mandate_Id__c,
            'fresh mandate id must be stamped over the dead one');
        // wave-2 W2: with unchanged bank details only the replaced id makes the
        // GoCardless idempotency keys differ from the dead mandate's.
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastMandateRequest);
        System.assertEquals('MD-DEAD', sent.get('replaces_mandate_id'));
    }

    // A first create sends no replaces_mandate_id.
    @isTest static void createMandate_firstCreate_sendsNoReplacedId() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        update a;
        GcMock mock = successMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        AA_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastMandateRequest);
        System.assert(!sent.containsKey('replaces_mandate_id'));
    }

    // wave-2 W2: if GoCardless still hands back a dead mandate, it must be a
    // failure: no dead status written back as "set up", no success toast.
    @isTest static void createMandate_recreateReturnsDeadMandate_fails() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-DEAD';
        a.DD_Mandate_Status__c        = 'cancelled';
        update a;

        GcMock mock = successMock();
        mock.mandateBody = '{"ok":true,"mandate_id":"MD-DEAD","customer_id":"CU0001","status":"cancelled","mandate_pdf":{"ok":true}}';
        Test.setMock(HttpCalloutMock.class, mock);
        Boolean threw = false;
        Test.startTest();
        try { AA_GoCardlessController.createMandateForApplication(a.Id); } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'a dead mandate returned by GoCardless is not a new Direct Debit');
        AA_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Failure_Reason__c
                                     FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('cancelled', after.DD_Mandate_Status__c);
        System.assertNotEquals(null, after.DD_Mandate_Failure_Reason__c);
    }

    // Wave-3 W3-2: the payer cancelled while the mandate PDF was pending, so the
    // record has a dead status and NO mandate id. A plain create (the old
    // "Create Direct Debit" button, or the auto-create Queueable) must not reach
    // GoCardless: Heroku used to mint a new mandate with no fresh agreement.
    @isTest static void createMandate_deadStatusWithoutId_plainCreateRefusedWithoutCallout() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Status__c        = 'cancelled';   // DD_Mandate_Id__c stays blank
        update a;
        // No mock: an attempted callout comes back as "Endpoint unreachable",
        // which the controller records as a failure reason. The gate throws
        // BEFORE the callout and records nothing.
        Boolean threw = false;
        Test.startTest();
        try { AA_GoCardlessController.createMandateForApplication(a.Id); } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw, 'a dead status without a mandate id needs the confirmed re-create');
        AA_Application__c after = [SELECT DD_Mandate_Failure_Reason__c, DD_Mandate_Id__c, DD_Mandate_Status__c
                                     FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.DD_Mandate_Failure_Reason__c, 'no callout may be attempted');
        System.assertEquals(null, after.DD_Mandate_Id__c);
        System.assertEquals('cancelled', after.DD_Mandate_Status__c);
    }

    // ...and the confirmed "Create a new Direct Debit" goes through, telling
    // Heroku the client agreed again (there is no replaced id to send).
    @isTest static void recreateMandate_deadStatusWithoutId_sendsClientReconfirmed() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Status__c        = 'cancelled';
        update a;
        GcMock mock = successMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Map<String, Object> res = AA_GoCardlessController.recreateMandateForApplication(a.Id);
        Test.stopTest();
        System.assertEquals(true, res.get('ok'));
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastMandateRequest);
        System.assertEquals(true, sent.get('client_reconfirmed'));
        System.assert(!sent.containsKey('replaces_mandate_id'));
        AA_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0001', after.DD_Mandate_Id__c);
        System.assertEquals('pending_submission', after.DD_Mandate_Status__c);
    }

    // A first create (no status at all) never claims the client re-agreed.
    @isTest static void createMandate_plainCreate_doesNotSendClientReconfirmed() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        update a;
        GcMock mock = successMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        AA_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastMandateRequest);
        System.assert(!sent.containsKey('client_reconfirmed'));
    }

    // Heroku's refusal (GoCardless holds only a dead mandate, no agreement sent)
    // reaches the rep as the plain-English message, not "gocardless_call_failed".
    @isTest static void createMandate_herokuDeadRefusal_showsAgreementMessage() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Status__c        = 'pending_submission';   // SF missed the cancel webhook
        update a;
        GcMock mock = successMock();
        mock.status = 502;
        mock.mandateBody = '{"ok":false,"error":"gocardless_call_failed","code":"mandate_dead_needs_client_agreement"}';
        Test.setMock(HttpCalloutMock.class, mock);
        Boolean threw = false;
        Test.startTest();
        try { AA_GoCardlessController.createMandateForApplication(a.Id); } catch (AuraHandledException e) { threw = true; }
        Test.stopTest();
        System.assert(threw);
        String reason = [SELECT DD_Mandate_Failure_Reason__c FROM AA_Application__c WHERE Id = :a.Id].DD_Mandate_Failure_Reason__c;
        System.assert(reason != null && reason.contains('fresh agreement'), 'got: ' + reason);
    }

    @isTest static void createMandate_bankNotVerified_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        Boolean threw = false;
        try {
            AA_GoCardlessController.createMandateForApplication(a.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'must throw when Bank_Verification_Status__c != Modulus Passed');
    }

    @isTest static void createMandate_termsNotRead_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        update a;

        Boolean threw = false;
        try {
            AA_GoCardlessController.createMandateForApplication(a.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'must throw when DD_Terms_Read_By_Sales__c != true');
    }

    @isTest static void createMandate_endpointFailure_persistsReason() {
        // Bypass the auto-create trigger for this test: we want to drive
        // ONLY the direct controller call. Otherwise the `update a` below
        // fires the trigger + Queueable, and Test.stopTest() re-runs the
        // controller synchronously — which would blow up on "uncommitted
        // work pending" (DML from recordFailure now precedes the retried
        // callout) and overwrite the failure_reason we're asserting on.
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        Test.setMock(HttpCalloutMock.class, failMock());
        Test.startTest();
        Boolean threw = false;
        try {
            AA_GoCardlessController.createMandateForApplication(a.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'endpoint failure must bubble as AuraHandledException');
        AA_Application__c after = [SELECT DD_Mandate_Failure_Reason__c, DD_Mandate_Id__c
                                    FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.DD_Mandate_Id__c);
        System.assert(after.DD_Mandate_Failure_Reason__c != null &&
            after.DD_Mandate_Failure_Reason__c.contains('gocardless_rejected'),
            'failure reason must be persisted, got: ' + after.DD_Mandate_Failure_Reason__c);
    }

    // -----------------------------------------------------------------
    // recordAward — validation + happy path
    // -----------------------------------------------------------------
    @isTest static void recordAward_happyPath_setsAmountAndStage() {
        upsertConfig();
        AA_Application__c a = makeApp();

        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.recordAward(a.Id, 800, null, null, null, true);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(800, ((Decimal) res.get('award_amount')));
        System.assertEquals(160, ((Decimal) res.get('fee_amount')));  // 20% of 800 (was 25% before 2026-08-18)
        System.assertEquals(1, ((Decimal) res.get('installments')).intValue());   // legacy signature = single charge (recordAward returns the SObject Decimal)
        System.assertEquals(160, ((Decimal) res.get('installment_amount')));
        System.assertEquals('Awarded', String.valueOf(res.get('stage')));
    }

    @isTest static void recordAward_planThreeInstallments_writesPlanField() {
        upsertConfig();
        AA_Application__c a = makeApp();

        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.recordAward(a.Id, 800, 3, 100, null, true);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(160, ((Decimal) res.get('fee_amount')));  // 20% of 800
        System.assertEquals(3, ((Decimal) res.get('installments')).intValue());
        // 160 / 3 = 53.33 (final row absorbs the £0.01 remainder)
        System.assertEquals(53.33, ((Decimal) res.get('installment_amount')));
    }

    @isTest static void recordAward_planOutOfRange_clampsToMax() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Map<String,Object> res = AA_GoCardlessController.recordAward(a.Id, 400, 99, null, null, true);
        System.assertEquals(3, ((Decimal) res.get('installments')).intValue(),
            'plan > 3 must clamp to PLAN_MAX (AA cap is three instalments — Fernando 2026-09-09)');
    }

    @isTest static void recordAward_zeroAmount_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            AA_GoCardlessController.recordAward(a.Id, 0, null, null, null, true);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'zero must throw');
    }

    @isTest static void recordAward_unrealisticallyLarge_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            AA_GoCardlessController.recordAward(a.Id, 999999, null, null, null, true);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, '>=100000 must throw as sanity guard');
    }

    // recordAward — DWP_Lump_Sum_Received__c persistence (2026-08-18)
    // The server does NOT compute the plan from the lump — the LWC does that.
    // Server just persists both fields and trusts the plan chosen by the val
    // team via the LWC (either auto-recommended or manually overridden).
    @isTest static void recordAward_persistsLumpSumReceived() {
        upsertConfig();
        AA_Application__c a = makeApp();

        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.recordAward(a.Id, 4000, 3, 300, null, true);
        Test.stopTest();

        System.assertEquals(300, ((Decimal) res.get('lump_sum_received')));
        System.assertEquals(3, ((Decimal) res.get('installments')).intValue(),
            'server trusts LWC plan choice — does NOT re-derive from lump vs fee');
        AA_Application__c after = [SELECT DWP_Lump_Sum_Received__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(300, after.DWP_Lump_Sum_Received__c);
    }

    @isTest static void recordAward_lumpSumNegative_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            AA_GoCardlessController.recordAward(a.Id, 800, 1, -50, null, true);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'negative lump sum must throw');
    }

    @isTest static void recordAward_nullLumpSumPreservesExisting() {
        upsertConfig();
        AA_Application__c a = makeApp();
        // Prime an existing lump sum
        a.DWP_Lump_Sum_Received__c = 250;
        update a;
        // Second save without lumpSum (null) must NOT wipe it
        AA_GoCardlessController.recordAward(a.Id, 900, 3, null, null, true);
        AA_Application__c after = [SELECT DWP_Lump_Sum_Received__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(250, after.DWP_Lump_Sum_Received__c,
            'null lumpSum on re-save must preserve prior value');
    }

    // -----------------------------------------------------------------
    // chargeFee — happy path + gates + idempotent
    // -----------------------------------------------------------------
    // audit 2026-10-02 F101/F79: Charge Fee no longer collects on the spot.
    // It schedules the plan no sooner than NOTICE_DAYS out, sends no callout
    // itself, and never builds a plan twice.
    @isTest static void chargeFee_schedulesNoSoonerThanNoticeDays_noCallout() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-ACTIVE';
        a.DD_Mandate_Status__c        = 'active';
        a.Award_Amount__c             = 800;
        a.Fee_First_Charge_Date__c    = Date.today();   // stored date now too close
        a.Stage__c                    = 'Awarded';
        update a;

        // No mock: the old fire-now path would call out here and fail.
        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();

        Date earliest = Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS);
        System.assertEquals(true, res.get('ok'));
        System.assertEquals(true, res.get('deferred'));
        System.assertEquals(earliest, (Date) res.get('first_charge_date'),
            'a first-charge date sooner than the 5-day notice must be moved to today+5');
        List<AA_Fee_Installment__c> rows = [
            SELECT Amount__c, Scheduled_Date__c, Payment_Id__c, Payment_Status__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id ORDER BY Installment_Number__c
        ];
        System.assertEquals(1, rows.size(), 'single-charge plan → 1 installment row');
        System.assertEquals(160, rows[0].Amount__c);
        System.assertEquals(earliest, rows[0].Scheduled_Date__c);
        System.assertEquals(null, rows[0].Payment_Id__c, 'nothing collected at click time');
        System.assertEquals('pending', rows[0].Payment_Status__c);
        AA_Application__c after = [SELECT Fee_First_Charge_Date__c, Fee_Payment_Id__c, Stage__c
                                    FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(earliest, after.Fee_First_Charge_Date__c, 'moved date written back');
        System.assertEquals(null, after.Fee_Payment_Id__c);
        System.assertEquals('Awarded', after.Stage__c);
    }

    @isTest static void chargeFee_threeInstallments_insertsRows() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-ACTIVE';
        a.DD_Mandate_Status__c        = 'active';
        a.Award_Amount__c             = 800;
        a.Fee_Plan_Installments__c    = 3;
        a.Fee_First_Charge_Date__c    = Date.today().addDays(20);
        a.Stage__c                    = 'Awarded';
        update a;

        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(3, ((Integer) res.get('installments')));
        System.assertEquals(53.33, ((Decimal) res.get('installment_amount')));
        System.assertEquals(false, res.get('notice_sent'), 'a date 20 days out is noticed by the daily sweep, not now');

        List<AA_Fee_Installment__c> rows = [
            SELECT Installment_Number__c, Amount__c, Scheduled_Date__c,
                   Payment_Id__c, Payment_Status__c
            FROM AA_Fee_Installment__c WHERE Application__c = :a.Id
            ORDER BY Installment_Number__c
        ];
        System.assertEquals(3, rows.size(), '3-installment plan → 3 rows');
        System.assertEquals(53.33, rows[0].Amount__c);
        System.assertEquals(53.33, rows[1].Amount__c);
        // Final row absorbs the £0.01 rounding remainder: 160 - 53.33*2 = 53.34
        System.assertEquals(53.34, rows[2].Amount__c);
        System.assertEquals(160, rows[0].Amount__c + rows[1].Amount__c + rows[2].Amount__c);
        System.assertEquals(Date.today().addDays(20), rows[0].Scheduled_Date__c);
        System.assertEquals(Date.today().addDays(20).addMonths(1), rows[1].Scheduled_Date__c);
        for (AA_Fee_Installment__c r : rows) {
            System.assertEquals(null, r.Payment_Id__c);
            System.assertEquals('pending', r.Payment_Status__c);
        }
    }

    // When instalment #1 is exactly NOTICE_DAYS out, the notice goes out on
    // the click and the GoCardless payment is created at once with
    // charge_date = that date (the row stays 'pending' until submitted).
    @isTest static void chargeFee_dueToday_sendsNoticeAndCreatesPaymentAhead() {
        upsertConfig();
        insert new AA_Message_Template__c(
            Channel__c = 'Email', Trigger_Event__c = 'Bacs_Advance_Notice', Active__c = true,
            Subject_Template__c = 'Bacs advance notice (test)', Body_Template__c = 'test body');
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Awarded';
        update a;

        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Test.setMock(HttpCalloutMock.class, successMock());
        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();   // runs the enqueued charge Queueable

        System.assertEquals(true, res.get('notice_sent'));
        System.assertEquals(1, AA_FeeInstallmentScheduler.testDispatched.size());
        AA_Fee_Installment__c row = [
            SELECT Payment_Id__c, Payment_Status__c, Charged_At__c, Bacs_Notice_Sent__c, Scheduled_Date__c
              FROM AA_Fee_Installment__c WHERE Application__c = :a.Id
        ];
        System.assertEquals(true, row.Bacs_Notice_Sent__c);
        System.assertEquals('PM0001', row.Payment_Id__c);
        System.assertNotEquals(null, row.Charged_At__c);
        System.assertEquals('pending', row.Payment_Status__c, 'created at GoCardless, not yet submitted');
        System.assertEquals(Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS), row.Scheduled_Date__c);
    }

    @isTest static void chargeFee_existingPlan_isNotRebuilt() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Awarded';
        update a;
        AA_Fee_Installment__c row = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 160,
            Scheduled_Date__c = Date.today().addDays(5), Payment_Status__c = 'pending',
            Bacs_Notice_Sent__c = true);
        insert row;

        Map<String,Object> res = AA_GoCardlessController.chargeFee(a.Id);
        System.assertEquals(true, res.get('existed'));
        List<AA_Fee_Installment__c> rows = [SELECT Id, Bacs_Notice_Sent__c FROM AA_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals(1, rows.size());
        System.assertEquals(row.Id, rows[0].Id, 'the existing row must not be deleted and re-inserted');
        System.assertEquals(true, rows[0].Bacs_Notice_Sent__c, 'notice stamp kept, no second notice');
    }

    @isTest static void chargeFee_doNotContact_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Do_Not_Contact__c    = true;
        update a;
        Boolean threw = false;
        try { AA_GoCardlessController.chargeFee(a.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'no collection can be scheduled for a Do Not Contact client');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]);
    }

    @isTest static void chargeFee_mandateNotActive_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-PENDING';
        a.DD_Mandate_Status__c = 'pending_submission';
        a.Award_Amount__c      = 800;
        update a;

        Boolean threw = false;
        try {
            AA_GoCardlessController.chargeFee(a.Id);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'must throw when DD_Mandate_Status__c != active');
    }

    // wave-2 W1: status 'active' with no mandate id (document pending) used to
    // pass this gate; the notice went out and Heroku refused the charge.
    @isTest static void chargeFee_activeStatusButNoMandateId_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Awarded';
        update a;
        Boolean threw = false;
        try { AA_GoCardlessController.chargeFee(a.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'no fee can be scheduled before the mandate id is on the record');
        System.assertEquals(0, [SELECT COUNT() FROM AA_Fee_Installment__c WHERE Application__c = :a.Id]);
    }

    @isTest static void chargeFee_awardNotRecorded_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        update a;

        Boolean threw = false;
        try {
            AA_GoCardlessController.chargeFee(a.Id);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'must throw when Award_Amount__c null');
    }

    @isTest static void chargeFee_idempotent_returnsExisting() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Fee_Payment_Id__c    = 'PM-EXISTING';
        a.Fee_Payment_Status__c = 'paid_out';
        a.Fee_Charged_At__c    = Datetime.now();
        update a;

        // No mock — must NOT call out.
        Test.startTest();
        Map<String,Object> res = AA_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('PM-EXISTING', res.get('payment_id'));
        System.assertEquals(true, res.get('existed'));
    }

    // -----------------------------------------------------------------
    // recordAward — annual-award band (audit 2026-10-02 F111) and the
    // 5-day notice floor on the first charge date (F101)
    // -----------------------------------------------------------------
    @isTest static void recordAward_weeklyFigure_needsConfirmation() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            // The weekly higher rate typed by mistake: a £22.08 fee.
            AA_GoCardlessController.recordAward(a.Id, 110.40, 1, null, null, false);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'an amount outside the annual band must not save without confirmation');
        System.assertEquals(null, [SELECT Award_Amount__c FROM AA_Application__c WHERE Id = :a.Id].Award_Amount__c);

        Map<String,Object> res = AA_GoCardlessController.recordAward(a.Id, 110.40, 1, null, null, true);
        System.assertEquals(true, res.get('ok'), 'an explicit confirmation still allows an unusual amount');
    }

    @isTest static void recordAward_annualHigherRate_savesWithoutConfirmation() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Map<String,Object> res = AA_GoCardlessController.recordAward(a.Id, 5740.80, 3, null, null, null);
        System.assertEquals(true, res.get('ok'));
        System.assertEquals(1148.16, ((Decimal) res.get('fee_amount')));
    }

    @isTest static void recordAward_firstChargeDateInsideNoticeWindow_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        Boolean threw = false;
        try {
            AA_GoCardlessController.recordAward(a.Id, 5740.80, 1, null,
                Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS - 1), null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a first charge date inside the 5-day notice window must be refused');
        Map<String,Object> ok = AA_GoCardlessController.recordAward(a.Id, 5740.80, 1, null,
            Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS), null);
        System.assertEquals(Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS), (Date) ok.get('first_charge_date'));
    }

    // -----------------------------------------------------------------
    // retryInstallment + getFeeInstallments (audit 2026-10-02 F110)
    // -----------------------------------------------------------------
    @isTest static void retryInstallment_failedRow_reschedulesWithFreshNotice() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Fee Charged';
        update a;
        AA_Fee_Installment__c row = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 160,
            Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed',
            Payment_Id__c = 'PM-FAILED', Charged_At__c = Datetime.now().addDays(-8),
            Bacs_Notice_Sent__c = true);
        insert row;

        List<Map<String,Object>> before = AA_GoCardlessController.getFeeInstallments(a.Id);
        System.assertEquals(true, before[0].get('can_retry'));

        Map<String,Object> res = AA_GoCardlessController.retryInstallment(row.Id);
        System.assertEquals(true, res.get('ok'));
        AA_Fee_Installment__c after = [
            SELECT Payment_Status__c, Payment_Id__c, Charged_At__c, Scheduled_Date__c, Bacs_Notice_Sent__c
              FROM AA_Fee_Installment__c WHERE Id = :row.Id
        ];
        System.assertEquals('pending', after.Payment_Status__c);
        System.assertEquals('PM-FAILED', after.Payment_Id__c, 'old payment id kept: the sweep re-collects it');
        System.assertEquals(null, after.Charged_At__c);
        System.assertEquals(Date.today().addDays(AA_FeeInstallmentScheduler.NOTICE_DAYS), after.Scheduled_Date__c);
    }

    @isTest static void retryInstallment_refusedOnChargebackAndPaidRows() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'DD Chargeback';
        update a;
        AA_Fee_Installment__c failed = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 80,
            Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed', Payment_Id__c = 'PM-F1');
        AA_Fee_Installment__c paid = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 2, Amount__c = 80,
            Scheduled_Date__c = Date.today().addDays(-1), Payment_Status__c = 'paid', Payment_Id__c = 'PM-P2');
        insert new List<AA_Fee_Installment__c>{ failed, paid };
        Boolean threw1 = false, threw2 = false;
        try { AA_GoCardlessController.retryInstallment(failed.Id); } catch (AuraHandledException e) { threw1 = true; }
        try { AA_GoCardlessController.retryInstallment(paid.Id); } catch (AuraHandledException e) { threw2 = true; }
        System.assert(threw1, 'a disputed plan is never re-collected');
        System.assert(threw2, 'a paid instalment cannot be retried');
    }

    // wave-2 W1: moving the Stage off 'DD Chargeback' by hand used to let the
    // retry email the client a fresh notice before Heroku refused the
    // charged-back payment. The Stage history now blocks it up front.
    @isTest static void retryInstallment_afterChargebackStageMovedOff_refusedWithoutNotice() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'DD Chargeback';
        update a;
        a.Stage__c = 'Fee Charged';
        update a;
        AA_Fee_Installment__c failed = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 160,
            Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed', Payment_Id__c = 'PM-CB');
        insert failed;
        AA_FeeInstallmentScheduler.testBypass = true;
        AA_FeeInstallmentScheduler.testDispatched.clear();
        Boolean threw = false;
        try { AA_GoCardlessController.retryInstallment(failed.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a plan that was ever charged back is not re-collected through the Direct Debit');
        System.assertEquals(0, AA_FeeInstallmentScheduler.testDispatched.size(), 'no notice sent');
        System.assertEquals('failed', [SELECT Payment_Status__c FROM AA_Fee_Installment__c WHERE Id = :failed.Id].Payment_Status__c);
    }

    @isTest static void retryInstallment_noMandateId_throws() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Fee Charged';
        update a;
        AA_Fee_Installment__c failed = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 160,
            Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed', Payment_Id__c = 'PM-F');
        insert failed;
        Boolean threw = false;
        try { AA_GoCardlessController.retryInstallment(failed.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw);
    }

    // -----------------------------------------------------------------
    // getDDStatus — projection
    // -----------------------------------------------------------------
    // Owner decision 2026-10-02: Do Not Contact pauses the fee. The rows stay
    // 'pending', so the card is told which ones are paused.
    @isTest static void getFeeInstallments_doNotContact_flagsPendingRowsPaused() {
        upsertConfig();
        AA_Application__c a = makeApp();
        insert new List<AA_Fee_Installment__c>{
            new AA_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1, Amount__c = 50,
                Scheduled_Date__c = Date.today().addDays(-20), Payment_Status__c = 'paid'),
            new AA_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 2, Amount__c = 50,
                Scheduled_Date__c = Date.today().addDays(10), Payment_Status__c = 'pending')
        };
        List<Map<String, Object>> live = AA_GoCardlessController.getFeeInstallments(a.Id);
        System.assertEquals(false, live[1].get('paused_dnc'), 'not paused while the client can be contacted');
        a.Do_Not_Contact__c = true;
        update a;
        List<Map<String, Object>> rows = AA_GoCardlessController.getFeeInstallments(a.Id);
        System.assertEquals(false, rows[0].get('paused_dnc'), 'a collected row is not paused');
        System.assertEquals(true, rows[1].get('paused_dnc'));
    }

    // Wave 4: the daily sweep stores the pause as Payment_Status__c='paused'.
    // While the flag is set the row is paused; once it is cleared (before the
    // next daily run restores 'pending') it is shown as resuming, not paused.
    @isTest static void getFeeInstallments_pausedStatus_pausedThenResuming() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Do_Not_Contact__c = true;
        update a;
        insert new AA_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1, Amount__c = 50,
            Scheduled_Date__c = Date.today().addDays(10), Payment_Status__c = 'paused');
        Map<String, Object> r = AA_GoCardlessController.getFeeInstallments(a.Id)[0];
        System.assertEquals('paused', r.get('status'));
        System.assertEquals(true, r.get('paused_dnc'));
        System.assertEquals(false, r.get('resuming'));
        System.assertEquals(false, r.get('can_retry'), 'a paused row resumes on its own, it is not retried');
        a.Do_Not_Contact__c = false;
        update a;
        r = AA_GoCardlessController.getFeeInstallments(a.Id)[0];
        System.assertEquals(false, r.get('paused_dnc'));
        System.assertEquals(true, r.get('resuming'));
    }

    // Integrator 2026-10-02: a pending row already created at GoCardless WILL
    // be collected unless ops cancels it, so the card must not call it paused.
    @isTest static void getFeeInstallments_doNotContact_rowAtGoCardless_isNotPaused() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Do_Not_Contact__c = true;
        update a;
        insert new List<AA_Fee_Installment__c>{
            new AA_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1, Amount__c = 50,
                Scheduled_Date__c = Date.today().addDays(3), Payment_Status__c = 'pending',
                Payment_Id__c = 'PM-AT-GC', Charged_At__c = Datetime.now().addDays(-2)),
            new AA_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 2, Amount__c = 50,
                Scheduled_Date__c = Date.today().addDays(33), Payment_Status__c = 'paused')
        };
        List<Map<String, Object>> rows = AA_GoCardlessController.getFeeInstallments(a.Id);
        System.assertEquals(false, rows[0].get('paused_dnc'), 'a payment already at GoCardless is not paused');
        System.assertEquals(true, rows[0].get('dnc_at_gc'));
        System.assertEquals(true, rows[1].get('paused_dnc'));
        System.assertEquals(false, rows[1].get('dnc_at_gc'));
    }

    // Integrator 2026-10-02: a retry at a stage where the Bacs advance notice
    // is suppressed would never be collected; it is refused up front, and the
    // row keeps its status. 'Closed - Fee Failed' still retries (it reopens
    // as 'Fee Charged'): see the next test.
    @isTest static void retryInstallment_atGatedStage_refused() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Mandatory Reconsideration Requested';
        update a;
        AA_Fee_Installment__c failed = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 160,
            Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed', Payment_Id__c = 'PM-F');
        insert failed;
        Boolean threw = false;
        try { AA_GoCardlessController.retryInstallment(failed.Id); } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'no retry where the notice cannot be sent');
        System.assertEquals('failed', [SELECT Payment_Status__c FROM AA_Fee_Installment__c WHERE Id = :failed.Id].Payment_Status__c);
    }

    @isTest static void retryInstallment_closedFeeFailed_reopensAndRetries() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Stage__c             = 'Closed - Fee Failed';
        update a;
        AA_Fee_Installment__c failed = new AA_Fee_Installment__c(
            Application__c = a.Id, Installment_Number__c = 1, Amount__c = 160,
            Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed', Payment_Id__c = 'PM-F');
        insert failed;
        AA_FeeInstallmentScheduler.testBypass = true;
        Map<String, Object> res = AA_GoCardlessController.retryInstallment(failed.Id);
        System.assertEquals(true, res.get('ok'));
        System.assertEquals('Fee Charged', [SELECT Stage__c FROM AA_Application__c WHERE Id = :a.Id].Stage__c);
        System.assertEquals('pending', [SELECT Payment_Status__c FROM AA_Fee_Installment__c WHERE Id = :failed.Id].Payment_Status__c);
    }

    @isTest static void getDDStatus_projectsAllFields() {
        upsertConfig();
        AA_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD1';
        a.DD_Mandate_Status__c        = 'active';
        a.Award_Amount__c             = 600;
        update a;

        Map<String,Object> s = AA_GoCardlessController.getDDStatus(a.Id);
        System.assertEquals('MD1', s.get('mandate_id'));
        System.assertEquals('active', s.get('mandate_status'));
        System.assertEquals(true, s.get('bank_verified'));
        System.assertEquals(true, s.get('dd_terms_read'));
        System.assertEquals(600, ((Decimal) s.get('award_amount')));
        // Fee_Amount__c formula must have materialised: 20% of 600 = 120
        // (rate dropped 25% → 20% on 2026-08-18).
        System.assertEquals(120, ((Decimal) s.get('fee_amount')));
    }

    // -----------------------------------------------------------------
    // Trigger + Queueable
    // -----------------------------------------------------------------
    @isTest static void trigger_enqueues_onEligibilityTransition() {
        upsertConfig();
        AA_Application__c a = makeApp();

        Test.setMock(HttpCalloutMock.class, successMock());
        Test.startTest();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        update a;
        Test.stopTest();  // flushes Queueable

        AA_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c
                                    FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0001', after.DD_Mandate_Id__c,
            'Queueable must have created the mandate via controller');
        System.assertEquals('pending_submission', after.DD_Mandate_Status__c);
    }

    @isTest static void trigger_respectsGlobalBypass() {
        upsertConfig();
        disableAutoCreate();
        AA_Application__c a = makeApp();

        // No mock — bypass must prevent enqueue → no callout.
        Test.startTest();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        update a;
        Test.stopTest();

        AA_Application__c after = [SELECT DD_Mandate_Id__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.DD_Mandate_Id__c,
            'bypass must prevent auto-mandate');
    }

    @isTest static void trigger_doesNotReenqueue_onUnrelatedUpdate() {
        upsertConfig();
        AA_Application__c a = makeApp();
        // Pre-load with a mandate so eligibility is FALSE from the start.
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-ALREADY';
        a.DD_Mandate_Status__c        = 'active';
        update a;

        // No mock — an unrelated field update on an already-mandated app
        // must NOT enqueue, so no callout must happen.
        Test.startTest();
        a.First_Name__c = 'Renamed';
        update a;
        Test.stopTest();

        AA_Application__c after = [SELECT DD_Mandate_Id__c FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD-ALREADY', after.DD_Mandate_Id__c,
            'existing mandate id must be untouched');
    }

    // -----------------------------------------------------------------
    // Eligibility helper — pure logic
    // -----------------------------------------------------------------
    @isTest static void eligibility_nullSafe() {
        System.assertEquals(false, AA_MandateEligibility.isEligible(null));
    }
    @isTest static void eligibility_allAxes() {
        AA_Application__c a = new AA_Application__c();
        System.assertEquals(false, AA_MandateEligibility.isEligible(a));
        a.Bank_Verification_Status__c = 'Modulus Passed';
        System.assertEquals(false, AA_MandateEligibility.isEligible(a));
        a.DD_Terms_Read_By_Sales__c = true;
        System.assertEquals(true, AA_MandateEligibility.isEligible(a));
        a.DD_Mandate_Id__c = 'MD-X';
        System.assertEquals(false, AA_MandateEligibility.isEligible(a));
    }
}