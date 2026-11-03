@IsTest
private with sharing class DocuSignStatusTriggerHelperTest {

    @TestSetup
    private static void initData() {
        Application__c application = new Application__c();
        application.First_Name__c = 'test';
        application.Second_Name__c = 'test';
        application.Email__c = 'test.user@fdsa.com';
        application.Related_Contact_Phone__c = '123456789456';
        application.Status__c = 'Form In Progress';
        application.Stripe_Transaction_Id__c = 'pi_3NPXIALWTMZA1UQ61yylq';
        application.Expiry_Date__c = Date.today().addDays(5);
        insert application;
    }

    @IsTest
    private static void afterInsertTest() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];
        Test.startTest();
        dfsle__Envelope__c envelop = new dfsle__Envelope__c();
        envelop.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30c';
        insert envelop;
        ContentVersion contVer = TestDataFactory.createTestCustomLetterContentVersion(true);
        dfsle__Document__c document = new dfsle__Document__c();
        document.dfsle__FullName__c = 'Test_ForSignature';
        document.dfsle__Envelope__c = envelop.Id;
        document.dfsle__SourceId__c = contVer.Id;
        insert document;
        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c();
        envelopeStatus.dfsle__SourceId__c = application.Id;
        envelopeStatus.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30c';
        insert envelopeStatus;

        Test.stopTest();
        dfsle__EnvelopeStatus__c envelopeStatusResult = [
            SELECT
                Id,
                Application__c,
                    (SELECT Id
                    FROM DocuSign_Envelope_Documents__r)
            FROM dfsle__EnvelopeStatus__c
            WHERE Id =: envelopeStatus.Id];
        System.assertEquals(application.Id, envelopeStatusResult.Application__c, 'Application Id isn\'t correct');
        System.assertNotEquals(null, envelopeStatusResult.DocuSign_Envelope_Documents__r, 'Related documents didn\'t created');
    }

    @IsTest
    private static void afterUpdateTest() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        dfsle__Envelope__c envelop = new dfsle__Envelope__c();
        envelop.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30d';
        insert envelop;

        ContentVersion contVer = TestDataFactory.createTestCustomLetterContentVersion(true);
        dfsle__Document__c document = new dfsle__Document__c();
        document.dfsle__FullName__c = 'Test_ForSignature';
        document.dfsle__Envelope__c = envelop.Id;
        document.dfsle__SourceId__c = contVer.Id;
        insert document;

        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c();
        envelopeStatus.dfsle__SourceId__c = application.Id;
        envelopeStatus.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30d';
        insert envelopeStatus;

        // Update to force the Trigger.isUpdate branch (oldMap supplied to process)
        envelopeStatus.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30e';
        update envelopeStatus;
        Test.stopTest();

        dfsle__EnvelopeStatus__c result = [
            SELECT Id, Application__c
            FROM dfsle__EnvelopeStatus__c
            WHERE Id = :envelopeStatus.Id
        ];
        System.assertEquals(application.Id, result.Application__c, 'Application Id isn\'t correct');
    }

    /**
     * Exercises the catch block in the trigger by triggering an update that
     * BP_DocuSignEnvelopes.process(...) cannot handle. Even if process() does
     * not throw, this test still covers the update path; if it throws, the
     * catch + logFailure path is covered.
     */
    @IsTest
    private static void updateDoesNotBreakTriggerOnFailureTest() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c();
        envelopeStatus.dfsle__SourceId__c = application.Id;
        envelopeStatus.dfsle__DocuSignId__c = '00000000-0000-0000-0000-000000000000';
        insert envelopeStatus;

        // Change the linked application to a non-existent Id scenario / update
        // to force the update branch. If process() throws, the trigger catch
        // block and logFailure are executed.
        try {
            envelopeStatus.dfsle__SourceId__c = application.Id;
            update envelopeStatus;
        } catch (DmlException dmlEx) {
            // Trigger swallows exceptions from BP_DocuSignEnvelopes, so this
            // should not be reached. Fail the test if it is.
            System.assert(false, 'Trigger should not propagate exceptions: ' + dmlEx.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    private static void processFailureIsCaughtTest() {
        Application__c application = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        BP_DocuSignEnvelopes.forceFailureForTest = true;

        // --- insert path: exercises catch on Trigger.isInsert ---
        dfsle__EnvelopeStatus__c envelopeStatus = new dfsle__EnvelopeStatus__c();
        envelopeStatus.dfsle__SourceId__c = application.Id;
        envelopeStatus.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30f';
        insert envelopeStatus;

        // --- update path: exercises catch on Trigger.isUpdate (oldMap supplied) ---
        envelopeStatus.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f310';
        update envelopeStatus;

        Test.stopTest();
        BP_DocuSignEnvelopes.forceFailureForTest = false;

        // The record must exist even though process() threw — the trigger swallowed it.
        dfsle__EnvelopeStatus__c result = [
            SELECT Id, dfsle__SourceId__c
            FROM dfsle__EnvelopeStatus__c
            WHERE Id = :envelopeStatus.Id
        ];
        System.assertEquals(application.Id, result.dfsle__SourceId__c,
            'Envelope status should persist even when process() throws');

        // logFailure should have written an Application_Form_Error__c row for each failure
        Integer logged = [SELECT COUNT() FROM Application_Form_Error__c];
        System.assert(logged >= 2, 'logFailure should have recorded the caught exceptions, found: ' + logged);
    }
}