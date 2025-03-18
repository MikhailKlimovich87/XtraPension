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
}