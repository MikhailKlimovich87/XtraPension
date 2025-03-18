@isTest
public class ContentDocumentTriggerHelperTest {
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
    static void saveNoteOnRelatedApplicationTest() {
        List<Application__c> testApps = [
            SELECT Id, Notes__c
            FROM Application__c
        ];
        Application__c app = testApps[0];
        Assert.isNull(app.Notes__c);
        ContentNote cn = new ContentNote();
        cn.Title = 'Test_UPLOAD';
        cn.Content = Blob.valueOf('<p>Unit Test Attachment Body</p>');
        insert cn;
        Id cvId = [SELECT LatestPublishedVersionId FROM ContentNote WHERE Id = :cn.Id][0].LatestPublishedVersionId;
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvId][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = app.Id;
        conDocLink.ContentDocumentId = contDocId;
        Test.startTest();
        insert conDocLink;
        Test.stopTest();
        List<ContentDocumentLink> testDocs = [
            SELECT
                ContentDocumentId,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE ContentDocument.FileType = 'SNOTE' AND
                  LinkedEntityId = :app.Id
        ];
        System.debug(testDocs[0].ContentDocument.LatestPublishedVersion.VersionData);
        List<Application__c> testAppsAfterUpdate = [
            SELECT Id, Notes__c
            FROM Application__c
        ];
        Assert.isNotNull(testAppsAfterUpdate[0].Notes__c);
        Assert.areEqual(testDocs[0].ContentDocument.LatestPublishedVersion.VersionData.toString(), testAppsAfterUpdate[0].Notes__c);
    }
}