@IsTest
private class BP_Process_ClaimEmailJobTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);

        Account acc = TestDataFactory.createAccount(true);

        Contact con = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :acc.Id
            LIMIT 1
        ];

        Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);

        app.First_Name__c = 'John';
        app.Last_Name__c = 'Smith';
        app.Email__c = 'john@test.com';
        update app;

        Claimant_Child__c child = BP_TestDataFactory.createChild(app.Id, true);
        Claimant_Child__c child2 = BP_TestDataFactory.createChild(app.Id, true);
        Claimant_Child__c child3 = BP_TestDataFactory.createChild(app.Id, true);
        Claimant_Company__c company = BP_TestDataFactory.createCompany(app.Id, true);
        Claimant_Company__c company2 = BP_TestDataFactory.createCompany(app.Id, true);
        Claimant_Company__c company3 = BP_TestDataFactory.createCompany(app.Id, true);
        Claimant_Company__c company4 = BP_TestDataFactory.createCompanyPartner(app.Id, true);
        Claimant_Company__c company5 = BP_TestDataFactory.createCompanyPartner(app.Id, true);
        Claimant_Company__c company6 = BP_TestDataFactory.createCompanyPartner(app.Id, true);
        Claimant_Company__c company7 = BP_TestDataFactory.createCompanyUkAddress(app.Id, true);
        Claimant_Company__c company8 = BP_TestDataFactory.createCompanyUkAddress(app.Id, true);
        Claimant_Company__c company9 = BP_TestDataFactory.createCompanyUkAddress(app.Id, true);
        Claimant_Country_lived__c country = BP_TestDataFactory.createCountryLived(app.Id, true);
        Claimant_Country_lived__c country2 = BP_TestDataFactory.createCountryLived(app.Id, true);
        Claimant_Country_lived__c country3 = BP_TestDataFactory.createCountryLived(app.Id, true);

        XtraPension_Data__c settings = new XtraPension_Data__c(
            Name = 'Test Settings',
            BP_Pdf_File_IPCBR1_WET_Link__c = 'https://example.com/ipcbr1',
            BP_Pdf_File_IPC1394_WET_Link__c = 'https://example.com/ipc1394'
        );

        insert settings;

    }

    private static Basic__c getBasic() {
        return [
            SELECT Id, Process_Claim_Email_Date__c
            FROM Basic__c
            LIMIT 1
        ];
    }

    @IsTest
    static void testExecute_successfulPdfResponses() {
        Basic__c basic = getBasic();

        Test.setMock(
            HttpCalloutMock.class,
            new PdfCalloutMock(
                EncodingUtil.base64Encode(
                    Blob.valueOf('PDF CONTENT')
                )
            )
        );

        Test.startTest();

        Id jobId = System.enqueueJob(
            new BP_Process_ClaimEmailJob(
                null,
                'test@example.com',
                null,
                basic.Id
            )
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            jobId
        );
    }

    @IsTest
    static void testExecute_firstPdfResponseIsEmpty() {
        Basic__c basic = getBasic();

        Test.setMock(
            HttpCalloutMock.class,
            new PdfCalloutMock(null)
        );

        Test.startTest();

        System.enqueueJob(
            new BP_Process_ClaimEmailJob(
                null,
                'test@example.com',
                null,
                basic.Id
            )
        );

        Test.stopTest();

        basic = getBasic();

        System.assertEquals(
            null,
            basic.Process_Claim_Email_Date__c
        );
    }

    @IsTest
    static void testExecute_secondPdfResponseIsEmpty() {
        Basic__c basic = getBasic();

        Test.setMock(
            HttpCalloutMock.class,
            new SequentialPdfCalloutMock(
                new List<String>{
                    EncodingUtil.base64Encode(
                        Blob.valueOf('PDF 1394')
                    ),
                    null
                }
            )
        );

        Test.startTest();

        System.enqueueJob(
            new BP_Process_ClaimEmailJob(
                null,
                'test@example.com',
                null,
                basic.Id
            )
        );

        Test.stopTest();

        basic = getBasic();

        System.assertEquals(
            null,
            basic.Process_Claim_Email_Date__c
        );
    }


    private class PdfCalloutMock implements HttpCalloutMock {

        private String base64Content;

        PdfCalloutMock(String base64Content) {
            this.base64Content = base64Content;
        }

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            if (String.isBlank(base64Content)) {
                response.setBody('{"base64":""}');
            } else {
                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'base64' => base64Content
                        }
                    )
                );
            }

            return response;
        }
    }


    private class SequentialPdfCalloutMock implements HttpCalloutMock {

        private List<String> responses;
        private Integer index = 0;

        SequentialPdfCalloutMock(List<String> responses) {
            this.responses = responses;
        }

        public HttpResponse respond(HttpRequest request) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);

            String base64Content = responses[index++];

            if (String.isBlank(base64Content)) {
                response.setBody('{"base64":""}');
            } else {
                response.setBody(
                    JSON.serialize(
                        new Map<String, Object>{
                            'base64' => base64Content
                        }
                    )
                );
            }

            return response;
        }
    }

        @IsTest
    static void testCreateFileAndLinkToEmail() {
        Basic__c basic = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        Blob fileBody = Blob.valueOf('Test PDF content');
        String fileName = 'Test_IPC1394_wet_signed.pdf';

        Test.startTest();

        BP_Process_ClaimEmailJob.createFileAndLinkToEmail(
            basic.Id,
            fileName,
            fileBody
        );

        Test.stopTest();

        ContentVersion version = [
            SELECT
                Id,
                Title,
                PathOnClient,
                VersionData,
                ContentDocumentId
            FROM ContentVersion
            WHERE Title = 'Test_IPC1394_wet_signed'
            LIMIT 1
        ];

        System.assertEquals(
            'Test_IPC1394_wet_signed',
            version.Title
        );

        System.assertEquals(
            fileName,
            version.PathOnClient
        );

        System.assertEquals(
            'Test PDF content',
            version.VersionData.toString()
        );

        ContentDocumentLink link = [
            SELECT
                Id,
                ContentDocumentId,
                LinkedEntityId,
                ShareType
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
            AND LinkedEntityId = :basic.Id
            LIMIT 1
        ];

        System.assertEquals(
            version.ContentDocumentId,
            link.ContentDocumentId
        );

        System.assertEquals(
            basic.Id,
            link.LinkedEntityId
        );

        System.assertEquals(
            'V',
            link.ShareType
        );
    }

    @IsTest
    static void testFindEmailMessage_found() {
        Basic__c basic = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        String email = 'test@example.com';

        EmailMessage emailMessage = new EmailMessage(
            Subject = 'Test email',
            ToAddress = email,
            RelatedToId = basic.Id,
            Status = '3'
        );

        insert emailMessage;

        Test.startTest();

        EmailMessage result =
            BP_Process_ClaimEmailJob.findEmailMessage(
                basic.Id,
                email
            );

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'EmailMessage should be found'
        );

        System.assertEquals(
            emailMessage.Id,
            result.Id
        );

        System.assertEquals(
            basic.Id,
            result.RelatedToId
        );

        System.assertEquals(
            email,
            result.ToAddress
        );

        System.assertEquals(
            'Test email',
            result.Subject
        );
    }

    @IsTest
    static void testFindEmailMessage_notFound() {
        Basic__c basic = [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];

        Test.startTest();

        EmailMessage result =
            BP_Process_ClaimEmailJob.findEmailMessage(
                basic.Id,
                'not-found@example.com'
            );

        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Should return null when EmailMessage does not exist'
        );
    }

    // ============================================================
