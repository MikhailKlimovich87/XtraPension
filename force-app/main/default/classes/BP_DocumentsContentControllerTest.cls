@IsTest
public with sharing class BP_DocumentsContentControllerTest {

    @TestSetup
    static void setup() {
        Basic__c basic = new Basic__c(
            First_Name__c = 'John',
            Last_Name__c = 'Smith'
        );
        insert basic;
    }

    private static Basic__c getBasic() {
        return [
            SELECT Id
            FROM Basic__c
            LIMIT 1
        ];
    }

    private static void createDocument(Id recordId, String title) {

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
            LinkedEntityId = recordId,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
    }

    @IsTest
    static void testNoDocuments() {

        Basic__c basic = getBasic();

        Test.startTest();
        BP_DocumentsContentController.DocumentsData data =
            BP_DocumentsContentController.getContentDocuments(basic.Id);
        Test.stopTest();

        System.assertEquals(null, data);
    }

    @IsTest
    static void testAllDocumentTypes() {

        Basic__c basic = getBasic();

        createDocument(basic.Id, 'IPCBR1');
        createDocument(basic.Id, 'IPC1394');
        createDocument(basic.Id, 'IPCBR1_Wet_Signature');
        createDocument(basic.Id, 'IPC1394_Wet_Signature');
        createDocument(basic.Id, 'Client Summary');
        createDocument(basic.Id, 'John_Pink');
        createDocument(basic.Id, 'John_Yellow');
        createDocument(basic.Id, 'John_DWP');
        createDocument(basic.Id, 'ENVELOPE_ZIP');
        createDocument(basic.Id, 'CLIENT_FULL_FORM_ZIP');

        Test.startTest();

        BP_DocumentsContentController.DocumentsData data =
            BP_DocumentsContentController.getContentDocuments(basic.Id);

        Test.stopTest();

        System.assertNotEquals(null, data);
        System.assertEquals(10, data.latestDocs.size());


        System.assertEquals('Pink Page', data.latestDocs[0].title);
        System.assertEquals('Yellow Page', data.latestDocs[1].title);
        System.assertEquals('IPCBR1 Full Form', data.latestDocs[2].title);
        System.assertEquals('IPC1394 Full Form', data.latestDocs[3].title);
        System.assertEquals('IPCBR1 Wet', data.latestDocs[4].title);
        System.assertEquals('IPC1394 Wet', data.latestDocs[5].title);
        System.assertEquals('Client Summary', data.latestDocs[6].title);

        for (BP_DocumentsContentController.DocumentInfo info : data.latestDocs) {

            System.assertNotEquals(null, info.documentId);
            System.assertEquals(false, info.isCustomLetter);
            System.assertEquals(false, info.isApplicationForm);
            System.assertEquals(true, info.isAgentAuthorisation);
            System.assertNotEquals(null, info.createdDate);
        }
    }

    @IsTest
    static void testStageZipsAreRecognisedByTheirRealNames() {
        Basic__c basic = getBasic();
        createDocument(basic.Id, 'John_Smith_C00001_Stage 1');
        createDocument(basic.Id, 'John_Smith_C00001_Stage 2');

        BP_DocumentsContentController.DocumentsData data =
            BP_DocumentsContentController.getContentDocuments(basic.Id);

        System.assertEquals(2, data.latestDocs.size());
        Map<String, BP_DocumentsContentController.DocumentInfo> byGroup = new Map<String, BP_DocumentsContentController.DocumentInfo>();
        for (BP_DocumentsContentController.DocumentInfo info : data.latestDocs) {
            byGroup.put(info.redoGroup, info);
        }
        System.assertEquals('BigEnvelope', byGroup.get('ColectBig').typeGroup, 'Stage 1 is the wet-signature pack');
        System.assert(byGroup.get('ColectBig').title.contains('Stage 1'));
        System.assertEquals('FullForms', byGroup.get('ColectFullForm').typeGroup);
        System.assert(byGroup.get('ColectFullForm').title.contains('Big Envelope'), 'Stage 2 is the printer\'s Big Envelope');
    }

    @IsTest
    static void testCompareTo() {

        BP_DocumentsContentController.DocumentInfo a =
            new BP_DocumentsContentController.DocumentInfo();
        a.order = 1;

        BP_DocumentsContentController.DocumentInfo b =
            new BP_DocumentsContentController.DocumentInfo();
        b.order = 2;

        System.assertEquals(-1, a.compareTo(b));
        System.assertEquals(1, b.compareTo(a));

        b.order = 1;
        System.assertEquals(0, a.compareTo(b));
    }
}