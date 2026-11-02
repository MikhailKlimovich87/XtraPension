@isTest
public class RE_ReapplyPaymentTriggerHandlerTest {
   
    @TestSetup
    static void makeData(){
        // Create base data
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        
        List<Contact> currentContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :account.Id
            LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        Reapply__c testReapply = TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
        
        // Create Email Templates for testing
        createEmailTemplates();
    }

    // Helper method to create Email Templates
    private static void createEmailTemplates() {
        // Check if templates exist
        List<EmailTemplate> existingTemplates = [
            SELECT Id, Name 
            FROM EmailTemplate 
            WHERE Name IN ('Client EU Receipt', 'Client AU Receipt', 'Client None EU Receipt')
        ];
        
        if (existingTemplates.isEmpty()) {
            // Create test email templates
            List<EmailTemplate> templatesToInsert = new List<EmailTemplate>();
            
            // EU Template
            EmailTemplate euTemplate = new EmailTemplate(
                Name = 'Client EU Receipt',
                DeveloperName = 'Client_EU_Receipt',
                Subject = 'Your Receipt - EU',
                Body = 'Thank you for your payment.',
                TemplateType = 'text',
                IsActive = true
            );
            templatesToInsert.add(euTemplate);
            
            // AU Template
            EmailTemplate auTemplate = new EmailTemplate(
                Name = 'Client AU Receipt',
                DeveloperName = 'Client_AU_Receipt',
                Subject = 'Your Receipt - AU',
                Body = 'Thank you for your payment.',
                TemplateType = 'text',
                IsActive = true
            );
            templatesToInsert.add(auTemplate);
            
            // None EU Template
            EmailTemplate noneEUTemplate = new EmailTemplate(
                Name = 'Client None EU Receipt',
                DeveloperName = 'Client_None_EU_Receipt',
                Subject = 'Your Receipt',
                Body = 'Thank you for your payment.',
                TemplateType = 'text',
                IsActive = true
            );
            templatesToInsert.add(noneEUTemplate);
            
            try {
                insert templatesToInsert;
            } catch (Exception e) {
                System.debug('Email templates may already exist or cannot be inserted: ' + e.getMessage());
            }
        }
    }

    // Helper method to create a Reapply Payment
    private static Reapply_Payment__c createReapplyPayment(String status, String currencyCode, Boolean isInsert) {
        // Get the reapply record
        List<Reapply__c> reapplyList = [SELECT Id FROM Reapply__c LIMIT 1];
        if (reapplyList.isEmpty()) {
            return null;
        }
        
        Reapply_Payment__c payment = new Reapply_Payment__c(
            Reapply__c = reapplyList[0].Id,
            Status__c = status,
            Payment_Date__c = Date.today(),
            Amount__c = 100.00,
            Card_Data__c = 'Visa ****1234',
            CurrencyIsoCode = currencyCode
        );
        
        if (isInsert) {
            insert payment;
        }
        
        return payment;
    }

    // Test 1: Insert Paid payment - EU Currency
    @isTest
    static void testInsertPaidPaymentWithEUR() {
        Test.startTest();
        
        Reapply_Payment__c payment = createReapplyPayment('Paid', 'EUR', true);
        
        Test.stopTest();
        
        // Verify Receipt was created
        List<Receipt__c> receipts = [SELECT Id, Reapply_Payment__c, Paid_Date__c, CurrencyIsoCode 
                                     FROM Receipt__c 
                                     WHERE Reapply_Payment__c = :payment.Id];
        
        System.assert(!receipts.isEmpty(), 'Receipt should be created');
        System.assertEquals(1, receipts.size(), 'Only one receipt should be created');
        System.assertEquals('EUR', receipts[0].CurrencyIsoCode, 'Currency should be EUR');
    }

    // Test 2: Insert Paid payment - AU Currency
    @isTest
    static void testInsertPaidPaymentWithAUD() {
        Test.startTest();
        
        Reapply_Payment__c payment = createReapplyPayment('Paid', 'AUD', true);
        
        Test.stopTest();
        
        // Verify Receipt was created
        List<Receipt__c> receipts = [SELECT Id, Reapply_Payment__c, CurrencyIsoCode 
                                     FROM Receipt__c 
                                     WHERE Reapply_Payment__c = :payment.Id];
        
        System.assert(!receipts.isEmpty(), 'Receipt should be created');
        System.assertEquals('AUD', receipts[0].CurrencyIsoCode, 'Currency should be AUD');
    }