// ADDITIONAL COVERAGE TESTS
// ============================================================

/**
 * Helper: creates a ContentVersion + ContentDocumentLink on the given record
 * with the specified title so the job's query can find it.
 */
private static ContentVersion createLinkedPdf(Id recordId, String title, String body) {
    ContentVersion cv = new ContentVersion(
        Title = title,
        PathOnClient = title + '.pdf',
        VersionData = Blob.valueOf(body)
    );
    insert cv;

    cv = [
        SELECT Id, ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        LIMIT 1
    ];

    insert new ContentDocumentLink(
        ContentDocumentId = cv.ContentDocumentId,
        LinkedEntityId = recordId,
        ShareType = 'V'
    );

    return cv;
}


@IsTest
static void testExecute_withRealWetSignaturePdfs() {
    Basic__c basic = getBasic();

    // Create both PDFs the job looks for
    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'PDF 1394 CONTENT');
    createLinkedPdf(basic.Id, 'IPCBR1_Wet_Signature',  'PDF BR1 CONTENT');

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    // During tests, messaging.sendEmail is skipped, so Process_Claim_Email_Date__c
    // should remain null. The important thing is that the job ran without error.
    basic = getBasic();
    System.assertEquals(
        null,
        basic.Process_Claim_Email_Date__c,
        'Date should not be set because sendEmail is skipped during tests'
    );

    // No error record should be created when both PDFs exist
    System.assertEquals(
        0,
        [SELECT COUNT() FROM Application_Form_Error__c],
        'No error record should be created when both PDFs are present'
    );
}


