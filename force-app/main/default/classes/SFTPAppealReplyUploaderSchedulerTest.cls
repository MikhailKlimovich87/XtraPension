@isTest
public class SFTPAppealReplyUploaderSchedulerTest {

    // ---------------------------------------------------------------------
    // Test Setup
    // ---------------------------------------------------------------------
    @TestSetup
    public static void setup() {
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

        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c = 'HMRC Appeal';
        insert testApplication;

        HMRC_Appeal_Reply__c testAppealReply = new HMRC_Appeal_Reply__c(
            Application__c = testApplication.Id
        );
        insert testAppealReply;

        // REPLY file
        ContentVersion cv1 = new ContentVersion(
            Title        = 'REPLY',
            PathOnClient = 'REPLY.pdf',
            VersionData  = Blob.valueOf('Test')
        );
        insert cv1;
        cv1 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv1.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv1.ContentDocumentId,
            LinkedEntityId    = testAppealReply.Id,
            Visibility        = 'AllUsers'
        );

        // UPLOAD file 1
        ContentVersion cv2 = new ContentVersion(
            Title        = 'UPLOAD',
            PathOnClient = 'UPLOAD.pdf',
            VersionData  = Blob.valueOf('Test')
        );
        insert cv2;
        cv2 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv2.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv2.ContentDocumentId,
            LinkedEntityId    = testAppealReply.Id,
            Visibility        = 'AllUsers'
        );

        // UPLOAD file 2
        ContentVersion cv3 = new ContentVersion(
            Title        = 'UPLOAD',
            PathOnClient = 'UPLOAD.pdf',
            VersionData  = Blob.valueOf('Test')
        );
        insert cv3;
        cv3 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv3.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv3.ContentDocumentId,
            LinkedEntityId    = testAppealReply.Id,
            Visibility        = 'AllUsers'
        );

        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }

    // ---------------------------------------------------------------------
    // Helper: create a fresh Application + HMRC_Appeal_Reply__c not tied to
    // the shared test setup (so we can control which records the batch
    // actually processes).
    // ---------------------------------------------------------------------
    private static HMRC_Appeal_Reply__c createReply(String status) {
        Account account = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];
        Contact con = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];

        Application__c app = TestDataFactory.createApplication(con.Id, false);
        app.Status__c = 'HMRC Appeal';
        insert app;

        HMRC_Appeal_Reply__c reply = new HMRC_Appeal_Reply__c(
            Application__c = app.Id,
            Status__c      = status
        );
        insert reply;
        return reply;
    }

    /**
     * Attaches a ContentVersion with the given title to the reply.
     */
    private static Id attachFile(Id replyId, String title, Blob body) {
        ContentVersion cv = new ContentVersion(
            Title        = title,
            PathOnClient = title + '.pdf',
            VersionData  = body
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = replyId,
            Visibility        = 'AllUsers'
        );
        return cv.Id;
    }

    /**
     * Deletes all HMRC_Appeal_Reply__c records created by @TestSetup so a
     * test can start with a clean slate and create its own.
     */
