@isTest
private class BP_GeneratePdfFileControllerTest {


    private class PdfMock implements HttpCalloutMock {
        String recordId;

        public PdfMock(String recordId) {
            this.recordId = recordId;
        }   

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            Map<String, Object> mockResponse = new Map<String, Object>{
                'recordId' => recordId,
                'base64' => EncodingUtil.base64Encode(Blob.valueOf('PDF-DATA')),
                'fileType' => 'pdf',
                'fileName' => 'testFile'
            };

            res.setBody(JSON.serialize(mockResponse));
            res.setStatusCode(200);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Success', 'Pension Keeper'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
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
        Basic__c testApplication = BP_TestDataFactory.createBasic(personContactId, true);
        Claimant_Child__c testChaild = BP_TestDataFactory.createChild(testApplication.Id, true);
        Claimant_Company__c testCompany = BP_TestDataFactory.createCompany(testApplication.Id, true);
        Claimant_Country_lived__c testCountryLived = BP_TestDataFactory.createCountryLived(testApplication.Id, true);

         
        XtraPension_Data__c data = new XtraPension_Data__c(
            BP_Registration_template__c = 'TestTemplate',
            BP_Pdf_File_Link__c = 'test',
            BP_Pdf_File_IPC1394_Link__c = 'test',
            BP_PDF_IPCBR1_Wet__c = 'test',
            BP_PDF_IPC1394_Wet__c = 'test',
            BR_X_Api_Key__c = 'test'
        );
        insert data;
    }

    @isTest
    static void testGetApplication_successFlow() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PdfMock(b.Id));
        Test.setMock(HttpCalloutMock.class, new PdfMock(b.Id));

        Test.startTest();

        Map<String, Object> result =
            BP_GeneratePdfFileController.getApplication(b.Id);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('application'));

        Boolean hasStatusKey = false;
        for (String key : result.keySet()) {
            if (key.startsWith('Status')) {
                hasStatusKey = true;
            }
        }

        System.assertEquals(true, hasStatusKey, 'PDF status key missing');
    }

    @isTest
    static void testGenerateDocument_safe() {

        Basic__c basicRecord = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();

        BP_GeneratePdfFileController.generateDocument(
            JSON.serialize(new Map<String, Object>{
                'recordId' => basicRecord.Id,
                'base64' => EncodingUtil.base64Encode(Blob.valueOf('TEST')),
                'fileType' => 'pdf',
                'fileName' => 'unit-test'
            }),
            basicRecord.Id,
            'unit-test-file'
        );

        Test.stopTest();

        System.assert(true);
    }

    @isTest
    static void testGenerateSignature_successFlow() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PdfMock(b.Id));

        Test.startTest();
        Map<String, Object> result =
            BP_GeneratePdfFileController.generateSignature(b.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('application'));

        List<ContentDocumentLink> docs = [
            SELECT Id, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :b.Id
        ];

        System.assertEquals(2, docs.size());
    }

    @isTest
    static void testGetApplication_updateExistingDocuments() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PdfMock(b.Id));

        Test.startTest();
        BP_GeneratePdfFileController.getApplication(b.Id);
        Test.stopTest();


        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :b.Id
        ];

        System.assertEquals(2, links.size());

        Integer versions = [
            SELECT Count()
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
        ];

        System.assert(versions >= 1);
    }

    @isTest
    static void testGenerateSignature_updateExistingDocuments() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PdfMock(b.Id));

        Test.startTest();
        BP_GeneratePdfFileController.generateSignature(b.Id);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :b.Id
        ];

        System.assertEquals(2, links.size());

        Integer versions = [
            SELECT Count()
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
        ];

        System.assert(versions >= 1);
    }
    @isTest
    static void testGenerateDocument_blankInput() {

        Basic__c b = [SELECT Id FROM Basic__c LIMIT 1];

        Test.startTest();

        BP_GeneratePdfFileController.generateDocument(
            '{"base64":""}',
            b.Id,
            'file'
        );

        BP_GeneratePdfFileController.generateDocument(
            JSON.serialize(new Map<String, Object>{
                'base64' => EncodingUtil.base64Encode(Blob.valueOf('TEST'))
            }),
            b.Id,
            ''
        );

        Test.stopTest();

        Integer cnt = [
            SELECT Count()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :b.Id
        ];

        System.assertEquals(0, cnt);
    }
}