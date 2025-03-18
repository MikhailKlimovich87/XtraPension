@isTest
public class ApplicationPaymentAfter72HoursTest {

    @TestSetup static void makeData(){
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

    @IsTest static void createPaymentAfter72HoursCase1() {
        Test.setMock(HttpCalloutMock.class, new GeneratePDFMock());
        List<Application__c> testApplications = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        ApplicationPaymentAfter72Hours.Request request =  new ApplicationPaymentAfter72Hours.Request();
        request.application = testApplications[0];
        List<ApplicationPaymentAfter72Hours.Request> requestDatas = new List<ApplicationPaymentAfter72Hours.Request>();
        requestDatas.add(request);
        Test.startTest();
            ApplicationPaymentAfter72Hours.createPaymentAfter72Hours(requestDatas);
        Test.stopTest();
    }

    @IsTest static void createPaymentAfter72HoursCase2() {
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
        ApplicationPaymentAfter72Hours.Request request =  new ApplicationPaymentAfter72Hours.Request();
        request.application = testApplications[0];
        List<ApplicationPaymentAfter72Hours.Request> requestDatas = new List<ApplicationPaymentAfter72Hours.Request>();
        requestDatas.add(request);
        Test.startTest();
            ApplicationPaymentAfter72Hours.createPaymentAfter72Hours(requestDatas);
        Test.stopTest();
    }
}