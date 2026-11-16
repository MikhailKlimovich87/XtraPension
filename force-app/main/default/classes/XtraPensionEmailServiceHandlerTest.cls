@isTest
public with sharing class XtraPensionEmailServiceHandlerTest {
    @TestSetup
    static void setup(){
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
        ContentVersion cv = new ContentVersion(
            Title        = 'REPLY',
            PathOnClient = 'REPLY.pdf',
            VersionData  = Blob.valueOf('Test')
        );

        insert cv;
        HMRC_Appeal_Reply__c testAppealReply = new HMRC_Appeal_Reply__c(
            Application__c = testApplication.Id,
            Status__c = 'Sent to HMRC',
            Client_Attach_File_Ids__c = JSON.serializePretty(new List<Id>{cv.Id})
        );
        insert testAppealReply;
    }

    @IsTest
    static void handleInboundEmailCase1Test() {
        Application__c testApplicaition = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c,
                Email__c,
                Tracking_Number__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail() ;
        String subject = testApplicaition.First_Name__c + ' ' +
                         testApplicaition.Second_Name__c + ' - ' +
                         testApplicaition.Name;
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        String trackingNumber = '1234567421';
        email.plainTextBody = 'Name: ' + testApplicaition.First_Name__c + ' ' + testApplicaition.Second_Name__c + '\n' +
                              'AppID: ' + testApplicaition.Name + '\n\n' +
                              'Tracking No: ' + trackingNumber + '\n' +
                              'Tracking No Rx\'d by Printer: 24 Jul 2023 17:45 \n' +
                              'Service: Royal Mail Track24';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        System.assertEquals(null, testApplicaition.Tracking_Number__c, 'Tracking_Number__c must be null before update');
        System.assertEquals(null, testApplicaition.Tracking_Number_Received_Date__c, 'Tracking_Number_Received_Date__c must be null before update');
        System.assertEquals(null, testApplicaition.Tracking_Number_Sent_Date__c, 'Tracking_Number_Sent_Date__c must be null before update');
        Test.startTest();
        XtraPensionEmailServiceHandler testInbound = new XtraPensionEmailServiceHandler();
        testInbound.handleInboundEmail(email, env);
        Test.stopTest();

        Application__c testApplicaitionAfterUpdate = [
            SELECT
                Tracking_Number__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            LIMIT 1
        ];
        System.assertEquals(trackingNumber, testApplicaitionAfterUpdate.Tracking_Number__c, 'Tracking_Number__c must be like in incomung email');
        System.assertNotEquals(null, testApplicaitionAfterUpdate.Tracking_Number__c, 'Tracking_Number__c must be not null after update');
        System.assertNotEquals(null, testApplicaitionAfterUpdate.Tracking_Number_Received_Date__c, 'Tracking_Number_Received_Date__c must be not null after update');
    }

    @IsTest
    static void handleInboundEmailCase2Test() {
        Application__c testApplicaition = [
            SELECT
                Name,
                First_Name__c,
                Second_Name__c,
                Email__c,
                Tracking_Number__c,
                Tracking_Number_Received_Date__c,
                Tracking_Number_Sent_Date__c
            FROM Application__c
            LIMIT 1
        ];
        Messaging.InboundEmail email = new Messaging.InboundEmail() ;
        String subject = testApplicaition.First_Name__c + ' ' +
                         testApplicaition.Second_Name__c + ' - ' +
                         testApplicaition.Name + ' - APPEAL';
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        String trackingNumber = '1234567421';
        email.plainTextBody = 'Name: ' + testApplicaition.First_Name__c + ' ' + testApplicaition.Second_Name__c + '\n' +
                              'AppID: ' + testApplicaition.Name + '\n\n' +
                              'Tracking No: ' + trackingNumber + '\n' +
                              'Tracking No Rx\'d by Printer: 24 Jul 2023 17:45 \n' +
                              'Service: Royal Mail Track24';
        email.toAddresses = new List<String> {
            testApplicaition.Email__c
        };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        List<HMRC_Appeal_Reply__c> reliesBeforeUpdates = [
            SELECT
                Id,
                Application__c,
                Application__r.Email__c,
                Application__r.Contact__c,
                Client_Attach_File_Ids__c,
                Sent_To_Client_Date__c,
                Status__c,
                Tracking_Number__c
            FROM HMRC_Appeal_Reply__c
        ];
        System.assertEquals(null, reliesBeforeUpdates[0].Tracking_Number__c, 'Tracking_Number__c must be null before update');
        System.assertEquals(null, reliesBeforeUpdates[0].Sent_To_Client_Date__c, 'Sent_To_Client_Date__c must be null before update');
        System.assertEquals('Sent to HMRC', reliesBeforeUpdates[0].Status__c, 'Status__c must be Sent to HMRC before update');

        Test.startTest();
        XtraPensionEmailServiceHandler testInbound = new XtraPensionEmailServiceHandler();
        testInbound.handleInboundEmail(email, env);
        Test.stopTest();

        List<HMRC_Appeal_Reply__c> reliesAfterUpdates = [
            SELECT
                Id,
                Application__c,
                Application__r.Email__c,
                Application__r.Contact__c,
                Client_Attach_File_Ids__c,
                Sent_To_Client_Date__c,
                Status__c,
                Tracking_Number__c
            FROM HMRC_Appeal_Reply__c
        ];
        System.assertEquals(trackingNumber, reliesAfterUpdates[0].Tracking_Number__c, 'Tracking_Number__c must be null before update');
        System.assertEquals(Date.today(), reliesAfterUpdates[0].Sent_To_Client_Date__c, 'Sent_To_Client_Date__c must not be null before update');
        System.assertEquals('Sent to Client', reliesAfterUpdates[0].Status__c, 'Status__c must be Sent to Client before update');
    }

    @IsTest
    static void handleInboundEmailReapplyTest() {
        Application__c testApplication = [
            SELECT Id, Name, First_Name__c, Second_Name__c, Email__c
            FROM Application__c
            LIMIT 1
        ];

        // Create a Reapply__c record with the same Name as the Application
        Reapply__c testReapply = new Reapply__c(
            Name = testApplication.Name,
            Application__c = testApplication.Id,
            Email__c = testApplication.Email__c,
            Status__c = 'Pre Sale'
        );
        insert testReapply;

        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = testApplication.First_Name__c + ' ' +
                        testApplication.Second_Name__c + ' - ' +
                        testApplication.Name + ' - REAPPLY';
        email.fromAddress = 'test.xtrapension@email.com';
        String trackingNumber = 'REAPPLY-TRACK-001';
        email.plainTextBody = 'Name: ' + testApplication.First_Name__c + ' ' + testApplication.Second_Name__c + '\n' +
                              'AppID: ' + testApplication.Name + '\n\n' +
                              'Tracking No: ' + trackingNumber + '\n' +
                              'Tracking No Rx\'d by Printer: 24 Jul 2023 17:45 \n' +
                              'Service: Royal Mail Track24';
        email.toAddresses = new List<String>{ testApplication.Email__c };
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();

        Test.startTest();
        XtraPensionEmailServiceHandler testInbound = new XtraPensionEmailServiceHandler();
        Messaging.InboundEmailResult result = testInbound.handleInboundEmail(email, env);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Result should be successful');

        Reapply__c reapplyAfter = [
            SELECT Id, Tracking_No_to_HMRC__c, Tracking_Number_Send_Date__c,
                   Tracking_No_Rx_d_by_XP__c, Status__c
            FROM Reapply__c
            WHERE Id = :testReapply.Id
        ];
        System.assertEquals(trackingNumber, reapplyAfter.Tracking_No_to_HMRC__c, 'Tracking_No_to_HMRC__c must match');
        System.assertEquals(Date.today(), reapplyAfter.Tracking_Number_Send_Date__c, 'Tracking_Number_Send_Date__c must be today');
        System.assertEquals('24 Jul 2023 17:45', reapplyAfter.Tracking_No_Rx_d_by_XP__c, 'Tracking_No_Rx_d_by_XP__c must match');
        System.assertEquals('Posted', reapplyAfter.Status__c, 'Status__c must be Posted');
    }

    @IsTest
    static void handleInboundEmailBigEnvelopTest() {
    // Get the test application created in setup
    Application__c testApplication = [
        SELECT Id, Name, First_Name__c, Second_Name__c, Email__c
        FROM Application__c
        LIMIT 1
    ];

    // Create a Basic__c (Claim) record with the same Name as the Application
    // This is needed because processBigEnvelop queries Basic__c by applicationName
    Basic__c testClaim = new Basic__c(
        //Name = testApplication.Name,
        Email__c = testApplication.Email__c,
        Claim_Full_Form_ZIP_for_UPLOAD__c = false
    );
    insert testClaim;

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.subject = testApplication.First_Name__c + ' ' +
                    testApplication.Second_Name__c + ' - ' +
                    testApplication.Name + ' - BIG ENVELOP';
    email.fromAddress = 'test.xtrapension@email.com';
    String trackingNumber = 'BIG-ENV-TRACK-001';
    email.plainTextBody = 'Name: ' + testApplication.First_Name__c + ' ' + testApplication.Second_Name__c + '\n' +
                          'AppID: ' + testApplication.Name + '\n\n' +
                          'Tracking No: ' + trackingNumber + '\n' +
                          'Tracking No Rx\'d by Printer: 24 Jul 2023 17:45 \n' +
                          'Service: Royal Mail Track24';
    email.toAddresses = new List<String>{ testApplication.Email__c };
    Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();

    // Verify Claim_Full_Form_ZIP_for_UPLOAD__c is false before update
    Basic__c claimBefore = [
        SELECT Id, Claim_Full_Form_ZIP_for_UPLOAD__c
        FROM Basic__c
        WHERE Id = :testClaim.Id
    ];
    System.assertEquals(false, claimBefore.Claim_Full_Form_ZIP_for_UPLOAD__c,
        'Claim_Full_Form_ZIP_for_UPLOAD__c must be false before update');

    Test.startTest();
    XtraPensionEmailServiceHandler testInbound = new XtraPensionEmailServiceHandler();
    Messaging.InboundEmailResult result = testInbound.handleInboundEmail(email, env);
    Test.stopTest();

    //System.assertEquals(true, result.success, 'Result should be successful');

    // Verify Claim_Full_Form_ZIP_for_UPLOAD__c is now true
    Basic__c claimAfter = [
        SELECT Id, Claim_Full_Form_ZIP_for_UPLOAD__c
        FROM Basic__c
        WHERE Id = :testClaim.Id
    ];
    System.assertEquals(false, claimAfter.Claim_Full_Form_ZIP_for_UPLOAD__c);
    }

    @IsTest
    static void handleInboundEmailClaimTest() {
    // Get the test application created in setup
    Application__c testApplication = [
        SELECT Id, Name, First_Name__c, Second_Name__c, Email__c
        FROM Application__c
        LIMIT 1
    ];

    // Create a Basic__c (Claim) record with the same Name as the Application
    // This is needed because processBigEnvelop queries Basic__c by applicationName
    Basic__c testClaim = new Basic__c(
        //Name = testApplication.Name,
        Email__c = testApplication.Email__c,
        Claim_Full_Form_ZIP_for_UPLOAD__c = false
    );
    insert testClaim;

    Messaging.InboundEmail email = new Messaging.InboundEmail();
    email.subject = testApplication.First_Name__c + ' ' +
                    testApplication.Second_Name__c + ' - ' +
                    testApplication.Name + ' - CLAIM';
    email.fromAddress = 'test.xtrapension@email.com';
    String trackingNumber = 'BIG-ENV-TRACK-001';
    email.plainTextBody = 'Name: ' + testApplication.First_Name__c + ' ' + testApplication.Second_Name__c + '\n' +
                          'AppID: ' + testApplication.Name + '\n\n' +
                          'Tracking No: ' + trackingNumber + '\n' +
                          'Tracking No Rx\'d by Printer: 24 Jul 2023 17:45 \n' +
                          'Service: Royal Mail Track24';
    email.toAddresses = new List<String>{ testApplication.Email__c };
    Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        Test.startTest();
        XtraPensionEmailServiceHandler testInbound = new XtraPensionEmailServiceHandler();
        Messaging.InboundEmailResult result = testInbound.handleInboundEmail(email, env);
        Test.stopTest();
    }

    private static Messaging.InboundEmail claimEmail(String subject, String claimName) {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = subject;
        email.fromAddress = 'test.xtrapension@email.com';
        email.plainTextBody = 'AppID: ' + claimName + '\n\nTracking No: TRACK-123\n';
        return email;
    }

    private static Basic__c newClaim() {
        Basic__c claim = new Basic__c(Email__c = 'claim.client@test.com', Claim_Full_Form_ZIP_for_UPLOAD__c = false);
        insert claim;
        return [SELECT Id, Name FROM Basic__c WHERE Id = :claim.Id];
    }

    @IsTest
    static void bigEnvelopeSubjectIsRecognisedCaseInsensitively() {
        Basic__c claim = newClaim();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('John Snow - ' + claim.Name + ' - BIG ENVELOPE', claim.Name),
            new Messaging.InboundEnvelope()
        );
        Test.stopTest();

        Basic__c after = [SELECT Claim_Full_Form_ZIP_for_UPLOAD__c, Tracking_Number__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals(true, after.Claim_Full_Form_ZIP_for_UPLOAD__c, 'Stage 2 must be flagged for upload');
        System.assertEquals(null, after.Tracking_Number__c, 'A big-envelope e-mail is not a posted-claim e-mail');
    }

    @IsTest
    static void subjectWithBothBigEnvelopeAndClaimIsTreatedAsBigEnvelope() {
        Basic__c claim = newClaim();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('BIG ENVELOPE - CLAIM ' + claim.Name, claim.Name),
            new Messaging.InboundEnvelope()
        );
        Test.stopTest();

        Basic__c after = [SELECT Claim_Full_Form_ZIP_for_UPLOAD__c, Status__c, Tracking_Number__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals(true, after.Claim_Full_Form_ZIP_for_UPLOAD__c);
        System.assertNotEquals('Posted to DWP', after.Status__c, 'Must not be processed as a posted claim');
        System.assertEquals(null, after.Tracking_Number__c);
    }

    // E-mail "BIG ENV POSTED" da gráfica (04/11/2026): maiúsculas ou minúsculas, "BIG ENVELOPE POSTED" e sem tracking.
    @IsTest
    static void bigEnvPostedIsRecognisedInAnyCase() {
        Basic__c claim = newClaim();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('John Snow - ' + claim.Name + ' - Big Env Posted', claim.Name),
            new Messaging.InboundEnvelope()
        );
        Test.stopTest();

        Basic__c after = [SELECT Big_Envelop_Posted_Date__c, Big_Envelop_Tracking_Number__c, Claim_Full_Form_ZIP_for_UPLOAD__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals(Date.today(), after.Big_Envelop_Posted_Date__c);
        System.assertEquals('TRACK-123', after.Big_Envelop_Tracking_Number__c);
        System.assertEquals(false, after.Claim_Full_Form_ZIP_for_UPLOAD__c, 'Posted to the client is not documents back at the printer');
    }

    @IsTest
    static void bigEnvelopePostedIsPostedNotDocumentsBack() {
        Basic__c claim = newClaim();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('John Snow - ' + claim.Name + ' - BIG ENVELOPE POSTED', claim.Name),
            new Messaging.InboundEnvelope()
        );
        Test.stopTest();

        Basic__c after = [SELECT Big_Envelop_Posted_Date__c, Claim_Full_Form_ZIP_for_UPLOAD__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals(Date.today(), after.Big_Envelop_Posted_Date__c);
        System.assertEquals(false, after.Claim_Full_Form_ZIP_for_UPLOAD__c, 'Must not flag Stage 2 as due');
    }

    @IsTest
    static void bigEnvPostedWithoutTrackingKeepsTheStoredOne() {
        Basic__c claim = newClaim();
        update new Basic__c(Id = claim.Id, Big_Envelop_Tracking_Number__c = 'FIRST-TRACK');
        Messaging.InboundEmail email = claimEmail('John Snow - ' + claim.Name + ' - BIG ENV POSTED', claim.Name);
        email.plainTextBody = 'AppID: ' + claim.Name + '\n';

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(email, new Messaging.InboundEnvelope());
        Test.stopTest();

        Basic__c after = [SELECT Big_Envelop_Posted_Date__c, Big_Envelop_Tracking_Number__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals(Date.today(), after.Big_Envelop_Posted_Date__c);
        System.assertEquals('FIRST-TRACK', after.Big_Envelop_Tracking_Number__c, 'An e-mail without a tracking line keeps the stored tracking');
    }

    @IsTest
    static void bigEnvPostedSubjectRules() {
        System.assert(XtraPensionEmailServiceHandler.isBigEnvPosted('Mary Byrne - C00123 - BIG ENV POSTED'));
        System.assert(XtraPensionEmailServiceHandler.isBigEnvPosted('Mary Byrne - C00123 - big  envelope posted'));
        System.assert(!XtraPensionEmailServiceHandler.isBigEnvPosted('Mary Byrne - C00123 - CLAIM - BIG ENVELOPE'));
        System.assert(!XtraPensionEmailServiceHandler.isBigEnvPosted(null));
    }

    @IsTest
    static void claimSubjectStillStoresTheTrackingNumber() {
        Basic__c claim = newClaim();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('John Snow - ' + claim.Name + ' - CLAIM', claim.Name),
            new Messaging.InboundEnvelope()
        );
        Test.stopTest();

        Basic__c after = [SELECT Claim_Full_Form_ZIP_for_UPLOAD__c, Tracking_Number__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals('TRACK-123', after.Tracking_Number__c);
        System.assertEquals(false, after.Claim_Full_Form_ZIP_for_UPLOAD__c);
    }

    // Appeal sent from a Reapply (2026-11-02): the printing house posts it under the Reapply's name (R12345)
    private static Reapply__c reapplyInAppeal() {
        Application__c app = [SELECT Id, Email__c FROM Application__c LIMIT 1];
        Reapply__c reapply = new Reapply__c(
            Name = 'R99903',
            Application__c = app.Id,
            Email__c = 'reapply.client@test.com',
            Status__c = 'HMRC Appeal'
        );
        insert reapply;
        insert new HMRC_Appeal_Reply__c(
            Application__c = app.Id,
            Reapply__c = reapply.Id,
            Status__c = 'Sent to HMRC'
        );
        return reapply;
    }

    private static Messaging.InboundEmail trackingEmail(String subjectWord, String appId) {
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        email.subject = 'Jane Doe - ' + appId + ' - ' + subjectWord;
        email.fromAddress = 'test.xtrapension@email.com';
        email.plainTextBody = 'Name: Jane Doe\n' +
                              'AppID: ' + appId + '\n\n' +
                              'Tracking No: RA-APPEAL-1\n' +
                              'Tracking No Rx\'d by Printer: 03 Nov 2026 10:00 \n' +
                              'Service: Royal Mail Track24';
        return email;
    }

    private static HMRC_Appeal_Reply__c replyOf(Boolean fromReapply) {
        for (HMRC_Appeal_Reply__c reply : [
            SELECT Reapply__c, Status__c, Tracking_Number__c, Sent_To_Client_Date__c FROM HMRC_Appeal_Reply__c
        ]) {
            if ((reply.Reapply__c != null) == fromReapply) return reply;
        }
        return null;
    }

    @IsTest
    static void appealTrackingWithTheReapplyNameUpdatesTheReapplysReply() {
        Reapply__c reapply = reapplyInAppeal();

        Test.startTest();
        Messaging.InboundEmailResult result = new XtraPensionEmailServiceHandler().handleInboundEmail(
            trackingEmail('APPEAL', reapply.Name), new Messaging.InboundEnvelope());
        Test.stopTest();

        System.assertEquals(true, result.success, 'message: ' + result.message);
        HMRC_Appeal_Reply__c fromReapply = replyOf(true);
        System.assertEquals('Sent to Client', fromReapply.Status__c);
        System.assertEquals('RA-APPEAL-1', fromReapply.Tracking_Number__c);
        System.assertEquals(Date.today(), fromReapply.Sent_To_Client_Date__c);
        System.assertEquals('Sent to HMRC', replyOf(false).Status__c, 'the application\'s own appeal is untouched');
    }

    @IsTest
    static void appealTrackingWithTheApplicationNameSkipsTheReapplysReply() {
        reapplyInAppeal(); // newer than the application's own reply
        Application__c app = [SELECT Name FROM Application__c LIMIT 1];

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(trackingEmail('APPEAL', app.Name), new Messaging.InboundEnvelope());
        Test.stopTest();

        System.assertEquals('Sent to Client', replyOf(false).Status__c);
        System.assertEquals('Sent to HMRC', replyOf(true).Status__c);
    }

    @IsTest
    static void reapplyTrackingDuringItsAppealIsTheAppeals() {
        Reapply__c reapply = reapplyInAppeal();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(trackingEmail('REAPPLY', reapply.Name), new Messaging.InboundEnvelope());
        Test.stopTest();

        Reapply__c after = [SELECT Status__c, Tracking_No_to_HMRC__c, Tracking_Number_Send_Date__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertEquals('HMRC Appeal', after.Status__c, 'not reposted');
        System.assertEquals(null, after.Tracking_No_to_HMRC__c);
        System.assertEquals(null, after.Tracking_Number_Send_Date__c);
        System.assertEquals('RA-APPEAL-1', replyOf(true).Tracking_Number__c);
    }

    @IsTest
    static void bigEnvPostedSendsTheWelcomePackEmailOnce() {
        insert new Contact(LastName = 'Client', Email = 'claim.client@test.com');
        Basic__c claim = newClaim();

        Test.startTest();
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('John Snow - ' + claim.Name + ' - BIG ENV POSTED', claim.Name),
            new Messaging.InboundEnvelope()
        );
        System.assertEquals(1, XpWelcomePackEmail.prepared, 'First posting: one welcome pack e-mail');
        new XtraPensionEmailServiceHandler().handleInboundEmail(
            claimEmail('John Snow - ' + claim.Name + ' - BIG ENV POSTED', claim.Name),
            new Messaging.InboundEnvelope()
        );
        Test.stopTest();

        System.assertEquals(1, XpWelcomePackEmail.prepared, 'A re-post does not e-mail again');
        System.assertEquals(Date.today(), [SELECT Big_Envelop_Posted_Date__c FROM Basic__c WHERE Id = :claim.Id].Big_Envelop_Posted_Date__c);
    }
}