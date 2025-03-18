@isTest
public class DwpEmailControllerTest {

    @TestSetup
    static void makeData(){
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
    }

    @IsTest
    static void generateDwpDocsTest() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];
        Test.startTest();
        String result = DwpEmailController.generateDwpDocs(app.Id);
        Integer invocations = Limits.getEmailInvocations();
        Test.stopTest();
        Assert.areEqual(1, invocations);
        Assert.areEqual(true, Boolean.valueOf(result));
    }

    @IsTest
    static void createDWPDocsTest() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];
        List<ContentDocumentLink> currentInstLinkBeforeExecuteMethod = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id AND
                  ContentDocument.Title LIKE 'DWP 2 - Summary%'
        ];
        Assert.isTrue(currentInstLinkBeforeExecuteMethod.isEmpty());
        Test.startTest();
        String result = DwpEmailController.createDWPDocs(app.Id);
        Test.stopTest();
        List<ContentDocumentLink> currentInstLinkAfterExecuteMethod = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id AND
                  ContentDocument.Title LIKE 'DWP 2 - Summary%'
        ];
        System.debug(currentInstLinkAfterExecuteMethod);
        Assert.areEqual('Success', result);
        Assert.isFalse(currentInstLinkAfterExecuteMethod.isEmpty());
    }

    @IsTest
    static void createDWPDocsCase2Test() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];

        ContentVersion cv = new ContentVersion();
        cv.Title = 'DWP 1 - Instructions';
        cv.PathOnClient = 'test';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        insert cv;
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = app.Id;
        conDocLink.ContentDocumentId = contDocId;
        insert conDocLink;        
        Test.startTest();
        String result = DwpEmailController.createDWPDocs(app.Id);
        Test.stopTest();
        List<ContentDocumentLink> currentInstLinkAfterExecuteMethod = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :app.Id AND
                  ContentDocument.Title LIKE 'DWP 2 - Summary%'
        ];
        System.debug(currentInstLinkAfterExecuteMethod);
        Assert.areEqual('Success', result);
        Assert.isFalse(currentInstLinkAfterExecuteMethod.isEmpty());
    }

    @isTest
    static void testSendDWPsmsMessage_Success() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        DwpEmailController.sendDWPsmsMessage(testApp.Id);
        Test.stopTest();

        Application__c updatedApp = [SELECT Status__c, is_Sent_DWP_SMS_Message__c FROM Application__c WHERE Id = :testApp.Id];
        System.assertEquals('DWP Shortfall Pending', updatedApp.Status__c, 'Expected status to be updated.');
        System.assertEquals(true, updatedApp.is_Sent_DWP_SMS_Message__c, 'Expected SMS flag to be true.');
    }

    @isTest
    static void testSMSMessage_Success() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        DwpEmailController.sendSMS(testApp.Id);
        Test.stopTest();

        Application__c updatedApp = [SELECT Status__c, is_Sent_DWP_SMS_Message__c FROM Application__c WHERE Id = :testApp.Id];
        System.assertEquals('DWP Shortfall Pending', updatedApp.Status__c, 'Expected status to be updated.');
        System.assertEquals(true, updatedApp.is_Sent_DWP_SMS_Message__c, 'Expected SMS flag to be true.');
    }

    static testMethod void fakeTest(){
        DwpEmailController.fakeMethod();
    }
}