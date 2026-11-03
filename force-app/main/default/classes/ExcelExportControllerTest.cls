@isTest
public class ExcelExportControllerTest {

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
    }

    @isTest
    static void testControllerWithRequestId() {

        Application__c app = [
            SELECT Id, Email__c
            FROM Application__c
            LIMIT 1
        ];

        Export_Request__c exportReq =
            new Export_Request__c(
                Application_Ids__c = app.Id
            );

        insert exportReq;

        PageReference pageRef =
            new PageReference('/apex/ExcelExportPage');

        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put(
            'requestId',
            exportReq.Id
        );

        Test.startTest();

        ExcelExportController controller =
            new ExcelExportController();

        Test.stopTest();

        System.assertEquals(
            1,
            controller.appList.size()
        );

        System.assertEquals(
            app.Email__c,
            controller.appList[0].Email__c
        );
    }

    @isTest
    static void testControllerWithoutRequestId() {

        PageReference pageRef =
            new PageReference('/apex/ExcelExportPage');

        Test.setCurrentPage(pageRef);

        Test.startTest();

        ExcelExportController controller =
            new ExcelExportController();

        Test.stopTest();

        System.assertEquals(
            0,
            controller.appList.size()
        );
    }

    @isTest
    static void testControllerWithInvalidRequestId() {

        PageReference pageRef =
            new PageReference('/apex/ExcelExportPage');

        Test.setCurrentPage(pageRef);

        ApexPages.currentPage().getParameters().put(
            'requestId',
            'a00000000000000AAA'
        );

        Test.startTest();

        ExcelExportController controller =
            new ExcelExportController();

        Test.stopTest();

        System.assertEquals(
            0,
            controller.appList.size()
        );
    }
}