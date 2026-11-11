@IsTest
public with sharing class BP_ClientSummaryPdfServiceTest {

    @TestSetup
    static void setup() {
        Basic__c basic = new Basic__c(
            First_Name__c = 'John',
            Last_Name__c = 'Smith'
        );
        insert basic;

        insert new XtraPension_Data__c(
            BP_Pdf_File_Link__c = 'test',
            BP_Pdf_File_IPC1394_Link__c = 'test',
            BP_PDF_IPCBR1_Wet__c = 'test',
            BP_PDF_IPC1394_Wet__c = 'test',
            BR_X_Api_Key__c = 'test'
        );
    }

    private static Basic__c getBasic() {
        return [
            SELECT Id, Name, First_Name__c, Last_Name__c
            FROM Basic__c
            LIMIT 1
        ];
    }


    private static void createDocument(Basic__c basic, String title) {

        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('TEST')
        );
        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        insert new ContentDocumentLink(
            LinkedEntityId = basic.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    @IsTest
    static void testGeneratePdf_NewDocument() {

        Basic__c basic = getBasic();

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generatePdf(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGeneratePdf_UpdateExisting() {

        Basic__c basic = getBasic();

        createDocument(basic, 'Client Summary');

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generatePdf(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGeneratePdf_UpdateExistingDocumentAsViewer() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        User agent = new User(
            Alias = 'agent',
            Email = 'agent@example.test',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Agent',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'agent.' + UserInfo.getUserId() + '@example.test'
        );
        insert agent;

        Basic__c basic;
        System.runAs(agent) {
            basic = new Basic__c(
                First_Name__c = 'Agent',
                Last_Name__c = 'Claim'
            );
            insert basic;
        }

        createDocument(basic, 'Client Summary');
        ContentDocumentLink documentLink = [
            SELECT ContentDocumentId, ShareType, ContentDocument.OwnerId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :basic.Id
            LIMIT 1
        ];
        System.assertEquals('V', documentLink.ShareType);
        System.assertNotEquals(agent.Id, documentLink.ContentDocument.OwnerId);
        Id existingDocumentId = documentLink.ContentDocumentId;
        Integer originalVersionCount = [
            SELECT Count()
            FROM ContentVersion
            WHERE ContentDocumentId = :existingDocumentId
        ];

        Test.startTest();
        Id resultDocumentId;
        System.runAs(agent) {
            resultDocumentId = BP_ClientSummaryPdfService.generatePdf(basic.Id);

            List<ContentDocumentLink> visibleDocuments = [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :basic.Id
            ];
            BP_GeneratePdfFileController.updateDocumentVersion(
                JSON.serialize(new Map<String, Object>{
                    'base64' => EncodingUtil.base64Encode(Blob.valueOf('FORM PDF'))
                }),
                'Client Summary',
                'pdf',
                visibleDocuments
            );
        }
        Test.stopTest();

        System.assertEquals(existingDocumentId, resultDocumentId);
        System.assertEquals(
            originalVersionCount + 2,
            [
                SELECT Count()
                FROM ContentVersion
                WHERE ContentDocumentId = :existingDocumentId
            ],
            'Both regeneration paths should add versions to the existing Viewer-shared file'
        );
    }

    @IsTest
    static void testGeneratePink_NewDocument() {

        Basic__c basic = getBasic();

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generatePink(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGeneratePink_UpdateExisting() {

        Basic__c basic = getBasic();

        createDocument(basic, 'Pink');

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generatePink(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGenerateYellow_NewDocument() {

        Basic__c basic = getBasic();

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generateYellow(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGenerateYellow_UpdateExisting() {

        Basic__c basic = getBasic();

        createDocument(basic, 'Yellow');

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generateYellow(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGenerateDWP_NewDocument() {

        Basic__c basic = getBasic();

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generateDWP(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGenerateDWP_UpdateExisting() {

        Basic__c basic = getBasic();

        createDocument(basic, 'DWP_Authority');

        Test.startTest();
        Id docId = BP_ClientSummaryPdfService.generateDWP(basic.Id);
        Test.stopTest();

        System.assertNotEquals(null, docId);
    }

    @IsTest
    static void testGeneratePinkAndYellow() {

        Basic__c basic = getBasic();

        Test.startTest();
        List<Id> ids = BP_ClientSummaryPdfService.generatePinkAndYellow(basic.Id);
        Test.stopTest();

        System.assertEquals(3, ids.size());
        System.assertNotEquals(null, ids[0]);
        System.assertNotEquals(null, ids[1]);
    }

}