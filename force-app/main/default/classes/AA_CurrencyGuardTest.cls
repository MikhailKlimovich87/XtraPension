/**
 * AA_CurrencyGuardTest — proves CurrencyIsoCode='GBP' is structural on the
 * three AA money-bearing objects (Application, Handoff, Fee Installment),
 * whatever the caller passes, and that an Application cannot be moved off GBP
 * afterwards (Currency_Must_Be_GBP validation rule). Mirrors
 * PC1_CurrencyGuardTest.
 */
@isTest
private class AA_CurrencyGuardTest {

    private static AA_Application__c parent(String tag) {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = tag, Last_Name__c = 'Parent' + System.now().getTime(),
            Email__c = tag.toLowerCase() + '@example.com', Stage__c = 'New');
        insert a;
        return a;
    }

    @isTest static void applicationInsertedInUiIsForcedToGbp() {
        // No CurrencyIsoCode passed — exactly what the Salesforce UI does, and
        // what leaves the record in the org's corporate EUR without the guard.
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Test', Last_Name__c = 'Claimant', Email__c = 'gbp@example.com',
            Stage__c = 'New');
        Test.startTest();
        insert a;
        Test.stopTest();
        AA_Application__c got = [SELECT CurrencyIsoCode FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'UI-created application must be GBP');
    }

    @isTest static void explicitEurIsOverriddenToGbp() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Euro', Last_Name__c = 'Override', Email__c = 'eur@example.com',
            Stage__c = 'New', CurrencyIsoCode = 'EUR');
        Test.startTest();
        insert a;
        Test.stopTest();
        AA_Application__c got = [SELECT CurrencyIsoCode FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'an explicit EUR must still be forced to GBP');
    }

    @isTest static void gbpIsLeftAlone() {
        AA_Application__c a = new AA_Application__c(
            First_Name__c = 'Already', Last_Name__c = 'Sterling', Email__c = 'ok@example.com',
            Stage__c = 'New', CurrencyIsoCode = 'GBP');
        Test.startTest();
        insert a;
        Test.stopTest();
        AA_Application__c got = [SELECT CurrencyIsoCode FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode);
    }

    @isTest static void handoffIsForcedToGbp() {
        AA_Application__c a = parent('H');
        AA_Handoff__c h = new AA_Handoff__c(Application__c = a.Id, Reason__c = 'test',
            Escalation_Type__c = 'other', CurrencyIsoCode = 'EUR');
        Test.startTest();
        insert h;
        Test.stopTest();
        AA_Handoff__c got = [SELECT CurrencyIsoCode FROM AA_Handoff__c WHERE Id = :h.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'handoff must be GBP');
    }

    @isTest static void feeInstallmentIsForcedToGbp() {
        AA_Application__c a = parent('F');
        AA_Fee_Installment__c fi = new AA_Fee_Installment__c(
            Application__c = a.Id, Amount__c = 100, Installment_Number__c = 1,
            Scheduled_Date__c = Date.today(), Payment_Status__c = 'pending',
            CurrencyIsoCode = 'EUR');
        Test.startTest();
        insert fi;
        Test.stopTest();
        AA_Fee_Installment__c got = [SELECT CurrencyIsoCode, Amount__c FROM AA_Fee_Installment__c WHERE Id = :fi.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'fee installment must be GBP');
    }

    @isTest static void applicationCannotBeMovedOffGbp() {
        // The guard is insert-only (PC1 parity) and CurrencyIsoCode is editable on
        // the layout, so the update path is closed by the Currency_Must_Be_GBP
        // validation rule instead. Without it a val agent could flip a GBP record
        // to EUR on any later edit and the Award/Fee amounts driving the
        // GoCardless charge would display in euros again.
        AA_Application__c a = parent('V');
        a.CurrencyIsoCode = 'EUR';
        Boolean rejected = false;
        Test.startTest();
        try {
            update a;
        } catch (DmlException e) {
            rejected = e.getDmlType(0) == StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION;
        }
        Test.stopTest();
        System.assert(rejected, 'moving an Application off GBP must be rejected by Currency_Must_Be_GBP');
        AA_Application__c got = [SELECT CurrencyIsoCode FROM AA_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'record must still be GBP after the rejected update');
    }

    @isTest static void bulkInsertAllGbp() {
        // 100 rows in one trigger chunk, alternating EUR/GBP so both branches of
        // the guard run inside the same chunk. Not the canonical 200: every
        // Application insert fans out through AA_DefaultAnswersHelper into 4
        // AA_Answer__c rows, whose trigger recomputes the full ~113-page AA flow
        // per Application (AA_FlowEngine.recomputeAndUpdate), so 200 rows meant
        // 200 flow walks in one test transaction against the 10 s CPU limit.
        // The guard's loop is exercised identically by 100.
        List<AA_Application__c> rows = new List<AA_Application__c>();
        for (Integer i = 0; i < 100; i++) {
            rows.add(new AA_Application__c(
                First_Name__c = 'Bulk', Last_Name__c = 'Row' + i,
                Email__c = 'bulk' + i + '@example.com', Stage__c = 'New',
                CurrencyIsoCode = Math.mod(i, 2) == 0 ? 'EUR' : 'GBP'));
        }
        Test.startTest();
        insert rows;
        Test.stopTest();
        Integer nonGbp = [SELECT COUNT() FROM AA_Application__c WHERE Id IN :rows AND CurrencyIsoCode != 'GBP'];
        System.assertEquals(0, nonGbp, 'no row in a bulk insert may stay non-GBP');
    }

    @isTest static void nullAndEmptyInputAreSafe() {
        Test.startTest();
        AA_CurrencyGuard.forceGbp(null);
        AA_CurrencyGuard.forceGbp(new List<AA_Application__c>());
        Test.stopTest();
        System.assert(true, 'null/empty input must not throw');
    }
}