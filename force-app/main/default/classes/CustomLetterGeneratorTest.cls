@isTest
public class CustomLetterGeneratorTest {

    @TestSetup
    static void makeData(){
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Contains_new_version_of_Custom_Letter__c = false;
        testApplication.DWP_Callback_Request__c = '12 Apr 12:00';
        insert testApplication;
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test_CustomLetter';
        cv.PathOnClient = 'test';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        cv.FirstPublishLocationId = testApplication.Id;
        insert cv;
    }

    @IsTest
    static void generateCustomLetterTest() {
        List<Application__c> testApps = [
            SELECT Id
            FROM Application__c
        ];
        Application__c app = testApps[0];
        List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CustomLetter%' AND
                  LinkedEntityId = :app.Id
        ];
        Assert.areEqual(1, oldDocuments.size());
        Test.startTest();
        CustomLetterGenerator.generateCustomLetter(app.Id);
        Test.stopTest();
        List<ContentDocumentLink> newDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CustomLetter%' AND
                  LinkedEntityId = :app.Id
        ];
        Assert.areEqual(2, newDocuments.size());
    }
}