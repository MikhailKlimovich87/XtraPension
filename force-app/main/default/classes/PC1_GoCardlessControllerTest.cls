/**
 * PC1_GoCardlessControllerTest — covers the four Aura-enabled methods on
 * PC1_GoCardlessController + the auto-create trigger + eligibility helper.
 *
 * Callouts are stubbed with a routing HttpCalloutMock so we can drive both
 * endpoints (create-mandate + charge-fee) from a single mock and toggle the
 * success/failure body on demand.
 *
 * Guard-rail tests deliberately DO NOT set a mock — they should throw
 * before any HTTP is issued.
 */
@isTest
private class PC1_GoCardlessControllerTest {

    // -----------------------------------------------------------------
    // Mock
    // -----------------------------------------------------------------
    /** Routes on the endpoint suffix so a single mock covers both endpoints. */
    private class GcMock implements HttpCalloutMock {
        public Integer status = 200;
        public String  mandateBody;
        public String  chargeBody;

        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            String url = req.getEndpoint();
            if (url.endsWith('/internal/gocardless/create-mandate')) {
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
        // mandate_pdf.ok: since 2026-08-18 the controller only stamps
        // DD_Mandate_Id__c once Node confirms the mandate PDF is in SF.
        m.mandateBody = '{"ok":true,"mandate_id":"MD0001","customer_id":"CU0001","status":"pending_submission","mandate_pdf":{"ok":true}}';
        m.chargeBody  = '{"ok":true,"payment_id":"PM0001","status":"pending_submission","charge_date":"2026-08-25"}';
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
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        PC1_Config__c cfg;
        if (rows.isEmpty()) {
            cfg = new PC1_Config__c(SetupOwnerId = UserInfo.getOrganizationId());
        } else {
            cfg = new PC1_Config__c(Id = rows[0].Id);
        }
        cfg.Internal_Admin_Token__c = 'TEST-TOKEN';
        cfg.Auto_Create_DD_Mandate__c = true;
        upsert cfg;
    }

    private static void disableAutoCreate() {
        List<PC1_Config__c> rows = [SELECT Id FROM PC1_Config__c LIMIT 1];
        update new PC1_Config__c(Id = rows[0].Id, Auto_Create_DD_Mandate__c = false);
    }

    /** Base intake row — ready to have bank + terms toggled by each test. */
    private static PC1_Application__c makeApp() {
        PC1_Application__c a = new PC1_Application__c(
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
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        Test.setMock(HttpCalloutMock.class, successMock());
        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('MD0001', res.get('mandate_id'));
        System.assertEquals('pending_submission', res.get('status'));

        PC1_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c, DD_Mandate_Created_At__c
                                    FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0001', after.DD_Mandate_Id__c);
        System.assertEquals('pending_submission', after.DD_Mandate_Status__c);
        System.assertNotEquals(null, after.DD_Mandate_Created_At__c);
    }

    @isTest static void createMandate_pdfPending_doesNotStampMandateId() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        GcMock m = successMock();
        m.mandateBody = '{"ok":true,"mandate_id":"MD0002","status":"pending_submission","mandate_pdf":{"ok":false}}';
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('pdf_pending'));
        System.assertEquals(null, [SELECT DD_Mandate_Id__c FROM PC1_Application__c WHERE Id = :a.Id].DD_Mandate_Id__c,
            'no mandate id until the PDF is in Salesforce (the watchdog retries)');
    }

    @isTest static void createMandate_replacesFailedMandate() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-DEAD';
        a.DD_Mandate_Status__c        = 'failed';
        update a;

