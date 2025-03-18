@isTest
public class WorkDisplayControllerTest {
    @TestSetup
    static void setup(){
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
    }

    @IsTest
    static void getApplicationTest() {
        Application__c testApp = [
            SELECT
                Id,
                (SELECT
                    Id,
                    Type__c
                FROM Employers__r)
            FROM Application__c
            LIMIT 1
        ];


        Test.startTest();
        WorkDisplayController.ResultData result = WorkDisplayController.getApplication(testApp.Id);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result must be not null');
        System.assertEquals('Career Break', result.typeOfAfterUKEmployer, 'typeOfAfterUKEmployer must be Career Break');
        System.assertEquals('Success', result.status, 'Status must be Success');
    }

    @IsTest
    static void getUKAddressesTest() {
        Application__c testApp = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        testApp.Current_Address_Abroad__City__s = 'New York';
        testApp.Current_Address_Abroad__PostalCode__s = '40145';
        testApp.Current_Address_Abroad_Country__c = 'United States';
        testApp.Current_Address_Abroad_State__c = 'Iowa';
        testApp.Current_Address_Abroad__Street__s = '21 Test Street';
        update testApp;
        Test.startTest();
        WorkDisplayController.ResultAddressesData result = WorkDisplayController.getUKAddresses(testApp.Id);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result must be not null');
        System.assertEquals(null, result.errorMessage, 'errorMessage must be null');
        System.assertEquals('Success', result.status, 'Status must be Success');
        System.assertEquals(1, result.ukAddresses.size(), 'Amount of ukAddresses must be 1');
    }
}