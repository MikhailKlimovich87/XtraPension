@isTest
public with sharing class ApplicationTriggerTest {
    @IsTest
    static void createApplicationTriggerTest(){
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
        testApplication.Agent_Making_Sale__c = 'None';
        insert testApplication;

        List<Application__c> testApps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Package_Name__c,
                Contact__c,
                Last_UK_Home_Address__CountryCode__s
            FROM Application__c
        ];
        System.assertNotEquals(0, testApps.size(), 'Freebie Application didn\'t create');
        Application__c app = testApps[0];
        System.assertEquals('John', app.First_Name__c, 'Application First Name must be John');
        System.assertNotEquals(null, app.Contact__c, 'Related contact must be not null');
        System.assertEquals('GB', app.Last_UK_Home_Address__CountryCode__s, 'CountryCode must be GB');
    }

    @IsTest
    static void updateSelfemployedAbroadFieldTestCase1() {
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
        testApplication.Agent_Making_Sale__c = 'None';
        insert testApplication;

        Employer__c selfEmployedEmployer = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Self-Employed', true);
        Employer__c employedEmployer     = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Employed', false);
        employedEmployer.Employers_Address__City__s        = 'Test';
        employedEmployer.Employers_Address__CountryCode__s = 'AU';
        employedEmployer.Employers_Address__PostalCode__s  = '1124';
        employedEmployer.Employers_Address__StateCode__s   = 'QLD';
        employedEmployer.Employers_Address__Street__s      = '12 Test Street';
        employedEmployer.Employers_Address_State__c        = 'Queensland';
        employedEmployer.Employers_Address_Country__c      = 'Australia';
        insert employedEmployer;
        testApplication.SelfEmployment_Employment_Abroad__c = 'Both';
        update testApplication;
        List<Application__c> applications = [
            SELECT
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_Address1_State__c,
                Abroad_Employer_Address1_Country__c,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return;
        }
        Application__c applicationAfterUpdate = applications[0];
        System.assertEquals(employedEmployer.Employers_Address__City__s, applicationAfterUpdate.Abroad_Employer_Address1__City__s);
        System.assertEquals(employedEmployer.Employers_Address__CountryCode__s, applicationAfterUpdate.Abroad_Employer_Address1__CountryCode__s);
    }

    @IsTest
    static void updateSelfemployedAbroadFieldTestCase2() {
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
        testApplication.Agent_Making_Sale__c = 'None';
        insert testApplication;

        Employer__c selfEmployedEmployer = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Self-Employed', true);
        Employer__c employedEmployer     = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Employed', false);
        employedEmployer.Employers_Address__City__s        = 'Test';
        employedEmployer.Employers_Address__CountryCode__s = 'AU';
        employedEmployer.Employers_Address__PostalCode__s  = '1124';
        employedEmployer.Employers_Address__StateCode__s   = 'QLD';
        employedEmployer.Employers_Address__Street__s      = '12 Test Street';
        employedEmployer.Employers_Address_State__c        = 'Queensland';
        employedEmployer.Employers_Address_Country__c      = 'Australia';
        insert employedEmployer;
        testApplication.SelfEmployment_Employment_Abroad__c = 'Employed';
        update testApplication;
        List<Application__c> applications = [
            SELECT
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_Address1_State__c,
                Abroad_Employer_Address1_Country__c,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return;
        }
        Application__c applicationAfterUpdate = applications[0];
        System.assertEquals(employedEmployer.Employers_Address__City__s, applicationAfterUpdate.Abroad_Employer_Address1__City__s);
        System.assertEquals(employedEmployer.Employers_Address__CountryCode__s, applicationAfterUpdate.Abroad_Employer_Address1__CountryCode__s);
        System.assertEquals(null, applicationAfterUpdate.Self_Employed_Start_Date1__c);
    }

    @IsTest
    static void updateSelfemployedAbroadFieldTestCase3() {
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
        testApplication.Agent_Making_Sale__c = 'None';
        insert testApplication;

        Employer__c selfEmployedEmployer = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Self-Employed', true);
        Employer__c employedEmployer     = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Employed', false);
        employedEmployer.Employers_Address__City__s        = 'Test';
        employedEmployer.Employers_Address__CountryCode__s = 'AU';
        employedEmployer.Employers_Address__PostalCode__s  = '1124';
        employedEmployer.Employers_Address__StateCode__s   = 'QLD';
        employedEmployer.Employers_Address__Street__s      = '12 Test Street';
        employedEmployer.Employers_Address_State__c        = 'Queensland';
        employedEmployer.Employers_Address_Country__c      = 'Australia';
        insert employedEmployer;
        testApplication.SelfEmployment_Employment_Abroad__c = null;
        update testApplication;
        List<Application__c> applications = [
            SELECT
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_Address1_State__c,
                Abroad_Employer_Address1_Country__c,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return;
        }
        Application__c applicationAfterUpdate = applications[0];
        System.assertEquals(null, applicationAfterUpdate.Self_Employed_Start_Date1__c);
        System.assertEquals(null, applicationAfterUpdate.Abroad_Employer_Start_Date1__c);
    }

        @IsTest
    static void updateSelfemployedAbroadFieldTestCase4() {
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
        testApplication.Agent_Making_Sale__c = 'None';
        insert testApplication;

        Employer__c selfEmployedEmployer = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Self-Employed', true);
        Employer__c employedEmployer     = TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Employed', false);
        employedEmployer.Employers_Address__City__s        = 'Test';
        employedEmployer.Employers_Address__CountryCode__s = 'AU';
        employedEmployer.Employers_Address__PostalCode__s  = '1124';
        employedEmployer.Employers_Address__StateCode__s   = 'QLD';
        employedEmployer.Employers_Address__Street__s      = '12 Test Street';
        employedEmployer.Employers_Address_State__c        = 'Queensland';
        employedEmployer.Employers_Address_Country__c      = 'Australia';
        insert employedEmployer;
        testApplication.SelfEmployment_Employment_Abroad__c = 'Self-Employed';
        update testApplication;
        List<Application__c> applications = [
            SELECT
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_Address1_State__c,
                Abroad_Employer_Address1_Country__c,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return;
        }
        Application__c applicationAfterUpdate = applications[0];
    }


    @IsTest
    static void updateRelatedDocumentsAfterChangeApplicationNameTest() {
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
        Application_Document__c testCustomLetter = TestDataFactory.createApplicationDocument(testApplication.Id, true);
        Application_Document__c testCF083 = TestDataFactory.createCF083ApplicationDocument(testApplication.Id, true);
        System.assertEquals(true, testCustomLetter.File_Name__c.contains('John_Snow'));
        System.assertEquals(true, testCF083.File_Name__c.contains('John_Snow'));
        Test.startTest();
        testApplication.First_Name__c = 'Jimmy';
        update testApplication;
        Test.stopTest();
        List<Application_Document__c> applicationDocumentsAfterUpdate = [
            SELECT File_Name__c
            FROM Application_Document__c
            WHERE Application__c = :testApplication.Id
        ];
        for (Application_Document__c document : applicationDocumentsAfterUpdate) {
            System.assertEquals(false, document.File_Name__c.contains('John_Snow'));
            System.assertEquals(true, document.File_Name__c.contains('Jimmy_Snow'));
        }
    }

    @IsTest
    static void updateRelatedContactAfterChangeEmail() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId,
                Email
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Test.startTest();
        testApplication.Email__c = 'jimmy.snow@gmail.com';
        update testApplication;
        Test.stopTest();
        List<Contact> currentContactAfterUpdate = [
            SELECT
                Email
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        System.assertNotEquals(currentContact[0].Email, currentContactAfterUpdate[0].Email);
        System.assertEquals('jimmy.snow@gmail.com', currentContactAfterUpdate[0].Email);
    }

    @IsTest
    static void updateIsKnowCheckboxTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT
                Id,
                AccountId,
                Email
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
         Test.startTest();
        testApplication.National_Insurance_Number__c = '';
        update testApplication;
        Test.stopTest();
        List<Application__c> testApps = [
            SELECT
                Is_Know_National_Insurance_Number__c,
                National_Insurance_Number__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Application__c currApp = testApps[0];
        Assert.areNotEqual(testApplication.National_Insurance_Number__c, currApp.National_Insurance_Number__c);
        Assert.isNull(currApp.National_Insurance_Number__c);
        Assert.isFalse(currApp.Is_Know_National_Insurance_Number__c);
    }

    @IsTest
    static void updateRelatedPaymentsTest() {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        List<Payment__c> relatedPayments = TestDataFactory.createRelatedPaymentToApplication(products, testApplication, order.Id, true);
        Pricebook2 customPricebook = new Pricebook2(
	        Name = 'Custom Test Pricebook',
	        IsActive = true
        );
        insert customPricebook;
        Integer counter = 200000;
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        for (Product2 product : products) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = customPricebook.Id;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
        Test.startTest();
        testApplication.Live_In_The_EU__c = false;
        update testApplication;
        Test.stopTest();
        List<Payment__c> paymentsAfterUpdate = [
            SELECT Amount__c
            FROM Payment__c
            WHERE Application__c = :testApplication.Id
        ];
        System.assertNotEquals(null, paymentsAfterUpdate);
    }

    @IsTest
    static void autoPopulateRequiredFieldsTest(){
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
        testApplication.Package_Name__c = 'Freebie';

        Test.startTest();
            insert testApplication;
        Test.stopTest();

        List<Application__c> testApps = [
            SELECT
                Id,
                Stripe_Transaction_Id__c,
                Personal_Details_Form_Link__c
            FROM Application__c
        ];
        System.assertEquals(false, testApps.isEmpty());
        System.assertEquals(true, testApps[0].Stripe_Transaction_Id__c.contains('pi'));
        System.assertNotEquals(null, testApps[0].Personal_Details_Form_Link__c);
    }

    @IsTest
    static void createApplicationTriggerCase2Test(){
        Application__c testApp = new Application__c(
            First_Name__c            = 'John',
            Second_Name__c           = 'Snow',
            Related_Contact_Phone__c = '+123451245',
            Email__c                 = 'john.snow@test.com',
            Package_Name__c          = 'Freebie'
        );
        insert testApp;
        List<Application__c> testApps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Package_Name__c,
                Contact__c,
                Last_UK_Home_Address__CountryCode__s
            FROM Application__c
        ];
        System.assertNotEquals(0, testApps.size(), 'Freebie Application didn\'t create');
        Application__c app = testApps[0];
        System.assertEquals('John', app.First_Name__c, 'Application First Name must be John');
        System.assertNotEquals(null, app.Contact__c, 'Related contact must be not null');
        System.assertEquals('GB', app.Last_UK_Home_Address__CountryCode__s, 'CountryCode must be GB');
    }

    @IsTest
    static void updateSendGoogleReviewSmsCheckbox() {
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
        testApplication.Agent_Making_Sale__c = 'None';
        testApplication.Appeal_Application__c = false;
        insert testApplication;
        List<Application__c> testAppsBeforeUpdate = [
            SELECT
                Google_Review_Send_Date__c,
                Delay_In_Days__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Application__c testAppBeforeUpdate = testAppsBeforeUpdate[0];
        Assert.areEqual(null, testAppBeforeUpdate.Google_Review_Send_Date__c);
        Assert.areEqual('1', testAppBeforeUpdate.Delay_In_Days__c);
        Test.startTest();
        testApplication.Send_Google_Review_SMS__c = true;
        update testApplication;
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Google_Review_Send_Date__c,
                Delay_In_Days__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Application__c testAppAfterUpdate = testAppsAfterUpdate[0];
        Assert.areEqual(Date.today().addDays(1), testAppAfterUpdate.Google_Review_Send_Date__c);
        Assert.areEqual('1', testAppAfterUpdate.Delay_In_Days__c);
    }

    @IsTest
    static void updateDelayInDaysData() {
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
        insert testApplication;
        testApplication.Send_Google_Review_SMS__c = true;
        update testApplication;
        List<Application__c> testAppsBeforeUpdate = [
            SELECT
                Google_Review_Send_Date__c,
                Delay_In_Days__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Application__c testAppBeforeUpdate = testAppsBeforeUpdate[0];
        Assert.areEqual(Date.today().addDays(1), testAppBeforeUpdate.Google_Review_Send_Date__c);
        Assert.areEqual('1', testAppBeforeUpdate.Delay_In_Days__c);
        Test.startTest();
        testApplication.Delay_In_Days__c = '3';
        update testApplication;
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Google_Review_Send_Date__c,
                Delay_In_Days__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Application__c testAppAfterUpdate = testAppsAfterUpdate[0];
        Assert.areEqual(Date.today().addDays(3), testAppAfterUpdate.Google_Review_Send_Date__c);
        Assert.areEqual('3', testAppAfterUpdate.Delay_In_Days__c);
    }

    @IsTest
    static void changeCurrentAddressAbroadStateTest(){
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
        testApplication.Current_Address_Abroad__CountryCode__s = 'IE';
        insert testApplication;

        List<Application__c> testAppsBeforeUpdate = [
            SELECT
                Id,
                Current_Address_Abroad__StateCode__s,
                Current_Address_Abroad_State__c
            FROM Application__c
        ];
        Application__c appBeforeUpdate = testAppsBeforeUpdate[0];
        Assert.areEqual(null, appBeforeUpdate.Current_Address_Abroad__StateCode__s);
        Assert.areEqual(null, appBeforeUpdate.Current_Address_Abroad_State__c);
        Test.startTest();
        appBeforeUpdate.Current_Address_Abroad__StateCode__s = 'D';
        update appBeforeUpdate;
        Test.stopTest();
        List<Application__c> testAppsAfterUpdate = [
            SELECT
                Id,
                Current_Address_Abroad__StateCode__s,
                Current_Address_Abroad_State__c
            FROM Application__c
        ];
        Application__c appAfterUpdate = testAppsAfterUpdate[0];

        Assert.areNotEqual(
            appBeforeUpdate.Current_Address_Abroad_State__c,
            appAfterUpdate.Current_Address_Abroad_State__c
        );
        Assert.areEqual('Dublin', appAfterUpdate.Current_Address_Abroad_State__c);
    }

    @IsTest
    static void updatePaymentsFromAppealAppsTest() {
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Monthly Updates', 'Success', 'Appeal'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
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
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        List<Payment__c> relatedPayments = TestDataFactory.createRelatedPaymentToApplication(newProducts, testApplication, order.Id, true);
        Pricebook2 customPricebook = new Pricebook2(
	        Name = 'Custom Test Pricebook',
	        IsActive = true
        );
        insert customPricebook;
        Integer counter2 = 200000;
        List<PriceBookEntry> testPriceBookEntries2 = new List<PriceBookEntry>();
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = customPricebook.Id;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter2;
            ret.IsActive = true;
            testPriceBookEntries2.add(ret);
            counter2 += 10000;
        }
        insert testPriceBookEntries2;
        List<Application__c> testApps = [
            SELECT Appeal_Application__c
            FROM Application__c
        ];
        Application__c currApp = testApps[0];
        List<Payment__c> paymentsBeforeUpdate = [
            SELECT Amount__c
            FROM Payment__c
            WHERE Product_Name__c = 'Application'
        ];
        Test.startTest();
        currApp.Appeal_Application__c = true;
        update currApp;
        Test.stopTest();
        List<Payment__c> paymentsAfterUpdate = [
            SELECT Amount__c
            FROM Payment__c
            WHERE Product_Name__c = 'Application'
        ];
        Assert.areNotEqual(paymentsBeforeUpdate[0].Amount__c, paymentsAfterUpdate[0].Amount__c);
        Assert.areEqual(850, paymentsAfterUpdate[0].Amount__c);
    }

    @isTest
    static void autoAssignToAgentTest() {
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
        Application__c testApplication1 = TestDataFactory.createApplication(personContactId, true);

        Account account2 = TestDataFactory.createAccount(true);
        List<Contact> currentContact2 = [
            SELECT
                Id,
                AccountId
            FROM Contact
            WHERE AccountId = :account2.Id
            LIMIT 1
        ];
        Id personContactId2 = currentContact2[0].Id;
        Application__c testApplication2 = TestDataFactory.createApplication(personContactId2, true);
        System.debug('testApplication2.Val_Agent__c ===' + [SELECT Val_Agent__c FROM Application__c WHERE Id = :testApplication2.Id][0].Val_Agent__c);

        Application__c testApplication3 = TestDataFactory.createApplication(personContactId, true);
        System.debug('testApplication3.Val_Agent__c ===' + [SELECT Val_Agent__c FROM Application__c WHERE Id = :testApplication3.Id][0].Val_Agent__c);

        Application__c testApplication4 = TestDataFactory.createApplication(personContactId, true);
        System.debug('testApplication4.Val_Agent__c ===' + [SELECT Val_Agent__c FROM Application__c WHERE Id = :testApplication4.Id][0].Val_Agent__c);

    }

    @isTest
    static void changeAgentStatusAppsTest() {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Application__c testApplication2 = TestDataFactory.createApplication(personContactId, true);
        Test.startTest();
        testApplication.Status__c = 'Agent Check';
        update testApplication;
        testApplication2.Status__c = 'Agent Check';
        update testApplication2;
        Test.stopTest();
    }

    @isTest
    static void sendSalesAgentCustomNotificationTest() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User u = new User(
            Alias = 'Sean',
            Email= 'sean@test.com',
            EmailEncodingKey='UTF-8',
            FirstName='Sean',
            LastName='Testing',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_IE_EURO',
            ProfileId = p.Id,
            TimeZoneSidKey ='Europe/Dublin',
            UserName = 'sean.xtrapension@test.com');
        insert u;
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        testApplication.Status__c = 'Agent Check';
        testApplication.Val_Agent__c = 'Sean';
        update testApplication;
        Test.startTest();
        testApplication.Status__c = 'Fix';
        update testApplication;
        Test.stopTest();
        Integer i = Limits.getEmailInvocations();
        System.assertEquals(1,i);
    }

    @isTest
    static void sendValAgentCustomNotificationTest() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User u = new User(
            Alias = 'Daniel',
            Email= 'daniel@test.com',
            EmailEncodingKey='UTF-8',
            FirstName='Daniel',
            LastName='Testing',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_IE_EURO',
            ProfileId = p.Id,
            TimeZoneSidKey ='Europe/Dublin',
            UserName = 'daniel.xtrapension@test.com');
        insert u;
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        testApplication.Status__c = 'Fix';
        update testApplication;
        Test.startTest();
        testApplication.Status__c = 'Agent Check';
        update testApplication;
        Test.stopTest();
        Integer i = Limits.getEmailInvocations();
        System.assertEquals(1,i);
    }

    @isTest
    static void deferredCustomNotificationAppsTest() {
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User'];
        User u = new User(
            Alias = 'Daniel',
            Email= 'daniel@test.com',
            EmailEncodingKey='UTF-8',
            FirstName='Daniel',
            LastName='Testing',
            LanguageLocaleKey='en_US',
            LocaleSidKey='en_IE_EURO',
            ProfileId = p.Id,
            TimeZoneSidKey ='Europe/Dublin',
            UserName = 'daniel.xtrapension@test.com');
        insert u;
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Test.startTest();
        testApplication.Status__c = 'Deferred';
        update testApplication;
        Test.stopTest();
        Integer i = Limits.getEmailInvocations();
        System.assertEquals(1,i);
    }

    @isTest
    static void didClientChangeNameTest() {
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
        testApplication.Did_Client_Change_Name__c = 'No';
        insert testApplication;
        Test.startTest();
        testApplication.Did_Client_Change_Name__c = 'Yes';
        update testApplication;
        Test.stopTest();
        List<Application__c> appsAfterUpdate = [
            SELECT Did_You_Change_Name__c
            FROM Application__c
        ];
        Assert.areEqual(true,appsAfterUpdate[0].Did_You_Change_Name__c);
    }

    @isTest
    static void updateDaysSinceContactTest() {
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
        testApplication.Who__c = 'John';
        insert testApplication;
        Test.startTest();
        testApplication.Who__c = 'Monica';
        update testApplication;
        Test.stopTest();
    }

    @isTest
    static void sendGoogleReviewEmailTest() {
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
        testApplication.Status__c = 'Agent Call';
        insert testApplication;
        Test.startTest();
        testApplication.Status__c = 'Charge CC';
        update testApplication;
        Test.stopTest();
    }

    @isTest
    static void generateSuccessDocsTest() {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Test.startTest();
        testApplication.Status__c = 'Send to Client';
        update testApplication;
        Test.stopTest();
    }

    @isTest
    static void generateAllMainDocsTest() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
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
        Agent__c testAgent = TestDataFactory.createAgent(true);
        testApplication.Agent__c = testAgent.Id;
        update testApplication;
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        TestDataFactory.createPayment(testApplication.Id, order.Id, true);
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
        Test.startTest();
        testApplication.Status__c = 'Form Completed';
        update testApplication;
        Test.stopTest();
    }

    private class PaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            // Create a fake response
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"id":"pm124512451", ' +
                    '"card":{' +
                        '"brand":"visa", ' +
                        '"last4":"4242"' +
                    '}' +
                '}');
            res.setStatusCode(200);
            return res;
        }
    }

    @IsTest
    static void generateReSubLetterCase1() {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        List<ContentDocumentLink> cdlsBeforeTest = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplication.Id AND
                  ContentDocument.Title LIKE '%ReSubLetter%'
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Test.startTest();
        testApplication.Status__c = 'REPEAT(NO edits)';
        update testApplication;
        Test.stopTest();
        List<ContentDocumentLink> cdlsAfterTest = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testApplication.Id AND
                  ContentDocument.Title LIKE '%ReSubLetter%'
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Assert.areNotEqual(cdlsAfterTest.size(), cdlsBeforeTest.size());
        Assert.areEqual(0, cdlsBeforeTest.size());
        Assert.areEqual(1, cdlsAfterTest.size());
    }

    @IsTest
    static void generateReSubLetterCase2() {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        ContentVersion cv = new ContentVersion();
        cv.Title = 'ReSubLetter_ForSignature';
        cv.PathOnClient = 'ReSubLetter_ForSignature.pdf';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test ReSubLetter Body','UTF-8'));
        insert cv;
        ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:cv.Id][0];
        ContentDocumentLink conDocLink = New ContentDocumentLink();
		conDocLink.LinkedEntityId = testApplication.Id;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
        conDocLink.Visibility = 'AllUsers';
		insert conDocLink;
        Test.startTest();
        testApplication.Status__c = 'REPEAT(NO edits)';
        update testApplication;
        Test.stopTest();
    }

    @IsTest
    static void createSplitPaymentsTest() {
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
        testApplication.Current_Address_Abroad__CountryCode__s = 'ZA';
        insert testApplication;
        List<Application__c> testAppBeforeUpdate = [
            SELECT
                Id,
                Split__c,
                Split_Date__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Map<Id, Payment__c> testPayments = new Map<Id, Payment__c>(TestDataFactory.createRelatedPaymentToApplication(products, testApplication, order.Id, true));
        List<Payment__c> paymentsBeforeUpdate = [
            SELECT
                Product_Name__c,
                Amount__c
            FROM Payment__c
            WHERE Application__c = :testApplication.Id AND
                  Product_Name__c  = 'Application'
        ];
        for (Payment__c payment : paymentsBeforeUpdate) {
            System.debug(payment);
        }
        Test.startTest();
        testApplication.Split__c = true;
        update testApplication;
        Test.stopTest();
        System.debug('=============================');
        List<Payment__c> paymentsAfterUpdate = [
            SELECT
                Product_Name__c,
                Amount__c
            FROM Payment__c
            WHERE Application__c = :testApplication.Id AND
                  Product_Name__c  = 'Application'
        ];
        for (Payment__c payment : paymentsAfterUpdate) {
            System.debug(payment);
        }
        System.debug('=============================');

        List<Application__c> testAppAfterUpdate = [
            SELECT
                Id,
                Split__c,
                Split_Date__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Assert.areNotEqual(0,paymentsAfterUpdate.size());
        Assert.isNull(testAppBeforeUpdate[0].Split_Date__c);
        Assert.areNotEqual(testAppBeforeUpdate[0].Split_Date__c,testAppAfterUpdate[0].Split_Date__c);
        Assert.isNotNull(testAppAfterUpdate[0].Split_Date__c);
        Assert.areEqual(paymentsAfterUpdate[0].Amount__c, paymentsBeforeUpdate[0].Amount__c/5);
    }
}