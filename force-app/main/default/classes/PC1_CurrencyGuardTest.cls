@isTest
private class PC1_CurrencyGuardTest {

    @isTest static void applicationInsertedInUiIsForcedToGbp() {
        // No CurrencyIsoCode passed — exactly what the Salesforce UI does, and
        // what used to leave the record in the org's corporate EUR.
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Test', Last_Name__c = 'Claimant', Email__c = 'gbp@example.com');
        Test.startTest();
        insert a;
        Test.stopTest();
        PC1_Application__c got = [SELECT CurrencyIsoCode FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'UI-created application must be GBP');
    }

    @isTest static void explicitEurIsOverriddenToGbp() {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Euro', Last_Name__c = 'Override', Email__c = 'eur@example.com',
            CurrencyIsoCode = 'EUR');
        Test.startTest();
        insert a;
        Test.stopTest();
        PC1_Application__c got = [SELECT CurrencyIsoCode FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'an explicit EUR must still be forced to GBP');
    }

    @isTest static void gbpIsLeftAlone() {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'Already', Last_Name__c = 'Sterling', Email__c = 'ok@example.com',
            CurrencyIsoCode = 'GBP');
        Test.startTest();
        insert a;
        Test.stopTest();
        PC1_Application__c got = [SELECT CurrencyIsoCode FROM PC1_Application__c WHERE Id = :a.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode);
    }

    @isTest static void handoffIsForcedToGbp() {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'H', Last_Name__c = 'Parent', Email__c = 'h@example.com');
        insert a;
        PC1_Handoff__c h = new PC1_Handoff__c(Application__c = a.Id, Reason__c = 'test',
            Escalation_Type__c = 'other', CurrencyIsoCode = 'EUR');
        Test.startTest();
        insert h;
        Test.stopTest();
        PC1_Handoff__c got = [SELECT CurrencyIsoCode FROM PC1_Handoff__c WHERE Id = :h.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'handoff must be GBP');
    }

    @isTest static void feeInstallmentIsForcedToGbp() {
        PC1_Application__c a = new PC1_Application__c(
            First_Name__c = 'F', Last_Name__c = 'Parent', Email__c = 'f@example.com');
        insert a;
        PC1_Fee_Installment__c fi = new PC1_Fee_Installment__c(
            Application__c = a.Id, Amount__c = 100, Installment_Number__c = 1,
            Scheduled_Date__c = Date.today(), CurrencyIsoCode = 'EUR');
        Test.startTest();
        insert fi;
        Test.stopTest();
        PC1_Fee_Installment__c got = [SELECT CurrencyIsoCode, Amount__c FROM PC1_Fee_Installment__c WHERE Id = :fi.Id];
        System.assertEquals('GBP', got.CurrencyIsoCode, 'fee installment must be GBP');
    }

    @isTest static void bulkInsertAllGbp() {
        List<PC1_Application__c> rows = new List<PC1_Application__c>();
        for (Integer i = 0; i < 200; i++) {
            rows.add(new PC1_Application__c(
                First_Name__c = 'Bulk', Last_Name__c = 'Row' + i,
                Email__c = 'bulk' + i + '@example.com',
                CurrencyIsoCode = Math.mod(i, 2) == 0 ? 'EUR' : 'GBP'));
        }
        Test.startTest();
        insert rows;
        Test.stopTest();
        Integer nonGbp = [SELECT COUNT() FROM PC1_Application__c WHERE Id IN :rows AND CurrencyIsoCode != 'GBP'];
        System.assertEquals(0, nonGbp, 'no row in a bulk insert may stay non-GBP');
    }

    @isTest static void nullAndEmptyInputAreSafe() {
        Test.startTest();
        PC1_CurrencyGuard.forceGbp(null);
        PC1_CurrencyGuard.forceGbp(new List<PC1_Application__c>());
        Test.stopTest();
        System.assert(true, 'null/empty input must not throw');
    }
}