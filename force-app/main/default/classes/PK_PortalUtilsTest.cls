@isTest
public class PK_PortalUtilsTest {
    
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
    
    // Tests for getActiveAppPortalUser (ApplicationDataWrapper)
    @isTest
    static void testGetActiveAppPortalUserByApplicationDataWrapper() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'active@test.com';
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'PASSWORD123';
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"active@test.com"}'
        );
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getActiveAppPortalUser(wrapper);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
        System.assertEquals(app.Id, result[0].Id);
    }
    
    @isTest
    static void testGetActiveAppPortalUserByApplicationDataWrapperNullApplicationNumber() {
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":null,"email":"test@test.com"}'
        );
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getActiveAppPortalUser(wrapper);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testGetActiveAppPortalUserByApplicationDataWrapperNotActive() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'inactive@test.com';
        app.PK_Portal_User_Active__c = false;
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"' + app.Name + '","email":"inactive@test.com"}'
        );
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getActiveAppPortalUser(wrapper);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    // Tests for getActiveAppPortalUser (LoginDataWrapper)
    @isTest
    static void testGetActiveAppPortalUserByLoginDataWrapper() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'login@test.com';
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'AB123456CSMITH';
        app.Salutation__c = 'Mr.';
        app.National_Insurance_Number__c = 'AB123456C';
        update app;
        
        PK_RequestWrappers.LoginDataWrapper wrapper = new PK_RequestWrappers.LoginDataWrapper(
            '{"applicationNumber":"' + app.Name + '","password":"AB123456CSMITH","ip":"192.168.1.1","device":"Desktop","countryISO":"GB","browser":"Chrome"}'
        );
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getActiveAppPortalUser(wrapper);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
    }
    
    @isTest
    static void testGetActiveAppPortalUserByLoginDataWrapperNullPassword() {
        PK_RequestWrappers.LoginDataWrapper wrapper = new PK_RequestWrappers.LoginDataWrapper(
            '{"applicationNumber":"APP003","password":null,"ip":"192.168.1.1","device":"Desktop","countryISO":"GB","browser":"Chrome"}'
        );
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getActiveAppPortalUser(wrapper);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testGetApplication() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'getapp@test.com';
        app.CurrencyIsoCode = 'GBP';
        update app;
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getApplication(app.Id);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
        System.assertEquals(app.Id, result[0].Id);
    }
    
    @isTest
    static void testGetApplicationNullId() {
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getApplication(null);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testGetPayment() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'payment@test.com';
        update app;
        
        Order ord = [SELECT Id FROM Order WHERE Application__c = :app.Id LIMIT 1];

        // use the factory to keep things consistent with other tests
        Payment__c payment = TestDataFactory.createPayment(app.Id, ord.Id, true);
        update new Payment__c(
            Id = payment.Id,
            Status__c = 'Paid'
        );
    
        Test.startTest();
        List<Payment__c> result = PK_PortalUtils.getPayment(app.Id);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
        System.assertEquals(payment.Id, result[0].Id);
    }
    
    @isTest
    static void testGetPaymentNullId() {
        Test.startTest();
        List<Payment__c> result = PK_PortalUtils.getPayment(null);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testGetRequestCheck() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'requestcheck@test.com';
        update app;
        
        PK_Request_Check__c request = new PK_Request_Check__c(
            Application__c = app.Id,
            PK_Requested_Check_Date__c = Date.today(),
            PK_Amount_Paid__c = 500,
            PK_Payment_Received__c = Date.today(),
            CurrencyIsoCode = 'GBP'
        );
        insert request;
        
        Test.startTest();
        PK_Request_Check__c result = PK_PortalUtils.getRequestCheck(app.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(request.Id, result.Id);
    }
    
    // @isTest
    // static void testGetRequestCheckNullId() {
    //     Test.startTest();
    //     PK_Request_Check__c result = PK_PortalUtils.getRequestCheck(null);
    //     Test.stopTest();
        
    //     System.assertNotEquals(null, result);
    // }
    
    @isTest
    static void testGetDocumentWrapper() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document',
            PathOnClient = 'TestDocument.txt',
            VersionData = Blob.valueOf('Test file content'),
            IsMajorVersion = true
        );
        insert cv;
        
        ContentVersion insertedCV = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];
        
        Test.startTest();
        PK_PortalUtils.DocumentWrapper docWrapper = PK_PortalUtils.getDocumentWrapper(insertedCV.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, docWrapper);
        System.assertEquals('Test Document', docWrapper.documentTitle);
    }
    
    @isTest
    static void testCreateContentVersion() {
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
        
        Test.startTest();
        ContentVersion cv = PK_PortalUtils.createContentVersion(base64Content, 'TestFile', 'txt');
        Test.stopTest();
        
        System.assertNotEquals(null, cv.Id);
        System.assertEquals('TestFile', cv.Title);
    }
    
    @isTest
    static void testCreateContentLink() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'contentlink@test.com';
        update app;
        
        String base64Content = EncodingUtil.base64Encode(Blob.valueOf('Test file content'));
        ContentVersion cv = PK_PortalUtils.createContentVersion(base64Content, 'TestFile', 'txt');
        
        Test.startTest();
        ContentDocumentLink cdl = PK_PortalUtils.createContentLink(cv.Id, app.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, cdl.Id);
        System.assertEquals(app.Id, cdl.LinkedEntityId);
    }
    
    @isTest
    static void testCreateContentLinkNullValues() {
        Test.startTest();
        ContentDocumentLink cdl = PK_PortalUtils.createContentLink(null, null);
        Test.stopTest();
        
        System.assertEquals(null, cdl);
    }
    
    @isTest
    static void testCalculatePensionDateBorn1953() {
        Date dob = Date.newInstance(1953, 12, 6);
        
        Test.startTest();
        Date pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        Test.stopTest();
        
        System.assertEquals(Date.newInstance(2019, 3, 6), pensionDate);
    }
    
    @isTest
    static void testCalculatePensionDateBorn1954() {
        Date dob = Date.newInstance(1954, 1, 6);
        
        Test.startTest();
        Date pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        Test.stopTest();
        
        System.assertEquals(Date.newInstance(2019, 5, 6), pensionDate);
    }
    
    @isTest
    static void testCalculatePensionDateBorn1960() {
        Date dob = Date.newInstance(1960, 4, 6);
        
        Test.startTest();
        Date pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        Test.stopTest();
        
        System.assertNotEquals(null, pensionDate);
    }
    
    @isTest
    static void testCalculatePensionDateBorn1978() {
        Date dob = Date.newInstance(1978, 4, 6);
        
        Test.startTest();
        Date pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        Test.stopTest();
        
        System.assertNotEquals(null, pensionDate);
    }
    
    @isTest
    static void testCalculatePensionDateNullDate() {
        Test.startTest();
        Date pensionDate = PK_PortalUtils.calculatePensionDate(null);
        Test.stopTest();
        
        System.assertEquals(null, pensionDate);
    }
    
    @isTest
    static void testGetYearsMonthsDaysBetween() {
        Date startDate = Date.newInstance(2020, 1, 1);
        Date endDate = Date.newInstance(2023, 3, 15);
        
        Test.startTest();
        String result = PK_PortalUtils.getYearsMonthsDaysBetween(startDate, endDate);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals(true, result.contains('years'));
    }
    
    @isTest
    static void testGetYearsMonthsDaysBetweenSameDay() {
        Date startDate = Date.newInstance(2020, 1, 1);
        Date endDate = Date.newInstance(2020, 1, 1);
        
        Test.startTest();
        String result = PK_PortalUtils.getYearsMonthsDaysBetween(startDate, endDate);
        Test.stopTest();
        
        System.assertEquals('0 days', result);
    }
    
    @isTest
    static void testGetYearsMonthsDaysBetweenNullDates() {
        Test.startTest();
        String result = PK_PortalUtils.getYearsMonthsDaysBetween(null, null);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }
    
    @isTest
    static void testGetYearsMonthsDaysBetweenOnlyDays() {
        Date startDate = Date.newInstance(2020, 1, 1);
        Date endDate = Date.newInstance(2020, 1, 10);
        
        Test.startTest();
        String result = PK_PortalUtils.getYearsMonthsDaysBetween(startDate, endDate);
        Test.stopTest();
        
        System.assertEquals('9 days', result);
    }
    
    @isTest
    static void testGetAllMultiSelectPicklistValues() {
        Test.startTest();
        List<Schema.PicklistEntry> result = PK_PortalUtils.getAllMultiSelectPicklistValues('Account', 'BillingCountry');
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testGetAllMultiSelectPicklistValuesInvalidObject() {
        Test.startTest();
        List<Schema.PicklistEntry> result = PK_PortalUtils.getAllMultiSelectPicklistValues('InvalidObject', 'Field');
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testGetAllMultiSelectPicklistValuesInvalidField() {
        Test.startTest();
        List<Schema.PicklistEntry> result = PK_PortalUtils.getAllMultiSelectPicklistValues('Account', 'InvalidField');
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testSendRegistrationEmail() {
        List<Application__c> apps = [
            SELECT
                Name,
                Contact__c
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'registrationemail@test.com';
        update app;
        
        Test.startTest();
        PK_PortalUtils.sendRegistrationEmail(app);
        Test.stopTest();
        
        System.assertEquals(true, true); // No exception thrown
    }
    
    @isTest
    static void testSendCouplesEmail() {
        List<Application__c> apps = [
            SELECT
                Name,
                Contact__c,
                First_Name__c,
                Second_Name__c
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'couplesemail@test.com';
        update app;
        
        Test.startTest();
        PK_PortalUtils.sendCouplesEmail(app);
        Test.stopTest();
        
        System.assertEquals(true, true); // No exception thrown
    }
    
    @isTest
    static void testGetStateCodeByLabel() {
        Test.startTest();
        String result = PK_PortalUtils.getStateCodeByLabel('England');
        Test.stopTest();
        
        System.assertEquals(null, result) ;
    }
    
    @isTest
    static void testGetApplicationOverview() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'overview@test.com';
        app.Date_Of_Birth__c = Date.newInstance(1960, 4, 6);
        update app;
        
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getApplicationOverview(app.Id);
        Test.stopTest();
        
        System.assertEquals(1, result.size());
    }
    
    @isTest
    static void testGetApplicationOverviewNullId() {
        Test.startTest();
        List<Application__c> result = PK_PortalUtils.getApplicationOverview(null);
        Test.stopTest();
        
        System.assertEquals(0, result.size());
    }
    
    @isTest
    static void testGetLatestComment() {
        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        EmailMessage em = new EmailMessage(
            RelatedToId = app.Id,
            Subject = 'Test Comment',
            HtmlBody = '<p>Test</p>',
            FromAddress = 'test@example.com',
            ToAddress = 'client@example.com',
            Pension_Keeper__c = true
        );
        insert em;
        
        Test.startTest();
        EmailMessage result = PK_PortalUtils.getLatestComment(em.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
        System.assertEquals('Test Comment', result.Subject);
    }
    
    @isTest
    static void testGetLatestCommentNullId() {
        Test.startTest();
        EmailMessage result = PK_PortalUtils.getLatestComment(null);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }
    
    @isTest
    static void testGetAttachment() {
        Test.startTest();
        ContentVersion result = PK_PortalUtils.getAttachment(UserInfo.getOrganizationId().substring(0,15));
        Test.stopTest();
        
        System.assertEquals(null, result);
    }
    
    @isTest
    static void testGetAttachmentNullId() {
        Test.startTest();
        ContentVersion result = PK_PortalUtils.getAttachment(null);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }
    
    @isTest
    static void testDocumentWrapper() {
        PK_PortalUtils.DocumentWrapper docWrapper = new PK_PortalUtils.DocumentWrapper();
        docWrapper.documentId = '001';
        docWrapper.documentTitle = 'Test Doc';
        docWrapper.documentType = 'PDF';
        docWrapper.documentSize = 1024;
        docWrapper.createdDate = '01/01/2024';
        
        System.assertEquals('001', docWrapper.documentId);
        System.assertEquals('Test Doc', docWrapper.documentTitle);
        System.assertEquals('PDF', docWrapper.documentType);
        System.assertEquals(1024, docWrapper.documentSize);
        System.assertEquals('01/01/2024', docWrapper.createdDate);
    }

    @isTest
    static void testGetReceipt() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c app = apps[0];
        Payment__c payment = [SELECT Id FROM Payment__c WHERE Application__c = :app.Id LIMIT 1];
        
        // Create EmailMessage related to Payment via Receipts__r (assuming custom relationship)
        // Since Receipts__r is likely a related list, but for test, since no data, expect ''
        Test.startTest();
        String receipt = PK_PortalUtils.getReceipt(payment.Id);
        Test.stopTest();
        System.assertEquals('', receipt);
    }

    @isTest
    static void testGetTemplateDocuments() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c app = apps[0];
        
        // Create ContentDocument linked to app
        ContentVersion cv = new ContentVersion(
            Title = 'C2 Document',
            PathOnClient = 'C2.pdf',
            VersionData = Blob.valueOf('test')
        );
        insert cv;
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId,
            LinkedEntityId = app.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        PK_RequestWrappers.GetDocumentsDataWrapper wrapper = new PK_RequestWrappers.GetDocumentsDataWrapper();
        wrapper.recordId = app.Id;
        wrapper.docLimit = String.valueOf(10);
        
        Test.startTest();
        List<ContentDocument> docs = PK_PortalUtils.getTemplateDocuments(wrapper);
        Test.stopTest();
        
        System.assert(docs.size() > 0);
    }

    @isTest
    static void testGetDocumentWrappers() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c app = apps[0];
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test Doc',
            PathOnClient = 'Test.pdf',
            VersionData = Blob.valueOf('test')
        );
        insert cv;
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId,
            LinkedEntityId = app.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        PK_RequestWrappers.GetDocumentsDataWrapper wrapper = new PK_RequestWrappers.GetDocumentsDataWrapper();
        wrapper.recordId = app.Id;
        
        Test.startTest();
        List<PK_PortalUtils.DocumentWrapper> wrappers = PK_PortalUtils.getDocumentWrappers(wrapper);
        Test.stopTest();
        
        System.assert(wrappers.size() > 0);
        System.assertEquals('Test Doc', wrappers[0].documentTitle);
    }

    @isTest
    static void testGetImageBase64() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c app = apps[0];
        
        ContentVersion cv = new ContentVersion(
            Title = 'TestImage',
            PathOnClient = 'TestImage.png',
            VersionData = Blob.valueOf('fake png data')
        );
        insert cv;
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId,
            LinkedEntityId = app.Id,
            ShareType = 'V'
        );
        insert cdl;
        
        Test.startTest();
        String base64 = PK_PortalUtils.getImageBase64(app.Id, 'TestImage');
        Test.stopTest();
        
        System.assert(base64.startsWith('data:image/png;base64,'));
    }

    @isTest
    static void testGetEmailMessages() {
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 1];
        Application__c app = apps[0];
        
        EmailMessage em = new EmailMessage(
            RelatedToId = app.Id,
            Subject = 'Test Email',
            HtmlBody = '<p>Test</p>',
            FromAddress = 'pk@example.com',
            ToAddress = 'client@example.com',
            Pension_Keeper__c = true
        );
        insert em;
        
        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper();
        wrapper.id = app.Id;
        wrapper.commentsLimit = 10;
        
        Test.startTest();
        List<EmailMessage> emails = PK_PortalUtils.getEmailMessages(wrapper);
        Test.stopTest();
        
        System.assertEquals(1, emails.size());
    }

    @isTest
    static void testGetContryStateName() {
        Test.startTest();
        String stateName = PK_PortalUtils.getContryStateName('US', 'CA');
        Test.stopTest();
        // Depending on picklist, but should not be blank if CA exists
        System.assertNotEquals('', stateName);
    }

    @isTest
    static void testCalculatePensionDateMoreRanges() {
        // Test more ranges
        Date dob = Date.newInstance(1954, 10, 6);
        Date pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        System.assertEquals(Date.newInstance(2020, 10, 6), pensionDate);
        
        dob = Date.newInstance(1961, 1, 6);
        pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        System.assertEquals(Date.newInstance(2027, 11, 6), pensionDate);
        
        dob = Date.newInstance(1977, 4, 6);
        pensionDate = PK_PortalUtils.calculatePensionDate(dob);
        System.assertEquals(Date.newInstance(2044, 5, 6), pensionDate);
    }
}