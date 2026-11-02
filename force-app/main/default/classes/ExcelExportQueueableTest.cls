@isTest
public class ExcelExportQueueableTest {

    @TestSetup
    static void createData() {

        List<String> productNames = new List<String>{
            'Deposit',
            'Application',
            'Success'
        };

        List<Product2> newProducts = new List<Product2>();

        for (String name : productNames) {

            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }

        insert newProducts;

        Id pricebookId = Test.getStandardPricebookId();

        List<PriceBookEntry> testPriceBookEntries =
            new List<PriceBookEntry>();

        Integer counter = 100000;

        for (Product2 product : newProducts) {

            PriceBookEntry pbe = new PriceBookEntry();

            pbe.Pricebook2Id = pricebookId;
            pbe.Product2Id = product.Id;
            pbe.UnitPrice = counter;
            pbe.IsActive = true;
            pbe.CurrencyIsoCode = 'EUR';

            testPriceBookEntries.add(pbe);

            counter += 10000;
        }

        insert testPriceBookEntries;

        TestDataFactory.createTestCountry(true);

        Account account =
            TestDataFactory.createAccount(true);

        Contact currentContact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Application__c app =
            TestDataFactory.createApplication(
                currentContact.Id,
                true
            );

        app.Email__c = 'test@test.com';

        update app;

        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testQueueable() {

        Application__c app = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];

        Export_Request__c exportReq =
            new Export_Request__c(
                Application_Ids__c = app.Id
            );

        insert exportReq;
        Test.setMock(
            HttpCalloutMock.class,
            new SFTPUploadMock()
        );
        Test.startTest();

        System.enqueueJob(
            new ExcelExportQueueable(exportReq.Id)
        );

        Test.stopTest();

        List<ContentVersion> files = [
            SELECT Id,
                   Title,
                   PathOnClient
            FROM ContentVersion
        ];

        System.assertEquals(
            2,
            files.size()
        );


        System.assertEquals(
            'Next Steps.pdf',
            files[0].PathOnClient
        );
    }

    public class SFTPUploadMock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true}');

            return res;
        }
    }
}