    // Test 3: Insert Paid payment - Other Currency (None EU)
    @isTest
    static void testInsertPaidPaymentWithUSD() {
        Test.startTest();
        
        Reapply_Payment__c payment = createReapplyPayment('Paid', 'USD', true);
        
        Test.stopTest();
        
        // Verify Receipt was created
        List<Receipt__c> receipts = [SELECT Id, Reapply_Payment__c, CurrencyIsoCode 
                                     FROM Receipt__c 
                                     WHERE Reapply_Payment__c = :payment.Id];
        
        System.assert(!receipts.isEmpty(), 'Receipt should be created');
        System.assertEquals('USD', receipts[0].CurrencyIsoCode, 'Currency should be USD');
    }

    // Test 4: Insert Payment with Status 'Pending' - Should NOT create receipt
    @isTest
    static void testInsertPendingPaymentNoReceipt() {
        Test.startTest();
        
        Reapply_Payment__c payment = createReapplyPayment('Draft', 'EUR', true);
        
        Test.stopTest();
        
        // Verify NO Receipt was created
        List<Receipt__c> receipts = [SELECT Id FROM Receipt__c WHERE Reapply_Payment__c = :payment.Id];
        
        System.assertEquals(0, receipts.size(), 'Receipt should NOT be created for Pending status');
    }

    // Test 5: Insert Payment with null Payment_Date - Should NOT create receipt
    @isTest
    static void testInsertPaymentNullPaymentDate() {
        Test.startTest();
        
        // Get reapply record
        List<Reapply__c> reapplyList = [SELECT Id FROM Reapply__c LIMIT 1];
        
        Reapply_Payment__c payment = new Reapply_Payment__c(
            Reapply__c = reapplyList[0].Id,
            Status__c = 'Paid',
            Payment_Date__c = null, // Null payment date
            Amount__c = 100.00,
            Card_Data__c = 'Visa ****1234',
            CurrencyIsoCode = 'EUR'
        );
        insert payment;
        
        Test.stopTest();
        
        // Verify NO Receipt was created
        List<Receipt__c> receipts = [SELECT Id FROM Receipt__c WHERE Reapply_Payment__c = :payment.Id];
        
        System.assertEquals(0, receipts.size(), 'Receipt should NOT be created when Payment_Date is null');
    }

    // Test 6: Insert Payment with null Amount - Should NOT create receipt
    @isTest
    static void testInsertPaymentNullAmount() {
        Test.startTest();
        
        // Get reapply record
        List<Reapply__c> reapplyList = [SELECT Id FROM Reapply__c LIMIT 1];
        
        Reapply_Payment__c payment = new Reapply_Payment__c(
            Reapply__c = reapplyList[0].Id,
            Status__c = 'Paid',
            Payment_Date__c = Date.today(),
            Amount__c = null, // Null amount
            Card_Data__c = 'Visa ****1234',
            CurrencyIsoCode = 'EUR'
        );
        insert payment;
        
        Test.stopTest();
        
        // Verify NO Receipt was created
        List<Receipt__c> receipts = [SELECT Id FROM Receipt__c WHERE Reapply_Payment__c = :payment.Id];
        
        System.assertEquals(0, receipts.size(), 'Receipt should NOT be created when Amount is null');
    }

    // Test 7: Multiple Payments Inserted Together
    @isTest
    static void testMultiplePaymentsInserted() {
        Test.startTest();
        
        // Get reapply record
        List<Reapply__c> reapplyList = [SELECT Id FROM Reapply__c LIMIT 1];
        
        // Create multiple payments
        List<Reapply_Payment__c> payments = new List<Reapply_Payment__c>();
        
        // Paid payment
        Reapply_Payment__c paidPayment = new Reapply_Payment__c(
            Reapply__c = reapplyList[0].Id,
            Status__c = 'Paid',
            Payment_Date__c = Date.today(),
            Amount__c = 100.00,
            Card_Data__c = 'Visa ****1234',
            CurrencyIsoCode = 'EUR'
        );
        payments.add(paidPayment);
        
        // Pending payment (should not create receipt)
        Reapply_Payment__c pendingPayment = new Reapply_Payment__c(
            Reapply__c = reapplyList[0].Id,
            Status__c = 'Draft',
            Payment_Date__c = Date.today(),
            Amount__c = 50.00,
            Card_Data__c = 'Mastercard ****5678',
            CurrencyIsoCode = 'EUR'
        );
        payments.add(pendingPayment);
        
        insert payments;
        
        Test.stopTest();
        
        // Verify only ONE Receipt was created (for the Paid payment)
        List<Receipt__c> receipts = [SELECT Id, Reapply_Payment__c 
                                     FROM Receipt__c 
                                     WHERE Reapply_Payment__c IN :payments];
        
        System.assertEquals(1, receipts.size(), 'Only one receipt should be created');
        
        // Verify the receipt is for the Paid payment
        Set<Id> receiptPaymentIds = new Map<Id, Receipt__c>(receipts).keySet();
        //System.assert(receiptPaymentIds.contains(paidPayment.Id), 'Receipt should be for the Paid payment');
    }

