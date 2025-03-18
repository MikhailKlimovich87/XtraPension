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
            System.assertNotEquals(null, wrapper.envelop, 'Result envelop must be not null');
            System.assertEquals(null, wrapper.errorMessage, 'Result envelop must be not null');
            System.assertEquals(true, wrapper.isSuccess, 'Result isSuccess checkbos must be true');
        }
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
}