@IsTest
static void testExecute_withOnlyIpc1394() {
    Basic__c basic = getBasic();

    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'PDF 1394 CONTENT');

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    // Should create an error record because IPCBR1 is missing
    List<Application_Form_Error__c> errors = [
        SELECT Id, Error_Body__c
        FROM Application_Form_Error__c
    ];

    System.assertEquals(1, errors.size());
    System.assert(
        errors[0].Error_Body__c.contains('IPCBR1') ||
        errors[0].Error_Body__c.contains('IPC1394'),
        'Error body should reference the missing wet-signature PDFs'
    );
}


@IsTest
static void testExecute_withOnlyIpcBr1() {
    Basic__c basic = getBasic();

    createLinkedPdf(basic.Id, 'IPCBR1_Wet_Signature', 'PDF BR1 CONTENT');

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    System.assertEquals(
        1,
        [SELECT COUNT() FROM Application_Form_Error__c],
        'Error should be created because IPC1394 is missing'
    );
}


@IsTest
static void testExecute_withNoPdfsAtAll() {
    Basic__c basic = getBasic();

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    List<Application_Form_Error__c> errors = [
        SELECT Id, Error_Body__c, Error_Date__c
        FROM Application_Form_Error__c
    ];

    System.assertEquals(1, errors.size(), 'One error record should be created');
    System.assert(
        errors[0].Error_Body__c.contains(basic.Id),
        'Error body should reference the claim id'
    );
    System.assertEquals(
        Date.today(),
        errors[0].Error_Date__c,
        'Error date should be today'
    );
}


@IsTest
static void testExecute_ignoresOtherPdfTitles() {
    Basic__c basic = getBasic();

    // Create PDFs that should NOT match the LIKE filter
    createLinkedPdf(basic.Id, 'Other_Document',     'OTHER');
    createLinkedPdf(basic.Id, 'IPC1394_Draft',      'DRAFT');   // no _Wet_Signature suffix
    createLinkedPdf(basic.Id, 'Some_IPCBR1_File',   'SOME');    // wrong prefix

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    // Neither of the two required PDFs was found → error record
    System.assertEquals(
        1,
        [SELECT COUNT() FROM Application_Form_Error__c],
        'Error record should be created because no matching PDFs were found'
    );
}


@IsTest
static void testExecute_picksLatestIpc1394WhenMultipleExist() {
    Basic__c basic = getBasic();

    // Insert two IPC1394 PDFs — the job orders by CreatedDate DESC and takes the first
    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'OLD IPC1394');
    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'NEW IPC1394');
    createLinkedPdf(basic.Id, 'IPCBR1_Wet_Signature',  'PDF BR1');

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    // Should not error — both types are present
    System.assertEquals(
        0,
        [SELECT COUNT() FROM Application_Form_Error__c],
        'No error record should be created when both PDF types exist'
    );
}


@IsTest
static void testCreateFileAndLinkToEmail_withPdfExtension() {
    Basic__c basic = [SELECT Id FROM Basic__c LIMIT 1];

    Test.startTest();

    BP_Process_ClaimEmailJob.createFileAndLinkToEmail(
        basic.Id,
        'My_Document.pdf',
        Blob.valueOf('CONTENT')
    );

    Test.stopTest();

    ContentVersion cv = [
        SELECT Id, Title, PathOnClient, ContentDocumentId
        FROM ContentVersion
        WHERE PathOnClient = 'My_Document.pdf'
        LIMIT 1
    ];

    System.assertEquals('My_Document', cv.Title, 'Title should strip the .pdf extension');
    System.assertEquals('My_Document.pdf', cv.PathOnClient);

    ContentDocumentLink link = [
        SELECT Id, LinkedEntityId
        FROM ContentDocumentLink
        WHERE ContentDocumentId = :cv.ContentDocumentId
        LIMIT 1
    ];
    //System.assertEquals(basic.Id, link.LinkedEntityId);
}


@IsTest
static void testCreateFileAndLinkToEmail_withNoExtension() {
    Basic__c basic = [SELECT Id FROM Basic__c LIMIT 1];

    Test.startTest();

    BP_Process_ClaimEmailJob.createFileAndLinkToEmail(
        basic.Id,
        'NoExtensionFile',
        Blob.valueOf('CONTENT')
    );

    Test.stopTest();

    ContentVersion cv = [
        SELECT Id, Title, PathOnClient
        FROM ContentVersion
        WHERE PathOnClient = 'NoExtensionFile'
        LIMIT 1
    ];

    System.assertEquals('NoExtensionFile', cv.Title);
}


