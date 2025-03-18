@isTest
public class PaymentScheduleProductFlowHelperTest {
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
        Payment__c payment = TestDataFactory.createPayment(testApplication.Id, order.Id, false);
        Product2 testProduct = [
            SELECT Id
            FROM Product2
            LIMIT 1
        ];
        payment.Product__c = testProduct.Id;
        insert payment;
    }

    @IsTest
    static void paySchedulePaymentCase1() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        List<Application__c> applications = [
            SELECT
                Id
            FROM Application__c
        ];
        Payment__c testPayment = [
            SELECT
                Name,
                Product__r.Name,
                Customer_Id__c,
                Payment_Method__c,
                Amount__c,
                Application__r.Email__c
            FROM Payment__c
            WHERE Application__c = :applications[0].Id
            LIMIT 1
        ];
        List<PaymentScheduleProductFlowHelper.Request> incomingRequests = new List<PaymentScheduleProductFlowHelper.Request>();
        PaymentScheduleProductFlowHelper.Request request = new PaymentScheduleProductFlowHelper.Request();
        request.payment = new List<Payment__c>();
        request.payment.add(testPayment);
        incomingRequests.add(request);
        Test.startTest();
        List<PaymentScheduleProductFlowHelper.Response> responses = PaymentScheduleProductFlowHelper.paySchedulePayment(incomingRequests);
        Test.stopTest();
        System.assertNotEquals(null, responses, 'Response must be not null');
        System.assertEquals('Success', responses[0].result, 'Result must be Success');
    }

    @IsTest
    static void paySchedulePaymentCase2() {
        List<PaymentScheduleProductFlowHelper.Request> incomingRequests = new List<PaymentScheduleProductFlowHelper.Request>();
        PaymentScheduleProductFlowHelper.Request request = new PaymentScheduleProductFlowHelper.Request();
        request.payment = new List<Payment__c>();
        request.payment.add(new Payment__c());
        incomingRequests.add(request);
        Test.startTest();
        List<PaymentScheduleProductFlowHelper.Response> responses = PaymentScheduleProductFlowHelper.paySchedulePayment(incomingRequests);
        Test.stopTest();
        System.assertNotEquals(null, responses, 'Response must be not null');
        System.assertEquals('Error', responses[0].result, 'Result must be Success');

    }
}