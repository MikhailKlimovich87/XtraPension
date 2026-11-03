@isTest
public with sharing class PK_WelcomeEmailReminderBatchTest {
    @TestSetup
    static void makeData() {
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
        Product2 successProduct = null;
        for (Product2 product : newProducts) {
            PriceBookEntry ret = new PriceBookEntry();
            ret.Pricebook2Id = pricebookId;
            ret.Product2Id = product.id;
            ret.UnitPrice = counter;
            ret.IsActive = true;
            ret.CurrencyIsoCode = 'EUR';
            testPriceBookEntries.add(ret);
            counter += 10000;
            if (product.Name == 'Success') {
                successProduct = product;
            }
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
        Application__c testApplication = TestDataFactory.createApplication(personContactId, false);
        testApplication.Status__c = 'No Annual';
        insert testApplication;
        Order order = TestDataFactory.createOrder(testApplication.Id, account.Id, true);
        Payment__c newPayment = new Payment__c();
        newPayment.Application__c    = testApplication.Id;
        newPayment.Amount__c         = 10000;
        newPayment.CurrencyIsoCode   = 'EUR';
        newPayment.Payment_Date__c   = Date.today().addDays(-45);
        newPayment.Product__c        = successProduct.Id;
        newPayment.Order__c          = order.Id;
        newPayment.Status__c         = 'Paid';
        newPayment.Customer_Id__c    = 'cus_asdQWca12';
        newPayment.Payment_Method__c = 'pm_s4sfawfasd';
        newPayment.Payment_Intent__c = 'pi_87541124578415';
        insert newPayment;
    }

    @IsTest
    static void testBatchExecute() {

        Test.startTest();

        PK_WelcomeEmailReminderBatch batchObj =
            new PK_WelcomeEmailReminderBatch();

        Database.executeBatch(batchObj, 1);

        Test.stopTest();

        Application__c updatedApp = [
            SELECT
                Id,
                Sent_Mass_Email_Message__c,
                Mass_Sms_Message_Send_Date__c,
                Pension_Keeper_Notification_Generated__c
            FROM Application__c
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedApp.Sent_Mass_Email_Message__c
        );

        System.assertEquals(
            Date.today(),
            updatedApp.Mass_Sms_Message_Send_Date__c
        );

        List<EmailMessage> emailMessages = [
            SELECT Id, RelatedToId
            FROM EmailMessage
        ];

        System.assert(
            emailMessages.size() > 0,
            'EmailMessage should be created'
        );

        List<ContentDocumentLink> emailLinks = [
            SELECT Id, LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :emailMessages[0].Id
        ];

        System.assert(
            emailLinks.size() > 0,
            'File should be linked to EmailMessage'
        );

        List<ContentDocumentLink> appLinks = [
            SELECT Id, LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :updatedApp.Id
        ];

        System.assert(
            appLinks.size() > 0,
            'File should be linked to Application'
        );
    }

    @IsTest
    static void testBatchWithExistingDocument() {

        Application__c appObj = [
            SELECT
                Id,
                First_Name__c,
                Second_Name__c,
                Name
            FROM Application__c
            LIMIT 1
        ];

        ContentVersion cv = new ContentVersion();

        cv.Title =
            appObj.First_Name__c + '_' +
            appObj.Second_Name__c + '_' +
            appObj.Name +
            '_Welcome_PK_Notification';

        cv.PathOnClient = 'existing.pdf';
        cv.VersionData = Blob.valueOf('Existing File');

        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ];

        ContentDocumentLink cdl =
            new ContentDocumentLink();

        cdl.LinkedEntityId = appObj.Id;
        cdl.ContentDocumentId = cv.ContentDocumentId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';

        insert cdl;

        Test.startTest();

        Database.executeBatch(
            new PK_WelcomeEmailReminderBatch(),
            1
        );

        Test.stopTest();

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :cv.ContentDocumentId
        ];

        System.assert(
            versions.size() > 1,
            'New version should be added to existing file'
        );
    }

    @IsTest
    static void testNoMatchingPayments() {

        List<Payment__c> payments = [
            SELECT Id
            FROM Payment__c
        ];

        for (Payment__c payment : payments) {
            payment.Status__c = 'Fail';
        }

        update payments;

        Test.startTest();

        Database.executeBatch(
            new PK_WelcomeEmailReminderBatch(),
            1
        );

        Test.stopTest();

        List<EmailMessage> emailMessages = [
            SELECT Id
            FROM EmailMessage
        ];

        System.assertEquals(
            2,
            emailMessages.size(),
            'No emails should be created'
        );
    }
}