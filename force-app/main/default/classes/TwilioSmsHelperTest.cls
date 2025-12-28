@isTest
public class TwilioSmsHelperTest {
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
        testData.Twilio_Endpoint__c = 'https://test.com/';
        insert testData;
    }

    @IsTest
    static void sendMesageTest(){
        List<Application__c> testApps = [
            SELECT
                Id,
                Contact__c
            FROM Application__c
        ];
        TwilioSmsHelper.SMSWrapper wrapper = new TwilioSmsHelper.SMSWrapper();
        wrapper.body = 'Test message';
        wrapper.to = '+123456123';
        wrapper.fromData = 'XtraPension';
        Test.setMock(HttpCalloutMock.class, new TwilioSuccessMessageMock());
        List<TwilioSF__Message__c> twilioMessagesBeforeSend = [
            SELECT Id
            FROM TwilioSF__Message__c
        ];
        Assert.areEqual(0, twilioMessagesBeforeSend.size());
        Test.startTest();
        TwilioSmsHelper helper  = new TwilioSmsHelper(testApps[0], wrapper);
        helper.sendMessage();
        Test.stopTest();
        List<TwilioSF__Message__c> twilioMessagesAfterSend = [
            SELECT Id
            FROM TwilioSF__Message__c
        ];
        Assert.areEqual(1, twilioMessagesAfterSend.size());
    }

    private class TwilioSuccessMessageMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{' +
                    '"sid":"123456",' +
                    '"status":"sent",' +
                    '"direction":"test"' +
                '}'
            );
            res.setStatusCode(201);
            return res;
        }
    }
}