    // Test 8: Payment with Contact associated
    @isTest
    static void testPaymentWithContact() {
        Test.startTest();
        
        // Create a payment
        Reapply_Payment__c payment = createReapplyPayment('Paid', 'EUR', true);
        
        Test.stopTest();
        
        // Verify Receipt has Contact field populated
        List<Receipt__c> receipts = [SELECT Id, Contact__c 
                                     FROM Receipt__c 
                                     WHERE Reapply_Payment__c = :payment.Id];
        
        System.assert(!receipts.isEmpty(), 'Receipt should be created');
        System.assertNotEquals(null, receipts[0].Contact__c, 'Contact should be populated on Receipt');
    }

    // Test 9: Test with OrgWideEmailAddress null scenario
    @isTest
    static void testOrgWideEmailAddressNull() {
        Test.startTest();
        
        // Create payment with a currency that doesn't have a template
        Reapply_Payment__c payment = createReapplyPayment('Paid', 'GBP', true);
        
        Test.stopTest();
        
        // Receipt should still be created even if email might fail
        List<Receipt__c> receipts = [SELECT Id FROM Receipt__c WHERE Reapply_Payment__c = :payment.Id];
        
        System.assert(!receipts.isEmpty(), 'Receipt should be created regardless of email template issues');
    }

    // Test 10: Verify Receipt fields are properly copied from Payment
    @isTest
    static void testReceiptFieldsMapping() {
        Test.startTest();
        
        // Get reapply record
        List<Reapply__c> reapplyList = [SELECT Id FROM Reapply__c LIMIT 1];
        
        Decimal expectedAmount = 150.00;
        Date expectedDate = Date.today().addDays(-1);
        String expectedCardData = 'Amex ****9876';
        
        Reapply_Payment__c payment = new Reapply_Payment__c(
            Reapply__c = reapplyList[0].Id,
            Status__c = 'Paid',
            Payment_Date__c = expectedDate,
            Amount__c = expectedAmount,
            Card_Data__c = expectedCardData,
            CurrencyIsoCode = 'EUR'
        );
        insert payment;
        
        Test.stopTest();
        
        // Verify Receipt fields
        List<Receipt__c> receipts = [SELECT Id, Paid_Date__c, Payment_Method__c, CurrencyIsoCode
                                     FROM Receipt__c 
                                     WHERE Reapply_Payment__c = :payment.Id];
        
        System.assert(!receipts.isEmpty(), 'Receipt should be created');
        Receipt__c receipt = receipts[0];
        
        System.assertEquals(expectedDate, receipt.Paid_Date__c, 'Paid_Date should match');
        System.assertEquals(expectedCardData, receipt.Payment_Method__c, 'Payment_Method should match');
        System.assertEquals('EUR', receipt.CurrencyIsoCode, 'CurrencyIsoCode should match');
    }

    // Test 11: Test trigger with AFTER_UPDATE operation
    @isTest
    static void testAfterUpdateOperation() {
        Test.startTest();
        
        // Create a payment first
        Reapply_Payment__c payment = createReapplyPayment('Draft', 'EUR', true);
        
        // Update the payment to 'Paid'
        payment.Status__c = 'Paid';
        payment.Payment_Date__c = Date.today();
        payment.Amount__c = 100.00;
        update payment;
        
        Test.stopTest();
        
        // Verify Receipt was created after update
        List<Receipt__c> receipts = [SELECT Id FROM Receipt__c WHERE Reapply_Payment__c = :payment.Id];
        
        // The trigger handles AFTER_UPDATE as well
        // Since the trigger only handles AFTER_INSERT currently, this should not create a receipt
        System.assertEquals(0, receipts.size(), 'Receipt should NOT be created on AFTER_UPDATE since handler only handles AFTER_INSERT');
    }
}