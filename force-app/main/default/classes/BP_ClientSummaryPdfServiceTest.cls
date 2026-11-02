@IsTest
public with sharing class BP_ClientSummaryPdfServiceTest {

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