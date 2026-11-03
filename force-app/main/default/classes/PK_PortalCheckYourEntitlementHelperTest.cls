@isTest
public class PK_PortalCheckYourEntitlementHelperTest {
    
    @TestSetup
    static void setup() {
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Success', 'Pension Keeper'};
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
        Order testOrder = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        List<Payment__c> testPayments = TestDataFactory.createRelatedPaymentToApplication(
            newProducts,
            testApplication,
            testOrder.Id,
            true
        );
    }
    
    @isTest
    static void testGetCheckYourEntitlementDataSuccess() {
        // Create test application
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(
            '{"id":"' + app.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.getCheckYourEntitlementData(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('application'));
    }
    
    @isTest
    static void testGetCheckYourEntitlementDataNullId() {
        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(
            '{"id":null}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.getCheckYourEntitlementData(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Id is null', result.get('message'));
    }
    
    @isTest
    static void testGetCheckYourEntitlementDataNullWrapper() {
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.getCheckYourEntitlementData(null);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Id is null', result.get('message'));
    }
    
    @isTest
    static void testGetCheckYourEntitlementDataApplicationNotFound() {
        PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper = new PK_RequestWrappers.ApplicationDetailsDataWrapper(
            '{"id":"' + UserInfo.getOrganizationId().substring(0,15) + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.getCheckYourEntitlementData(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }
    
    @isTest
    static void testSaveTaxYearAllocationsSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        List<PK_RequestWrappers.TaxYearAllocationWrapper> taxYears = new List<PK_RequestWrappers.TaxYearAllocationWrapper>();
        taxYears.add(new PK_RequestWrappers.TaxYearAllocationWrapper('2023 to 2024', true));
        taxYears.add(new PK_RequestWrappers.TaxYearAllocationWrapper('2024 to 2025', false));
        
        PK_RequestWrappers.SaveTaxYearWrapper wrapper = new PK_RequestWrappers.SaveTaxYearWrapper(
            '{"id":"' + app.Id + '","taxYearAllocation":[{"label":"2023 to 2024","isChecked":true}]}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveTaxYearAllocations(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        
        Application__c updatedApp = [SELECT Tax_Year_Allocation__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('2023 to 2024', updatedApp.Tax_Year_Allocation__c);
    }
    
    @isTest
    static void testSaveTaxYearAllocationsMultiple() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.SaveTaxYearWrapper wrapper = new PK_RequestWrappers.SaveTaxYearWrapper(
            '{"id":"' + app.Id + '","taxYearAllocation":[{"label":"2023 to 2024","isChecked":true},{"label":"2024 to 2025","isChecked":true}]}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveTaxYearAllocations(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        
        Application__c updatedApp = [SELECT Tax_Year_Allocation__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('2023 to 2024;2024 to 2025', updatedApp.Tax_Year_Allocation__c);
    }
    
    @isTest
    static void testSaveTaxYearAllocationsNullId() {
        PK_RequestWrappers.SaveTaxYearWrapper wrapper = new PK_RequestWrappers.SaveTaxYearWrapper(
            '{"id":null,"taxYearAllocation":[]}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveTaxYearAllocations(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
    }
    
    @isTest
    static void testSaveTaxYearAllocationsApplicationNotFound() {
        PK_RequestWrappers.SaveTaxYearWrapper wrapper = new PK_RequestWrappers.SaveTaxYearWrapper(
            '{"id":"' + UserInfo.getOrganizationId().substring(0,15) + '","taxYearAllocation":[]}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveTaxYearAllocations(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }
    
    @isTest
    static void testSaveRequestCheckSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.RequestCheckWrapper wrapper = new PK_RequestWrappers.RequestCheckWrapper(
            '{"id":"' + app.Id + '","amountPaid":500,"whenPaid":"2024-01-15"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveRequestCheck(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testSaveRequestCheckNullId() {
        PK_RequestWrappers.RequestCheckWrapper wrapper = new PK_RequestWrappers.RequestCheckWrapper(
            '{"id":null,"amountPaid":500,"whenPaid":"2024-01-15"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveRequestCheck(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Id is null', result.get('message'));
    }
    
    @isTest
    static void testSaveRequestCheckApplicationNotFound() {
        PK_RequestWrappers.RequestCheckWrapper wrapper = new PK_RequestWrappers.RequestCheckWrapper(
            '{"id":"' + UserInfo.getOrganizationId().substring(0,15) + '","amountPaid":500,"whenPaid":"2024-01-15"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.saveRequestCheck(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Not found application', result.get('message'));
    }
    
    @isTest
    static void testGetRequestCheckSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        // Create request check
        PK_Request_Check__c request = new PK_Request_Check__c(
            Application__c = app.Id,
            PK_Requested_Check_Date__c = Date.today(),
            PK_Amount_Paid__c = 500,
            PK_When_Paid__c = Date.today(),
            PK_Payment_Received__c = Date.today(),
            CurrencyIsoCode = 'GBP'
        );
        insert request;
        
        PK_RequestWrappers.RequestCheckWrapper wrapper = new PK_RequestWrappers.RequestCheckWrapper(
            '{"id":"' + app.Id + '","amountPaid":500,"whenPaid":"2024-01-15"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.getRequestCheck(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('checkRequest'));
    }
    
    @isTest
    static void testGetRequestCheckNullId() {
        PK_RequestWrappers.RequestCheckWrapper wrapper = new PK_RequestWrappers.RequestCheckWrapper(
            '{"id":null,"amountPaid":500,"whenPaid":"2024-01-15"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.getRequestCheck(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
    }
    
    @isTest
    static void testEditExtraYearsSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.EditExtraYearsWrapper wrapper = new PK_RequestWrappers.EditExtraYearsWrapper(
            '{"id":"' + app.Id + '","extraYears":5}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.editExtraYears(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        
        Application__c updatedApp = [SELECT PK_Extra_Years__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(5, updatedApp.PK_Extra_Years__c);
    }
    
    @isTest
    static void testEditExtraYearsNullId() {
        PK_RequestWrappers.EditExtraYearsWrapper wrapper = new PK_RequestWrappers.EditExtraYearsWrapper(
            '{"id":null,"extraYears":5}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.editExtraYears(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
    }
    
    @isTest
    static void testTickEntitlementOptionNewEntry() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + app.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.tickEntitlementOption(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        
        Application__c updatedApp = [SELECT Tax_Year_Allocation__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('2025 to 2026', updatedApp.Tax_Year_Allocation__c);
    }
    
    @isTest
    static void testTickEntitlementOptionExistingEntry() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Tax_Year_Allocation__c = '2023 to 2024';
        update app;
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + app.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.tickEntitlementOption(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        
        Application__c updatedApp = [SELECT Tax_Year_Allocation__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('2023 to 2024;2025 to 2026', updatedApp.Tax_Year_Allocation__c);
    }
    
    @isTest
    static void testTickEntitlementOptionAlreadyExists() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Tax_Year_Allocation__c = '2025 to 2026';
        update app;
        
        PK_RequestWrappers.RecordDataWrapper wrapper = new PK_RequestWrappers.RecordDataWrapper(
            '{"id":"' + app.Id + '"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalCheckYourEntitlementHelper.tickEntitlementOption(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        
        Application__c updatedApp = [SELECT Tax_Year_Allocation__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('2025 to 2026', updatedApp.Tax_Year_Allocation__c);
    }
}