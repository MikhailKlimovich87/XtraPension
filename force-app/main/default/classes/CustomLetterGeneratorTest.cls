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
        Assert.areEqual(0, oldDocuments.size());
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
        Assert.areEqual(1, newDocuments.size());
    }
}