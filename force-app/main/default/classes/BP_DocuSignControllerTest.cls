@IsTest
public with sharing class BP_DocuSignControllerTest {

    @TestSetup
    static void setup() {

        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Basic__c testApplication = BP_TestDataFactory.createBasic(personContactId, true);

        dfsle__EnvelopeConfiguration__c testTemplate = new dfsle__EnvelopeConfiguration__c();
        testTemplate.dfsle__SourceObject__c = 'Basic__c';
        testTemplate.Name = 'Summary';
        testTemplate.dfsle__DocuSignId__c = '49b7d84b-478c-4eec-b53d-b6237666f30c';
        insert testTemplate;

        ContentVersion summaryContent = new ContentVersion(
            Title = 'Client Summary',
            PathOnClient = 'Client_Summary.pdf',
            VersionData = Blob.valueOf('Test Summary PDF Content'),
            IsMajorVersion = true
        );
        insert summaryContent;

        summaryContent = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :summaryContent.Id
        ];

        ContentDocumentLink summaryLink = new ContentDocumentLink(
            LinkedEntityId = testApplication.Id,
            ContentDocumentId = summaryContent.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert summaryLink;
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    private static Basic__c getBasic() {
        return [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Contact__c,
                   Bank_Account_Owner_Name__c, Bank_Account_Owner_Email__c
            FROM Basic__c
            LIMIT 1
        ];
    }

    /** Attach a ddMandate document to the claim. */
    private static void attachMandateDocument(Id applicationId) {
        ContentVersion mandate = new ContentVersion(
            Title = 'ddMandate',
            PathOnClient = 'ddMandate.pdf',
            VersionData = Blob.valueOf('Test ddMandate PDF Content'),
            IsMajorVersion = true
        );
        insert mandate;

        mandate = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :mandate.Id
        ];

        insert new ContentDocumentLink(
            LinkedEntityId = applicationId,
            ContentDocumentId = mandate.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    /** Attach a Summary document to the claim (in addition to whatever exists). */
    private static void attachSummaryDocument(Id applicationId) {
        ContentVersion summary = new ContentVersion(
            Title = 'Client Summary',
            PathOnClient = 'Client_Summary.pdf',
            VersionData = Blob.valueOf('Another Summary PDF'),
            IsMajorVersion = true
        );
        insert summary;

        summary = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :summary.Id
        ];

        insert new ContentDocumentLink(
            LinkedEntityId = applicationId,
            ContentDocumentId = summary.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    // -------------------------------------------------------------------------
    // Existing tests (kept)
    // -------------------------------------------------------------------------

    @IsTest
    static void testSendEnvelope_NoApplication() {
        Test.startTest();

        BP_DocuSignController.ResponseWrapper result =
            BP_DocuSignController.sendEnvelopeMethod('001000000000000AAA');

        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.errorMessage.contains('Claims not found'));
    }

    @IsTest static void testSendEnvelope() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        List<Basic__c> testApplications = [SELECT Id FROM Basic__c];

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper wrapper =
                BP_DocuSignController.sendEnvelopeMethod(testApplications[0].Id);
            Test.stopTest();

            System.assertNotEquals(null, wrapper, 'Wrapper must be not null');
        }
    }

    @IsTest static void testGetForSignatureDocuments2() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        List<Basic__c> testApplications = [SELECT Id FROM Basic__c];

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            List<BP_DocuSignController.DocumentWrapper> wrapper =
                BP_DocuSignController.getForSignatureDocuments(testApplications[0].Id);
            Test.stopTest();

            System.assertNotEquals(0, wrapper.size(), 'Wrapper must be not null');
            System.assertNotEquals(null, wrapper[0].Title, 'Application Title must be not null');
        }
    }

    // -------------------------------------------------------------------------
    // NEW TESTS
    // -------------------------------------------------------------------------

    /**
     * Applicant email is blank -> early validation error.
     */
    @IsTest
    static void testSendEnvelope_BlankEmail() {
        Basic__c app = getBasic();
        app.Email__c = null;
        update app;

        Test.startTest();
        BP_DocuSignController.ResponseWrapper result =
            BP_DocuSignController.sendEnvelopeMethod(app.Id);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess);
        System.assert(result.errorMessage.containsIgnoreCase('valid email'));
    }

    /**
     * Case B: bank owner blank, both documents exist, applicant signs all.
     * Checks that isSuccess = true and needsSecondEnvelope is NOT set.
     */
    @IsTest
    static void testSendEnvelope_CaseB_Combined() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        BP_DocuSignController.skipMissingInfoCheck = true;

        Basic__c app = getBasic();
        attachMandateDocument(app.Id);

        // Make sure bank owner fields are blank
        app.Bank_Account_Owner_Name__c  = null;
        app.Bank_Account_Owner_Email__c = null;
        update app;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendEnvelopeMethod(app.Id);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess,
                'Case B should send successfully. Error: ' + result.errorMessage);
            System.assertEquals(null, result.needsSecondEnvelope,
                'Case B must not request a second envelope');
        }
    }

    /**
     * Case B with a missing ddMandate -> validation error.
     */
    @IsTest
    static void testSendEnvelope_CaseB_MissingMandate() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        BP_DocuSignController.skipMissingInfoCheck = true;

        Basic__c app = getBasic();
        app.Bank_Account_Owner_Name__c  = null;
        app.Bank_Account_Owner_Email__c = null;
        update app;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendEnvelopeMethod(app.Id);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess);
            System.assert(result.errorMessage.containsIgnoreCase('Summary and a ddMandate'));
        }
    }

    /**
     * Case A: bank owner present, both documents present.
     * Entry point should send ONLY the Summary and set needsSecondEnvelope = true.
     */
    @IsTest
    static void testSendEnvelope_CaseA_SummaryOnly() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        BP_DocuSignController.skipMissingInfoCheck = true;

        Basic__c app = getBasic();
        attachMandateDocument(app.Id);

        app.Bank_Account_Owner_Name__c  = 'John Bank Owner';
        app.Bank_Account_Owner_Email__c = 'bankowner@example.com';
        update app;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendEnvelopeMethod(app.Id);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess,
                'Case A summary send should succeed. Error: ' + result.errorMessage);
            System.assertEquals(true, result.needsSecondEnvelope,
                'Case A must request the second (ddMandate) envelope');
        }
    }

    // @IsTest
    // static void testSendEnvelope_AlreadySigned() {
    //     Basic__c app = getBasic();
    //     update new Basic__c(Id = app.Id, Status__c = BP_DocuSignController.STATUS_SIGNED_WAITING_DOCS);

    //     Test.startTest();
    //     BP_DocuSignController.ResponseWrapper result = BP_DocuSignController.sendEnvelopeMethod(app.Id);
    //     Test.stopTest();

    //     System.assertEquals(false, result.isSuccess);
    //     System.assert(result.errorMessage.containsIgnoreCase('already been signed'));
    // }

    /**
     * sendSummaryEnvelope directly — success path.
     */
    @IsTest
    static void testSendSummaryEnvelope_Success() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        Basic__c app = getBasic();

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendSummaryEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess,
                'Summary envelope should send. Error: ' + result.errorMessage);
        }
    }

    /**
     * sendSummaryEnvelope — no Summary document attached.
     */
    @IsTest
    static void testSendSummaryEnvelope_NoSummaryDoc() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Basic__c app = getBasic();
        // Remove all Summary ContentDocumentLinks
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id
        ];
        delete links;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendSummaryEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess);
            System.assert(result.errorMessage.containsIgnoreCase('No Summary'));
        }
    }

    /**
     * sendMandateEnvelope — success path.
     */
    @IsTest
    static void testSendMandateEnvelope_Success() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Basic__c app = getBasic();
        attachMandateDocument(app.Id);
        app.Bank_Account_Owner_Name__c  = 'John Bank Owner';
        app.Bank_Account_Owner_Email__c = 'bankowner@example.com';
        update app;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendMandateEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess,
                'Mandate envelope should send. Error: ' + result.errorMessage);
        }
    }

    /**
     * sendMandateEnvelope — bank owner missing -> validation error.
     */
    @IsTest
    static void testSendMandateEnvelope_NoBankOwner() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Basic__c app = getBasic();
        app.Bank_Account_Owner_Name__c  = null;
        app.Bank_Account_Owner_Email__c = null;
        update app;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendMandateEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess);
            System.assert(result.errorMessage.containsIgnoreCase('Bank account owner'));
        }
    }

    /**
     * sendMandateEnvelope — no ddMandate document -> validation error.
     */
    @IsTest
    static void testSendMandateEnvelope_NoMandateDoc() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Basic__c app = getBasic();
        app.Bank_Account_Owner_Name__c  = 'John Bank Owner';
        app.Bank_Account_Owner_Email__c = 'bankowner@example.com';
        update app;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendMandateEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess);
            System.assert(result.errorMessage.containsIgnoreCase('No ddMandate'));
        }
    }

    /**
     * sendCombinedEnvelope — success path.
     */
    @IsTest
    static void testSendCombinedEnvelope_Success() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Basic__c app = getBasic();
        attachMandateDocument(app.Id);

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendCombinedEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(true, result.isSuccess,
                'Combined envelope should send. Error: ' + result.errorMessage);
        }
    }

    /**
     * sendCombinedEnvelope — missing one of the two docs -> validation error.
     */
    @IsTest
    static void testSendCombinedEnvelope_MissingMandate() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());
        Basic__c app = getBasic();

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            BP_DocuSignController.ResponseWrapper result =
                BP_DocuSignController.sendCombinedEnvelope(app.Id);
            Test.stopTest();

            System.assertEquals(false, result.isSuccess);
            System.assert(result.errorMessage.containsIgnoreCase('Summary and a ddMandate'));
        }
    }

    /**
     * getForSignatureDocuments — no documents attached.
     */
    @IsTest
    static void testGetForSignatureDocuments_Empty() {
        dfsle.TestUtils.setMock(new dfsle.ESignatureAPIMock());

        Basic__c app = getBasic();
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id
        ];
        delete links;

        System.runAs(dfsle.UserMock.createDocuSignSender()) {
            Test.startTest();
            List<BP_DocuSignController.DocumentWrapper> result =
                BP_DocuSignController.getForSignatureDocuments(app.Id);
            Test.stopTest();

            System.assertEquals(0, result.size());
        }
    }

    /**
     * DocumentWrapper default constructor coverage.
     */
    @IsTest
    static void testDocumentWrapperConstructors() {
        BP_DocuSignController.DocumentWrapper empty = new BP_DocuSignController.DocumentWrapper();
        System.assertEquals(null, empty.Title);

        BP_DocuSignController.DocumentWrapper full =
            new BP_DocuSignController.DocumentWrapper('fakeId', 'fakeTitle');
        System.assertEquals('fakeTitle', full.Title);
    }

    /**
     * ResponseWrapper defaults.
     */
    @IsTest
    static void testResponseWrapperDefaults() {
        BP_DocuSignController.ResponseWrapper w =
            new BP_DocuSignController.ResponseWrapper();
        System.assertEquals(null, w.errorMessage);
        System.assertEquals(null, w.infoMessage);
        System.assertEquals(null, w.envelop);
        System.assertEquals(null, w.additionalEnvelopes);
        System.assertEquals(null, w.isSuccess);
        System.assertEquals(null, w.needsSecondEnvelope);
    }
}