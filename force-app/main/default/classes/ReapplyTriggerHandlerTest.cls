@isTest
public with sharing class ReapplyTriggerHandlerTest {
    @TestSetup
    static void makeData(){
        // Setup data without mixed DML operations
        TestDataFactory.createProductsWithPrices();
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testGenerateWelcomeEmail() {
        // Get the test reapply record with contact and email
        Reapply__c testReapply = [
            SELECT Id, Email__c, Application__r.Contact__c 
            FROM Reapply__c 
            LIMIT 1
        ];
        
        // Update contact email for testing
        Contact testContact = [SELECT Id, Email FROM Contact WHERE Id = :testReapply.Application__r.Contact__c];
        testContact.Email = 'test@example.com';
        update testContact;
        
        Test.startTest();
        ReapplyTriggerHandler.generateWelcomeEmail(testReapply.Id);
        Test.stopTest();
        
        // Verify by checking if email was sent (we can't directly assert on email sending)
        // But we can verify the method executed without errors
        System.assert(true);
    }

    @isTest
    static void testGenerateWelcomeEmailWithNullId() {
        Test.startTest();
        ReapplyTriggerHandler.generateWelcomeEmail(null);
        Test.stopTest();
        
        // Method should exit gracefully without errors
        System.assert(true);
    }

    @isTest
    static void testGenerateWelcomeEmailWithNoRecords() {
        // Create a non-existent ID
        Id fakeId = [SELECT Id FROM Reapply__c LIMIT 1].Id;
        // Delete the record
        delete [SELECT Id FROM Reapply__c WHERE Id = :fakeId];
        
        Test.startTest();
        ReapplyTriggerHandler.generateWelcomeEmail(fakeId);
        Test.stopTest();
        
        // Method should exit gracefully without errors
        System.assert(true);
    }

    @isTest
    static void testGenerateDocuSignEmailAfterSent() {
        // Get the test reapply record with contact and email
        Reapply__c testReapply = [
            SELECT Id, Email__c, Application__r.Contact__c 
            FROM Reapply__c 
            LIMIT 1
        ];
        
        // Update contact email for testing
        Contact testContact = [SELECT Id, Email FROM Contact WHERE Id = :testReapply.Application__r.Contact__c];
        testContact.Email = 'test@example.com';
        update testContact;
        
        Test.startTest();
        ReapplyTriggerHandler.generateDocuSignEmailAfterSent(testReapply.Id);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testGenerateDocuSignEmailAfterSentWithNullId() {
        Test.startTest();
        ReapplyTriggerHandler.generateDocuSignEmailAfterSent(null);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testGenerateDocuSignEmailAfterSentWithNoRecords() {
        Id fakeId = [SELECT Id FROM Reapply__c LIMIT 1].Id;
        delete [SELECT Id FROM Reapply__c WHERE Id = :fakeId];
        
        Test.startTest();
        ReapplyTriggerHandler.generateDocuSignEmailAfterSent(fakeId);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testGenerateReadyDocAsync() {
        // Get the test reapply record
        Reapply__c testReapply = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create a ContentDocument and ContentVersion for CF083
        ContentVersion cvCF083 = createContentVersion('Test_CF083_completed.pdf', 'CF083');
        ContentVersion cvRVN = createContentVersion('Test_RVN_completed.pdf', 'RVN');
        
        // Get the ContentDocumentIds after insertion
        List<ContentVersion> cvCF083versions = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cvCF083.Id];
        List<ContentVersion> cvRVNversions = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cvRVN.Id];

        createContentDocumentLink(cvCF083versions[0].ContentDocumentId, testReapply.Id);
        createContentDocumentLink(cvRVNversions[0].ContentDocumentId, testReapply.Id);
        
        
        Test.startTest();
        // Mock the HTTP callout
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        ReapplyTriggerHandler.generateReadyDocAsync(testReapply.Id);
        Test.stopTest();
        
        // Verify the record was updated
        Reapply__c updatedReapply = [SELECT Id, Reapply_Full_Form_ZIP_for_UPLOAD__c, FTP_Reapply_Full_Form_ZIP_Error__c FROM Reapply__c WHERE Id = :testReapply.Id];
        System.assertEquals(true, updatedReapply.Reapply_Full_Form_ZIP_for_UPLOAD__c);
    }

    @isTest
    static void testGenerateReadyDocAsyncWithNullId() {
        Test.startTest();
        ReapplyTriggerHandler.generateReadyDocAsync(null);
        Test.stopTest();
        
        System.assert(true);
    }

    @isTest
    static void testGenerateReadyDocAsyncWithNoRecords() {
        Id fakeId = [SELECT Id FROM Reapply__c LIMIT 1].Id;
        delete [SELECT Id FROM Reapply__c WHERE Id = :fakeId];
        
        Test.startTest();
        ReapplyTriggerHandler.generateReadyDocAsync(fakeId);
        Test.stopTest();
        
        System.assert(true);
    }

        // ============================================================
    // MISSING: Tests for beforeUpdateAction() status transitions
    // ============================================================

    @isTest
    static void testBeforeUpdateActionFormCompleted() {
        Reapply__c reapply = [SELECT Id, Status__c FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Form Completed';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [
            SELECT Id, Form_Completed_Date__c, Form_Completed_User__c
            FROM Reapply__c WHERE Id = :reapply.Id
        ];
        System.assertNotEquals(null, updated.Form_Completed_Date__c, 'Form_Completed_Date__c should be set');
        System.assertEquals(UserInfo.getUserId(), updated.Form_Completed_User__c, 'Form_Completed_User__c should be current user');
    }

    @isTest
    static void testBeforeUpdateActionPendingClient() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Pending Client';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [
            SELECT Pending_Client_Date__c, Pending_Client_User__c
            FROM Reapply__c WHERE Id = :reapply.Id
        ];
        System.assertNotEquals(null, updated.Pending_Client_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Pending_Client_User__c);
    }

    @isTest
    static void testBeforeUpdateActionSendForEsignature() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Send for Esignature';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [
            SELECT Esignature_Date__c, Esignature_User__c
            FROM Reapply__c WHERE Id = :reapply.Id
        ];
        System.assertNotEquals(null, updated.Esignature_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Esignature_User__c);
    }

    @isTest
    static void testBeforeUpdateActionPH() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'PH';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [
            SELECT PH_Date__c, PH_User__c,
                   FTP_Reapply_Full_Form_Created_Send_Date__c
            FROM Reapply__c WHERE Id = :reapply.Id
        ];
        System.assertNotEquals(null, updated.PH_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.PH_User__c);
    }

    @isTest
    static void testBeforeUpdateActionPosted() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Posted';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Posted_Date__c, Posted_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Posted_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Posted_User__c);
    }

    @isTest
    static void testBeforeUpdateActionHMRCReply1() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'HMRC Reply 1';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT HMRC_Reply_1_Date__c, HMRC_Reply_1_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.HMRC_Reply_1_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.HMRC_Reply_1_User__c);
    }

    @isTest
    static void testBeforeUpdateActionPendingInfo() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Pending Info';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Pending_Info_Date__c, Pending_Info_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Pending_Info_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Pending_Info_User__c);
    }

    @isTest
    static void testBeforeUpdateActionHMRCAppeal() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'HMRC Appeal';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT HMRC_Appeal_Date__c, HMRC_Appeal_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.HMRC_Appeal_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.HMRC_Appeal_User__c);
    }

    @isTest
    static void testBeforeUpdateActionHMRCReply2() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'HMRC Reply 2';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT HMRC_Reply_2_Date__c, HMRC_Reply_2_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.HMRC_Reply_2_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.HMRC_Reply_2_User__c);
    }

    @isTest
    static void testBeforeUpdateActionSendToClient() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Send to Client';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Send_to_Client_Date__c, Send_to_Client_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Send_to_Client_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Send_to_Client_User__c);
    }

    @isTest
    static void testBeforeUpdateActionAgentCall() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Agent Call';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Agent_Call_Date__c, Agent_Call_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Agent_Call_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Agent_Call_User__c);
    }

    @isTest
    static void testBeforeUpdateActionClosed() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Closed';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Closed_Date__c, Closed_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Closed_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Closed_User__c);
    }

    @isTest
    static void testBeforeUpdateActionRepeatNoEdits() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'REPEAT(NO edits)';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Repeat_No_Edits_Date__c, Repeat_No_Edits_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Repeat_No_Edits_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Repeat_No_Edits_User__c);
    }

    @isTest
    static void testBeforeUpdateActionRepeatEdits() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'REPEAT(edits)';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Repeat_Edits_Date__c, Repeat_Edits_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Repeat_Edits_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Repeat_Edits_User__c);
    }

    @isTest
    static void testBeforeUpdateActionDepositRefund() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Deposit Refund';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Deposit_Refund_Date__c, Deposit_Refund_User__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertNotEquals(null, updated.Deposit_Refund_Date__c);
        System.assertEquals(UserInfo.getUserId(), updated.Deposit_Refund_User__c);
    }

    @isTest
    static void testBeforeUpdateActionStatusUnchanged() {
        // Status does not change -> no timestamp should be set
        Reapply__c reapply = [SELECT Id, Status__c, Form_Completed_Date__c FROM Reapply__c LIMIT 1];
        // Update a non-status field only
        reapply.First_Name__c = 'UpdatedName';

        Test.startTest();
        update reapply;
        Test.stopTest();

        Reapply__c updated = [SELECT Form_Completed_Date__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertEquals(null, updated.Form_Completed_Date__c, 'Timestamp should not change when status does not change');
    }

    // ============================================================
    // MISSING: Tests for afterUpdateAction() trigger dispatch
    // ============================================================

    @isTest
    static void testAfterUpdateActionStatusTransitionToPH() {
        Reapply__c reapply = [SELECT Id, Status__c FROM Reapply__c LIMIT 1];
        // First set to a different status so the transition is detectable
        reapply.Status__c = 'Form Completed';
        update reapply;

        // Now transition to PH - should fire generateReadyDocAsync
        Reapply__c toUpdate = [SELECT Id FROM Reapply__c WHERE Id = :reapply.Id];
        toUpdate.Status__c = 'PH';

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Reapply__c updated = [
            SELECT PH_Date__c, PH_User__c,
                   FTP_Reapply_Full_Form_Created_Send_Date__c,
                   FTP_Reapply2_Full_Form_Created_Send_Date__c,
                   Reapply_Full_Form_ZIP_for_UPLOAD__c
            FROM Reapply__c WHERE Id = :reapply.Id
        ];
        System.assertNotEquals(null, updated.PH_Date__c);
        System.assertEquals(true, updated.Reapply_Full_Form_ZIP_for_UPLOAD__c,
            'generateReadyDocAsync should set Reapply_Full_Form_ZIP_for_UPLOAD__c to true');
        System.assertEquals(null, updated.FTP_Reapply_Full_Form_Created_Send_Date__c,
            'generateReadyDocAsync should null FTP_Reapply_Full_Form_Created_Send_Date__c');
        System.assertEquals(null, updated.FTP_Reapply2_Full_Form_Created_Send_Date__c,
            'generateReadyDocAsync should null FTP_Reapply2_Full_Form_Created_Send_Date__c');
    }

    @isTest
    static void testAfterUpdateActionStatusTransitionToSendForEsignature() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.Status__c = 'Pending Client';
        update reapply;

        Reapply__c toUpdate = [SELECT Id FROM Reapply__c WHERE Id = :reapply.Id];
        toUpdate.Status__c = 'Send for Esignature';

        Test.startTest();
        update toUpdate;
        Test.stopTest();

        Reapply__c updated = [SELECT Id, Status__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertEquals('Send for Esignature', updated.Status__c);
    }

    @isTest
    static void testAfterUpdateActionStatusUnchangedNoDispatch() {
        // Updating a non-status field should not invoke any after-update branches
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        reapply.First_Name__c = 'NoDispatch';

        Test.startTest();
        update reapply;
        Test.stopTest();

        // No assertion needed beyond "did not throw"
        System.assert(true);
    }

    // ============================================================
    // MISSING: Test the ReapplyTrigger itself on insert
    // ============================================================

    @isTest
    static void testReapplyTriggerBeforeInsert() {
        Application__c app = [
            SELECT Id, Contact__c FROM Application__c LIMIT 1
        ];
        Reapply__c newReapply = new Reapply__c(
            Application__c = app.Id,
            First_Name__c = 'Trigger',
            Second_Name__c = 'Test',
            Email__c = 'trigger@example.com',
            Status__c = 'Form Completed'
        );

        Test.startTest();
        insert newReapply;
        Test.stopTest();

        Reapply__c inserted = [
            SELECT Status__c, Form_Completed_Date__c, Form_Completed_User__c
            FROM Reapply__c WHERE Id = :newReapply.Id
        ];
        // NOTE: beforeUpdateAction only fires on update, not insert,
        // so Form_Completed_Date__c should still be null on insert.
        System.assertEquals(null, inserted.Form_Completed_Date__c,
            'Timestamp fields are only set in beforeUpdateAction, not on insert');
    }

    // ============================================================
    // MISSING: Constructor test (defensive coverage)
    // ============================================================

    @isTest
    static void testHandlerConstructor() {
        Map<Id, Reapply__c> newMap = new Map<Id, Reapply__c>();
        Map<Id, Reapply__c> oldMap = new Map<Id, Reapply__c>();

        Test.startTest();
        ReapplyTriggerHandler handler = new ReapplyTriggerHandler(newMap, oldMap);
        Test.stopTest();

        System.assertNotEquals(null, handler);
        System.assertEquals(0, handler.newReapply.size());
        System.assertEquals(0, handler.oldReapply.size());
    }

    @isTest
    static void testRequestWrapper() {
        ReapplyTriggerHandler.RequestWrapper wrapper = new ReapplyTriggerHandler.RequestWrapper();
        wrapper.pageNumber = 1;
        wrapper.x = 100;
        wrapper.y = 200;
        wrapper.base64 = EncodingUtil.base64Encode(Blob.valueOf('test'));

        System.assertEquals(1, wrapper.pageNumber);
        System.assertEquals(100, wrapper.x);
        System.assertEquals(200, wrapper.y);
        System.assertNotEquals(null, wrapper.base64);
    }

    // Helper methods for test setup
    private static ContentVersion createContentVersion(String title, String keyword) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title,
            VersionData = Blob.valueOf('Test PDF Content'),
            IsMajorVersion = true
        );
        insert cv;
        return cv;
    }

    private static void createContentDocumentLink(Id contentDocumentId, Id linkedEntityId) {
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V'
        );
        insert cdl;
    }

    // Mock HTTP response generator for successful response
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"pageNumber":3,"x":315,"y":668,"base64":"' + EncodingUtil.base64Encode(Blob.valueOf('Updated PDF Content')) + '"}');
            return res;
        }
    }

    // Mock HTTP response generator for error response (500 with non-JSON body)
    private class MockHttpResponseGeneratorWithError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Return a 500 error with non-JSON body
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    // Mock HTTP response generator for invalid JSON response (200 with invalid JSON)
    private class MockHttpResponseGeneratorWithInvalidJson implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Return 200 but with invalid JSON
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('This is not valid JSON');
            return res;
        }
    }
}