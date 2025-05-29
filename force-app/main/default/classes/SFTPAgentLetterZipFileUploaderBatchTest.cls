@isTest
public class SFTPAgentLetterZipFileUploaderBatchTest {
    @TestSetup
    public static void setup() {
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
        testApplication.Tracking_Number_Received_Date__c = Date.newInstance(2025, 01, 02);
        testApplication.AgentAuthApp__c = true;
        insert testApplication;

        ContentVersion cv = new ContentVersion(
            Title        = 'Test_64-8_AgentAuth',
            PathOnClient = 'Test_64-8_AgentAuth.zip',
            VersionData  = Blob.valueOf('Test')
        );

        insert cv;

        cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id =: cv.Id
        ];

        ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId    = testApplication.Id,
                Visibility        = 'AllUsers'
        );

        insert cdl;

        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @IsTest
    static void SFTPAgentAuthLetterZipFileUploadFileTest() {
        Test.setMock(HttpCalloutMock.class, new SFTPFileUploaderHttpCalloutMock());
        List<Application__c> testAppBeforeSendDocs = [
            SELECT 
                X64_8_AgentLetter_FTP_Send_Date__c,
                X64_8_AgentLetter_FTP_Uploading_Error__c
            FROM Application__c
        ];
        Assert.areEqual(null, testAppBeforeSendDocs[0].X64_8_AgentLetter_FTP_Send_Date__c);
        Test.startTest();
        Database.executeBatch(new SFTPAgentAuthLetterZipFileUploaderBatch(), 1);
        Test.stopTest();
        List<Application__c> testAppAfterSendDocs = [
            SELECT 
                X64_8_AgentLetter_FTP_Send_Date__c,
                X64_8_AgentLetter_FTP_Uploading_Error__c
            FROM Application__c
        ];
        Assert.areNotEqual(null, testAppAfterSendDocs[0].X64_8_AgentLetter_FTP_Send_Date__c);
        Assert.areEqual(Date.today(), testAppAfterSendDocs[0].X64_8_AgentLetter_FTP_Send_Date__c);
    }

    @isTest
    public static void fileUploaderTest() {

        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);

        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';

        Test.setMock(HttpCalloutMock.class, new SFTPFileUploaderHttpCalloutMock());

        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new SFTPAgentAuthLetterZipFileUploadSchedule());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedule Job Id must be not null');
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE id = :jobId
        ];
        System.assertEquals(scheduleTime, ct.CronExpression, 'CronExpression must be like scheduleTime');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');
    }

    public class SFTPFileUploaderHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('Success');
            response.setStatusCode(200);
            return response;
        }
    }
}