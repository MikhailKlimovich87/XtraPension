public class TestDataFactory {

    public static List<Product2> createProductsWithPrices() {
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
        // Pricebook2 standardPricebook = new Pricebook2(
	    //     Id = pricebookId,
	    //     IsActive = true
        // );
        // update standardPricebook;
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
        return newProducts;
    }

    public static List<Country__c> createTestCountry(Boolean isInsertOrNon) {
        List<Country__c> newCountry = new List<Country__c>();
        newCountry.add(new Country__c(
            Name = 'United States',
            Country_Code__c = 'US'
        ));
        if (isInsertOrNon) {
            insert newCountry;
        }
        return newCountry;
    }

    public static Application__c createApplication(Id contactId, Boolean isInsertOrNone) {
        Application__c application = new Application__c(
            First_Name__c                         = 'John',
            Second_Name__c                        = 'Snow',
            Expiry_Date__c                        = Datetime.now().addDays(14),
            Package_Name__c                       = 'Basic',
            Payment_Method__c                     = 'pm_123456789',
            Stripe_Customer_Id__c                 = 'cus_123456789',
            Status__c                             = 'Form In Progress',
            Is_Payment_Completed__c               = true,
            Step__c                               = 'Personal Details',
            Stripe_Transaction_Id__c              = '1111111111111111111',
            Last_UK_Home_Address__CountryCode__s  = 'GB',
            Related_Contact_Phone__c              = '+12345678912',
            Email__c                              = 'john.snow@gmail.com',
            Live_In_The_EU__c                     = true,
            Contact__c                            = contactId,
            National_Insurance_Number__c          = 'AS1234578A',
            Previous_UK_Address_1__City__s        = 'London',
            Previous_UK_Address_1__CountryCode__s = 'GB',
            Previous_UK_Address_1__PostalCode__s  = '1as5DS',
            Previous_UK_Address_1__Street__s      = 'Test street',
            CurrencyIsoCode                       = 'EUR'
        );
        if (isInsertOrNone) {
            insert application;
        }
        return application;
    }

    public static ContentVersion createTestContentVersion(Boolean isInsertOrNone) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test_UPLOAD';
        cv.PathOnClient = 'test';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test Attachment Body','UTF-8'));
        if (isInsertOrNone) {
            insert cv;
        }
        return cv;
    }

    public static ContentVersion createTestForSignatureContentVersion(Boolean isInsertOrNone) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Test_CF083_ForSignature';
        cv.PathOnClient = 'Test_CF083_ForSignature.pdf';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test ForSignature Body','UTF-8'));
        if (isInsertOrNone) {
            insert cv;
        }
        return cv;
    }

    public static ContentVersion createTestCustomLetterContentVersion(Boolean isInsertOrNone) {
        ContentVersion cv = new ContentVersion();
        cv.Title = 'CustomLetter_ForSignature';
        cv.PathOnClient = 'CustomLetter_ForSignature.pdf';
        cv.VersionData = EncodingUtil.base64Decode(EncodingUtil.urlEncode('Unit Test CustomLetter Body','UTF-8'));
        if (isInsertOrNone) {
            insert cv;
        }
        return cv;
    }

    public static Agent__c createAgent(Boolean isInsertOrNone) {
        Agent__c agent = new Agent__c();
        agent.First_Name__c = 'John';
        agent.Last_Name__c = 'Snow';
        agent.Name_of_Company__c = 'Test Company';
        if (isInsertOrNone) {
            insert agent;
        }
        return agent;
    }

    public static Order createOrder(Id applicationId, Id accountId, Boolean isInsertOrNone) {
        Order newOrder = new Order(
            Status         = 'Draft',
            EffectiveDate  = Date.today(),
            Pricebook2Id   = Test.getStandardPricebookId(),
            AccountId      = accountId,
            Application__c = applicationId
        );
        if (isInsertOrNone) {
            insert newOrder;
        }
        return newOrder;
    }


    public static Payment__c createPayment(Id applicationId, Id testOrderId, Boolean isInsertOrNone) {
        Payment__c newPayment = new Payment__c();
        newPayment.Application__c    = applicationId;
        newPayment.Amount__c         = 10000;
        newPayment.Order__c          = testOrderId;
        newPayment.Status__c         = 'Schedule';
        newPayment.Customer_Id__c    = 'cus_asdQWca12';
        newPayment.Payment_Method__c = 'pm_s4sfawfasd';
        newPayment.Payment_Intent__c = 'pi_87541124578415';
        if (isInsertOrNone) {
            insert newPayment;
        }
        return newPayment;
    }

    public static Account createAccount(Boolean isInsertOrNone) {
        Account account = new Account(
            LastName                = 'John Snow',
            PersonEmail             = 'john.snow@gmail.com',
            PersonMobilePhone       = '+123456789456',
            PersonMailingCity       = 'Test',
            PersonMailingCountry    = 'US',
            PersonMailingState      = 'Ohio',
            PersonMailingPostalCode = '04075',
            PersonMailingStreet     = 'Test'
        );
        if (isInsertOrNone) {
            insert account;
        }
        return account;
    }

    public static List<Payment__c> createRelatedPaymentToApplication(List<Product2> testProducts, Application__c testApp, Id orderId, Boolean isInsertOrNone) {
        Set<Id> productIds = new Set<Id>();
        for (Product2 product : testProducts) {
            productIds.add(product.Id);
        }
        List<PricebookEntry> relatedPriceBooks = [
            SELECT
                Product2Id,
                Product2.Name,
                UnitPrice
            FROM PricebookEntry
            WHERE Product2Id =: productIds
        ];
        Map<Id, Decimal> productIdByUnitPrice = new Map<Id, Decimal>();
        for (PricebookEntry price : relatedPriceBooks) {
            productIdByUnitPrice.put(price.Product2Id, price.UnitPrice);
        }
        List<Payment__c> newPayments = new List<Payment__c>();
        for(Product2 product : testProducts) {
            newPayments.add(new Payment__c(
                Application__c    = testApp.Id,
                Product__c        = product.Id,
                Payment_Method__c = testApp.Payment_Method__c,
                Status__c         = 'Draft',
                Customer_Id__c    = testApp.Stripe_Customer_Id__c,
                Amount__c         = productIdByUnitPrice.get(product.Id),
                Order__c          = orderId
            ));
        }
        if (isInsertOrNone) {
            insert newPayments;
        }
        return newPayments;
    }

    public static Employer__c createEmployer(Id appId, String type, String typeOfAfterUKEmployer, Boolean isInsertOrNone) {
        Employer__c testEmployer = new Employer__c(
            Start_Date__c                  = Date.valueOf('2009-03-08'),
            End_Date__c                    = Date.valueOf('2010-02-09'),
            Is_First_Employer__c           = true,
            Type__c                        = type,
            Type_Of_After_UK_Employment__c = typeOfAfterUKEmployer,
            Application__c                 = appId,
            Current_Work__c                = 'Yes'
        );
        if (isInsertOrNone) {
            insert testEmployer;
        }
        return testEmployer;
    }

    public static Application_Document__c createApplicationDocument(Id appId, Boolean isInsertOrNone) {
        Application_Document__c testApplicationDocument = new Application_Document__c(
            Application__c = appId,
            File_Name__c   = 'John_Snow_CustomLetter_ForSignature',
            Status__c      = 'New',
            Type__c        = 'Custom Letter'
        );
        if (isInsertOrNone) {
            insert testApplicationDocument;
        }
        return testApplicationDocument;
    }

    public static Application_Document__c createCF083ApplicationDocument(Id appId, Boolean isInsertOrNone) {
        Application_Document__c testApplicationDocument = new Application_Document__c(
            Application__c = appId,
            File_Name__c   = 'John_Snow_CF083_ForSignature',
            Status__c      = 'New',
            Type__c        = 'Statement of Social Insurance'
        );
        if (isInsertOrNone) {
            insert testApplicationDocument;
        }
        return testApplicationDocument;
    }

    public static Application_Document__c createAgentApplicationDocument(Id appId, Boolean isInsertOrNone) {
        Application_Document__c testApplicationDocument = new Application_Document__c(
            Application__c = appId,
            File_Name__c   = '64-8_ForSignature',
            Status__c      = 'New',
            Type__c        = 'Statement of Social Insurance'
        );
        if (isInsertOrNone) {
            insert testApplicationDocument;
        }
        return testApplicationDocument;
    }

    public static Credit_Note__c createCreditNotes(Id paymentId, Boolean isInsertOrNone) {
        List<Payment__c> payments = [
            SELECT
                Amount__c,
                Product__c,
                Payment_Method__c,
                Tax_VAT__c
            FROM Payment__c
            WHERE Id = :paymentId
        ];
        Payment__c testPayment= payments[0];
        Credit_Note__c testCreditNote = new Credit_Note__c(
            Amount__c = testPayment.Amount__c,
            Payment__c = paymentId,
            Product__c = testPayment.Product__c,
            Refund_Date__c = Date.today(),
            Refund_Method__c = testPayment.Payment_Method__c,
            Tax_EU__c = testPayment.Tax_VAT__c
        );
        if (isInsertOrNone) {
            insert testCreditNote;
        }
        return testCreditNote;
    }

    public static XtraPension_Data__c createXtraPensionDataCustomSetting(Boolean isInsertOrNone) {
        XtraPension_Data__c setting = new XtraPension_Data__c();
        setting.Fill_Pdf_File_Link__c = 'https://test.com/fill';
        setting.Form_Link__c = 'https://test.com/form';
        setting.Person_Account_Record_Type_Id__c = '012fdsaerqwasdf1';
        setting.SFTP_Upload_File_Link__c = 'https://test.com/upload/data';
        setting.Twilio_Account__c = 'AC4567891234568789';
        if (isInsertOrNone == true) {
            insert setting;
        }
        return setting;
    }

    public static Lead createLead(Boolean isInsertOrNone) {
        Lead testLead = new Lead(
            FirstName = 'John',
            LastName  = 'Snow',
            Email = 'john.snow@test.com',
            Estimate__c = 'https://check.test.com/pdf/john.snow@test.com.pdf'
        );
        if (isInsertOrNone) {
            insert testLead;
        }
        return testLead;
    }

    public static HMRC_SMS_Schedule_Date__c createHMRCSMSScheduleDate(Boolean isInsertOrNone) {
        HMRC_SMS_Schedule_Date__c scheduleDateTest = new HMRC_SMS_Schedule_Date__c(
            SMS_message__c  = 'Test message',
            Execute_Date__c = Date.today()
        );
        if (isInsertOrNone) {
            insert scheduleDateTest;
        }
        return scheduleDateTest;
    }

    public static TwilioSF__Message__c createTwilioMessageRecord(Boolean isInsertOrNone) {
        TwilioSF__Message__c message = new TwilioSF__Message__c();
        message.TwilioSF__Body__c = 'This test message';
        message.TwilioSF__To_Number__c = '+11111236456';
        if (isInsertOrNone == true) {
            insert message;
        }
        return message;
    }
}