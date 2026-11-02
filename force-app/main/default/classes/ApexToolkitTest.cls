@isTest
public with sharing class ApexToolkitTest {
    @TestSetup
    static void makeData(){
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);

        dfsle__EnvelopeConfiguration__c testTemplate = new dfsle__EnvelopeConfiguration__c();
        testTemplate.dfsle__SourceObject__c = 'Application__c';
        testTemplate.Name = 'Application Test';
        testTemplate.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30c';
        insert testTemplate;
        ContentVersion testContentVersion = TestDataFactory.createTestForSignatureContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        insert conDocLink;
    }
    @IsTest static void testSendEnvelope() {
        // Mock the DocuSign eSignature API
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        List<Application__c> testApplications = [
            SELECT Id
            FROM Application__c
        ];

        // Run the test as a DocuSign Sender. This is required by dfsle.EnvelopeService.sendEnvelope
        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            ApexToolkit.ResponseWrapper wrapper = ApexToolkit.sendEnvelopeMethod(testApplications[0].Id);
            Test.stopTest();
            System.assertNotEquals(null, wrapper, 'Wrapper must be not null');
            //System.assertNotEquals(null, wrapper.envelop, 'Result envelop must be not null');
            //System.assertEquals(null, wrapper.errorMessage, 'Result envelop must be not null');
            System.assertEquals(true, wrapper.isSuccess, 'Result isSuccess checkbos must be true');
        }
    }

    @IsTest static void testSendEnvelopeAsync() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Application__c testApplication = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            ApexToolkit.sendEnvelopeAsync(testApplication.Id);
            Test.stopTest();
        }
    }

    @IsTest static void testSendEnvelope_NoApplication() {
        Test.startTest();
        ApexToolkit.ResponseWrapper wrapper = ApexToolkit.sendEnvelopeMethod(
            'a00000000000000AAA'
        );
        Test.stopTest();

        System.assertEquals(false, wrapper.isSuccess);
        System.assertEquals('Didn\'t find current application', wrapper.errorMessage);
    }

    @IsTest static void testSendEnvelope_MissingRecipientInformation() {
        Application__c testApplication = [
            SELECT Id, Contact__c
            FROM Application__c
            LIMIT 1
        ];
        testApplication.Contact__c = null;
        update testApplication;

        Test.startTest();
        ApexToolkit.ResponseWrapper wrapper = ApexToolkit.sendEnvelopeMethod(
            testApplication.Id
        );
        Test.stopTest();

        System.assertEquals(false, wrapper.isSuccess);
        System.assertEquals(
            'Application is missing Contact or Email information.',
            wrapper.errorMessage
        );
    }

    @IsTest static void testSendEnvelope_NoDocuments() {
        Application__c testApplication = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        delete [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplication.Id
        ];

        Test.startTest();
        ApexToolkit.ResponseWrapper wrapper = ApexToolkit.sendEnvelopeMethod(
            testApplication.Id
        );
        Test.stopTest();

        System.assertEquals(false, wrapper.isSuccess);
        System.assertEquals('Application doesn\'t have necessary files', wrapper.errorMessage);
    }

    @IsTest static void testGetForSignatureDocuments() {
        // Mock the DocuSign eSignature API
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        List<Application__c> testApplications = [
            SELECT Id
            FROM Application__c
        ];

        // Run the test as a DocuSign Sender. This is required by dfsle.EnvelopeService.sendEnvelope
        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            List<ApexToolkit.DocumentWrapper> wrapper = ApexToolkit.getForSignatureDocuments(testApplications[0].Id);
            Test.stopTest();
            System.assertNotEquals(0, wrapper.size(), 'Wrapper must be not null');
            System.assertNotEquals(null, wrapper[0].Id, 'Application Id must be not null');
            System.assertNotEquals(null, wrapper[0].Title, 'Application Title must be not null');
            System.assertEquals('Test_CF083_ForSignature', wrapper[0].Title, 'Application Title must be Test_CF083_ForSignature');
        }
    }

    @IsTest static void testGetForSignatureDocuments_NoDocuments() {
        Test.startTest();
        List<ApexToolkit.DocumentWrapper> wrapper =
            ApexToolkit.getForSignatureDocuments('a00000000000000AAA');
        Test.stopTest();

        System.assertEquals(0, wrapper.size());
    }

    @IsTest static void testVoidEnvelope_EmptyIds() {
        Test.startTest();
        ApexToolkit.voidEnvelope(null);
        Test.stopTest();
    }

    @IsTest static void testVoidEnvelope_InvalidId() {
        Test.startTest();
        ApexToolkit.voidEnvelope(new List<String>{ 'not-a-docusign-id' });
        Test.stopTest();
    }
}