        GcMock m = successMock();
        m.mandateBody = '{"ok":true,"mandate_id":"MD0009","status":"pending_submission","mandate_pdf":{"ok":false},'
                      + '"replaced":{"id":"MD-DEAD","cancelled":false,"note":"already_inactive"}}';
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals('MD-DEAD', res.get('replaced'));
        PC1_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0009', after.DD_Mandate_Id__c, 'replacement stamps the new id even while its PDF is pending');
        System.assertEquals('pending_submission', after.DD_Mandate_Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Stage_Log__c WHERE Application__c = :a.Id AND Note__c LIKE 'Direct Debit replaced%']);
    }

    @isTest static void bankChange_parksLiveMandate() {
        upsertConfig();
        disableAutoCreate();
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-LIVE';
        a.DD_Mandate_Status__c        = 'active';
        update a;

        Test.startTest();
        insert new PC1_Answer__c(Application__c = a.Id, Field_Id__c = 'q0_sp_account', Value__c = '11223344', Source__c = 'human');
        Test.stopTest();

        PC1_Application__c after = [SELECT DD_Mandate_Status__c, DD_Mandate_Failure_Reason__c, Bank_Verification_Status__c
                                      FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('cancelled', after.DD_Mandate_Status__c, 'old account must not be charged');
        System.assert(after.DD_Mandate_Failure_Reason__c.startsWith('Bank details changed'), after.DD_Mandate_Failure_Reason__c);
        System.assertEquals('Unverified', after.Bank_Verification_Status__c);
    }

    private class RetryMock implements HttpCalloutMock {
        Integer status; String body;
        RetryMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().endsWith('/internal/gocardless/retry-payment'), req.getEndpoint());
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    @isTest static void retryInstallment_reSubmitsFailedRow() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        PC1_Fee_Installment__c i = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 2,
            Amount__c = 53.33, Scheduled_Date__c = Date.today().addDays(-3), Payment_Status__c = 'failed', Payment_Id__c = 'PM0002');
        insert i;
        Test.setMock(HttpCalloutMock.class, new RetryMock(200, '{"ok":true,"payment_id":"PM0002","status":"pending_submission","charge_date":"2026-10-07"}'));
        Test.startTest();
        Map<String,Object> r = PC1_GoCardlessController.retryInstallment(i.Id);
        Test.stopTest();
        System.assertEquals(true, r.get('ok'));
        System.assertEquals('submitted', [SELECT Payment_Status__c FROM PC1_Fee_Installment__c WHERE Id = :i.Id].Payment_Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM PC1_Stage_Log__c WHERE Application__c = :a.Id AND Note__c LIKE 'Installment 2 retried%']);
        System.assertEquals(1, PC1_GoCardlessController.getInstallments(a.Id).size());
    }

    @isTest static void retryInstallment_refusals() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        PC1_Fee_Installment__c paid = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1,
            Amount__c = 10, Scheduled_Date__c = Date.today(), Payment_Status__c = 'paid', Payment_Id__c = 'PM1');
        PC1_Fee_Installment__c noPay = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 2,
            Amount__c = 10, Scheduled_Date__c = Date.today(), Payment_Status__c = 'failed');
        PC1_Fee_Installment__c gcNo = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 3,
            Amount__c = 10, Scheduled_Date__c = Date.today(), Payment_Status__c = 'failed', Payment_Id__c = 'PM3');
        insert new List<PC1_Fee_Installment__c>{ paid, noPay, gcNo };
        Boolean t1 = false, t2 = false, t3 = false, t4 = false;
        try { PC1_GoCardlessController.retryInstallment(paid.Id); } catch (AuraHandledException e) { t1 = true; }
        try { PC1_GoCardlessController.retryInstallment(noPay.Id); } catch (AuraHandledException e) { t2 = true; }
        try { PC1_GoCardlessController.retryInstallment(null); } catch (AuraHandledException e) { t3 = true; }
        Test.setMock(HttpCalloutMock.class, new RetryMock(409, '{"ok":false,"error":"not_failed","detail":"payment PM3 is confirmed"}'));
        try { PC1_GoCardlessController.retryInstallment(gcNo.Id); } catch (AuraHandledException e) { t4 = true; }
        System.assert(t1 && t2 && t3 && t4);
        System.assertEquals('failed', [SELECT Payment_Status__c FROM PC1_Fee_Installment__c WHERE Id = :gcNo.Id].Payment_Status__c,
            'GoCardless refusal leaves the row as it was');
        System.assertEquals(0, PC1_GoCardlessController.getInstallments(null).size());
    }

    @isTest static void createMandate_idempotent_shortCircuits() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-EXISTING';
        a.DD_Mandate_Status__c        = 'active';
        update a;

        // No mock set — if we tried to call out this would raise
        // "HttpCalloutMock must be set" and the test would fail.
        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('MD-EXISTING', res.get('mandate_id'));
        System.assertEquals(true, res.get('existed'));
    }

    @isTest static void createMandate_bankNotVerified_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        Boolean threw = false;
        try {
            PC1_GoCardlessController.createMandateForApplication(a.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'must throw when Bank_Verification_Status__c != Modulus Passed');
    }

    @isTest static void createMandate_termsNotRead_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        update a;

        Boolean threw = false;
        try {
            PC1_GoCardlessController.createMandateForApplication(a.Id);
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
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c = true;
        update a;

        Test.setMock(HttpCalloutMock.class, failMock());
        Test.startTest();
        Boolean threw = false;
        try {
            PC1_GoCardlessController.createMandateForApplication(a.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'endpoint failure must bubble as AuraHandledException');
        PC1_Application__c after = [SELECT DD_Mandate_Failure_Reason__c, DD_Mandate_Id__c
                                    FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.DD_Mandate_Id__c);
        System.assert(after.DD_Mandate_Failure_Reason__c != null &&
            after.DD_Mandate_Failure_Reason__c.contains('gocardless_rejected'),
            'failure reason must be persisted, got: ' + after.DD_Mandate_Failure_Reason__c);
        // Audit 2026-11-11 PC-APEX-13: the stage-log half of the failure trail
        // was never written (To_Stage__c is required and was left blank).
        List<PC1_Stage_Log__c> trail = [SELECT From_Stage__c, To_Stage__c, Actor__c FROM PC1_Stage_Log__c
                                         WHERE Application__c = :a.Id AND Note__c LIKE 'Mandate create failed%'];
        System.assertEquals(1, trail.size(), 'the failure is on the stage timeline');
        System.assertEquals(trail[0].From_Stage__c, trail[0].To_Stage__c, 'a note row, not a stage change');
        System.assertEquals('system', trail[0].Actor__c);
    }

    // -----------------------------------------------------------------
    // recordAward — validation + happy path
    // -----------------------------------------------------------------
    @isTest static void recordAward_happyPath_setsAmountAndStage() {
        upsertConfig();
        PC1_Application__c a = makeApp();

        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 800, null, null, null);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(800, ((Decimal) res.get('award_amount')));
        System.assertEquals(160, ((Decimal) res.get('fee_amount')));  // 20% of 800 (was 25% before 2026-08-18)
        System.assertEquals(1, ((Decimal) res.get('installments')).intValue());   // legacy signature = single charge
        System.assertEquals(160, ((Decimal) res.get('installment_amount')));
        System.assertEquals('Awarded', String.valueOf(res.get('stage')));
    }

    @isTest static void recordAward_planThreeInstallments_writesPlanField() {
        upsertConfig();
        PC1_Application__c a = makeApp();

        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 800, 3, 100, null);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(160, ((Decimal) res.get('fee_amount')));  // 20% of 800
        System.assertEquals(3, ((Decimal) res.get('installments')).intValue());
        // 160 / 3 = 53.33 (final row absorbs the £0.01 remainder)
        System.assertEquals(53.33, ((Decimal) res.get('installment_amount')));
    }

    @isTest static void recordAward_planOutOfRange_clampsToMax() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 400, 99, null, null);
        System.assertEquals(6, ((Decimal) res.get('installments')).intValue(),
            'plan > 6 must clamp to PLAN_MAX (widened 3 → 6 on 2026-08-25)');
    }

    @isTest static void recordAward_zeroAmount_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        Boolean threw = false;
        try {
            PC1_GoCardlessController.recordAward(a.Id, 0, null, null, null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'zero must throw');
    }

    @isTest static void recordAward_unrealisticallyLarge_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        Boolean threw = false;
        try {
            PC1_GoCardlessController.recordAward(a.Id, 999999, null, null, null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, '>=100000 must throw as sanity guard');
    }

    // recordAward — DWP_Lump_Sum_Received__c persistence (2026-08-18)
    // The server does NOT compute the plan from the lump — the LWC does that.
    // Server just persists both fields and trusts the plan chosen by the val
    // team via the LWC (either auto-recommended or manually overridden).
    @isTest static void recordAward_persistsLumpSumReceived() {
        upsertConfig();
        PC1_Application__c a = makeApp();

        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 4000, 3, 300, null);
        Test.stopTest();

        System.assertEquals(300, ((Decimal) res.get('lump_sum_received')));
        System.assertEquals(3, ((Decimal) res.get('installments')).intValue(),
            'server trusts LWC plan choice — does NOT re-derive from lump vs fee');
        PC1_Application__c after = [SELECT DWP_Lump_Sum_Received__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(300, after.DWP_Lump_Sum_Received__c);
    }

    @isTest static void recordAward_lumpSumNegative_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        Boolean threw = false;
        try {
            PC1_GoCardlessController.recordAward(a.Id, 800, 1, -50, null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'negative lump sum must throw');
    }

    @isTest static void recordAward_nullLumpSumPreservesExisting() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        // Prime an existing lump sum
        a.DWP_Lump_Sum_Received__c = 250;
        update a;
        // Second save without lumpSum (null) must NOT wipe it
        PC1_GoCardlessController.recordAward(a.Id, 900, 3, null, null);
        PC1_Application__c after = [SELECT DWP_Lump_Sum_Received__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(250, after.DWP_Lump_Sum_Received__c,
            'null lumpSum on re-save must preserve prior value');
    }

    // -----------------------------------------------------------------
    // recordAward — frozen once the fee is being collected (audit C7)
    // -----------------------------------------------------------------
    @isTest static void recordAward_lockedOnceInstallmentsExist() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        PC1_GoCardlessController.recordAward(a.Id, 10000, 3, null, null);
        insert new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1,
            Amount__c = 666.67, Scheduled_Date__c = Date.today(), Payment_Status__c = 'paid');

        Boolean threw = false;
        try {
            PC1_GoCardlessController.recordAward(a.Id, 8000, 3, null, null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'changing the award after collection started must be refused');

        threw = false;
        try {
            PC1_GoCardlessController.recordAward(a.Id, 10000, 1, null, null);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'changing the plan after collection started must be refused');

        // Same values + a lump sum note is still fine.
        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 10000, 3, 500, null);
        System.assertEquals(true, res.get('ok'));
        System.assertEquals(10000, [SELECT Award_Amount__c FROM PC1_Application__c WHERE Id = :a.Id].Award_Amount__c);
    }

    @isTest static void recordAward_freeToChangeBeforeCollection() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        PC1_GoCardlessController.recordAward(a.Id, 10000, 3, null, null);
        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 8000, 3, null, null);
        System.assertEquals(1600, ((Decimal) res.get('fee_amount')), 'no installment yet: correction allowed');
    }

    // -----------------------------------------------------------------
    // chargeFee — happy path + gates + idempotent
    // -----------------------------------------------------------------
    // Since 2026-11-11 (audit PC-APEX-4 / PC-SFUI-4) Charge Fee never calls
    // GoCardless itself: it schedules the plan no sooner than
    // FIRST_CHARGE_MIN_DAYS out and emails the advance notice; the daily
    // sweep creates each payment with the noticed date. None of these tests
    // sets a callout mock: a callout from chargeFee would fail them.

    /** Award recorded, mandate active: ready for Charge Fee. */
    private static PC1_Application__c makeChargeableApp(Integer plan) {
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD-ACTIVE';
        a.DD_Mandate_Status__c        = 'active';
        a.Award_Amount__c             = 800;
        a.Fee_Plan_Installments__c    = plan;
        a.Stage__c                    = 'Awarded';
        update a;
        return a;
    }

    private static void bacsTemplate() {
        insert new PC1_Message_Template__c(Channel__c = 'Email', Trigger_Event__c = 'Bacs_Advance_Notice',
            Active__c = true, Subject_Template__c = 'Notice', Body_Template__c = 'Hi');
    }

    @isTest static void chargeFee_happyPath_schedulesAndNotices_noGoCardlessCall() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(1);
        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_FeeInstallmentScheduler.testDispatched.clear();
        Date earliest = Date.today().addDays(PC1_GoCardlessController.FIRST_CHARGE_MIN_DAYS);

        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(true, res.get('deferred'), 'nothing is taken at click time any more');
        System.assertEquals(true, res.get('notice_sent'), 'the client is emailed the date and amount at once');
        System.assertEquals(earliest, (Date) res.get('first_charge_date'));
        // installment #1 amount — single-charge plan → 20% of 800 = 160
        System.assertEquals(160, ((Decimal) res.get('amount_pounds')));
        System.assertEquals(1, (Integer) res.get('installments'));
        System.assertEquals(1, PC1_FeeInstallmentScheduler.testDispatched.size(), 'one advance notice');

        PC1_Application__c after = [SELECT Fee_Payment_Id__c, Fee_First_Charge_Date__c, Fee_Plan_Next_Charge_Date__c, Stage__c
                                    FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.Fee_Payment_Id__c, 'the payment is created by the sweep, not here');
        System.assertEquals(earliest, after.Fee_First_Charge_Date__c, 'the date really used is written back for the card');
        System.assertEquals(earliest, after.Fee_Plan_Next_Charge_Date__c);
        System.assertEquals('Awarded', after.Stage__c, 'Fee Charged lands when the payment exists');

        List<PC1_Fee_Installment__c> rows = [
            SELECT Installment_Number__c, Amount__c, Payment_Id__c, Payment_Status__c, Scheduled_Date__c, Bacs_Notice_Sent__c
            FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id ORDER BY Installment_Number__c
        ];
        System.assertEquals(1, rows.size(), 'single-charge plan → 1 installment row');
        System.assertEquals(160, rows[0].Amount__c);
        System.assertEquals('pending', rows[0].Payment_Status__c);
        System.assertEquals(null, rows[0].Payment_Id__c);
        System.assertEquals(earliest, rows[0].Scheduled_Date__c);
        System.assertEquals(true, rows[0].Bacs_Notice_Sent__c);
    }

    @isTest static void chargeFee_threeInstallments_insertsRows_aMonthApart() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(3);
        PC1_FeeInstallmentScheduler.testBypass = true;
        Date earliest = Date.today().addDays(PC1_GoCardlessController.FIRST_CHARGE_MIN_DAYS);

        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals(3, (Integer) res.get('installments'));
        System.assertEquals(53.33, ((Decimal) res.get('installment_amount')));

        List<PC1_Fee_Installment__c> rows = [
            SELECT Installment_Number__c, Amount__c, Scheduled_Date__c,
                   Payment_Id__c, Payment_Status__c, Bacs_Notice_Sent__c
            FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id
            ORDER BY Installment_Number__c
        ];
        System.assertEquals(3, rows.size(), '3-installment plan → 3 rows');
        System.assertEquals(53.33, rows[0].Amount__c);
        System.assertEquals(53.33, rows[1].Amount__c);
        // Final row absorbs the £0.01 rounding remainder: 160 - 53.33*2 = 53.34
        System.assertEquals(53.34, rows[2].Amount__c);
        // Sum equals total fee exactly.
        Decimal sum = rows[0].Amount__c + rows[1].Amount__c + rows[2].Amount__c;
        System.assertEquals(160, sum);
        System.assertEquals(earliest, rows[0].Scheduled_Date__c);
        System.assertEquals(earliest.addMonths(1), rows[1].Scheduled_Date__c);
        System.assertEquals(earliest.addMonths(2), rows[2].Scheduled_Date__c);
        for (PC1_Fee_Installment__c r : rows) {
            System.assertEquals(null, r.Payment_Id__c, 'no payment exists yet');
            System.assertEquals('pending', r.Payment_Status__c);
        }
        System.assertEquals(true, rows[0].Bacs_Notice_Sent__c, 'installment 1 is noticed now');
        System.assertEquals(false, rows[1].Bacs_Notice_Sent__c, 'the others by the daily sweep');
    }

    // PC-SFUI-4: the award was recorded weeks ago, Charge is clicked today.
    // The stale date used to be the anchor: #1 went out at once and #2 was
    // already overdue, collected the next morning with no notice.
    @isTest static void chargeFee_pastFirstChargeDate_isMovedForward() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(3);
        update new PC1_Application__c(Id = a.Id, Fee_First_Charge_Date__c = Date.today().addDays(-35));
        PC1_FeeInstallmentScheduler.testBypass = true;
        Date earliest = Date.today().addDays(PC1_GoCardlessController.FIRST_CHARGE_MIN_DAYS);

        Map<String,Object> res = PC1_GoCardlessController.chargeFee(a.Id);

        System.assertEquals(earliest, (Date) res.get('first_charge_date'));
        List<PC1_Fee_Installment__c> rows = [SELECT Scheduled_Date__c FROM PC1_Fee_Installment__c
                                              WHERE Application__c = :a.Id ORDER BY Installment_Number__c];
        System.assertEquals(earliest, rows[0].Scheduled_Date__c);
        System.assertEquals(earliest.addMonths(1), rows[1].Scheduled_Date__c, 'a full month after installment 1');
        System.assertEquals(earliest, [SELECT Fee_First_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id].Fee_First_Charge_Date__c);
    }

    @isTest static void chargeFee_laterDateChosenByTheAgent_isKept_noticeLeftToTheSweep() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(1);
        Date chosen = Date.today().addDays(30);
        update new PC1_Application__c(Id = a.Id, Fee_First_Charge_Date__c = chosen);
        PC1_FeeInstallmentScheduler.testBypass = true;

        Map<String,Object> res = PC1_GoCardlessController.chargeFee(a.Id);

        System.assertEquals(chosen, (Date) res.get('first_charge_date'));
        System.assertEquals(false, res.get('notice_sent'), 'too early for the notice');
        PC1_Fee_Installment__c row = [SELECT Scheduled_Date__c, Bacs_Notice_Sent__c FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id];
        System.assertEquals(chosen, row.Scheduled_Date__c);
        System.assertEquals(false, row.Bacs_Notice_Sent__c);
    }

    @isTest static void chargeFee_secondClick_returnsTheSchedule_withoutRebuildingIt() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(3);
        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_GoCardlessController.chargeFee(a.Id);
        Set<Id> before = new Map<Id, PC1_Fee_Installment__c>([SELECT Id FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id]).keySet();
        PC1_FeeInstallmentScheduler.testDispatched.clear();

        Map<String,Object> res = PC1_GoCardlessController.chargeFee(a.Id);

        System.assertEquals(true, res.get('existed'));
        System.assertEquals(3, (Integer) res.get('installments'));
        Set<Id> after = new Map<Id, PC1_Fee_Installment__c>([SELECT Id FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id]).keySet();
        System.assertEquals(before, after, 'same rows: their notice stamps survive');
        System.assertEquals(0, PC1_FeeInstallmentScheduler.testDispatched.size(), 'no second advance notice');
    }

    @isTest static void chargeFee_refusedWhereTheSweepWouldNeverCollect() {
        upsertConfig();
        disableAutoCreate();   // clearing the mandate id below must not start a new mandate
        PC1_Application__c a = makeChargeableApp(1);
        Boolean t1 = false, t2 = false, t3 = false;
        update new PC1_Application__c(Id = a.Id, Do_Not_Contact__c = true);
        try { PC1_GoCardlessController.chargeFee(a.Id); } catch (AuraHandledException e) { t1 = true; }
        update new PC1_Application__c(Id = a.Id, Do_Not_Contact__c = false, Stage__c = 'Needs Human');
        try { PC1_GoCardlessController.chargeFee(a.Id); } catch (AuraHandledException e) { t2 = true; }
        update new PC1_Application__c(Id = a.Id, Stage__c = 'Awarded', DD_Mandate_Id__c = null);
        try { PC1_GoCardlessController.chargeFee(a.Id); } catch (AuraHandledException e) { t3 = true; }
        System.assert(t1, 'Do Not Contact: the advance notice cannot be sent');
        System.assert(t2, 'not a collectable stage');
        System.assert(t3, 'mandate document pending: Heroku would refuse every charge');
        System.assertEquals(0, [SELECT COUNT() FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id]);
    }

    // -----------------------------------------------------------------
    // Award / plan freeze on direct field writes (audit PC-APEX-9)
    // -----------------------------------------------------------------
    @isTest static void feeFreeze_blocksDirectFieldWrites_onceCollectionStarted() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(3);
        // Before any installment: free to correct.
        update new PC1_Application__c(Id = a.Id, Award_Amount__c = 900);
        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_GoCardlessController.chargeFee(a.Id);

        Boolean b1 = false, b2 = false, b3 = false;
        try { update new PC1_Application__c(Id = a.Id, Award_Amount__c = 700); } catch (DmlException e) { b1 = e.getMessage().contains('administrator'); }
        try { update new PC1_Application__c(Id = a.Id, Fee_Plan_Installments__c = 1); } catch (DmlException e) { b2 = true; }
        try { update new PC1_Application__c(Id = a.Id, Fee_First_Charge_Date__c = Date.today().addDays(50)); } catch (DmlException e) { b3 = true; }
        System.assert(b1, 'an inline edit of the award after the plan exists is refused, and says who can help');
        System.assert(b2, 'so is the plan');
        System.assert(b3, 'and the first charge date');
        System.assertEquals(900, [SELECT Award_Amount__c FROM PC1_Application__c WHERE Id = :a.Id].Award_Amount__c);
        // Everything else on the record still saves.
        update new PC1_Application__c(Id = a.Id, Notes__c = 'still editable', DWP_Lump_Sum_Received__c = 100);
    }

    // PC-SFUI-10: the award card re-sends the stored first date on every Edit.
    @isTest static void recordAward_unchangedStaleDate_isNotRefused() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        Date stale = Date.today().addDays(-3);
        update new PC1_Application__c(Id = a.Id, Award_Amount__c = 800, Fee_Plan_Installments__c = 1, Fee_First_Charge_Date__c = stale);

        Map<String,Object> res = PC1_GoCardlessController.recordAward(a.Id, 800, 1, 250, stale);
        System.assertEquals(true, res.get('ok'), 'the same date sent back is not a new choice');
        System.assertEquals(250, ((Decimal) res.get('lump_sum_received')));

        Boolean threw = false;
        try { PC1_GoCardlessController.recordAward(a.Id, 800, 1, null, Date.today().addDays(-1)); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'a NEW date in the past is still refused');
    }

    // -----------------------------------------------------------------
    // Held installment (no GoCardless payment) → Retry puts it back
    // -----------------------------------------------------------------
    @isTest static void retryInstallment_heldRowWithoutPayment_isPutBackWithAFreshNotice() {
        upsertConfig();
        bacsTemplate();
        PC1_Application__c a = makeChargeableApp(2);
        PC1_Fee_Installment__c held = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1,
            Amount__c = 80, Scheduled_Date__c = Date.today().addDays(-2), Payment_Status__c = 'failed',
            Bacs_Notice_Sent__c = true, Bacs_Notice_Sent_At__c = Datetime.now().addDays(-9));
        insert held;
        PC1_FeeInstallmentScheduler.testBypass = true;
        PC1_FeeInstallmentScheduler.testDispatched.clear();

        Map<String,Object> r = PC1_GoCardlessController.retryInstallment(held.Id);

        Date nd = Date.today().addDays(PC1_GoCardlessController.FIRST_CHARGE_MIN_DAYS);
        System.assertEquals(true, r.get('requeued'));
        System.assertEquals(true, r.get('notice_sent'));
        System.assertEquals(String.valueOf(nd), r.get('charge_date'));
        PC1_Fee_Installment__c after = [SELECT Payment_Status__c, Scheduled_Date__c, Bacs_Notice_Sent__c, Bacs_Notice_Sent_At__c
                                          FROM PC1_Fee_Installment__c WHERE Id = :held.Id];
        System.assertEquals('pending', after.Payment_Status__c);
        System.assertEquals(nd, after.Scheduled_Date__c);
        System.assertEquals(true, after.Bacs_Notice_Sent__c, 'noticed afresh for the new date');
        System.assert(after.Bacs_Notice_Sent_At__c > Datetime.now().addHours(-1));
        System.assertEquals(1, PC1_FeeInstallmentScheduler.testDispatched.size());
        System.assertEquals(nd, [SELECT Fee_Plan_Next_Charge_Date__c FROM PC1_Application__c WHERE Id = :a.Id].Fee_Plan_Next_Charge_Date__c);
    }

    // -----------------------------------------------------------------
    // Replacement mandate resumes the plan (audit PC-APEX-10)
    // -----------------------------------------------------------------
    @isTest static void createMandate_replacement_putsCancelledInstallmentsBack() {
        upsertConfig();
        disableAutoCreate();
        PC1_Application__c a = makeChargeableApp(3);
        update new PC1_Application__c(Id = a.Id, DD_Mandate_Id__c = 'MD-DEAD', DD_Mandate_Status__c = 'cancelled');
        // What the GoCardless webhook leaves behind when a mandate dies:
        // #1 paid, #2 cancelled at GoCardless (it had a payment), #3 never sent.
        PC1_Fee_Installment__c p1 = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 1,
            Amount__c = 53.33, Scheduled_Date__c = Date.today().addDays(-40), Payment_Status__c = 'paid', Payment_Id__c = 'PM_A1');
        PC1_Fee_Installment__c p2 = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 2,
            Amount__c = 53.33, Scheduled_Date__c = Date.today().addDays(-10), Payment_Status__c = 'cancelled', Payment_Id__c = 'PM_A2');
        PC1_Fee_Installment__c p3 = new PC1_Fee_Installment__c(Application__c = a.Id, Installment_Number__c = 3,
            Amount__c = 53.34, Scheduled_Date__c = Date.today().addDays(20), Payment_Status__c = 'cancelled',
            Bacs_Notice_Sent__c = true, Bacs_Notice_Sent_At__c = Datetime.now().addDays(-3));
        insert new List<PC1_Fee_Installment__c>{ p1, p2, p3 };

        GcMock m = successMock();
        m.mandateBody = '{"ok":true,"mandate_id":"MD0010","status":"pending_submission","mandate_pdf":{"ok":true},'
                      + '"replaced":{"id":"MD-DEAD","cancelled":false,"note":"already_inactive"}}';
        Test.setMock(HttpCalloutMock.class, m);
        Test.startTest();
        PC1_GoCardlessController.createMandateForApplication(a.Id);
        Test.stopTest();

        Map<Id, PC1_Fee_Installment__c> rows = new Map<Id, PC1_Fee_Installment__c>(
            [SELECT Payment_Status__c, Bacs_Notice_Sent__c FROM PC1_Fee_Installment__c WHERE Application__c = :a.Id]);
        System.assertEquals('pending', rows.get(p3.Id).Payment_Status__c,
            'never reached GoCardless: collected on the new Direct Debit');
        System.assertEquals(false, rows.get(p3.Id).Bacs_Notice_Sent__c, 'with a fresh advance notice');
        System.assertEquals('cancelled', rows.get(p2.Id).Payment_Status__c,
            'its GoCardless payment was cancelled and cannot be collected again');
        System.assertEquals('paid', rows.get(p1.Id).Payment_Status__c);
        List<PC1_Handoff__c> h = [SELECT Next_Step_Suggestion__c FROM PC1_Handoff__c
                                   WHERE Application__c = :a.Id AND Reason__c LIKE 'New Direct Debit set up%'];
        System.assertEquals(1, h.size(), 'somebody decides about installment 2');
        System.assert(h[0].Next_Step_Suggestion__c.contains('PM_A2'), h[0].Next_Step_Suggestion__c);
    }

    @isTest static void chargeFee_mandateNotActive_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-PENDING';
        a.DD_Mandate_Status__c = 'pending_submission';
        a.Award_Amount__c      = 800;
        update a;

        Boolean threw = false;
        try {
            PC1_GoCardlessController.chargeFee(a.Id);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'must throw when DD_Mandate_Status__c != active');
    }

    @isTest static void chargeFee_awardNotRecorded_throws() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        update a;

        Boolean threw = false;
        try {
            PC1_GoCardlessController.chargeFee(a.Id);
        } catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'must throw when Award_Amount__c null');
    }

    @isTest static void chargeFee_idempotent_returnsExisting() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.DD_Mandate_Id__c     = 'MD-ACTIVE';
        a.DD_Mandate_Status__c = 'active';
        a.Award_Amount__c      = 800;
        a.Fee_Payment_Id__c    = 'PM-EXISTING';
        a.Fee_Payment_Status__c = 'paid_out';
        a.Fee_Charged_At__c    = Datetime.now();
        update a;

        // No mock — must NOT call out.
        Test.startTest();
        Map<String,Object> res = PC1_GoCardlessController.chargeFee(a.Id);
        Test.stopTest();

        System.assertEquals(true, res.get('ok'));
        System.assertEquals('PM-EXISTING', res.get('payment_id'));
        System.assertEquals(true, res.get('existed'));
    }

    // -----------------------------------------------------------------
    // getDDStatus — projection
    // -----------------------------------------------------------------
    @isTest static void getDDStatus_projectsAllFields() {
        upsertConfig();
        PC1_Application__c a = makeApp();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        a.DD_Mandate_Id__c            = 'MD1';
        a.DD_Mandate_Status__c        = 'active';
        a.Award_Amount__c             = 600;
        update a;

        Map<String,Object> s = PC1_GoCardlessController.getDDStatus(a.Id);
        System.assertEquals('MD1', s.get('mandate_id'));
        System.assertEquals('active', s.get('mandate_status'));
        System.assertEquals(true, s.get('bank_verified'));
        System.assertEquals(true, s.get('dd_terms_read'));
        System.assertEquals(600, ((Decimal) s.get('award_amount')));
        // Fee_Amount__c formula must have materialised.
        System.assertEquals(120, ((Decimal) s.get('fee_amount')));  // 20% of 600
    }

    // -----------------------------------------------------------------
    // Trigger + Queueable
    // -----------------------------------------------------------------
    @isTest static void trigger_enqueues_onEligibilityTransition() {
        upsertConfig();
        PC1_Application__c a = makeApp();

        Test.setMock(HttpCalloutMock.class, successMock());
        Test.startTest();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        update a;
        Test.stopTest();  // flushes Queueable

        PC1_Application__c after = [SELECT DD_Mandate_Id__c, DD_Mandate_Status__c
                                    FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD0001', after.DD_Mandate_Id__c,
            'Queueable must have created the mandate via controller');
        System.assertEquals('pending_submission', after.DD_Mandate_Status__c);
    }

    @isTest static void trigger_respectsGlobalBypass() {
        upsertConfig();
        disableAutoCreate();
        PC1_Application__c a = makeApp();

        // No mock — bypass must prevent enqueue → no callout.
        Test.startTest();
        a.Bank_Verification_Status__c = 'Modulus Passed';
        a.DD_Terms_Read_By_Sales__c   = true;
        update a;
        Test.stopTest();

        PC1_Application__c after = [SELECT DD_Mandate_Id__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals(null, after.DD_Mandate_Id__c,
            'bypass must prevent auto-mandate');
    }

    @isTest static void trigger_doesNotReenqueue_onUnrelatedUpdate() {
        upsertConfig();
        PC1_Application__c a = makeApp();
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

        PC1_Application__c after = [SELECT DD_Mandate_Id__c FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('MD-ALREADY', after.DD_Mandate_Id__c,
            'existing mandate id must be untouched');
    }

    // -----------------------------------------------------------------
    // Eligibility helper — pure logic
    // -----------------------------------------------------------------
    @isTest static void eligibility_nullSafe() {
        System.assertEquals(false, PC1_MandateEligibility.isEligible(null));
    }
    @isTest static void eligibility_allAxes() {
        PC1_Application__c a = new PC1_Application__c();
        System.assertEquals(false, PC1_MandateEligibility.isEligible(a));
        a.Bank_Verification_Status__c = 'Modulus Passed';
        System.assertEquals(false, PC1_MandateEligibility.isEligible(a));
        a.DD_Terms_Read_By_Sales__c = true;
        System.assertEquals(true, PC1_MandateEligibility.isEligible(a));
        a.DD_Mandate_Id__c = 'MD-X';
        System.assertEquals(false, PC1_MandateEligibility.isEligible(a));
    }
}