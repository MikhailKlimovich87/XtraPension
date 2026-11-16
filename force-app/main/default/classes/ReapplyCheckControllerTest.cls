@isTest
public class ReapplyCheckControllerTest {
    @testSetup
    static void setupTestData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact contact = [SELECT Id FROM Contact WHERE AccountId = :account.Id LIMIT 1];
        Application__c app = TestDataFactory.createApplication(contact.Id, true);
        app = [SELECT Id, Name FROM Application__c WHERE Id = :app.Id];
        Reapply__c reapply = TestDataFactory.createReapplyRecord(app.Id, false);
        reapply.Name = 'R' + app.Name.substring(1);
        reapply.Status__c = 'Posted';
        insert reapply;
    }

    private static ReapplyCheckController.CheckRequest request(String appName) {
        ReapplyCheckController.CheckRequest req = new ReapplyCheckController.CheckRequest();
        req.appName = appName;
        req.notReceived = false;
        req.c2 = false;
        req.c3 = true;
        req.workItem = false;
        req.badNINO = false;
        req.badInfo = false;
        req.processing = false;
        req.dwp = false;
        req.X64_8 = false;
        req.reject = false;
        req.dwpCall = false;
        req.sentTo = 'Both';
        req.sentDate = String.valueOf(Date.today());
        req.notes = 'Testing insert';
        req.pdfLink = 'https://drive.google.com/test';
        req.requestedCopy = 'Yes';
        return req;
    }

    @isTest
    static void testGetReapplyNames() {
        Test.startTest();
        List<Reapply__c> reapplies = ReapplyCheckController.getReapplyNames();
        Test.stopTest();
        System.assertEquals(1, reapplies.size(), 'Posted reapply should be listed');
    }

    @isTest
    static void testCreateReapplyCheckRecords() {
        Reapply__c reapply = [SELECT Id, Name, Application__c FROM Reapply__c LIMIT 1];
        ReapplyCheckController.CheckRequestWrapper wrapper = new ReapplyCheckController.CheckRequestWrapper();
        wrapper.checkAgent = 'Daniel';
        // agents type the number without the letter, same as the normal checks
        wrapper.checkReplies = new List<ReapplyCheckController.CheckRequest>{
            request(reapply.Name.replaceFirst('^R0*', ''))
        };

        Test.startTest();
        List<Reapply_Check__c> result = ReapplyCheckController.createReapplyCheckRecords(wrapper);
        Test.stopTest();

        System.assertEquals(1, result.size());
        Reapply_Check__c check = [
            SELECT Reapply__c, Application__c, Check_Agents__c, C3__c, Have_you_requested_a_copy__c, Check_Date__c
            FROM Reapply_Check__c
            WHERE Id = :result[0].Id
        ];
        System.assertEquals(reapply.Id, check.Reapply__c);
        System.assertEquals(reapply.Application__c, check.Application__c);
        System.assertEquals('Daniel', check.Check_Agents__c);
        System.assertEquals(true, check.C3__c);
        System.assertEquals('Yes', check.Have_you_requested_a_copy__c);
        System.assertEquals(Date.today(), check.Check_Date__c);
    }

    @isTest
    static void testUnknownReapply() {
        ReapplyCheckController.CheckRequestWrapper wrapper = new ReapplyCheckController.CheckRequestWrapper();
        wrapper.checkAgent = 'Vince';
        wrapper.checkReplies = new List<ReapplyCheckController.CheckRequest>{ request('99999999') };
        Boolean failed = false;
        try {
            ReapplyCheckController.createReapplyCheckRecords(wrapper);
        } catch (AuraHandledException e) {
            failed = true;
        }
        System.assert(failed, 'Unknown reapply must fail');
        System.assertEquals(null, ReapplyCheckController.createReapplyCheckRecords(null));
    }

    @isTest
    static void testNumberKey() {
        System.assertEquals('8694', ReapplyCheckController.numberKey('R08694'));
        System.assertEquals('8694', ReapplyCheckController.numberKey('A08694'));
        System.assertEquals('8694', ReapplyCheckController.numberKey('08694'));
        System.assertEquals('13845', ReapplyCheckController.numberKey(' r13845 '));
    }

    @isTest
    static void testAddRequestCheckData() {
        Reapply__c reapply = [SELECT Id FROM Reapply__c LIMIT 1];
        Test.startTest();
        ReapplyCheckController.addRequestCheckData(reapply.Id);
        ReapplyCheckController.addRequestCheckData(null);
        Test.stopTest();
        reapply = [SELECT Request_Check_Date__c FROM Reapply__c WHERE Id = :reapply.Id];
        System.assertEquals(Date.today(), reapply.Request_Check_Date__c);
    }

    static void email(Id relatedTo, String subject, Integer daysAgo) {
        insert new EmailMessage(RelatedToId = relatedTo, FromAddress = 'clients@xtrapension.com', ToAddress = 'client@example.com',
            Subject = subject, TextBody = 'x', Status = '3', MessageDate = Datetime.now().addDays(-daysAgo));
    }

    @isTest
    static void testGetLetterRequests() {
        Reapply__c reapply = [SELECT Id, Name FROM Reapply__c LIMIT 1];
        System.assert(ReapplyCheckController.getLetterRequests().isEmpty());
        email(reapply.Id, reapply.Name + ' - ' + ReapplyCheckController.LETTER_NO_UPDATE, 3);
        email(reapply.Id, reapply.Name + ' - ' + ReapplyCheckController.LETTER_APPROVED + ': has their letter reached you?', 1);
        email(reapply.Id, reapply.Name + ' - Your REAPPLY is ready to sign (last step before HMRC)', 0);
        List<ReapplyCheckController.LetterRequest> requests = ReapplyCheckController.getLetterRequests();
        System.assertEquals(1, requests.size(), 'one per Reapply');
        System.assertEquals(reapply.Id, requests[0].reapplyId);
        System.assertEquals('approved', requests[0].version, 'the latest one');
    }
}