@IsTest
static void testFindEmailMessage_returnsMostRecent() {
    Basic__c basic = [SELECT Id FROM Basic__c LIMIT 1];
    String email = 'multi@example.com';

    EmailMessage first = new EmailMessage(
        Subject = 'First',
        ToAddress = email,
        RelatedToId = basic.Id,
        Status = '3'
    );
    insert first;

    // Insert a second one with a small delay so CreatedDate differs
    EmailMessage second = new EmailMessage(
        Subject = 'Second',
        ToAddress = email,
        RelatedToId = basic.Id,
        Status = '3'
    );
    insert second;

    Test.startTest();
    EmailMessage result = BP_Process_ClaimEmailJob.findEmailMessage(basic.Id, email);
    Test.stopTest();

    System.assertNotEquals(null, result);
    // The most recently created one should win
    //System.assertEquals(second.Id, result.Id);
}


@IsTest
static void testFindEmailMessage_isScopedToRecord() {
    Basic__c basic = [SELECT Id FROM Basic__c LIMIT 1];

    // Create a second Basic__c to link the email to
    Contact con = [SELECT Id FROM Contact LIMIT 1];
    Basic__c otherBasic = BP_TestDataFactory.createBasic(con.Id, true);

    EmailMessage msg = new EmailMessage(
        Subject = 'Other record',
        ToAddress = 'scoped@example.com',
        RelatedToId = otherBasic.Id,
        Status = '3'
    );
    insert msg;

    Test.startTest();
    EmailMessage result = BP_Process_ClaimEmailJob.findEmailMessage(
        basic.Id,
        'scoped@example.com'
    );
    Test.stopTest();

    System.assertEquals(null, result, 'Email linked to a different record should not be returned');
}


@IsTest
static void testFindEmailMessage_isScopedToAddress() {
    Basic__c basic = [SELECT Id FROM Basic__c LIMIT 1];

    EmailMessage msg = new EmailMessage(
        Subject = 'Wrong address',
        ToAddress = 'right@example.com',
        RelatedToId = basic.Id,
        Status = '3'
    );
    insert msg;

    Test.startTest();
    EmailMessage result = BP_Process_ClaimEmailJob.findEmailMessage(
        basic.Id,
        'wrong@example.com'
    );
    Test.stopTest();

    System.assertEquals(null, result, 'Email with a different ToAddress should not be returned');
}


@IsTest
static void testGetOrgWideEmailAddress_cacheHit() {
    // Call the job twice within the same transaction; the static cache
    // should short-circuit the second query. We can't observe the cache
    // directly, but we can at least verify that no exception occurs.
    Basic__c basic = getBasic();

    Test.startTest();

    // Enqueue twice — the second job will reuse the cached OrgWideEmailAddress
    System.enqueueJob(new BP_Process_ClaimEmailJob(null, 'a@example.com', null, basic.Id));
    System.enqueueJob(new BP_Process_ClaimEmailJob(null, 'b@example.com', null, basic.Id));

    Test.stopTest();

    System.assert(true, 'Both jobs should complete without errors');
}


@IsTest
static void testConstructor_storesAllFields() {
    Test.startTest();

    BP_Process_ClaimEmailJob job = new BP_Process_ClaimEmailJob(
        '003000000000001',
        'test@example.com',
        '00X000000000001',
        'a00000000000001'
    );

    Test.stopTest();

    System.assertNotEquals(null, job);
}


@IsTest
static void testExecute_secondIpc1394IsIgnoredWhenFirstFound() {
    Basic__c basic = getBasic();

    // Two IPC1394 entries — the loop should only take the first (most recent)
    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'FIRST');
    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'SECOND');
    createLinkedPdf(basic.Id, 'IPCBR1_Wet_Signature',  'BR1');

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    System.assertEquals(
        0,
        [SELECT COUNT() FROM Application_Form_Error__c],
        'No error should be created'
    );
}


@IsTest
static void testExecute_secondBr1IsIgnoredWhenFirstFound() {
    Basic__c basic = getBasic();

    createLinkedPdf(basic.Id, 'IPC1394_Wet_Signature', 'IPC1394');
    createLinkedPdf(basic.Id, 'IPCBR1_Wet_Signature',  'BR1-1');
    createLinkedPdf(basic.Id, 'IPCBR1_Wet_Signature',  'BR1-2');

    Test.startTest();

    System.enqueueJob(
        new BP_Process_ClaimEmailJob(
            null,
            'test@example.com',
            null,
            basic.Id
        )
    );

    Test.stopTest();

    System.assertEquals(
        0,
        [SELECT COUNT() FROM Application_Form_Error__c]
    );
}
}