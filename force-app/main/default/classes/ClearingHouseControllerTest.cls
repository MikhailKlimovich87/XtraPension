@isTest
public class ClearingHouseControllerTest {
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
        ContentVersion testContentVersion = TestDataFactory.createTestContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        insert conDocLink;
        Employer__c testEmpl1 = TestDataFactory.createEmployer(
            testApplication.Id,
            'Work After UK',
            'Employed',
            false
        );
        testEmpl1.Start_Date__c = Date.newInstance(2007, 2, 2);
        testEmpl1.End_Date__c = Date.newInstance(2008, 2, 2);
        testEmpl1.Employers_Address__CountryCode__s = 'IE';
        insert testEmpl1;
        Employer__c testEmpl2 = TestDataFactory.createEmployer(
            testApplication.Id,
            'Work After UK',
            'Unemployed',
            false
        );
        testEmpl2.Start_Date__c = Date.newInstance(2010, 2, 2);
        testEmpl2.End_Date__c = Date.newInstance(2014, 2, 2);
        testEmpl2.Employers_Address__CountryCode__s = 'IE';
        insert testEmpl2;
        TestDataFactory.createEmployer(
            testApplication.Id,
            'UK Work',
            'Unemployed',
            true
        );
    }

    @IsTest
    static void getApplicationsTestCase1() {
        Test.startTest();
        ClearingHouseController.CleaningHouseTableWrapper testTableData = ClearingHouseController.getApplications();
        Test.stopTest();
        Assert.areEqual(false, testTableData.tableUp.isEmpty());
        Assert.areEqual(1, testTableData.tableUp.size());
        Assert.areNotEqual(null, testTableData.tableUp[0].app.National_Insurance_Number__c);
    }

    @IsTest
    static void getApplicationsTestCase2() {List<Application__c> apps = [
        SELECT
            First_Name__c,
            Second_Name__c,
            Name,
            Status__c,
            National_Insurance_Number__c
        FROM Application__c
    ];
        Application__c testApp = apps[0];
        testApp.National_Insurance_Number__c = null;
        update testApp;
        Test.startTest();
        ClearingHouseController.CleaningHouseTableWrapper testTableData = ClearingHouseController.getApplications();
        Test.stopTest();
        Assert.areEqual(false, testTableData.tableUp.isEmpty());
        Assert.areEqual(1, testTableData.tableUp.size());
        Assert.areEqual(null, testTableData.tableUp[0].app.National_Insurance_Number__c);
    }

    @IsTest
    static void getApplicationsTestCase3() {
        List<Employer__c> employers = [
            SELECT Id, Type__c
            FROM Employer__c
            WHERE Type__c = 'Work After UK'
        ];
        System.debug(employers);
        System.debug(employers.size());
        delete employers[0];
        Test.startTest();
        ClearingHouseController.CleaningHouseTableWrapper testTableData = ClearingHouseController.getApplications();
        Test.stopTest();
        Assert.areEqual(false, testTableData.tableUp.isEmpty());
        Assert.areEqual(1, testTableData.tableUp.size());
        Assert.areEqual('AS1234578A', testTableData.tableUp[0].app.National_Insurance_Number__c);
    }
}