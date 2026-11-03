@isTest
public class AwsS3ApplicationServiceTest {
    
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
        
        // Create Application without S3 Package ID
        Application__c testApplication = new Application__c(
            First_Name__c = 'John',
        Second_Name__c = 'Snow',
        Contact__c = personContactId,
        AWS_S3_Package_Id__c = null,
        Send_To_AWS_S3_Date__c = null
            );
        insert testApplication;
        
        // Create Application with existing S3 Package ID
        Application__c existingApp = new Application__c(
            First_Name__c = 'Gimmy',
        Second_Name__c = 'Gorh',
        Contact__c = personContactId,
        AWS_S3_Package_Id__c = 'existing-package-123',
        Send_To_AWS_S3_Date__c = Date.today().addDays(-1)
            );
        insert existingApp;
    }
    
    /**
     * Test: Constructor
     */
    @isTest
    static void testConstructor() {
        // Setup
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        UploadConfiguration config = new UploadConfiguration();
        AwsS3BatchState state = new AwsS3BatchState();
        
        Test.startTest();
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, service, 'Service should be instantiated');
    }
    
    /**
     * Test: updateApplication with new application (no S3 Package ID)
     * Should set S3 Package ID and upload date
     */
    @isTest
    static void testUpdateApplicationNewApplication() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'test-package-456';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        state.packageAction = 'CREATE_NEW';
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        // Verify initial state
        System.assertEquals(null, app.AWS_S3_Package_Id__c, 'S3 Package ID should be null initially');
        System.assertEquals(null, app.Send_To_AWS_S3_Date__c, 'Upload date should be null initially');
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify updates
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals('test-package-456', updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should be set');
        System.assertEquals(Date.today(), updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should be set to today');
        System.assertEquals(true, updatedApp.Send_Files_To_AWS_S3__c, 'Send Files flag should be true');
    }
    
    /**
     * Test: updateApplication with existing S3 Package ID
     * Should not override existing S3 Package ID
     */
    @isTest
    static void testUpdateApplicationExistingPackage() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Existing Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'new-package-789';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        state.packageAction = 'UPDATE_EXISTING';
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        // Verify initial state
        System.assertEquals('existing-package-123', app.AWS_S3_Package_Id__c, 'S3 Package ID should exist initially');
        System.assertEquals(Date.today().addDays(-1), app.Send_To_AWS_S3_Date__c, 'Upload date should be yesterday');
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify existing S3 Package ID was NOT overridden
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals('existing-package-123', updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should NOT be overridden');
        System.assertEquals(Date.today(), updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should be updated to today');
        System.assertEquals(true, updatedApp.Send_Files_To_AWS_S3__c, 'Send Files flag should be true');
    }
    
    /**
     * Test: updateApplication when all uploads are not successful
     * Should not update the upload date
     */
    @isTest
    static void testUpdateApplicationWithFailedUploads() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'test-package-456';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = false;  // Not all uploads succeeded
        state.packageAction = 'UPDATE_EXISTING';
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify S3 Package ID was set but upload date was not
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals('test-package-456', updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should be set');
        System.assertEquals(null, updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should NOT be set when uploads fail');
    }
    
    /**
     * Test: updateApplication when config is null
     * Should handle gracefully
     */
    @isTest
    static void testUpdateApplicationWithNullConfig() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, null, state);
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify no updates were made (config is null)
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals(null, updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should remain null');
        System.assertEquals(Date.today(), updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should be set');
    }
    
    /**
     * Test: updateApplication when state is null
     * Should handle gracefully
     */
    @isTest
    static void testUpdateApplicationWithNullState() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'test-package-456';
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, null);
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify S3 Package ID was set despite state being null
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals('test-package-456', updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should be set');
        System.assertEquals(null, updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should NOT be set when state is null');
    }
    
    /**
     * Test: updateApplication with invalid Application ID
     * Should throw exception
     */
    @isTest
    static void testUpdateApplicationWithInvalidId() {
        // Setup
        Id invalidId = '001000000000000000';  // Non-existent ID
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'test-package-456';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(invalidId, config, state);
        
        Test.startTest();
        try {
            service.updateApplication();
            System.assert(false, 'Exception should have been thrown');
        } catch (AwsS3ApplicationService.AwsS3ApplicationException e) {
            System.assert(true, 'Exception was thrown as expected');
            System.assert(e.getMessage().contains('Failed to update Application'), 'Exception message should be correct');
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception type: ' + e.getTypeName());
        }
        Test.stopTest();
    }
    
    /**
     * Test: updateApplication when no updates are needed
     * Should not perform any updates
     */
    @isTest
    static void testUpdateApplicationNoUpdatesNeeded() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Existing Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = null;  // No S3 Package ID to set
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = false;  // Uploads not successful
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        // Save initial state
        String initialPackageId = app.AWS_S3_Package_Id__c;
        Date initialDate = app.Send_To_AWS_S3_Date__c;
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify no changes were made
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals(initialPackageId, updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should not change');
        System.assertEquals(initialDate, updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should not change');
    }
    
    /**
     * Test: updateApplication with package action tracking
     * Tests that package action is tracked
     */
    @isTest
    static void testUpdateApplicationWithPackageAction() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'test-package-456';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        state.packageAction = 'UPDATE_EXISTING';
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify updates
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals('test-package-456', updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should be set');
        System.assertEquals(Date.today(), updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should be set to today');
    }
    
    /**
     * Test: updateApplication when S3 Package ID is already set but config has new ID
     * Should NOT override existing S3 Package ID
     */
    @isTest
    static void testUpdateApplicationWithExistingPackageIdAndNewConfig() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Existing Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'new-package-999';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        state.packageAction = 'UPDATE_EXISTING';
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        // Verify initial state
        System.assertEquals('existing-package-123', app.AWS_S3_Package_Id__c, 'S3 Package ID should exist initially');
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify existing S3 Package ID was NOT overridden
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals('existing-package-123', updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should NOT be overridden');
        System.assertEquals(Date.today(), updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should be updated to today');
    }
    
    /**
     * Test: updateApplication when config has blank s3PackageId
     * Should not set S3 Package ID
     */
    @isTest
    static void testUpdateApplicationWithBlankPackageId() {
        // Setup
        Application__c app = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                             FROM Application__c WHERE Name = 'Test Application' LIMIT 1];
        
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = '';  // Blank S3 Package ID
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(app.Id, config, state);
        
        // Verify initial state
        System.assertEquals(null, app.AWS_S3_Package_Id__c, 'S3 Package ID should be null initially');
        
        Test.startTest();
        service.updateApplication();
        Test.stopTest();
        
        // Verify S3 Package ID was NOT set (blank value)
        Application__c updatedApp = [SELECT Id, AWS_S3_Package_Id__c, Send_To_AWS_S3_Date__c 
                                    FROM Application__c WHERE Id = :app.Id];
        
        System.assertEquals(null, updatedApp.AWS_S3_Package_Id__c, 'S3 Package ID should remain null');
        System.assertEquals(Date.today(), updatedApp.Send_To_AWS_S3_Date__c, 'Upload date should be set');
    }
    
    /**
     * Test: updateApplication with null Application ID
     * Should throw exception
     */
    @isTest
    static void testUpdateApplicationWithNullApplicationId() {
        // Setup
        UploadConfiguration config = new UploadConfiguration();
        config.s3PackageId = 'test-package-456';
        
        AwsS3BatchState state = new AwsS3BatchState();
        state.allUploadsSuccessful = true;
        
        AwsS3ApplicationService service = new AwsS3ApplicationService(null, config, state);
        
        Test.startTest();
        try {
            service.updateApplication();
            System.assert(false, 'Exception should have been thrown');
        } catch (AwsS3ApplicationService.AwsS3ApplicationException e) {
            System.assert(true, 'Exception was thrown as expected');
            System.assert(e.getMessage().contains('Failed to update Application'), 'Exception message should be correct');
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception type: ' + e.getTypeName());
        }
        Test.stopTest();
    }
}