private static void clearSetupReplies() {
    List<HMRC_Appeal_Reply__c> existing = [
        SELECT Id FROM HMRC_Appeal_Reply__c
    ];
    if (existing.isEmpty()) {
        return;
    }

    Set<Id> replyIds = new Map<Id, HMRC_Appeal_Reply__c>(existing).keySet();

    List<ContentDocumentLink> links = [
        SELECT Id
        FROM ContentDocumentLink
        WHERE LinkedEntityId IN :replyIds
    ];
    if (!links.isEmpty()) {
        delete links;
    }

    delete existing;
}

    // ---------------------------------------------------------------------
    // Scheduler test (existing)
    // ---------------------------------------------------------------------
    @isTest
    public static void fileUploaderTest() {

        Datetime currentTime = Datetime.now();
        String scheduleHours = String.valueOf(currentTime.hour());

        String scheduleTime = '0 0 ' + scheduleHours + ' * * ?';

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        Test.startTest();
        String jobId = System.schedule(
            'Test',
            scheduleTime,
            new SFTPAppealReplyUploaderScheduler()
        );
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Schedule Job Id must be not null');
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(scheduleTime, ct.CronExpression, 'CronExpression must be like scheduleTime');
        System.assertEquals(0, ct.TimesTriggered, 'TimesTriggered must be 0');
    }

    // ---------------------------------------------------------------------
    // Batch: happy path — REPLY1 + two UPLOADs, all 200 OK
    // ---------------------------------------------------------------------
    @isTest
    public static void batchSuccessTest() {
        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        // Use the reply created in @TestSetup (it already has REPLY + 2 UPLOADs)
        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c reply = [
            SELECT Status__c, Sent_To_HMRC_Date__c, Error_Message__c
            FROM HMRC_Appeal_Reply__c
            WHERE Status__c = 'Sent to HMRC'
            LIMIT 1
        ];
        System.assertEquals('Sent to HMRC', reply.Status__c, 'Status should be Sent to HMRC');
        System.assertEquals(Date.today(), reply.Sent_To_HMRC_Date__c, 'Sent date should be today');
        System.assertEquals(null, reply.Error_Message__c, 'Error message should be null');
    }

    // ---------------------------------------------------------------------
    // Batch: no records qualify — execute should early-return
    // ---------------------------------------------------------------------
    @isTest
    public static void batchNoRecordsTest() {
        clearSetupReplies();

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM HMRC_Appeal_Reply__c WHERE Status__c = 'Failed'],
            'No records should be marked Failed'
        );
    }

    // ---------------------------------------------------------------------
    // Batch: reply has no ContentDocumentLinks — execute early-returns
    // ---------------------------------------------------------------------
    @isTest
    public static void batchNoContentDocumentsTest() {
        clearSetupReplies();
        HMRC_Appeal_Reply__c reply = createReply('New');

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c result = [
            SELECT Status__c, Sent_To_HMRC_Date__c
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :reply.Id
        ];
        System.assertEquals('New', result.Status__c, 'Status should remain New when no files');
        System.assertEquals(null, result.Sent_To_HMRC_Date__c, 'Sent date should be null');
    }

    // ---------------------------------------------------------------------
    // Batch: HTTP error on first file — should mark Failed and stop
    // ---------------------------------------------------------------------
    @isTest
    public static void batchHttpErrorTest() {
        clearSetupReplies();
        HMRC_Appeal_Reply__c reply = createReply('New');
        attachFile(reply.Id, 'REPLY', Blob.valueOf('Test'));

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyErrorHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c result = [
            SELECT Status__c, Error_Message__c, Sent_To_HMRC_Date__c
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :reply.Id
        ];
        System.assertEquals('Failed', result.Status__c, 'Status should be Failed');
        System.assertNotEquals(null, result.Error_Message__c, 'Error message should be populated');
        System.assertEquals(null, result.Sent_To_HMRC_Date__c, 'Sent date should remain null');
    }

    // ---------------------------------------------------------------------
    // Batch: file exceeds MAX_FILE_SIZE — should be caught, marked Failed
    // ---------------------------------------------------------------------
    @isTest
    public static void batchFileTooLargeTest() {
        clearSetupReplies();
        HMRC_Appeal_Reply__c reply = createReply('New');

        // Build a blob just above MAX_FILE_SIZE (3,000,000 bytes)
        Blob bigBlob = Blob.valueOf('x'.repeat(3000001));
        attachFile(reply.Id, 'REPLY', bigBlob);

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c result = [
            SELECT Status__c, Error_Message__c
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :reply.Id
        ];
        System.assertEquals('Failed', result.Status__c, 'Status should be Failed');
        System.assert(
            result.Error_Message__c != null
                && result.Error_Message__c.contains('exceeding max'),
            'Error message should mention max file size, got: ' + result.Error_Message__c
        );
    }

    // ---------------------------------------------------------------------
    // Batch: callout throws (mock throws) — caught and marked Failed
    // ---------------------------------------------------------------------
    @isTest
    public static void batchCalloutExceptionTest() {
        clearSetupReplies();
        HMRC_Appeal_Reply__c reply = createReply('New');
        attachFile(reply.Id, 'REPLY', Blob.valueOf('Test'));

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyThrowingHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c result = [
            SELECT Status__c, Error_Message__c
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :reply.Id
        ];
        System.assertEquals('Failed', result.Status__c, 'Status should be Failed');
        System.assertNotEquals(null, result.Error_Message__c, 'Error message should be populated');
    }

    // ---------------------------------------------------------------------
    // Batch: REPLY1 not present — all files become REPLY1, REPLY2, ...
    // ---------------------------------------------------------------------
    @isTest
    public static void batchNoReply1Test() {
        clearSetupReplies();
        HMRC_Appeal_Reply__c reply = createReply('New');
        attachFile(reply.Id, 'UPLOAD_ONE', Blob.valueOf('Test'));
        attachFile(reply.Id, 'UPLOAD_TWO', Blob.valueOf('Test'));

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c result = [
            SELECT Status__c, Sent_To_HMRC_Date__c
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :reply.Id
        ];
        System.assertEquals('Sent to HMRC', result.Status__c, 'Status should be Sent to HMRC');
        System.assertEquals(Date.today(), result.Sent_To_HMRC_Date__c);
    }

    // ---------------------------------------------------------------------
    // Batch: reply already Sent to HMRC is not picked up by start()
    // ---------------------------------------------------------------------
    @isTest
    public static void batchIgnoresAlreadySentTest() {
        clearSetupReplies();
        HMRC_Appeal_Reply__c reply = createReply('New');
        attachFile(reply.Id, 'REPLY', Blob.valueOf('Test'));

        // Mark it as already sent BEFORE the batch runs.
        reply.Sent_To_HMRC_Date__c = Date.today().addDays(-1);
        reply.Status__c = 'Sent to HMRC';
        update reply;

        Test.setMock(HttpCalloutMock.class, new SFTPAppealReplyHttpCalloutMock());

        Test.startTest();
        Database.executeBatch(new SFTPAppealReplyUploaderBatch(), 1);
        Test.stopTest();

        HMRC_Appeal_Reply__c result = [
            SELECT Status__c, Sent_To_HMRC_Date__c
            FROM HMRC_Appeal_Reply__c
            WHERE Id = :reply.Id
        ];
        // Should be unchanged
        System.assertEquals('Sent to HMRC', result.Status__c);
        System.assertEquals(
            Date.today().addDays(-1),
            result.Sent_To_HMRC_Date__c,
            'Sent date should not be modified by the batch'
        );
    }

    // ---------------------------------------------------------------------
    // HttpCalloutMock implementations
    // ---------------------------------------------------------------------

    public class SFTPAppealReplyHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('Success');
            response.setStatusCode(200);
            return response;
        }
    }

    public class SFTPAppealReplyErrorHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setBody('Server Error');
            response.setStatusCode(500);
            return response;
        }
    }

    public class SFTPAppealReplyThrowingHttpCalloutMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Simulated callout failure');
        }
    }
}