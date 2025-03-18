@isTest
public class DwpStatusCheckControllerTest {
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
    static void genetateDWPDocTest(){
        List<Application__c> testApps = [
            SELECT
                Id,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%DWPStatusCheck%')
            FROM Application__c
            LIMIT 1
        ];
        Application__c app = testApps[0];
        Assert.areEqual(0, app.ContentDocumentLinks.size());
        Test.startTest();
        String result = DwpStatusCheckController.genetateDWPDoc(app.Id);
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                (SELECT
                    ContentDocument.Title
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%DWPStatusCheck%')
            FROM Application__c
            WHERE Id = :app.Id
            LIMIT 1
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];
        Assert.areEqual(1, appAfterUpdate.ContentDocumentLinks.size());
    }
}