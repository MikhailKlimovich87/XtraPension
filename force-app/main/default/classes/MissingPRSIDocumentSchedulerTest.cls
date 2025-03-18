@isTest
public class MissingPRSIDocumentSchedulerTest {
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
        TestDataFactory.createEmployer(
            testApplication.Id,
            'UK Work',
            'Unemployed',
            true
        );
    }


    @IsTest
    static void reportEmailScheduleTestCase1(){
        List<Application__c> testAppsBeforeUpdate = [
            SELECT
                Contain_Docs__c
            FROM Application__c
        ];
        Assert.areEqual(testAppsBeforeUpdate.isEmpty(), false);
        Assert.areEqual(testAppsBeforeUpdate[0].Contain_Docs__c, false);
        Test.startTest();
        MissingPRSIDocumentScheduler testScheduler = new MissingPRSIDocumentScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test status Check', cronEspression, testScheduler);
        Test.stopTest();
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId];
        Assert.areNotEqual(null, ct);
        Assert.areEqual('0 0 23 * * ?', ct.CronExpression);
        Assert.areEqual(0, ct.TimesTriggered);
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Contain_Docs__c
            FROM Application__c
        ];
        Assert.areEqual(testAppsAfterUpdate.isEmpty(), false);
        Assert.areEqual(testAppsAfterUpdate[0].Contain_Docs__c, true);
    }

    @IsTest
    static void reportEmailScheduleTestCase2() {
        List<Application__c> testAppsBeforeUpdate = [
            SELECT
                Contain_Docs__c
            FROM Application__c
        ];
        Employer__c testEmpl2 = TestDataFactory.createEmployer(
            testAppsBeforeUpdate[0].Id,
            'Work After UK',
            'Unemployed',
            false
        );
        testEmpl2.Start_Date__c = Date.newInstance(2010, 2, 2);
        testEmpl2.End_Date__c = Date.newInstance(2014, 2, 2);
        insert testEmpl2;
        Test.startTest();
        MissingPRSIDocumentScheduler testScheduler = new MissingPRSIDocumentScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test status Check', cronEspression, testScheduler);
        Test.stopTest();
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId];
        Assert.areNotEqual(null, ct);
        Assert.areEqual('0 0 23 * * ?', ct.CronExpression);
        Assert.areEqual(0, ct.TimesTriggered);
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Gap_Yrs_After_2006__c
            FROM Application__c
        ];
        Assert.areEqual(testAppsAfterUpdate.isEmpty(), false);
        Assert.areEqual(testAppsAfterUpdate[0].Gap_Yrs_After_2006__c, 4);
    }

    @IsTest
    static void reportEmailScheduleTestCase3() {
        List<Application__c> testAppsBeforeUpdate = [
            SELECT
                Contain_Docs__c
            FROM Application__c
        ];
        Employer__c testEmpl1 = TestDataFactory.createEmployer(
            testAppsBeforeUpdate[0].Id,
            'Work After UK',
            'Employed',
            false
        );
        testEmpl1.Start_Date__c = Date.newInstance(2007, 2, 2);
        testEmpl1.End_Date__c = Date.newInstance(2008, 2, 2);
        testEmpl1.Employers_Address__CountryCode__s = 'IE';
        insert testEmpl1;
        Employer__c testEmpl2 = TestDataFactory.createEmployer(
            testAppsBeforeUpdate[0].Id,
            'Work After UK',
            'Unemployed',
            false
        );
        testEmpl2.Start_Date__c = Date.newInstance(2010, 2, 2);
        testEmpl2.End_Date__c = Date.newInstance(2014, 2, 2);
        testEmpl2.Employers_Address__CountryCode__s = 'IE';
        insert testEmpl2;
        Test.startTest();
        MissingPRSIDocumentScheduler testScheduler = new MissingPRSIDocumentScheduler();
        String cronEspression = '0 0 23 * * ?';
		Id jobId = System.schedule('Test status Check', cronEspression, testScheduler);
        Test.stopTest();
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId];
        Assert.areNotEqual(null, ct);
        Assert.areEqual('0 0 23 * * ?', ct.CronExpression);
        Assert.areEqual(0, ct.TimesTriggered);
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Gap_Yrs_After_2006__c
            FROM Application__c
        ];
        Assert.areEqual(testAppsAfterUpdate.isEmpty(), false);
        Assert.areEqual(testAppsAfterUpdate[0].Gap_Yrs_After_2006__c, 0);
    }
}