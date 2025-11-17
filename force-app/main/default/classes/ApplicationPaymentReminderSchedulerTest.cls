@isTest
public class ApplicationPaymentReminderSchedulerTest {
    @TestSetup
    static void makeData() {
        List<Product2> testProducts = TestDataFactory.createProductsWithPrices();
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
        ContentVersion testContentVersion = TestDataFactory.createTestContentVersion(true);
        Id contDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :testContentVersion.Id][0].ContentDocumentId;
        ContentDocumentLink conDocLink = new ContentDocumentLink();
        conDocLink.LinkedEntityId = testApplication.Id;
        conDocLink.ContentDocumentId = contDocId;
        insert conDocLink;
        Agent__c testAgent = TestDataFactory.createAgent(true);
        testApplication.Agent__c = testAgent.Id;
        update testApplication;
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c testPayment = TestDataFactory.createPayment(testApplication.Id, order.Id, false);
        for (Product2 product : testProducts) {
            if (product.Name == 'Application') {
                testPayment.Product__c = product.Id;
                break;
            }
        }
        testPayment.Payment_Date__c = Date.today().addDays(1);
        insert testPayment;
        XtraPension_Data__c testData = TestDataFactory.createXtraPensionDataCustomSetting(false);
        testData.Twilio_Account__c = '123456789456123';
        testData.Twilio_Token__c = '9874512457';
        insert testData;
    }

    @IsTest
    static void executeBatchTest(){
        List<Payment__c> testPaymentsBeforeUpdate = [
            SELECT
                Id,
                Application_Reminder_Sent_Date__c
            FROM Payment__c
        ];
        Assert.isNull(testPaymentsBeforeUpdate[0].Application_Reminder_Sent_Date__c);
        Test.startTest();
        ApplicationPaymentReminderSchedulerBatch testBatch = new ApplicationPaymentReminderSchedulerBatch();
        Database.executeBatch(testBatch);
        Test.stopTest();
        List<Payment__c> testPaymentsAfterUpdate = [
            SELECT
                Id,
                Application_Reminder_Sent_Date__c
            FROM Payment__c
        ];
        Assert.isNotNull(testPaymentsAfterUpdate[0].Application_Reminder_Sent_Date__c);
        Assert.areEqual(Date.today(), testPaymentsAfterUpdate[0].Application_Reminder_Sent_Date__c);
    }

    @IsTest
    static void executeScheduleTest() {
        String cronEspression = '0 0 23 * * ?';
        Test.startTest();
		Id jobId = System.schedule('Test send reminder notification', cronEspression, new ApplicationPaymentReminderScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Job Id must be not null');
        CronTrigger ct = [
            SELECT
                Id,
                CronExpression,
                TimesTriggered,
                NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(cronEspression, ct.CronExpression);
    }
}