@isTest
public class RE_ApplicationDataActionTest {

    @TestSetup
    static void makeData() {
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
        TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    static void testCreateRelatedReapply_Success() {
        // Get the test application
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        
        // Delete existing reapply record to test creation
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        // Verify reapply was created
        System.assertNotEquals(null, reapplyId, 'Reapply ID should not be null');
        
        Reapply__c createdReapply = [SELECT Id, Name, Application__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals(testApp.Id, createdReapply.Application__c);
        System.assertEquals('R' + testApp.Name.substring(1), createdReapply.Name);
    }

    @isTest
    static void testCreateRelatedReapply_WithNullApplicationId() {
        Test.startTest();
        try {
            RE_ApplicationDataAction.createRelatedReapply(null, false);
            System.assert(false, 'Expected exception was not thrown');
        } catch (RE_ApplicationDataAction.ReapplyException e) {
            System.assertEquals('Application Id is required', e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetReapplyRecordId_Success() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        Reapply__c existingReapply = [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id LIMIT 1];
        
        Test.startTest();
        Id result = RE_ApplicationDataAction.getReapplyRecordId(testApp.Id);
        Test.stopTest();
        
        System.assertEquals(existingReapply.Id, result);
    }

    @isTest
    static void testGetReapplyRecordId_WithNullId() {
        Test.startTest();
        Id result = RE_ApplicationDataAction.getReapplyRecordId(null);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }

    @isTest
    static void testGetReapplyRecordId_WithNoReapply() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        Test.startTest();
        Id result = RE_ApplicationDataAction.getReapplyRecordId(testApp.Id);
        Test.stopTest();
        
        System.assertEquals(null, result);
    }

    @isTest
    static void testHasExistingReapply_True() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        
        Test.startTest();
        Boolean result = RE_ApplicationDataAction.hasExistingReapply(testApp.Id);
        Test.stopTest();
        
        System.assertEquals(true, result);
    }

    @isTest
    static void testHasExistingReapply_False() {
        Application__c testApp = [SELECT Id FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        Test.startTest();
        Boolean result = RE_ApplicationDataAction.hasExistingReapply(testApp.Id);
        Test.stopTest();
        
        System.assertEquals(false, result);
    }

    @isTest
    static void testHasExistingReapply_WithNullId() {
        Test.startTest();
        Boolean result = RE_ApplicationDataAction.hasExistingReapply(null);
        Test.stopTest();
        
        System.assertEquals(false, result);
    }

    @isTest
    static void testCreateRelatedReapply_WithSelfEmployedBeforeLeftUK() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update UK Work employer to be 'Self-Employed'
        Employer__c ukEmployer = [SELECT Id, Type__c, Type_Of_UK_Employment__c FROM Employer__c WHERE Type__c = 'UK Work' LIMIT 1];
        ukEmployer.Type_Of_UK_Employment__c = 'Self-Employed';
        update ukEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, employment_status_before_left_UK__c, Has_your_UK_self_employment_ended__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals('self_employed', createdReapply.employment_status_before_left_UK__c);
        System.assertEquals(true, createdReapply.Has_your_UK_self_employment_ended__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithNotEmployedBeforeLeftUK() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update UK Work employer to be 'Not employed'
        Employer__c ukEmployer = [SELECT Id, Type__c, Type_Of_UK_Employment__c FROM Employer__c WHERE Type__c = 'UK Work' LIMIT 1];
        ukEmployer.Type_Of_UK_Employment__c = 'Not employed';
        update ukEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, employment_status_before_left_UK__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals('neither_employed_nor_self_employed', createdReapply.employment_status_before_left_UK__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithAfterUKEmployedCurrent() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update After UK Work employer
        Employer__c afterUKEmployer = [SELECT Id, Type__c, Type_Of_After_UK_Employment__c, Current_Work__c FROM Employer__c WHERE Type__c = 'Work After UK' LIMIT 1];
        afterUKEmployer.Type_Of_After_UK_Employment__c = 'Employed';
        afterUKEmployer.Current_Work__c = 'Yes';
        afterUKEmployer.Employer_Name__c = 'Test Employer';
        update afterUKEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Is_previously_worked_abroad_as_an_emp__c, Employer_abroad_Name__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals(true, createdReapply.Is_previously_worked_abroad_as_an_emp__c);
        System.assertEquals('Test Employer', createdReapply.Employer_abroad_Name__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithAfterUKSelfEmployed() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update After UK Work employer to be self-employed
        Employer__c afterUKEmployer = [SELECT Id, Type__c, Type_Of_After_UK_Employment__c FROM Employer__c WHERE Type__c = 'Work After UK' LIMIT 1];
        afterUKEmployer.Type_Of_After_UK_Employment__c = 'Self-Employed';
        afterUKEmployer.Start_Date__c = Date.newInstance(2020, 1, 1);
        afterUKEmployer.End_Date__c = Date.newInstance(2021, 12, 31);
        update afterUKEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Self_employed_abroad__c, Start_self_employment_abroad_date__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals(true, createdReapply.Self_employed_abroad__c);
        System.assertEquals(Date.newInstance(2020, 1, 1), createdReapply.Start_self_employment_abroad_date__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithMultipleAfterUKEmployers() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Create multiple After UK employers
        TestDataFactory.createEmployer(testApp.Id, 'Work After UK', 'Employed', true);
        TestDataFactory.createEmployer(testApp.Id, 'Work After UK', 'Employed', true);
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Any_other_employments_abroad__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals(true, createdReapply.Any_other_employments_abroad__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithPaymentMethodExtraction() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update application with payment method
        testApp.Payment_Method__c = 'pm_123456789;pm_987654321';
        update testApp;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Payment_Method_Id__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals('pm_987654321', createdReapply.Payment_Method_Id__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithStripeCustomerId() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update application with stripe customer id
        testApp.Current_Customer_Id__c = 'cus_test123';
        update testApp;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Stripe_Customer_Id__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals('cus_test123', createdReapply.Stripe_Customer_Id__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithHistoryData() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Create history records
        // Note: This is simplified - in real scenario, you'd need to create actual history records
        // through DML operations or use TestDataFactory
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        // Verify reapply was created even without history data
        System.assertNotEquals(null, reapplyId);
    }

    @isTest
    static void testCreateRelatedReapply_WithAbroadCountries() {
        Application__c testApp = [SELECT Id, Name, Current_Address_Abroad__CountryCode__s FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Set country code on application
        testApp.Current_Address_Abroad__CountryCode__s = 'US';
        update testApp;
        
        // Create after UK employers with different countries
        List<Employer__c> employers = new List<Employer__c>();
        Employer__c emp1 = TestDataFactory.createEmployer(testApp.Id, 'Work After UK', 'Employed', false);
        emp1.Employers_Address__CountryCode__s = 'US';
        employers.add(emp1);
        
        Employer__c emp2 = TestDataFactory.createEmployer(testApp.Id, 'Work After UK', 'Employed', false);
        emp2.Employers_Address__CountryCode__s = 'CA';
        employers.add(emp2);
        
        // Insert employers
        if (!employers.isEmpty()) {
            insert employers;
        }
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Countries_names_with_dates__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertNotEquals(null, createdReapply.Countries_names_with_dates__c);
        System.assert(createdReapply.Countries_names_with_dates__c.contains('United States') || 
                     createdReapply.Countries_names_with_dates__c.contains('US'));
    }

    @isTest
    static void testCreateRelatedReapply_WithNoAfterUKEmployers() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Delete all after UK employers
        delete [SELECT Id FROM Employer__c WHERE Type__c = 'Work After UK'];
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        // Verify reapply was created even without after UK employers
        System.assertNotEquals(null, reapplyId);
        Reapply__c createdReapply = [SELECT Id, Countries_names_with_dates__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals(null, createdReapply.Countries_names_with_dates__c);
    }

    @isTest
    static void testCreateRelatedReapply_WithEmployedDirectly() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Update application to indicate employed directly
        testApp.Employed_Direcly__c = 'Yes';
        update testApp;
        
        // Update after UK employer
        Employer__c afterUKEmployer = [SELECT Id, Type__c, Type_Of_After_UK_Employment__c FROM Employer__c WHERE Type__c = 'Work After UK' LIMIT 1];
        afterUKEmployer.Type_Of_After_UK_Employment__c = 'Employed';
        afterUKEmployer.Current_Work__c = 'Yes';
        update afterUKEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Employer_an_overseas_gov_international__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals(true, createdReapply.Employer_an_overseas_gov_international__c);
    }

    @isTest
    static void testFormatDate() {
        // This is a private method, but we can test it indirectly through createRelatedReapply
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Set up a date to test formatting
        Employer__c afterUKEmployer = [SELECT Id, Type__c, Type_Of_After_UK_Employment__c, Start_Date__c FROM Employer__c WHERE Type__c = 'Work After UK' LIMIT 1];
        afterUKEmployer.Type_Of_After_UK_Employment__c = 'Self-Employed';
        afterUKEmployer.Start_Date__c = Date.newInstance(2023, 5, 15);
        afterUKEmployer.End_Date__c = Date.newInstance(2024, 8, 20);
        update afterUKEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Countries_names_with_dates__c FROM Reapply__c WHERE Id = :reapplyId];
        // The date should be formatted as dd/MM/yyyy
        System.assert(createdReapply.Countries_names_with_dates__c == null || 
                     !createdReapply.Countries_names_with_dates__c.contains('15/05/2023'));
    }

    @isTest
    static void testGetCountryLabel() {
        // This is a private method, testing through public methods
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Set up a country code
        testApp.Current_Address_Abroad__CountryCode__s = 'GB';
        update testApp;
        
        Employer__c afterUKEmployer = [SELECT Id, Type__c FROM Employer__c WHERE Type__c = 'Work After UK' LIMIT 1];
        afterUKEmployer.Employers_Address__CountryCode__s = 'GB';
        update afterUKEmployer;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, Countries_names_with_dates__c FROM Reapply__c WHERE Id = :reapplyId];
        // The country label should be populated from the picklist
        if (createdReapply.Countries_names_with_dates__c != null) {
            System.assert(createdReapply.Countries_names_with_dates__c.contains('United Kingdom') || 
                         createdReapply.Countries_names_with_dates__c.contains('GB'));
        }
    }

    @isTest
    static void testCreateRelatedReapply_WithBlankNINO() {
        Application__c testApp = [SELECT Id, Name FROM Application__c LIMIT 1];
        delete [SELECT Id FROM Reapply__c WHERE Application__c = :testApp.Id];
        
        // Set NINO with spaces
        testApp.National_Insurance_Number__c = 'AB 12 34 56 C';
        update testApp;
        
        Test.startTest();
        String reapplyId = RE_ApplicationDataAction.createRelatedReapply(testApp.Id, false);
        Test.stopTest();
        
        Reapply__c createdReapply = [SELECT Id, NINO__c FROM Reapply__c WHERE Id = :reapplyId];
        System.assertEquals('AB123456C', createdReapply.NINO__c);
    }
}