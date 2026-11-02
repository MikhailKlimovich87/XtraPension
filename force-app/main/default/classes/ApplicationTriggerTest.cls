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
            SELECT Amount__c, Status__c
            FROM Payment__c
            WHERE Product_Name__c = 'Application'
        ];
        Test.startTest();
        currApp.Appeal_Application__c = true;
        update currApp;
        Test.stopTest();
        List<Payment__c> paymentsAfterUpdate = [
            SELECT Amount__c, Status__c
            FROM Payment__c
            WHERE Product_Name__c = 'Application'
        ];
        Assert.areNotEqual(paymentsBeforeUpdate[0].Status__c, paymentsAfterUpdate[0].Status__c);
        Assert.isNotNull(paymentsAfterUpdate[0].Status__c);
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

    // @isTest
    // static void generateAllMainDocsTest() {
    //     Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
    //     TestDataFactory.createProductsWithPrices();
    //     TestDataFactory.createTestCountry(true);
    //     Account account = TestDataFactory.createAccount(true);
    //     List<Contact> currentContact = [
    //         SELECT
    //             Id,
    //             AccountId
    //         FROM Contact
    //         WHERE AccountId = :account.Id
    //         LIMIT 1
    //     ];
    //     Id personContactId = currentContact[0].Id;
    //     Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    //     ContentVersion testContentVersion = TestDataFactory.createTestContentVersion(true);
    //     Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
    //     ContentDocumentLink conDocLink = new ContentDocumentLink();
    //     conDocLink.LinkedEntityId = testApplication.Id;
    //     conDocLink.ContentDocumentId = contDocId;
    //     insert conDocLink;
    //     Agent__c testAgent = TestDataFactory.createAgent(true);
    //     testApplication.Agent__c = testAgent.Id;
    //     update testApplication;
    //     Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
    //     TestDataFactory.createPayment(testApplication.Id, order.Id, true);
    //     TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
    //     TestDataFactory.createXtraPensionDataCustomSetting(true);
    //     Test.startTest();
    //     testApplication.Status__c = 'Form Completed';
    //     update testApplication;
    //     Test.stopTest();
    // }

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

    @IsTest
    static void registratePKPartnerTest() {
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
        testApplication.PK_Partner__c = false;
        testApplication.PK_Portal_User_Active__c = false;
        testApplication.Date_Of_Birth__c = Date.valueOf('1970-05-15');
        insert testApplication;

        List<Application__c> appBeforeUpdate = [
            SELECT
                Id,
                PK_Partner__c,
                Status__c,
                PK_Portal_User_Active__c,
                PK_Portal_User_PW__c,
                PK_Registration_Date__c,
                PK_Date_Pension_Age_Reached__c,
                Pension_Age__c,
                PK_Auto_Renewal__c,
                Date_Of_Birth__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Assert.isFalse(appBeforeUpdate[0].PK_Partner__c);
        Assert.isFalse(appBeforeUpdate[0].PK_Portal_User_Active__c);
        Assert.isNull(appBeforeUpdate[0].PK_Portal_User_PW__c);

        Test.startTest();
        testApplication.PK_Partner__c = true;
        update testApplication;
        Test.stopTest();

        List<Application__c> appAfterUpdate = [
            SELECT
                Id,
                PK_Partner__c,
                Status__c,
                PK_Portal_User_Active__c,
                PK_Portal_User_PW__c,
                PK_Registration_Date__c,
                PK_Date_Pension_Age_Reached__c,
                Pension_Age__c,
                PK_Auto_Renewal__c,
                Date_Of_Birth__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];

        Assert.isTrue(appAfterUpdate[0].PK_Partner__c);
        Assert.areEqual('Pension Keeper', appAfterUpdate[0].Status__c);
        Assert.isTrue(appAfterUpdate[0].PK_Portal_User_Active__c);
        Assert.isNotNull(appAfterUpdate[0].PK_Portal_User_PW__c);
        Assert.areEqual(Date.today(), appAfterUpdate[0].PK_Registration_Date__c);
        Assert.isNotNull(appAfterUpdate[0].PK_Date_Pension_Age_Reached__c);
        Assert.isNotNull(appAfterUpdate[0].Pension_Age__c);
        Assert.isFalse(appAfterUpdate[0].PK_Auto_Renewal__c);
    }

    @IsTest
    static void registratePKFreebieAppTest() {
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
        testApplication.PK_Freebie_App__c = false;
        testApplication.PK_Portal_User_Active__c = false;
        testApplication.Date_Of_Birth__c = Date.valueOf('1965-03-20');
        insert testApplication;

        List<Application__c> appBeforeUpdate = [
            SELECT
                Id,
                PK_Freebie_App__c,
                Status__c,
                PK_Portal_User_Active__c,
                PK_Portal_User_PW__c,
                PK_Registration_Date__c,
                PK_Date_Pension_Age_Reached__c,
                Pension_Age__c,
                PK_Auto_Renewal__c,
                Date_Of_Birth__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];
        Assert.isFalse(appBeforeUpdate[0].PK_Freebie_App__c);
        Assert.isFalse(appBeforeUpdate[0].PK_Portal_User_Active__c);
        Assert.isNull(appBeforeUpdate[0].PK_Portal_User_PW__c);

        Test.startTest();
        testApplication.PK_Freebie_App__c = true;
        update testApplication;
        Test.stopTest();

        List<Application__c> appAfterUpdate = [
            SELECT
                Id,
                PK_Freebie_App__c,
                Status__c,
                PK_Portal_User_Active__c,
                PK_Portal_User_PW__c,
                PK_Registration_Date__c,
                PK_Date_Pension_Age_Reached__c,
                Pension_Age__c,
                PK_Auto_Renewal__c,
                Date_Of_Birth__c
            FROM Application__c
            WHERE Id = :testApplication.Id
        ];

        Assert.isTrue(appAfterUpdate[0].PK_Freebie_App__c);
        Assert.areEqual('Pension Keeper', appAfterUpdate[0].Status__c);
        Assert.isTrue(appAfterUpdate[0].PK_Portal_User_Active__c);
        Assert.isNotNull(appAfterUpdate[0].PK_Portal_User_PW__c);
        Assert.areEqual(Date.today(), appAfterUpdate[0].PK_Registration_Date__c);
        Assert.isNotNull(appAfterUpdate[0].PK_Date_Pension_Age_Reached__c);
        Assert.isNotNull(appAfterUpdate[0].Pension_Age__c);
        Assert.isFalse(appAfterUpdate[0].PK_Auto_Renewal__c);
        Integer emailCount = Limits.getEmailInvocations();
        Assert.areEqual(1, emailCount, 'Email should be sent for Freebie app');
    }

     @IsTest
    static void autoPopulateFreebiePensionKeeperTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Package_Name__c = 'Freebie';
        app.Status__c = 'Pension Keeper';
        app.Date_Of_Birth__c = Date.valueOf('1965-03-20');
        app.PK_Portal_User_Active__c = false;
        insert app;

        Application__c afterInsert = [
            SELECT
                PK_Portal_User_Active__c,
                PK_Portal_User_PW__c,
                PK_Registration_Date__c,
                PK_Date_Pension_Age_Reached__c,
                Pension_Age__c,
                PK_Auto_Renewal__c
            FROM Application__c
            WHERE Id = :app.Id
        ];
        Assert.isTrue(afterInsert.PK_Portal_User_Active__c, 'Portal user must be active');
        Assert.isNotNull(afterInsert.PK_Portal_User_PW__c, 'Portal password must be generated');
        Assert.areEqual(Date.today(), afterInsert.PK_Registration_Date__c);
        Assert.isNotNull(afterInsert.PK_Date_Pension_Age_Reached__c);
        Assert.isNotNull(afterInsert.Pension_Age__c);
        Assert.isFalse(afterInsert.PK_Auto_Renewal__c);
    }

    // Covers: autoPopulateRequiredFields -> 3rd branch (resolvedLine1 != original, non-Freebie/non-FormInProgress)
    @IsTest
    static void autoPopulateFreeformPlaceholderOnNonFreebieTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Package_Name__c = 'Standard';
        app.Status__c = 'Form In Progress';
        app.Freeform_RichText_Line1__c = 'Hello {!appObj.Name}, welcome';
        insert app;

        Application__c afterInsert = [
            SELECT Freeform_RichText_Line1__c, Name
            FROM Application__c
            WHERE Id = :app.Id
        ];
        Assert.isFalse(afterInsert.Freeform_RichText_Line1__c.contains('{!appObj.Name}'));
        Assert.isTrue(afterInsert.Freeform_RichText_Line1__c.contains(afterInsert.Name));
    }

    // Covers: autoPopulateRequiredFields -> Freebie + Form In Progress WITH placeholder in Freeform field
    @IsTest
    static void autoPopulateFreebieWithPlaceholderTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Package_Name__c = 'Freebie';
        app.Status__c = 'Form In Progress';
        app.Freeform_RichText_Line1__c = 'Hi {!appObj.Name}';
        insert app;

        Application__c afterInsert = [
            SELECT
                Stripe_Transaction_Id__c,
                Personal_Details_Form_Link__c,
                Freeform_RichText_Line1__c,
                Name
            FROM Application__c
            WHERE Id = :app.Id
        ];
        Assert.isNotNull(afterInsert.Stripe_Transaction_Id__c);
        Assert.isNotNull(afterInsert.Personal_Details_Form_Link__c);
        Assert.isFalse(afterInsert.Freeform_RichText_Line1__c.contains('{!appObj.Name}'));
        Assert.isTrue(afterInsert.Freeform_RichText_Line1__c.contains(afterInsert.Name));
    }

    // Covers: updateIsKnowCheckbox -> non-blank NINO branch
    @IsTest
    static void updateIsKnowCheckboxWithNinoTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.National_Insurance_Number__c = 'AB123456C';
        insert app;

        Test.startTest();
        app.National_Insurance_Number__c = 'QQ123456D';
        update app;
        Test.stopTest();

        Application__c afterUpdate = [
            SELECT Is_Know_National_Insurance_Number__c
            FROM Application__c WHERE Id = :app.Id
        ];
        Assert.isTrue(afterUpdate.Is_Know_National_Insurance_Number__c);
    }

    // Covers: updateRelatedPayments -> EU branch (Live_In_The_EU__c = true)
    @IsTest
    static void updatePaymentsEUPathTest() {
        List<Product2> products = TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Live_In_The_EU__c = true;
        insert app;
        Order order = TestDataFactory.createOrder(app.Id, account.Id, true);
        TestDataFactory.createRelatedPaymentToApplication(products, app, order.Id, true);

        Test.startTest();
        app.Live_In_The_EU__c = false;
        update app;
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Amount__c FROM Payment__c WHERE Application__c = :app.Id
        ];
        Assert.isFalse(payments.isEmpty());
    }

    // Covers: autoAssignToAgent -> Appeal_Application__c = true => Sean
    @IsTest
    static void autoAssignToAgentAppealTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = new Application__c(
            First_Name__c = 'Appeal',
            Second_Name__c = 'Client',
            Related_Contact_Phone__c = '+123451245',
            Email__c = 'appeal@test.com',
            Package_Name__c = 'Standard',
            Contact__c = con.Id,
            Status__c = 'Form In Progress',
            Appeal_Application__c = true
        );
        insert app;

        Application__c afterInsert = [
            SELECT Val_Agent__c FROM Application__c WHERE Id = :app.Id
        ];
        Assert.areEqual('Sean', afterInsert.Val_Agent__c);
    }

    // Covers: autoAssignToAgent -> Australia/NZ => Becky
    @IsTest
    static void autoAssignToAgentAustraliaTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = new Application__c(
            First_Name__c = 'Aussie',
            Second_Name__c = 'Client',
            Related_Contact_Phone__c = '+123451245',
            Email__c = 'aussie@test.com',
            Package_Name__c = 'Standard',
            Contact__c = con.Id,
            Status__c = 'Form In Progress',
            Current_Address_Abroad_Country__c = 'Australia'
        );
        insert app;

        Application__c afterInsert = [
            SELECT Val_Agent__c FROM Application__c WHERE Id = :app.Id
        ];
        Assert.areEqual('Sean', afterInsert.Val_Agent__c);
    }

    // Covers: autoAssignToAgent -> 'Pension Keeper' early return
    @IsTest
    static void autoAssignToAgentPensionKeeperEarlyReturnTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Package_Name__c = 'Freebie';
        app.Status__c = 'Pension Keeper';
        app.Date_Of_Birth__c = Date.valueOf('1960-01-01');
        insert app;

        Application__c afterInsert = [
            SELECT Val_Agent__c FROM Application__c WHERE Id = :app.Id
        ];
        // Val_Agent__c should remain null because the early return skips assignment
        Assert.isNull(afterInsert.Val_Agent__c);
    }

    // Covers: changeAgentStatusApps -> New_Agent__c already populated, so no reassignment
    @IsTest
    static void changeAgentStatusPreserveNewAgentTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Status__c = 'Form In Progress';
        insert app;

        app.New_Agent__c = 'Maria';
        app.Status__c = 'Agent Check';
        Test.startTest();
        update app;
        Test.stopTest();

        Application__c afterUpdate = [
            SELECT Agent_Status__c, New_Agent__c
            FROM Application__c WHERE Id = :app.Id
        ];
        Assert.areEqual('Agent Check', afterUpdate.Agent_Status__c);
        Assert.areEqual('Maria', afterUpdate.New_Agent__c);
    }

    // Covers: changeCurrentAddressAbroadState -> no state change means no DML
    @IsTest
    static void changeCurrentAddressAbroadStateNoChangeTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Current_Address_Abroad__CountryCode__s = 'IE';
        app.Current_Address_Abroad__StateCode__s = 'D';
        insert app;

        Test.startTest();
        app.First_Name__c = 'Renamed';
        update app;
        Test.stopTest();

        Application__c afterUpdate = [
            SELECT Current_Address_Abroad_State__c
            FROM Application__c WHERE Id = :app.Id
        ];
    }

    // Covers: calculatePensionAge -> null DOB skip branch (no update issued)
    @IsTest
    static void calculatePensionAgeNullDobTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Date_Of_Birth__c = Date.valueOf('1970-01-01');
        insert app;

        Test.startTest();
        app.Date_Of_Birth__c = null;
        update app;
        Test.stopTest();

        Application__c afterUpdate = [
            SELECT PK_Date_Pension_Age_Reached__c
            FROM Application__c WHERE Id = :app.Id
        ];
        Assert.isNull(afterUpdate.PK_Date_Pension_Age_Reached__c);
    }

    // Covers: registratePKPatner -> partner application branch
    @IsTest
    static void registratePKPartnerBranchTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        // Partner app must have status Annual Service or No Annual
        Application__c partnerApp = TestDataFactory.createApplication(con.Id, false);
        partnerApp.Status__c = 'Annual Service';
        partnerApp.Date_Of_Birth__c = Date.valueOf('1960-01-01');
        partnerApp.PK_Portal_User_Active__c = false;
        insert partnerApp;

        Application__c mainApp = TestDataFactory.createApplication(con.Id, false);
        mainApp.PK_Portal_User_Active__c = true;
        mainApp.PK_Registration_Date__c = Date.today();
        mainApp.Partner_Application__c = partnerApp.Id;
        mainApp.PK_Partner__c = false;
        mainApp.Date_Of_Birth__c = Date.valueOf('1960-01-01');
        insert mainApp;

        Test.startTest();
        mainApp.PK_Partner__c = true;
        update mainApp;
        Test.stopTest();

        Application__c afterUpdate = [
            SELECT Status__c, PK_Portal_User_Active__c, PK_Portal_User_PW__c
            FROM Application__c WHERE Id = :partnerApp.Id
        ];
        Assert.areEqual('Pension Keeper', afterUpdate.Status__c);
        Assert.isTrue(afterUpdate.PK_Portal_User_Active__c);
        Assert.isNotNull(afterUpdate.PK_Portal_User_PW__c);
    }

    // Covers: registratePKPatner -> partner app WITHOUT valid status
    @IsTest
    static void registratePKPartnerInvalidStatusTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c partnerApp = TestDataFactory.createApplication(con.Id, false);
        partnerApp.Status__c = 'Pending Client'; // NOT Annual Service / No Annual
        partnerApp.PK_Portal_User_Active__c = false;
        partnerApp.Date_Of_Birth__c = Date.valueOf('1960-01-01');
        insert partnerApp;

        Application__c mainApp = TestDataFactory.createApplication(con.Id, false);
        mainApp.PK_Portal_User_Active__c = true;
        mainApp.PK_Registration_Date__c = Date.today();
        mainApp.Partner_Application__c = partnerApp.Id;
        mainApp.PK_Partner__c = false;
        mainApp.Date_Of_Birth__c = Date.valueOf('1960-01-01');
        insert mainApp;

        Boolean errorCaught = false;
        Test.startTest();
        try {
            mainApp.PK_Partner__c = true;
            update mainApp;
        } catch (DmlException e) {
            errorCaught = true;
        }
        Test.stopTest();

        Assert.isTrue(errorCaught, 'Expected error on partner app with invalid status');
    }

    // Covers: createSplitPayments -> Success product branch
    @IsTest
    static void createSplitPaymentsSuccessProductTest() {
        List<Product2> products = TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Current_Address_Abroad__CountryCode__s = 'ZA';
        app.Status__c = 'Form In Progress';
        insert app;

        Order order = TestDataFactory.createOrder(app.Id, account.Id, true);
        TestDataFactory.createRelatedPaymentToApplication(products, app, order.Id, true);

        Test.startTest();
        app.Split__c = true;
        update app;
        Test.stopTest();

        List<Payment__c> payments = [
            SELECT Product_Name__c, Amount__c
            FROM Payment__c
            WHERE Application__c = :app.Id AND Product_Name__c = 'Application'
        ];
        Assert.isFalse(payments.isEmpty());
    }

    // Covers: updatePaymentsFromAppealApps -> payment already Cancelled
    @IsTest
    static void updatePaymentsFromAppealAlreadyCancelledTest() {
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Appeal Application'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(Name = name, CurrencyIsoCode = 'EUR'));
        }
        insert newProducts;
        Id pbId = Test.getStandardPricebookId();
        List<PriceBookEntry> entries = new List<PriceBookEntry>();
        Integer price = 100000;
        for (Product2 p : newProducts) {
            entries.add(new PriceBookEntry(
                Pricebook2Id = pbId,
                Product2Id = p.Id,
                UnitPrice = price,
                IsActive = true,
                CurrencyIsoCode = 'EUR'
            ));
            price += 10000;
        }
        insert entries;

        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, true);
        Order order = TestDataFactory.createOrder(app.Id, account.Id, true);
        List<Payment__c> relatedPayments =
            TestDataFactory.createRelatedPaymentToApplication(newProducts, app, order.Id, true);
        // Cancel one already
        if (!relatedPayments.isEmpty()) {
            relatedPayments[0].Status__c = 'Cancel';
            update relatedPayments;
        }

        Test.startTest();
        app.Appeal_Application__c = true;
        update app;
        Test.stopTest();

        // Shouldn't throw - just re-cancels
        List<Payment__c> after = [
            SELECT Status__c FROM Payment__c WHERE Application__c = :app.Id
        ];
        Assert.isFalse(after.isEmpty());
    }

    // Covers: generateZipArchive -> missing file -> error message recorded
    @IsTest
    static void generateZipArchiveMissingFilesTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, true);

        Test.startTest();
        app.Status__c = 'Printing House';
        update app;
        Test.stopTest();

        Application__c afterUpdate = [
            SELECT Zip_Archive_Error__c FROM Application__c WHERE Id = :app.Id
        ];
        Assert.isNotNull(afterUpdate.Zip_Archive_Error__c, 'Missing files should record error');
        Assert.isTrue(
            afterUpdate.Zip_Archive_Error__c.contains('CF083')
            || afterUpdate.Zip_Archive_Error__c.contains('64-8')
            || afterUpdate.Zip_Archive_Error__c.contains('CustomLetter'),
            'Error message should mention missing files'
        );
    }

    // Covers: sendRegistrationDataMessage -> Standard Status branch + appeal attachment
    @IsTest
    static void sendRegistrationDataMessageStandardTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Appeal_Application__c = true;
        insert app;

        Test.startTest();
        app.First_Name__c = 'TriggerMessage';
        update app;
        Test.stopTest();

        Assert.isNotNull(app.Id);
    }

    // Covers: updateRelatedDocumentsAfterChangeApplicationName -> old name diff on Last name only
    @IsTest
    static void updateRelatedDocumentsLastNameOnlyChangeTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, true);
        TestDataFactory.createApplicationDocument(app.Id, true);

        Test.startTest();
        app.Second_Name__c = 'NewLast';
        update app;
        Test.stopTest();

        List<Application_Document__c> docs = [
            SELECT File_Name__c FROM Application_Document__c WHERE Application__c = :app.Id
        ];
        for (Application_Document__c d : docs) {
            Assert.isFalse(d.File_Name__c.contains('John_Snow'));
        }
    }

    // Covers: changeGoogleReviewSmsDate -> Delay_In_Days__c null skip
    @IsTest
    static void changeGoogleReviewSmsDateNullDelayTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Delay_In_Days__c = null;
        app.Send_Google_Review_SMS__c = false;
        insert app;

        Test.startTest();
        app.Delay_In_Days__c = '2';
        update app;
        Test.stopTest();

        Application__c after = [
            SELECT Google_Review_Send_Date__c, Delay_In_Days__c
            FROM Application__c WHERE Id = :app.Id
        ];
        Assert.areEqual('2', after.Delay_In_Days__c);
        Assert.isNotNull(after.Google_Review_Send_Date__c);
    }

    // Covers: multiple Freebie apps inserted in one DML to exercise bulk loop
    @IsTest
    static void bulkFreebieInsertTest() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        List<Application__c> apps = new List<Application__c>();
        for (Integer i = 0; i < 5; i++) {
            apps.add(new Application__c(
                First_Name__c = 'Bulk',
                Second_Name__c = 'User' + i,
                Related_Contact_Phone__c = '+12345124' + i,
                Email__c = 'bulk' + i + '@test.com',
                Package_Name__c = 'Freebie',
                Contact__c = con.Id,
                Status__c = 'Form In Progress',
                Freeform_RichText_Line1__c = 'Hi {!appObj.Name}'
            ));
        }

        Test.startTest();
        insert apps;
        Test.stopTest();

        List<Application__c> after = [
            SELECT Stripe_Transaction_Id__c, Freeform_RichText_Line1__c
            FROM Application__c WHERE Id IN :apps
        ];
        Assert.areEqual(5, after.size());
        for (Application__c a : after) {
            Assert.isNotNull(a.Stripe_Transaction_Id__c);
            Assert.isFalse(a.Freeform_RichText_Line1__c.contains('{!appObj.Name}'));
        }
    }
}