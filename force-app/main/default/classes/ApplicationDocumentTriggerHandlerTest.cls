@isTest
public class ApplicationDocumentTriggerHandlerTest {
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
    static void createApplicationDocument() {
        Application__c testApp = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        TestDataFactory.createApplicationDocument(testApp.Id, true);
    }
}