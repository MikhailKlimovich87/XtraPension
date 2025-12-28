@isTest
public class CallFollowUpModuleControllerTest {
    @TestSetup
    static void setupData() {
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

        TestDataFactory.createStandardUser(true);
    }


    @IsTest
    static void testLogCall_Success() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        User u = [SELECT Id FROM User WHERE FirstName = 'TestFirst' LIMIT 1];

        Test.startTest();
        Id taskId = CallFollowUpModuleController.logCall('Follow up', testApp.Id, u.Id);
        Test.stopTest();

        Task t = [SELECT Subject, Status, WhatId, Type FROM Task WHERE Id = :taskId];
        System.assertEquals('Completed', t.Status);
        System.assertEquals('Call', t.Type);
        System.assertEquals(testApp.Id, t.WhatId);
        System.assert(t.Subject.contains('Follow up'));
        System.assert(t.Subject.contains('Creator: TestFirst'));
    }
}