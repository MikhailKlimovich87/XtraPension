@isTest
public class ApplicationPaymentAfter73HoursTest {

    @TestSetup static void makeData() {
        List<Product2> products = TestDataFactory.createProductsWithPrices();
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
        Application__c application =  TestDataFactory.createApplication(personContactId, true);
        Order order = TestDataFactory.createOrder(application.Id, account.Id, true);
        TestDataFactory.createRelatedPaymentToApplication(products, application, order.Id, true);
    }

    @IsTest static void createPaymentAfter73HoursCase1() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        List<Application__c> testApplications = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        ApplicationPaymentAfter73Hours.Request request =  new ApplicationPaymentAfter73Hours.Request();
        request.application = testApplications[0];
        List<ApplicationPaymentAfter73Hours.Request> requestDatas = new List<ApplicationPaymentAfter73Hours.Request>();
        requestDatas.add(request);
        Test.startTest();
            ApplicationPaymentAfter73Hours.createPaymentAfter73Hours(requestDatas);
        Test.stopTest();
    }

    @IsTest static void createPaymentAfter73HoursCase2() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        List<Application__c> testApplications = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        List<Payment__c> payments = [
            SELECT Id
            FROM Payment__c
            WHERE Application__c = :testApplications[0].Id
        ];
        delete payments;
        ApplicationPaymentAfter73Hours.Request request =  new ApplicationPaymentAfter73Hours.Request();
        request.application = testApplications[0];
        List<ApplicationPaymentAfter73Hours.Request> requestDatas = new List<ApplicationPaymentAfter73Hours.Request>();
        requestDatas.add(request);
        Test.startTest();
            ApplicationPaymentAfter73Hours.createPaymentAfter73Hours(requestDatas);
        Test.stopTest();
    }
}