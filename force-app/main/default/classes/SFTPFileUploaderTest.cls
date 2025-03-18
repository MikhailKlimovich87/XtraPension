@isTest
global class SFTPFileUploaderTest {
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        Application_Document__c ad = new Application_Document__c(
            Status__c = 'Ready For PH',
            File_Name__c = 'CF083_ForSignature',
            Application__c = testApplication.Id
        );

        insert ad;

        ContentVersion cv = new ContentVersion(
            Title        = 'CF083',
            PathOnClient = 'CF083.txt',
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
                LinkedEntityId    = ad.Id,
                Visibility        = 'AllUsers'
        );

        insert cdl;

        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    @isTest
    public static void fileUploaderTest() {

        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour() + 1);

        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';

        Test.setMock(HttpCalloutMock.class, new SFTPFileUploaderHttpCalloutMock());

        Test.startTest();
        String jobId = System.schedule('Test', scheduleTime, new SFTPFileUploaderSchedule());
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

    global class SFTPFileUploaderHttpCalloutMock implements HttpCalloutMock {
        global HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('Success');
            response.setStatusCode(200);
            return response;
        }
    }

}