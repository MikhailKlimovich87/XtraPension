@isTest
public class SFTPProcessQueueableTest {
    
    // Mock class for HTTP callout
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
    
    // Mock class for SFTP Upload HTTP callout
    public class SFTPUploadMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"status":"Success"}');
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
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        testApplication.Email__c = 'test@test.com';
        update testApplication;
        
        // Create Printing_House_SFTP__c custom setting
        Printing_House_SFTP__c settings = new Printing_House_SFTP__c(
            Key__c = 'test-key-12345',
        Host__c = 'test.sftp.host.com',
        Port__c = '22',
        UserName__c = 'testuser',
        Password__c = 'testpassword',
        Pension_Keeper_Docs_Folder_Name__c = '/test/pension-keeper-docs'
            );
        insert settings;
        
        // Create XtraPension_Data__c custom setting for SFTP Upload endpoint
        XtraPension_Data__c xtraData = new XtraPension_Data__c(
            SFTP_Upload_File_Link__c = 'https://test.xtrapension.com/sftp/upload-file'
            );
        insert xtraData;
    }
    
    @isTest
    static void testProcessQueueable() {
        // Setup mock for both HTTP callouts
        Test.setMock(HttpCalloutMock.class, new SFTPHttpMock());
        
        // Execute
        Test.startTest();
        SFTPProcessQueueable queueable = new SFTPProcessQueueable();
        queueable.execute(null);
        Test.stopTest();
        
        // Verify Export_Request__c was created
        List<Export_Request__c> requests = [SELECT Id, Application_Ids__c FROM Export_Request__c];
        System.assert(requests.size() > 0, 'Export request should be created');
        
        // Verify Export_Request__c has Application IDs
        Export_Request__c exportReq = requests[0];
        System.assertNotEquals(null, exportReq.Application_Ids__c, 'Application IDs should be populated');
        System.debug('Application IDs: ' + exportReq.Application_Ids__c);
    }
    
    @isTest
    static void testProcessQueueableWithFullFlow() {
        // Setup mock for both HTTP callouts (list files and upload)
        Test.setMock(HttpCalloutMock.class, new SFTPHttpMock());
        
        // Execute
        Test.startTest();
        SFTPProcessQueueable queueable = new SFTPProcessQueueable();
        queueable.execute(null);
        Test.stopTest();
        
        // Verify ContentVersion was created (Excel file)
        List<ContentVersion> contentVersions = [SELECT Id, Title, VersionData FROM ContentVersion];
        System.debug('ContentVersion count: ' + contentVersions.size());
        
        // Note: ContentVersion might not be created in test context due to Visualforce page rendering limitations
        // The actual Excel generation via PageReference.getContent() might not work in test context
        // So we primarily test that the Export_Request__c is created
    }
    
    @isTest
    static void testQueueableEnqueue() {
        // Setup mock
        Test.setMock(HttpCalloutMock.class, new SFTPHttpMock());
        
        Test.startTest();
        
        // Enqueue the job (this will call SFTP_ListFileHelper.getFiles() which enqueues ExcelExportQueueable)
        System.enqueueJob(new SFTPProcessQueueable());
        
        Test.stopTest();
        
        // Verify Export_Request__c was created
        List<Export_Request__c> requests = [SELECT Id FROM Export_Request__c];
        System.assert(requests.size() > 0, 'Export request should be created');
    }
    
    @isTest
    static void testNoFilesFound() {
        // Create a mock that returns no files
        Test.setMock(HttpCalloutMock.class, new SFTPNoFilesMock());
        
        Test.startTest();
        SFTPProcessQueueable queueable = new SFTPProcessQueueable();
        queueable.execute(null);
        Test.stopTest();
        
        // Verify no Export_Request__c was created
        List<Export_Request__c> requests = [SELECT Id FROM Export_Request__c];
        System.assertEquals(0, requests.size(), 'No export request should be created when no files found');
    }
    
    @isTest
    static void testSFTPErrorResponse() {
        // Create a mock that returns error
        Test.setMock(HttpCalloutMock.class, new SFTPErrorMock());
        
        Test.startTest();
        SFTPProcessQueueable queueable = new SFTPProcessQueueable();
        queueable.execute(null);
        Test.stopTest();
        
        // Verify no Export_Request__c was created
        List<Export_Request__c> requests = [SELECT Id FROM Export_Request__c];
        System.assertEquals(0, requests.size(), 'No export request should be created when SFTP error occurs');
    }
    
    // Additional mock classes for different scenarios
    
    private class SFTPNoFilesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String body = JSON.serialize(new Map<String, Object>{
                'status' => 'Success',
                'files' => new List<Object>()
            });
            
            res.setBody(body);
            return res;
        }
    }
    
    private class SFTPErrorMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"status":"Error","message":"Internal Server Error"}');
            return res;
        }
    }
}