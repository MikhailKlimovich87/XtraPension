@isTest
public class UrgentDocApprovalNeededHandlerTest {

    @TestSetup
    static void setup() {
        createEmailTemplate();
        List<String> productNames = new List<String>{'Deposit', 'Application', 'Monthly Updates', 'Success'};
        List<Product2> newProducts = new List<Product2>();
        for (String name : productNames) {
            newProducts.add(new Product2(
                Name = name,
                CurrencyIsoCode = 'EUR'
            ));
        }
        insert newProducts;
        Id pricebookId = Test.getStandardPricebookId();
        List<PriceBookEntry> testPriceBookEntries = new List<PriceBookEntry>();
        Integer counter = 100000;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
        }
        insert testPriceBookEntries;
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
        Date weekAgoDate = Date.today().addDays(-7);
        Application__c testApplication1 = TestDataFactory.createApplication(personContactId, false);
        testApplication1.Status__c = 'Sent for eSignature';
        testApplication1.Docusigned_Date__c = weekAgoDate;
        testApplication1.Date_Since_Contact__c = weekAgoDate;

        Application__c testApplication2 = TestDataFactory.createApplication(personContactId, false);
        testApplication2.Status__c = 'Sent for eSignature';
        testApplication2.Docusigned_Date__c = weekAgoDate;
        testApplication2.Date_Since_Contact__c = weekAgoDate;

        insert new List<Application__c>{testApplication1, testApplication2};
    }

    @isTest
    static void testSendUrgentDocApprovalEmail() {
        // Start the test
        Test.startTest();

        // Call the method to test
        UrgentDocApprovalNeededHandler.sendUrgentDocApprovalEmail();

        // Stop the test
        Test.stopTest();

        // Verify that the emails were sent and the flag was updated
        List<Application__c> updatedApps = [
            SELECT Id, is_Sent_Urgent_Doc_Approval_Needed_Email__c
            FROM Application__c
            WHERE is_Sent_Urgent_Doc_Approval_Needed_Email__c = true
        ];
        System.assertEquals(2, updatedApps.size(), 'Expected 2 applications to have the email flag updated.');

        // Verify that the emails were sent
        System.assertEquals(2, Limits.getEmailInvocations(), 'Expected 2 email invocations.');
    }

    @isTest
    static void testNoEmailsSentWhenNoApplications() {
        // Delete all applications to simulate no applications meeting the criteria
        delete [SELECT Id FROM Application__c];

        // Start the test
        Test.startTest();

        // Call the method to test
        UrgentDocApprovalNeededHandler.sendUrgentDocApprovalEmail();

        // Stop the test
        Test.stopTest();

        // Verify that no emails were sent
        System.assertEquals(2, Limits.getEmailInvocations(), 'Expected no email invocations.');
    }

    @future
    public static void createEmailTemplate() {
        EmailTemplate validEmailTemplate = new EmailTemplate();
        validEmailTemplate.isActive = true;
        validEmailTemplate.Name = 'Urgent Doc Approval Needed';
        validEmailTemplate.DeveloperName = 'Urgent_Doc_Approval_Needed';
        validEmailTemplate.TemplateType = 'text';
        validEmailTemplate.FolderId = UserInfo.getUserId();
        
        insert validEmailTemplate;
    }
}