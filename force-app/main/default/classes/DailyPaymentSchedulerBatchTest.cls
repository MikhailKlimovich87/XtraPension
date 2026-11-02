@IsTest
private class DailyPaymentSchedulerBatchTest {
    @TestSetup
    static void setup() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        Contact contact = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Application__c application = TestDataFactory.createApplication(contact.Id, false);
        application.Status__c = 'Posted';
        insert application;

        TestDataFactory.createOrder(application.Id, account.Id, true);
    }

    @IsTest
    static void processesScheduledPaymentDueToday() {
        Payment__c dueToday = createPayment('Schedule');
        Payment__c dueTomorrow = createPayment('Schedule');
        dueToday.Payment_Date__c = Date.today();
        dueTomorrow.Payment_Date__c = Date.today().addDays(1);
        update new List<Payment__c>{ dueToday, dueTomorrow };

        runBatch();

        assertStatus(dueToday.Id, 'Paid');
        assertStatus(dueTomorrow.Id, 'Schedule');
        Payment__c chargedPayment = [
            SELECT Payment_Intent__c, Source__c, Card_Data__c
            FROM Payment__c
            WHERE Id = :dueToday.Id
        ];
        System.assertEquals('pi_3hjNHGnBjgkjhg1FD', chargedPayment.Payment_Intent__c);
        System.assertEquals('ch_123456789', chargedPayment.Source__c);
        System.assertEquals('visa - 4242', chargedPayment.Card_Data__c);
    }

    @IsTest
    static void processesFirstRetryDueToday() {
        Payment__c payment = createPayment('Fail');
        payment.Repeated_Payment_Date_1__c = Date.today();
        update payment;

        runBatch();

        assertStatus(payment.Id, 'Paid');
    }

    @IsTest
    static void processesSecondRetryDueToday() {
        Payment__c payment = createPayment('Fail');
        payment.Repeated_Payment_Date_2__c = Date.today();
        update payment;

        runBatch();

        assertStatus(payment.Id, 'Paid');
    }

    @IsTest
    static void processesThirdRetryDueToday() {
        Payment__c payment = createPayment('Fail');
        payment.Repeated_Payment_Date_3__c = Date.today();
        update payment;

        runBatch();

        assertStatus(payment.Id, 'Paid');
    }

    @IsTest
    static void doesNotProcessFailedPaymentWithoutRetryDueToday() {
        Payment__c payment = createPayment('Fail');

        runBatch();

        assertStatus(payment.Id, 'Fail');
    }

    private static Payment__c createPayment(String status) {
        Application__c application = [
            SELECT Id
            FROM Application__c
            LIMIT 1
        ];
        Order order = [
            SELECT Id
            FROM Order
            WHERE Application__c = :application.Id
            LIMIT 1
        ];
        Product2 product = [
            SELECT Id
            FROM Product2
            WHERE Name = 'Application'
            LIMIT 1
        ];
        Payment__c payment = TestDataFactory.createPayment(application.Id, order.Id, false);
        payment.Product__c = product.Id;
        payment.Status__c = status;
        insert payment;
        return payment;
    }

    private static void runBatch() {
        Test.setMock(HttpCalloutMock.class, new PaymentServiceMock());
        Test.startTest();
        Database.executeBatch(new DailyPaymentSchedulerBatch(), 1);
        Test.stopTest();
    }

    private static void assertStatus(Id paymentId, String expectedStatus) {
        Payment__c payment = [
            SELECT Status__c
            FROM Payment__c
            WHERE Id = :paymentId
        ];
        System.assertEquals(expectedStatus, payment.Status__c);
    }
}