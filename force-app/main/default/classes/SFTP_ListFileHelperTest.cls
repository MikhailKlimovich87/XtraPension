@isTest
public class SFTP_ListFileHelperTest {

    public class SFTPHttpMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            // Get created application dynamically
            Application__c app = [
                SELECT Id, Name
                FROM Application__c
                LIMIT 1
            ];

            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            String body = JSON.serialize(new Map<String, Object>{
                'status' => 'Success',
                'files' => new List<Object>{
                    new Map<String, Object>{
                        'name' => 'Adam_Hugh_' + app.Name + '_Welcome_PK_Notification.pdf'
                    },
                    new Map<String, Object>{
                        'name' => 'Processed By WDM_Test.pdf'
                    }
                }
            });

            res.setBody(body);

            return res;
        }
    }

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

            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.Id;
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
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Id personContactId = currentContact[0].Id;

        Application__c testApplication =
            TestDataFactory.createApplication(personContactId, true);

        testApplication.Email__c = 'test@test.com';

        update testApplication;
        Printing_House_SFTP__c setting = new Printing_House_SFTP__c();
        setting.Port__c = '22';
        setting.Host__c = 'host';
        setting.Key__c = 'key';
        setting.UserName__c = 'user';
        setting.Password__c = 'pass';
        setting.Pension_Keeper_Docs_Folder_Name__c = 'folder';
        insert setting;

        XtraPension_Data__c xtraPensionData = TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testGetFiles() {

        Test.setMock(HttpCalloutMock.class, new SFTPHttpMock());

        Application__c app = [
            SELECT Id, Name
            FROM Application__c
            LIMIT 1
        ];

        Test.startTest();

        List<String> results =
            SFTP_ListFileHelper.getFiles();

        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(app.Name, results[0]);

        List<ContentVersion> files = [
            SELECT Id, Title
            FROM ContentVersion
        ];

        System.assertEquals(2, files.size());
    }

    @isTest
    static void testGetFilesFromSFTP() {

        Test.setMock(HttpCalloutMock.class, new SFTPHttpMock());

        SFTP_ListFileHelper.SFTPWrapper wrapper =
            new SFTP_ListFileHelper.SFTPWrapper();

        wrapper.key = 'test';
        wrapper.sftpHost = 'host';
        wrapper.sftpPort = '22';
        wrapper.sftpUserName = 'user';
        wrapper.sftpPassword = 'pass';
        wrapper.folderPath = 'folder';

        Test.startTest();

        HttpResponse response =
            SFTP_ListFileHelper.getFilesFromSFTP(wrapper);

        Test.stopTest();

        System.assertEquals(200, response.getStatusCode());
        System.assert(
            response.getBody().contains('Success')
        );
    }
}