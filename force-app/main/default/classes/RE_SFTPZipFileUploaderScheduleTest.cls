@isTest
public class RE_SFTPZipFileUploaderScheduleTest {
    @TestSetup
    static void makeData(){
        // 1. Create the Printing_House_SFTP__c custom setting FIRST
        createPrintingHouseSFTP();
        
        // 2. Create the XtraPension_Data__c custom setting
        createXtraPensionData();
        
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, false);
        testReapply.FTP_Reapply_Full_Form_Created_Send_Date__c = NULL;
        testReapply.Reapply_Full_Form_ZIP_for_UPLOAD__c = true;
        insert testReapply;
        
        // Create content version with proper naming that batch expects
        ContentVersion testContentVersion1 = new ContentVersion(
            Title = 'Test_CF083_completed',
            PathOnClient = 'Test_CF083_completed.pdf',
            VersionData = Blob.valueOf('Test Content 1')
        );
        insert testContentVersion1;
        
        ContentVersion testContentVersion2 = new ContentVersion(
            Title = 'Test_RVN_completed',
            PathOnClient = 'Test_RVN_completed.pdf',
            VersionData = Blob.valueOf('Test Content 2')
        );
        insert testContentVersion2;
        
        // Create ContentDocumentLinks
        List<ContentVersion> insertedVersions = [SELECT Id, ContentDocumentId FROM ContentVersion];
        List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
        for (ContentVersion cv : insertedVersions) {
            ContentDocumentLink link = new ContentDocumentLink(
                LinkedEntityId = testReapply.Id,
                ContentDocumentId = cv.ContentDocumentId,
                ShareType = 'V'
            );
            linksToInsert.add(link);
        }
        insert linksToInsert;
    }

    @IsTest
    static void checkStatusSuccesResultTest(){
        // Set up mock for any SFTP callouts
        Test.setMock(HttpCalloutMock.class, new SFTPMockResponse());
        
        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);
        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';
        
        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new RE_SFTPZipFileUploaderSchedule());
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Schedule Job Id must be not null');
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE id = :jobId
        ];
        System.assertEquals(scheduleTime, ct.CronExpression, 'CronExpression must be like scheduleTime');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');
    }
    
    // Helper method to create Printing_House_SFTP__c custom setting
    private static void createPrintingHouseSFTP() {
        Printing_House_SFTP__c sftpSetting = new Printing_House_SFTP__c(
            Name = 'Default',
            Key__c = 'test-key',
            Host__c = 'test.sftp.com',
            Port__c = '22',
            UserName__c = 'testuser',
            Password__c = 'testpass',
            Reapply_Folder__c = '/test/folder'
        );
        // Use insert with bypass sharing if needed, or just insert
        insert sftpSetting;
    }
    
    // Helper method to create XtraPension_Data__c custom setting
    private static void createXtraPensionData() {
        // Check if your TestDataFactory already creates this, but if not:
        XtraPension_Data__c xtraData = new XtraPension_Data__c(
            Name = 'Default',
            RE_SFTP_Upload_File_Link__c = 'https://test-sftp-endpoint.com/upload'
        );
        insert xtraData;
    }
    
    // Mock class for SFTP responses
    private class SFTPMockResponse implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }
}