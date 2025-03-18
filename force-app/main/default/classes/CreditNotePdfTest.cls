@isTest
public class CreditNotePdfTest {
    @TestSetup
    static void makeData() {
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
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', null, true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c testPayment = TestDataFactory.createPayment(testApplication.Id, order.Id, true);
        TestDataFactory.createCreditNotes(testPayment.Id, true);
    }

    @isTest
    static void generateCreditNotePdfTest() {
        List<Payment__c> testPayments = [
            SELECT
                Id,
                Amount__c
            FROM Payment__c
        ];
        Payment__c payment = testPayments[0];
        Test.startTest();
        CreditNoteHelper.generateCreditNotePdf(payment.Id);
        Test.stopTest();
        List<Credit_Note__c> creditNotes = [
            SELECT
                Amount__c,
                Refund_Method__c,
                Payment__c
            FROM Credit_Note__c
            WHERE Payment__c = :testPayments[0].Id
        ];
        System.assertNotEquals(0, creditNotes.size());
        Credit_Note__c testCreditNote = creditNotes[0];
        System.assertEquals(payment.Id, testCreditNote.Payment__c);
        System.assertEquals(payment.Amount__c, testCreditNote.Amount__c);
    }

    @IsTest
    static void pdfActionTest() {
        List<Payment__c> testPayments = [
            SELECT
                Id,
                Amount__c
            FROM Payment__c
        ];
        Payment__c payment = testPayments[0];
        Test.startTest();
        PageReference pageRef = Page.CreditNote;
        pageRef.getParameters().put('id', String.valueOf(testPayments[0].Id));
        Test.setCurrentPage(pageRef);
        ApexPages.StandardController stdController = new ApexPages.StandardController(testPayments[0]);
        CreditNotePdf testCreditNotes = new CreditNotePdf(stdController);
        Test.stopTest();
        List<Credit_Note__c> creditNotes = [
            SELECT
                Amount__c,
                Refund_Method__c,
                Payment__c
            FROM Credit_Note__c
            WHERE Payment__c = :testPayments[0].Id
        ];
        System.assertNotEquals(0, creditNotes.size());
        Credit_Note__c testNote = creditNotes[0];
        System.assertEquals(payment.Id, testNote.Payment__c);
        System.assertEquals(payment.Amount__c, testNote.Amount__c);
    }
}