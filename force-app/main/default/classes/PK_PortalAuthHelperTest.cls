@isTest
public class PK_PortalAuthHelperTest {
    
    @TestSetup
    static void setup() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
    }
    
    @isTest
    static void testLoginSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'login@test.com';
        app.National_Insurance_Number__c = 'AB123456C';
        app.Second_Name__c = 'Smith';
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'AB123456CSMITH';
        app.Salutation__c = 'Mr.';
        update app;
        
        PK_RequestWrappers.LoginDataWrapper wrapper = new PK_RequestWrappers.LoginDataWrapper(
            '{"applicationNumber":"'+ app.Name +'","password":"AB123456CSMITH","ip":"192.168.1.1","device":"Desktop","countryISO":"GB","browser":"Chrome"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.login(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
        System.assertNotEquals(null, result.get('application'));
    }
    
    @isTest
    static void testLoginInvalidPassword() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'login2@test.com';
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'AB123456CSMITH';
        update app;
        
        PK_RequestWrappers.LoginDataWrapper wrapper = new PK_RequestWrappers.LoginDataWrapper(
            '{"applicationNumber":"'+ app.Name +'","password":"WRONGPASSWORD","ip":"192.168.1.1","device":"Desktop","countryISO":"GB","browser":"Chrome"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.login(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Active Application not found', result.get('message'));
    }
    
    @isTest
    static void testLoginNullFields() {
        PK_RequestWrappers.LoginDataWrapper wrapper = new PK_RequestWrappers.LoginDataWrapper(
            '{"applicationNumber":null,"password":"test","ip":"192.168.1.1","device":"Desktop","countryISO":"GB","browser":"Chrome"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.login(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
    }
    
    @isTest
    static void testLoginApplicationNotFound() {
        PK_RequestWrappers.LoginDataWrapper wrapper = new PK_RequestWrappers.LoginDataWrapper(
            '{"applicationNumber":"NONEXISTENT","password":"test","ip":"192.168.1.1","device":"Desktop","countryISO":"GB","browser":"Chrome"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.login(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Active Application not found', result.get('message'));
    }
    
    @isTest
    static void testForgotPasswordSuccess() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'forgot@test.com';
        app.PK_Portal_User_Active__c = true;
        app.PK_Portal_User_PW__c = 'AB123456CSMITH';
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"'+ app.Name +'","email":"forgot@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.forgotPassword(wrapper);
        Test.stopTest();
        
        System.assertEquals('success', result.get('status'));
    }
    
    @isTest
    static void testForgotPasswordNullApplicationNumber() {
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":null,"email":"test@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.forgotPassword(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Application Number is null', result.get('message'));
    }
    
    @isTest
    static void testForgotPasswordApplicationNotFound() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.Email__c = 'forgot2@test.com';
        update app;
        
        PK_RequestWrappers.ApplicationDataWrapper wrapper = new PK_RequestWrappers.ApplicationDataWrapper(
            '{"applicationNumber":"'+ app.Name +'","email":"forgot2@test.com"}'
        );
        
        Test.startTest();
        Map<String, Object> result = PK_PortalAuthHelper.forgotPassword(wrapper);
        Test.stopTest();
        
        System.assertEquals('error', result.get('status'));
        System.assertEquals('Active Application not found', result.get('message'));
    }
    
    @isTest
    static void testGeneratePassword() {
        List<Application__c> apps = [
            SELECT
                Name
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.National_Insurance_Number__c = 'AB123456C';
        app.Second_Name__c = 'Smith';
        update app;
        
        Test.startTest();
        String password = PK_PortalAuthHelper.generatePassword(app);
        Test.stopTest();
        
        System.assertNotEquals(null, password);
        System.assertEquals('AB123456CSMITH', password);
    }
    
    @isTest
    static void testGeneratePasswordWithApostrophe() {
        List<Application__c> apps = [
            SELECT
                Id,
                National_Insurance_Number__c,
                Second_Name__c
            FROM Application__c
        ];
        Application__c app = apps[0];
        app.National_Insurance_Number__c = 'AB123456C';
        app.Second_Name__c = 'O\'Brien';
        update app;
        
        Test.startTest();
        String password = PK_PortalAuthHelper.generatePassword(app);
        Test.stopTest();
        
        System.assertNotEquals(null, password);
        System.assertEquals('AB123456COBRIEN', password);
    }
}