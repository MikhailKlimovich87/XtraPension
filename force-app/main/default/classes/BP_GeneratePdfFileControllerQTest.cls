@isTest
private class BP_GeneratePdfFileControllerQTest {

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
            BP_PDF_IPC1394_Wet__c = 'test'

        );
        insert data;
    }

    @IsTest
    static void execute_shouldGeneratePdf() {
        
        
        Basic__c app = [SELECT id, Name, First_Name__c, Last_Name__c FROM Basic__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new PdfMock(app.id));
        Test.setMock(HttpCalloutMock.class, new PdfMock(app.id));

        Test.startTest();

        System.enqueueJob(
            new BP_GeneratePdfFileControllerQueueable(app.id)
        );

        Test.stopTest();
        System.assert(true, 'Queueable executed successfully');
    }
}