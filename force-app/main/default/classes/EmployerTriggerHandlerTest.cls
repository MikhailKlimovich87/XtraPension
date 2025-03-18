@isTest
public class EmployerTriggerHandlerTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c = 'Agent Check';
        testApplication.Type_Of_Employment__c = 'Self-Employed';
        testApplication.Date_Of_Leaving_Last_UK__c = Date.valueOf('2009-01-09');
        testApplication.Abroad_Start_Date__c = Date.valueOf('2007-01-09');
        testApplication.SelfEmployment_Employment_Abroad__c = 'Employed';
        insert testApplication;
        Employer__c firstTestEmployer = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK','Career Break', false);
        firstTestEmployer.Is_First_Employer__c = false;
        Employer__c secondTestEmployer   = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK','Self-Employed', false);
        secondTestEmployer.Start_Date__c = Date.valueOf('2010-03-09');
        secondTestEmployer.End_Date__c   = Date.valueOf('2011-02-09');
        Employer__c thirdTestEmployer    = TestDataFactory.createEmployer(testApplication.Id, 'UK Work','Self-Employed', false);
        thirdTestEmployer.Start_Date__c = Date.valueOf('2008-03-08');
        thirdTestEmployer.End_Date__c   = Date.valueOf('2009-01-09');
        thirdTestEmployer.Type_Of_UK_Employment__c = 'Self-Employed';
        thirdTestEmployer.Type_Of_After_UK_Employment__c = null;
        List<Employer__c> testEmployers = new List<Employer__c>();
        testEmployers.add(firstTestEmployer);
        testEmployers.add(secondTestEmployer);
        testEmployers.add(thirdTestEmployer);
        insert testEmployers;
    }

    @isTest
    static void updateApplicationAfterUKEmployerStartDateTest() {
        Application__c testAppBeforeUpdate = [
            SELECT
                Abroad_Start_Date__c,
                Self_Employed_Start_Date1__c
            FROM Application__c
        ];
        System.assertNotEquals(null, testAppBeforeUpdate);
        //System.assertEquals(null, testAppBeforeUpdate.Abroad_Start_Date__c);
        System.assertEquals(null, testAppBeforeUpdate.Self_Employed_Start_Date1__c);
        Test.startTest();
        List<Employer__c> testEmployers = [
            SELECT
                Type_Of_After_UK_Employment__c,
                Start_Date__c
            FROM Employer__c
        ];
        for (Employer__c employer : testEmployers) {
            if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                employer.Start_Date__c = Date.valueOf('2010-03-10');
            }
            if (employer.Type_Of_After_UK_Employment__c == 'Career Break') {
                employer.Start_Date__c = Date.valueOf('2010-03-11');
            }
        }
        update testEmployers;
        Test.stopTest();
        Application__c testAppAfterUpdate = [
            SELECT
                Abroad_Start_Date__c,
                Self_Employed_Start_Date1__c
            FROM Application__c
        ];
        System.assertNotEquals(null, testAppAfterUpdate);
        System.assertNotEquals(null, testAppAfterUpdate.Abroad_Start_Date__c);
        System.assertNotEquals(null, testAppAfterUpdate.Self_Employed_Start_Date1__c);
        System.assertEquals(Date.valueOf('2010-03-10'), testAppAfterUpdate.Abroad_Start_Date__c);
        System.assertEquals(Date.valueOf('2010-03-10'), testAppAfterUpdate.Self_Employed_Start_Date1__c);
        System.assertNotEquals(Date.valueOf('2010-03-11'), testAppAfterUpdate.Abroad_Start_Date__c);
        System.assertNotEquals(Date.valueOf('2010-03-11'), testAppAfterUpdate.Self_Employed_Start_Date1__c);
    }

    @isTest
    static void updateAddressDataTestCase1() {
        Application__c testAppBeforeUpdate = [
            SELECT
                Id,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__Street__s
            FROM Application__c
        ];
        System.assertNotEquals(null, testAppBeforeUpdate);
        System.assertEquals(null, testAppBeforeUpdate.Abroad_Employer_Name1__c);
        System.assertEquals(null, testAppBeforeUpdate.Abroad_Employer_Address1__PostalCode__s);
        System.assertEquals(null, testAppBeforeUpdate.Abroad_Employer_Address1__Street__s);
        System.assertEquals(null, testAppBeforeUpdate.Abroad_Employer_Address1__City__s);
        Employer__c testEmpl = TestDataFactory.createEmployer(testAppBeforeUpdate.Id, 'Work After UK', 'Employed', false);
        testEmpl.Employer_Name__c                  = 'Test Employer';
        testEmpl.Employers_Address__City__s        = 'Test';
        testEmpl.Employers_Address__CountryCode__s = 'AU';
        testEmpl.Employers_Address__PostalCode__s  = '1111';
        testEmpl.Employers_Address__StateCode__s   = 'SA';
        testEmpl.Employers_Address__Street__s      = '1 Test Street';
        insert testEmpl;
        testEmpl.Employers_Address__PostalCode__s = '2222';
        testEmpl.Employers_Address__City__s        = 'Test2';
        testEmpl.Employers_Address__Street__s      = '2 Test Street';
        testEmpl.Employer_Name__c                  = 'Test Employer2';
        update testEmpl;
        Application__c testAppAfterUpdate = [
            SELECT
                Abroad_Employer_Name1__c,
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__Street__s
            FROM Application__c
        ];
        System.assertNotEquals(null, testAppAfterUpdate);
        System.assertNotEquals(null, testAppAfterUpdate.Abroad_Employer_Name1__c);
        System.assertNotEquals(null, testAppAfterUpdate.Abroad_Employer_Address1__City__s);
        System.assertNotEquals(null, testAppAfterUpdate.Abroad_Employer_Address1__PostalCode__s);
        System.assertNotEquals(null, testAppAfterUpdate.Abroad_Employer_Address1__Street__s);
        System.assertEquals(testEmpl.Employers_Address__PostalCode__s, testAppAfterUpdate.Abroad_Employer_Address1__PostalCode__s);
        System.assertEquals(testEmpl.Employers_Address__City__s, testAppAfterUpdate.Abroad_Employer_Address1__City__s);
        System.assertEquals(testEmpl.Employers_Address__Street__s, testAppAfterUpdate.Abroad_Employer_Address1__Street__s);
        System.assertEquals(testEmpl.Employer_Name__c, testAppAfterUpdate.Abroad_Employer_Name1__c);
    }

    @isTest
    static void updateAddressDataTestCase2() {
        Application__c testAppBeforeUpdate = [
            SELECT
                Id,
                Last_UK_Employer_Name__c,
                Last_UK_Employer_Address__City__s,
                Last_UK_Employer_Address__CountryCode__s,
                Last_UK_Employer_Address__Street__s,
                Last_UK_Employer_Address__PostalCode__s
            FROM Application__c
        ];
        System.assertNotEquals(null, testAppBeforeUpdate);
        System.assertEquals(null, testAppBeforeUpdate.Last_UK_Employer_Name__c);
        System.assertEquals(null, testAppBeforeUpdate.Last_UK_Employer_Address__CountryCode__s);
        System.assertEquals(null, testAppBeforeUpdate.Last_UK_Employer_Address__Street__s);
        System.assertEquals(null, testAppBeforeUpdate.Last_UK_Employer_Address__City__s);
        System.assertEquals(null, testAppBeforeUpdate.Last_UK_Employer_Address__PostalCode__s);
        Employer__c testEmpl = TestDataFactory.createEmployer(testAppBeforeUpdate.Id, 'UK Work', null, false);
        testEmpl.Employer_Name__c                  = 'Test Employer';
        testEmpl.Employers_Address__City__s        = 'Test';
        testEmpl.Employers_Address__CountryCode__s = 'AU';
        testEmpl.Employers_Address__PostalCode__s  = '1111';
        testEmpl.Employers_Address__StateCode__s   = 'SA';
        testEmpl.Employers_Address__Street__s      = '1 Test Street';
        insert testEmpl;
        testEmpl.Employers_Address__CountryCode__s = 'GB';
        testEmpl.Employers_Address__City__s        = 'Test2';
        testEmpl.Employers_Address__Street__s      = '2 Test Street';
        testEmpl.Employer_Name__c                  = 'Test Employer2';
        testEmpl.Employers_Address__PostalCode__s  = '2222';
        update testEmpl;
        Application__c testAppAfterUpdate = [
            SELECT
                Last_UK_Employer_Name__c,
                Last_UK_Employer_Address__City__s,
                Last_UK_Employer_Address__CountryCode__s,
                Last_UK_Employer_Address__Street__s,
                Last_UK_Employer_Address__PostalCode__s
            FROM Application__c
        ];
        System.assertNotEquals(null, testAppAfterUpdate);
        System.assertNotEquals(null, testAppAfterUpdate.Last_UK_Employer_Name__c);
        System.assertNotEquals(null, testAppAfterUpdate.Last_UK_Employer_Address__City__s);
        System.assertNotEquals(null, testAppAfterUpdate.Last_UK_Employer_Address__CountryCode__s);
        System.assertNotEquals(null, testAppAfterUpdate.Last_UK_Employer_Address__Street__s);
        System.assertNotEquals(null, testAppAfterUpdate.Last_UK_Employer_Address__PostalCode__s);
        System.assertEquals(testEmpl.Employers_Address__CountryCode__s, testAppAfterUpdate.Last_UK_Employer_Address__CountryCode__s);
        System.assertEquals(testEmpl.Employers_Address__City__s, testAppAfterUpdate.Last_UK_Employer_Address__City__s);
        System.assertEquals(testEmpl.Employers_Address__Street__s, testAppAfterUpdate.Last_UK_Employer_Address__Street__s);
        System.assertEquals(testEmpl.Employer_Name__c, testAppAfterUpdate.Last_UK_Employer_Name__c);
        System.assertEquals(testEmpl.Employers_Address__PostalCode__s, testAppAfterUpdate.Last_UK_Employer_Address__PostalCode__s);
    }

    @isTest
    static void checkEmployersAfterCreateTestCase1() {
        List<Application__c> testApplicationBeforeInsert = [
            SELECT
                Type_Of_Employment__c,
                Date_Of_Leaving_Last_UK__c
            FROM Application__c
        ];
        if (testApplicationBeforeInsert.isEmpty()) {
            return;
        }
        Application__c applicationBeforeInsert = testApplicationBeforeInsert[0];
        Employer__c testEmployer = new Employer__c(
            Start_Date__c                  = Date.valueOf('2009-03-08'),
            End_Date__c                    = Date.valueOf('2010-02-09'),
            Type__c                        = 'UK Work',
            Type_Of_UK_Employment__c       = 'Unemployed',
            Application__c                 = applicationBeforeInsert.Id
        );
        System.assertEquals('Self-Employed', applicationBeforeInsert.Type_Of_Employment__c);
        System.assertEquals(Date.valueOf('2009-01-09'), applicationBeforeInsert.Date_Of_Leaving_Last_UK__c);
        Test.startTest();
        insert testEmployer;
        Test.stopTest();
        List<Application__c> testApplicationAfterInsert = [
            SELECT
                Type_Of_Employment__c,
                Date_Of_Leaving_Last_UK__c
            FROM Application__c
        ];
        if (testApplicationAfterInsert.isEmpty()) {
            return;
        }
        Application__c applicationAfterInsert = testApplicationAfterInsert[0];
        System.assertNotEquals(applicationAfterInsert.Type_Of_Employment__c, applicationBeforeInsert.Type_Of_Employment__c);
        System.assertNotEquals(applicationAfterInsert.Date_Of_Leaving_Last_UK__c, applicationBeforeInsert.Date_Of_Leaving_Last_UK__c);
        System.assertEquals('Unemployed', applicationAfterInsert.Type_Of_Employment__c);
        System.assertEquals(Date.valueOf('2010-02-09'), applicationAfterInsert.Date_Of_Leaving_Last_UK__c);
    }

    @isTest
    static void checkEmployersAfterCreateTestCase2() {
        List<Application__c> testApplicationBeforeInsert = [
            SELECT
                Abroad_Start_Date__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
        ];
        if (testApplicationBeforeInsert.isEmpty()) {
            return;
        }
        Application__c applicationBeforeInsert = testApplicationBeforeInsert[0];
        System.assertEquals('Employed', applicationBeforeInsert.SelfEmployment_Employment_Abroad__c);
        System.assertEquals(Date.valueOf('2007-01-09'), applicationBeforeInsert.Abroad_Start_Date__c);
        Employer__c testEmployer = new Employer__c(
            Start_Date__c                     = Date.valueOf('2005-01-08'),
            End_Date__c                       = Date.valueOf('2010-02-09'),
            Type__c                           = 'Work After UK',
            Type_Of_After_UK_Employment__c    = 'Self-Employed',
            Application__c                    = applicationBeforeInsert.Id
        );
        insert testEmployer;
        List<Application__c> testApplicationAfterInsert = [
            SELECT
                Abroad_Start_Date__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
        ];
        if (testApplicationAfterInsert.isEmpty()) {
            return;
        }
        Application__c applicationAfterInsert = testApplicationAfterInsert[0];
        System.assertNotEquals(applicationAfterInsert.Abroad_Start_Date__c, applicationBeforeInsert.Abroad_Start_Date__c);
        System.assertNotEquals(applicationAfterInsert.SelfEmployment_Employment_Abroad__c, applicationBeforeInsert.SelfEmployment_Employment_Abroad__c);
        System.assertEquals('Self-employed', applicationAfterInsert.SelfEmployment_Employment_Abroad__c);
    }

    @isTest
    static void checkEmployersAfterCreateTestCase3() {
        List<Application__c> testApplicationBeforeInsert = [
            SELECT
                Type_Of_Employment__c,
                Date_Of_Leaving_Last_UK__c
            FROM Application__c
        ];
        if (testApplicationBeforeInsert.isEmpty()) {
            return;
        }
        Application__c applicationBeforeInsert = testApplicationBeforeInsert[0];
        System.assertEquals('Self-Employed', applicationBeforeInsert.Type_Of_Employment__c);
        System.assertEquals(Date.valueOf('2009-01-09'), applicationBeforeInsert.Date_Of_Leaving_Last_UK__c);
        Employer__c testEmployer = new Employer__c(
            Start_Date__c                     = Date.valueOf('2008-01-08'),
            End_Date__c                       = Date.valueOf('2010-02-09'),
            Type__c                           = 'UK Work',
            Type_Of_UK_Employment__c          = 'Employed',
            Application__c                    = applicationBeforeInsert.Id,
            Employer_Name__c                  = 'London Taxi',
            Employers_Address__City__s        = 'London',
            Employers_Address__CountryCode__s = 'GB',
            Employers_Address__PostalCode__s  = '04A075',
            Employers_Address__Street__s      = '34 Test Street'
        );
        Test.startTest();
        insert testEmployer;
        Test.stopTest();
        List<Application__c> testApplicationAfterInsert = [
            SELECT
                Type_Of_Employment__c,
                Date_Of_Leaving_Last_UK__c,
                Last_UK_Employer_Name__c
            FROM Application__c
        ];
        if (testApplicationAfterInsert.isEmpty()) {
            return;
        }
        Application__c applicationAfterInsert = testApplicationAfterInsert[0];
        System.assertNotEquals(applicationAfterInsert.Type_Of_Employment__c, applicationBeforeInsert.Type_Of_Employment__c);
        System.assertNotEquals(applicationAfterInsert.Date_Of_Leaving_Last_UK__c, applicationBeforeInsert.Date_Of_Leaving_Last_UK__c);
        System.assertEquals('Employed', applicationAfterInsert.Type_Of_Employment__c);
        System.assertEquals(Date.valueOf('2010-02-09'), applicationAfterInsert.Date_Of_Leaving_Last_UK__c);
        System.assertEquals('London Taxi', applicationAfterInsert.Last_UK_Employer_Name__c);
    }
}