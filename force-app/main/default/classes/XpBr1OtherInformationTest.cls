@IsTest
private class XpBr1OtherInformationTest {

    private static final String PDF = EncodingUtil.base64Encode(Blob.valueOf('PDF-DATA'));

    private static String answer(String report) {
        return '{"base64":"' + PDF + '","status":"Success"' + (report == null ? '' : ',"otherInformation":' + report) + '}';
    }

    private class PdfMock implements HttpCalloutMock {
        private String body;
        PdfMock(String body) {
            this.body = body;
        }
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(body);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact person = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        Basic__c claim = BP_TestDataFactory.createBasic(person.Id, true);
        BP_TestDataFactory.createCompany(claim.Id, true);
        BP_TestDataFactory.createCountryLived(claim.Id, true);
        insert new XtraPension_Data__c(
            BP_Registration_template__c = 'TestTemplate', BP_Pdf_File_Link__c = 'test', BP_Pdf_File_IPC1394_Link__c = 'test',
            BP_PDF_IPCBR1_Wet__c = 'test', BP_PDF_IPC1394_Wet__c = 'test', BR_X_Api_Key__c = 'test'
        );
    }

    private static Basic__c claim() {
        return [SELECT Id, BR1_Other_Info_Sheets__c, BR1_Other_Info_Cut__c FROM Basic__c LIMIT 1];
    }

    // the count as a whole number (null while nothing was ever kept)
    private static Integer sheets() {
        Decimal kept = claim().BR1_Other_Info_Sheets__c;
        return kept == null ? null : kept.intValue();
    }

    @IsTest
    static void readsTheReportNextToThePdf() {
        XpBr1OtherInformation.Report report = XpBr1OtherInformation.read(
            answer('{"lines":124,"fontSize":8.5,"continuationSheets":2,"cut":false}'));
        System.assertEquals(124, report.lines);
        System.assertEquals(8.5, report.fontSize);
        System.assertEquals(2, report.continuationSheets);
        System.assertEquals(false, report.cut);
        // the wrapper the generators already use is not disturbed by the extra key
        System.assertEquals(PDF, new BP_RequestWrappers.UploadDocumentDataWrapper(
            answer('{"lines":124,"fontSize":10,"continuationSheets":2,"cut":false}')).base64);
    }

    @IsTest
    static void anAnswerWithoutTheReportIsNoReport() {
        System.assertEquals(null, XpBr1OtherInformation.read(null));
        System.assertEquals(null, XpBr1OtherInformation.read(''));
        System.assertEquals(null, XpBr1OtherInformation.read(PDF), 'the plain base64 some mocks answer');
        System.assertEquals(null, XpBr1OtherInformation.read(answer(null)), 'the PDF service before the change');
        System.assertEquals(null, XpBr1OtherInformation.read('{"otherInformation": not json'));
        System.assertEquals(null, XpBr1OtherInformation.read('{"status":"Success","otherInformation":null}'));
    }

    @IsTest
    static void savesTheSheetsOnTheClaim() {
        Id claimId = claim().Id;
        XpBr1OtherInformation.save(claimId, answer('{"lines":124,"fontSize":10,"continuationSheets":2,"cut":false}'));
        System.assertEquals(2, sheets());
        System.assertEquals(false, claim().BR1_Other_Info_Cut__c);

        // shortened afterwards: back on page 13 alone
        XpBr1OtherInformation.save(claimId, answer('{"lines":40,"fontSize":10,"continuationSheets":0,"cut":false}'));
        System.assertEquals(0, sheets());

        // nothing to say: nothing changes
        XpBr1OtherInformation.save(claimId, answer(null));
        XpBr1OtherInformation.save(claimId, PDF);
        XpBr1OtherInformation.save(null, answer('{"lines":124,"fontSize":10,"continuationSheets":2,"cut":false}'));
        System.assertEquals(0, sheets());
        System.assertEquals(0, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    @IsTest
    static void aCutTextIsFlaggedAndLogged() {
        Id claimId = claim().Id;
        XpBr1OtherInformation.save(claimId, answer('{"lines":900,"fontSize":6,"continuationSheets":0,"cut":true,"error":"no more pages"}'));
        System.assertEquals(true, claim().BR1_Other_Info_Cut__c);
        System.assertEquals(0, sheets());
        Application_Form_Error__c log = [SELECT Error_Body__c FROM Application_Form_Error__c];
        System.assert(log.Error_Body__c.contains('NOT on the form') && log.Error_Body__c.contains('no more pages'), log.Error_Body__c);

        // the same answer again writes nothing more
        XpBr1OtherInformation.save(claimId, answer('{"lines":900,"fontSize":6,"continuationSheets":0,"cut":true,"error":"no more pages"}'));
        System.assertEquals(1, [SELECT COUNT() FROM Application_Form_Error__c]);
    }

    @IsTest
    static void theFullPackGenerationKeepsTheReport() {
        Id claimId = claim().Id;
        Test.setMock(HttpCalloutMock.class, new PdfMock(answer('{"lines":80,"fontSize":10,"continuationSheets":1,"cut":false}')));
        Test.startTest();
        BP_GeneratePdfFileController.getApplication(claimId);
        Test.stopTest();
        System.assertEquals(1, sheets());
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :claimId AND ContentDocument.Title LIKE '%_IPCBR1'],
            'the IPCBR1 is saved as before');
    }

    @IsTest
    static void theEditorsRegenerationKeepsTheReport() {
        Id claimId = claim().Id;
        Test.setMock(HttpCalloutMock.class, new PdfMock(answer('{"lines":300,"fontSize":10,"continuationSheets":5,"cut":false}')));
        Test.startTest();
        BP_GenerateApplication_BR1.getApplication_BR1(claimId);
        Test.stopTest();
        System.assertEquals(5, sheets());
    }

    @IsTest
    static void anOlderPdfServiceChangesNothing() {
        Id claimId = claim().Id;
        Test.setMock(HttpCalloutMock.class, new PdfMock(answer(null)));
        Test.startTest();
        BP_GeneratePdfFileController.getApplication(claimId);
        BP_GenerateApplication_BR1.getApplication_BR1(claimId);
        Test.stopTest();
        System.assertEquals(null, sheets());
        System.assertEquals(false, claim().BR1_Other_Info_Cut__c);
    }
}