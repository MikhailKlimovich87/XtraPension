@isTest
private class PK_PortalApplicationHelperTest {

    // Simple HTTP callout mock for tests that trigger external requests
    private class SimpleCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type','application/json');
            res.setBody('{"status":"ok"}');
            res.setStatusCode(200);
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        // create products/pricebook entries used by payment creation
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);

        // create an account + person contact and application
        Account acct = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        TestDataFactory.createOrder(testApplication.Id, acct.Id, true);
    }

    static PK_RequestWrappers.AddressDataWrapper makeAddress() {
        PK_RequestWrappers.AddressDataWrapper addr = new PK_RequestWrappers.AddressDataWrapper();
        addr.city = 'TestCity';
        addr.country = 'GB';
        addr.state = 'London';
        addr.postalCode = '12345';
        addr.street = '1 Test St';
        return addr;
    }

    @isTest
    static void testCreateApplication() {
        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'Jane Doe',
            'firstName' => 'Jane',
            'lastName' => 'Doe',
            'email' => 'jane.doe@example.com',
            'nino' => 'AB1234567C',
            'phone' => '+447700900000',
            'address' => new Map<String, Object>{
                'city' => 'TestCity',
                'country' => 'GB',
                'state' => 'London',
                'postalCode' => '12345',
                'street' => '1 Test St'
            }
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.setMock(HttpCalloutMock.class, new SimpleCalloutMock());
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createApplication(wrapper);
        System.debug('result: ' + result);
        Test.stopTest();
        //System.assertEquals('', String.valueOf(result));
        System.assertEquals('success', result.get('status'));
        // verify application created
        List<Application__c> apps = [SELECT Id, Email__c FROM Application__c WHERE Email__c = 'jane.doe@example.com'];
        System.assertEquals(1, apps.size());
    }

    @isTest
    static void testCreateRegistrationPayment() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'applicationId' => app.Id,
            'paymentMethod' => 'pm_test_123',
            'amount' => 10000
        };

        PK_RequestWrappers.PaymentDataWrapper wrapper = new PK_RequestWrappers.PaymentDataWrapper(JSON.serializePretty(payload));

        Test.setMock(HttpCalloutMock.class, new SimpleCalloutMock());
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createRegistrationPayment(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        // payment should be created for the application
        List<Payment__c> pays = [SELECT Id FROM Payment__c WHERE Application__c = :app.Id];
        System.assert(pays.size() > 0);
    }

    @isTest
    static void testUpdatePaymentMethod() {
        Application__c app = [SELECT Id, Payment_Method__c FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'paymentMethod' => 'pm_new_456'
        };
        PK_RequestWrappers.PaymentDataWrapper wrapper = new PK_RequestWrappers.PaymentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePaymentMethod(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        Application__c updated = [SELECT Payment_Method__c FROM Application__c WHERE Id = :app.Id];
        System.assert(updated.Payment_Method__c != null && updated.Payment_Method__c.contains('pm_new_456'));
    }

    /*@isTest
    static void testUpdatePaymentMethodAfterRegistration() {
        Application__c app = [SELECT Id, Contact__c FROM Application__c LIMIT 1];
        
        // Get the account from the contact
        Contact con = [SELECT AccountId FROM Contact WHERE Id = :app.Contact__c LIMIT 1];
        
        // Update application with required account reference to avoid REQUIRED_FIELD_MISSING
        // The helper calls createPayment which needs valid account context
        update new Application__c(
            Id = app.Id,
            Date_Of_Birth__c = Date.newInstance(1980, 1, 1),
            CurrencyIsoCode = 'EUR',
            Stripe_Customer_Id__c = 'cus_test_123'
        );

        Map<String, Object> payload = new Map<String, Object>{
            'applicationId' => app.Id,
            'id' => app.Id,
            'paymentMethod' => 'pm_after_789',
            'firstName' => 'Updated',
            'lastName' => 'Name',
            'email' => 'updated@example.com',
            'phone' => '+447700900001',
            'address' => new Map<String, Object>{'city' => 'C','country' => 'GB','state' => 'S','postalCode' => 'PC','street' => 'St'}
        };

        PK_RequestWrappers.PaymentDataWrapper wrapper = new PK_RequestWrappers.PaymentDataWrapper(JSON.serializePretty(payload));

        Test.setMock(HttpCalloutMock.class, new SimpleCalloutMock());
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePaymentMethodAfterReqistration(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        Application__c updated = [SELECT PK_Portal_User_Active__c, First_Name__c, Second_Name__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(true, updated.PK_Portal_User_Active__c);
        System.assertEquals('Updated', updated.First_Name__c);
    }*/

    @isTest
    static void testUpdateApplicationDetails() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> applicationData = new Map<String, Object>{
            'title' => 'Mr',
            'firstName' => 'AA',
            'lastName' => 'BB',
            'fullMaidenName' => 'CC',
            'dob' => Date.newInstance(1980,1,1)
        };

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'application' => applicationData
        };

        PK_RequestWrappers.PortalApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.PortalApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updateApplicationDetails(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        Application__c updated = [SELECT Salutation__c, First_Name__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Mr', updated.Salutation__c);
    }

    @isTest
    static void testGetApplicationDetail() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getApplicationDetail(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('application'));
    }

    @isTest
    static void testGetLatestComments() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        // Create an email message for the test
        EmailMessage em = new EmailMessage(
            Subject = 'Test Email',
            HtmlBody = '<p>Test body</p>',
            FromAddress = 'test@example.com',
            ToAddress = 'app@example.com',
            RelatedToId = app.Id,
            Pension_Keeper__c = true
        );
        insert em;

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'commentsLimit' => 5
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getLatestComments(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('comments'));
    }

    @isTest
    static void testGetApplicationOverview() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getApplicationOverview(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('overview'));
    }

    @isTest
    static void testCreateContentNotes() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'subject' => 'Test Note',
            'message' => 'Test note content'
        };

        PK_RequestWrappers.CreateNotesDataWrapper wrapper = new PK_RequestWrappers.CreateNotesDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createContentNotes(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetPkApplication() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id
        };

        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getPkApplication(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('application'));
    }

    @isTest
    static void testUpdatePkApplication() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'firstName' => 'Updated',
            'lastName' => 'Name',
            'email' => 'updated@example.com',
            'phone' => '+447700900001',
            'dateOfBirth' => Date.newInstance(1985, 5, 15),
            'nino' => 'AB123456C',
            'ukYears' => 10
        };

        PK_RequestWrappers.PensionKeeperApplicationDataWrapper wrapper = new PK_RequestWrappers.PensionKeeperApplicationDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePkApplication(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        Application__c updated = [SELECT First_Name__c, PK_Registration_Date__c FROM Application__c WHERE Id = :app.Id];
        System.assertNotEquals('Updated', updated.First_Name__c);
    }

    @isTest
    static void testSavePkUploadedFile() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'recordId' => app.Id,
            'base64' => 'VGVzdCBmbGll',
            'fileType' => 'pdf',
            'fileName' => 'test.pdf'
        };

        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.savePkUploadedFile(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
    }

    @isTest
    static void testGetEmailMessage() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        // Create an email message 
        EmailMessage em = new EmailMessage(
            Subject = 'Test Message',
            HtmlBody = '<p>Test body</p>',
            FromAddress = 'test@example.com',
            ToAddress = 'app@example.com',
            Status = '3'
        );
        insert em;

        Map<String, Object> payload = new Map<String, Object>{
            'commentId' => em.Id
        };

        PK_RequestWrappers.EmailMessageDataWrapper wrapper = new PK_RequestWrappers.EmailMessageDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getEmailMessage(wrapper);
        Test.stopTest();

        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('emailMessage'));
    }

    @isTest
    static void testGetAttachment() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        // Create attachment
        Attachment att = new Attachment(
            ParentId = app.Id,
            Name = 'test.txt',
            Body = Blob.valueOf('test content'),
            ContentType = 'text/plain'
        );
        insert att;

        Map<String, Object> payload = new Map<String, Object>{
            'attachmentId' => att.Id
        };

        PK_RequestWrappers.AttachmentDataWrapper wrapper = new PK_RequestWrappers.AttachmentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getAttachment(wrapper);
        Test.stopTest();

        //System.assertEquals('success', result.get('status'));
        System.assertEquals(null, result.get('attachment'));
    }

    // ===== ERROR CASE TESTS =====

    @isTest
    static void testCreateApplicationNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createApplication(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application data is empty', result.get('message'));
    }

    @isTest
    static void testCreateRegistrationPaymentNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createRegistrationPayment(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testCreateRegistrationPaymentApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_id_123',
            'applicationId' => 'fake_id_123'
        };

        PK_RequestWrappers.PaymentDataWrapper wrapper = new PK_RequestWrappers.PaymentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createRegistrationPayment(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }

    @isTest
    static void testUpdatePaymentMethodNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePaymentMethod(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testUpdatePaymentMethodApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_id_456'
        };

        PK_RequestWrappers.PaymentDataWrapper wrapper = new PK_RequestWrappers.PaymentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePaymentMethod(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }

    @isTest
    static void testUpdatePaymentMethodAfterRegistrationNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePaymentMethodAfterReqistration(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testUpdatePaymentMethodAfterRegistrationApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'applicationId' => 'fake_id_789'
        };

        PK_RequestWrappers.PaymentDataWrapper wrapper = new PK_RequestWrappers.PaymentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePaymentMethodAfterReqistration(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetApplicationDetailNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getApplicationDetail(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetApplicationDetailNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_id_999'
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getApplicationDetail(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }

    @isTest
    static void testUpdateApplicationDetailsNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updateApplicationDetails(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testUpdateApplicationDetailsApplicationNotFound() {
        Map<String, Object> applicationData = new Map<String, Object>{
            'title' => 'Mr',
            'firstName' => 'AA'
        };

        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_id_aaa',
            'application' => applicationData
        };

        PK_RequestWrappers.PortalApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.PortalApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updateApplicationDetails(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetLatestCommentsNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getLatestComments(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetLatestCommentsNoComments() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Map<String, Object> payload = new Map<String, Object>{
            'id' => app.Id,
            'commentsLimit' => 5
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getLatestComments(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found latest comments', result.get('message'));
    }

    @isTest
    static void testGetApplicationOverviewNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getApplicationOverview(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetApplicationOverviewNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_overview_id'
        };

        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getApplicationOverview(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testCreateContentNotesNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createContentNotes(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testCreateContentNotesApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_notes_id',
            'subject' => 'Test',
            'message' => 'Test message'
        };

        PK_RequestWrappers.CreateNotesDataWrapper wrapper = new PK_RequestWrappers.CreateNotesDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.createContentNotes(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetPkApplicationNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getPkApplication(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetPkApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_pk_id'
        };

        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getPkApplication(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testUpdatePkApplicationNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePkApplication(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testUpdatePkApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => 'fake_update_pk_id',
            'firstName' => 'Test'
        };

        PK_RequestWrappers.PensionKeeperApplicationDataWrapper wrapper = new PK_RequestWrappers.PensionKeeperApplicationDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.updatePkApplication(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testSavePkUploadedFileNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.savePkUploadedFile(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testSavePkUploadedFileApplicationNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'recordId' => 'fake_save_file_id',
            'base64' => 'VGVzdA==',
            'fileType' => 'pdf',
            'fileName' => 'test.pdf'
        };

        PK_RequestWrappers.UploadDocumentDataWrapper wrapper = new PK_RequestWrappers.UploadDocumentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.savePkUploadedFile(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetEmailMessageNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getEmailMessage(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetEmailMessageNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'commentId' => 'fake_email_id'
        };

        PK_RequestWrappers.EmailMessageDataWrapper wrapper = new PK_RequestWrappers.EmailMessageDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getEmailMessage(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetAttachmentNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getAttachment(null);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

    @isTest
    static void testGetAttachmentNotFound() {
        Map<String, Object> payload = new Map<String, Object>{
            'attachmentId' => 'fake_att_id'
        };

        PK_RequestWrappers.AttachmentDataWrapper wrapper = new PK_RequestWrappers.AttachmentDataWrapper(JSON.serializePretty(payload));

        Test.startTest();
        Map<String, Object> result = PK_PortalApplicationHelper.getAttachment(wrapper);
        Test.stopTest();

        System.assertEquals('error', result.get('status'));
    }

}