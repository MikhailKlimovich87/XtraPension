@isTest
public class FailPaymentPageredirectorTest {
    @TestSetup
    static void makeData(){
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
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        TestDataFactory.createPayment(testApplication.Id, order.Id, true);
    }
    @IsTest
    static void doRedirectActionTest() {
        List<Payment__c> testPayments = [
            SELECT
                Id,
                Amount__c,
                Status__c
            FROM Payment__c
        ];
        Payment__c payment = testPayments[0];
        Test.startTest();
        PageReference pageRef = Page.PhoneFailPayment;
        pageRef.getParameters().put('id', String.valueOf(payment.Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(payment);
        FailPaymentPageredirector testRedirector = new FailPaymentPageredirector(stdController);
        testRedirector.doRedirectAction();
        Test.stopTest();
        String nextPage = testRedirector.doRedirectAction().getUrl();
        System.assertNotEquals(null, nextPage);
    }
}