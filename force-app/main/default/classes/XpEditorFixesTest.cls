// Correções dos editores IPCBR1 / IPC1394 (04/11/2026): o pacote regenerado depois do Save e o BSB do IPC1394.
@IsTest
private class XpEditorFixesTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account acc = TestDataFactory.createAccount(true);
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
        Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);
        BP_TestDataFactory.createChild(app.Id, true);
        BP_TestDataFactory.createCompany(app.Id, true);
        BP_TestDataFactory.createCountryLived(app.Id, true);
    }

    private static Basic__c claimIn(String status) {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];
        // with a mandate id the move to "Signed" does not create a GoCardless mandate (not what these tests are about)
        update new Basic__c(Id = claim.Id, Status__c = status, GoCardless_Mandate_Id__c = 'MD-TEST');
        return claim;
    }

    private static XpEditorDocsAfterSave.Request request(Id claimId, String form) {
        XpEditorDocsAfterSave.Request request = new XpEditorDocsAfterSave.Request();
        request.recordId = claimId;
        request.form = form;
        return request;
    }

    @IsTest
    static void beforeSignatureTheWholePackIsRegenerated() {
        Basic__c claim = claimIn('Agent Check');

        Test.startTest();
        XpEditorDocsAfterSave.afterSave(new List<XpEditorDocsAfterSave.Request>{ request(claim.Id, 'IPC1394') });
        System.assertEquals(1, Limits.getQueueableJobs(), 'An edit before signing must regenerate the whole pack');
        System.assertEquals(0, Limits.getFutureCalls(), 'The single-form generation is replaced by the pack');
        Test.stopTest();
    }

    @IsTest
    static void bothEditorsAndTheTriggerQueueThePackOnce() {
        Basic__c claim = claimIn('Pending Client');

        Test.startTest();
        System.assert(BasicTriggerHandler.queuePackRegeneration(claim.Id));
        XpEditorDocsAfterSave.afterSave(new List<XpEditorDocsAfterSave.Request>{
            request(claim.Id, 'BR1'), request(claim.Id, 'IPC1394')
        });
        System.assertEquals(1, Limits.getQueueableJobs(), 'One regeneration per claim and transaction');
        System.assertEquals(0, Limits.getFutureCalls());
        Test.stopTest();
    }

    @IsTest
    static void otherStatusesKeepTheirOwnForm() {
        Basic__c claim = claimIn('Signed - Waiting Docs at WDM');

        Test.startTest();
        XpEditorDocsAfterSave.afterSave(new List<XpEditorDocsAfterSave.Request>{ request(claim.Id, 'IPC1394') });
        XpEditorDocsAfterSave.afterSave(new List<XpEditorDocsAfterSave.Request>{ request(claim.Id, 'BR1') });
        System.assertEquals(0, Limits.getQueueableJobs());
        System.assertEquals(2, Limits.getFutureCalls(), 'After signing each editor regenerates its own form');
        Test.stopTest();
    }

    private static BasicTriggerHandler handlerFor(Basic__c before, Basic__c after) {
        return new BasicTriggerHandler(
            new List<Basic__c>{ after },
            new Map<Id, Basic__c>{ after.Id => after },
            new Map<Id, Basic__c>{ before.Id => before }
        );
    }

    @IsTest
    static void detailsEditBeforeSignatureRegeneratesThePack() {
        Basic__c claim = new Basic__c(Status__c = 'Agent Check', First_Name__c = 'John');
        insert claim;
        Basic__c edited = new Basic__c(Id = claim.Id, Status__c = 'Agent Check', First_Name__c = 'Johnny');

        Test.startTest();
        handlerFor(claim, edited).regeneratePackOnSourceChange();
        System.assertEquals(1, Limits.getQueueableJobs(), 'Agent Check, QC Approved and Pending Client behave like Form completed');
        Test.stopTest();
    }

    @IsTest
    static void theClientsOwnFormDoesNotRegenerateOnEveryAutosave() {
        Basic__c claim = new Basic__c(Status__c = 'Pending Client', First_Name__c = 'John');
        insert claim;
        Basic__c edited = new Basic__c(Id = claim.Id, Status__c = 'Pending Client', First_Name__c = 'Johnny');
        RestContext.request = new RestRequest();

        Test.startTest();
        handlerFor(claim, edited).regeneratePackOnSourceChange();
        System.assertEquals(0, Limits.getQueueableJobs(), 'The portal regenerates the pack on its last step');
        Test.stopTest();
    }

    @IsTest
    static void statusChangeAloneDoesNotRegenerate() {
        Basic__c claim = new Basic__c(Status__c = 'Pending Client', First_Name__c = 'John');
        insert claim;
        Basic__c moved = new Basic__c(Id = claim.Id, Status__c = 'Agent Check', First_Name__c = 'John');

        Test.startTest();
        handlerFor(claim, moved).regeneratePackOnSourceChange();
        System.assertEquals(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void everyCountryPrintsLivedWorkedAndPaidSocialSecurity() {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];
        delete [SELECT Id FROM Claimant_Country_lived__c WHERE Basic__c = :claim.Id];
        insert new List<Claimant_Country_lived__c>{
            new Claimant_Country_lived__c(Basic__c = claim.Id, Name = 'Ireland', From_date__c = Date.newInstance(1980, 1, 1),
                Is_Live_Here_Now__c = true, Social_Security_Number__c = '1234567T'),
            new Claimant_Country_lived__c(Basic__c = claim.Id, Name = 'Australia', From_date__c = Date.newInstance(1965, 1, 1),
                To_Date__c = Date.newInstance(1979, 12, 31), Is_Live_Here_Now__c = false, Social_Security_Number__c = 'TFN1'),
            new Claimant_Country_lived__c(Basic__c = claim.Id, Name = 'France', From_date__c = Date.newInstance(1960, 1, 1),
                To_Date__c = Date.newInstance(1964, 12, 31), Is_Live_Here_Now__c = false)
        };

        BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(claim.Id)[0]);

        // the order of the rows is the wrapper's; whichever country is first or second, both print Lived + Worked + Q58/Q62 Yes
        System.assertEquals(true, w.q55a);
        System.assertEquals(true, w.q55b);
        System.assertEquals(true, w.q58_yes);
        System.assertEquals(false, w.q58_no);
        System.assertEquals(true, w.q59a);
        System.assertEquals(true, w.q59b);
        System.assertEquals(true, w.q62_yes);
        System.assertEquals(false, w.q62_no);
        System.assert(w.q64.contains('Lived and worked, Did you pay into the social security system of that country? - Yes'));
        System.assert(!w.q64.contains('social security system of that country? - No'));
    }

    @IsTest
    static void bsbTypedWithoutTheDashIsSplitThreeAndThree() {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];
        update new Basic__c(Id = claim.Id, Bank_Country_Code__c = 'AU', Bank_Sort_Code__c = '062000');
        BP_IPC1394_Wrapper.ApplicationDataWrapper wrap =
            new BP_IPC1394_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(claim.Id)[0]);
        System.assertEquals('062', wrap.Q17a);
        System.assertEquals('000', wrap.Q17b);

        update new Basic__c(Id = claim.Id, Bank_Sort_Code__c = '062-001');
        wrap = new BP_IPC1394_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(claim.Id)[0]);
        System.assertEquals('062', wrap.Q17a);
        System.assertEquals('001', wrap.Q17b);
    }
}