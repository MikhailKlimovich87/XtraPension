@isTest
public class PK_PortalDocumentHelperTest {
    
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Order testOrder = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        List<Payment__c> testPayments = TestDataFactory.createRelatedPaymentToApplication(
            newProducts,
            testApplication,
            testOrder.Id,
            true
        );
    }
    
    @isTest
    static void testGetDocumentsFromRecordWithRecordId() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.GetDocumentsDataWrapper wrapper = new PK_RequestWrappers.GetDocumentsDataWrapper(
            '{"recordId":"' + app.Id + '","docLimit":"10"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.getDocumentsFromRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('documents'));
    }
    
    @isTest
    static void testGetDocumentsFromRecordEmptyRecordId() {
        PK_RequestWrappers.GetDocumentsDataWrapper wrapper = new PK_RequestWrappers.GetDocumentsDataWrapper(
            '{"recordId":"","docLimit":"10"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.getDocumentsFromRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testUploadFileToRecordSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];

        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
        
        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(
            '{"recordId":"' + app.Id + '","base64":"' + base64Content + '","fileName":"TestFile","fileType":"txt"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.uploadFileToRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('document'));
    }
    
    @isTest
    static void testUploadFileToRecordEmptyBase64() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(
            '{"recordId":"' + app.Id + '","base64":"","fileName":"TestFile","fileType":"txt"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.uploadFileToRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testUploadFileToRecordEmptyFileName() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
        
        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(
            '{"recordId":"' + app.Id + '","base64":"' + base64Content + '","fileName":"","fileType":"txt"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.uploadFileToRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testUploadFileToRecordEmptyFileType() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
        
        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(
            '{"recordId":"' + app.Id + '","base64":"' + base64Content + '","fileName":"TestFile","fileType":""}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.uploadFileToRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testGetFileBase64Success() {
        // Create a content version
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.txt',
            VersionData = Blob.valueOf('Test file content'),
            IsMajorVersion = true
        );
        insert cv;
        
        ContentVersion insertedCV = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];
        
        PK_RequestWrappers.GetDocumentDataWrapper wrapper = new PK_RequestWrappers.GetDocumentDataWrapper(
            '{"documentId":"' + insertedCV.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.getFileBase64(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('base64Data'));
        System.assertEquals('Test Document', result.get('fileTitle'));
    }
    
    @isTest
    static void testGetFileBase64DocumentNotFound() {
        PK_RequestWrappers.GetDocumentDataWrapper wrapper = new PK_RequestWrappers.GetDocumentDataWrapper(
            '{"documentId":"' + UserInfo.getOrganizationId().substring(0,18) + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.getFileBase64(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Document is not found!', result.get('message'));
    }
    
    @isTest
    static void testDeleteFileFromRecordSuccess() {
        // Create a content version
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document Delete',
            PathOnClient = 'TestDocumentDelete.txt',
            VersionData = Blob.valueOf('Test file content'),
            IsMajorVersion = true
        );
        insert cv;
        
        ContentVersion insertedCV = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        
        PK_RequestWrappers.GetDocumentDataWrapper wrapper = new PK_RequestWrappers.GetDocumentDataWrapper(
            '{"documentId":"' + insertedCV.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.deleteFileFromRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertEquals('Document deleted successfully', result.get('message'));
        
        // Verify document was deleted
        List<ContentDocument> deletedDocs = [SELECT Id FROM ContentDocument WHERE Id = :insertedCV.ContentDocumentId];
        System.assertEquals(0, deletedDocs.size());
    }
    
    @isTest
    static void testDeleteFileFromRecordDocumentNotFound() {
        PK_RequestWrappers.GetDocumentDataWrapper wrapper = new PK_RequestWrappers.GetDocumentDataWrapper(
            '{"documentId":"' + UserInfo.getOrganizationId().substring(0,18) + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.deleteFileFromRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Document is not found!', result.get('message'));
    }
    
    @isTest
    static void testUploadFileToRecordExceptionHandling() {
        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(
            '{"recordId":"invalid","base64":"' + EncodingUtil.base64Encode(Blob.valueOf('test')) + '","fileName":"Test","fileType":"txt"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalDocumentHelper.uploadFileToRecord(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertNotEquals(null, result.get('message'));
    }
}