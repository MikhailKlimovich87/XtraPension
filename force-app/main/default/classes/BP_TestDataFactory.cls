public with sharing class BP_TestDataFactory {
       public static Basic__c createBasic (Id contactId, Boolean isInsertOrNone) {
        Basic__c application = new Basic__c(
            Agent_Making_Sale__c = 'None',
            Bank_Account__c = 'AIB',
            Bank_Account_Owner_Name__c = 'AIB',
            Bank_Account_Type__c = '11-11-11',
            Bank_IBAN__c = 'AI11 II11 II12',
            Bank_Name__c = 'test',
            Bank_Sort_Code__c = '11-12-12',
            Claimant_address1__c = 'London',
            Claimant_address2__c = 'Test',
            Claimant_Bereavement_Benefit__c = true,
            Claimant_maiden_Name__c = 'John Snow',
            Claimant_marital_Status__c = 'Single',
            Claimant_nationality__c = 'test',
            Claimant_other_names__c = 'test',
            Claimant_title__c = 'Mr',
            Contact__c = contactId,
            First_Name__c = 'John',
            Last_Name__c = 'Snow',
            Payment_Method__c  = 'pm_123456789',
            Stripe_Customer_Id__c = 'cus_123456789',
            Status__c = 'Form In Progress',
            Step__c  = 'Friend / Family for Communication',
            Stripe_Transaction_Id__c  = '1111111111111111111',
            How_did_you_hear_about_us__c = 'test',
            Partner_Address1__c = 'test',
            Partner_Address2__c = 'test',
            Friend_Phone__c = '+12345678912',
            Email__c = 'john.snow@gmail.com',
            Phone__c = '+12345678912',
            Relationship__c = 'Friend',
            CurrencyIsoCode = 'EUR',
            Claimant_City__c = 'Test',
            Current_Address_Abroad_State_Name__c = 'Dublin',
            Eircode__c = '123456',
            Current_Address_Abroad_Country_Name__c = 'Ireland',
            Bank_Address__c = 'Test',
            Bank_City__c = 'Test',
            Bank_Post_Code__c = 'Test',
            Bank_Country__c = 'Test'
        );
        if (isInsertOrNone) {
            insert application;
        }
        return application;
    }

    public static Claimant_Child__c createChild(Id BasicId, Boolean isInsertOrNone) {
        Claimant_Child__c child = new Claimant_Child__c(
            Basic__c = BasicId,
            CurrencyIsoCode = 'EUR',
            Dob__c = Date.today(),
            Minded_From__c = Date.today(),
            Minded_To__c = Date.today(),
            Name = 'Child test',
            Nino__c = 'AA123456B'
        );

        if (isInsertOrNone) {
            insert child;
        }
        return child;
    }

    public static Claimant_Company__c createCompany(Id BasicId, Boolean isInsertOrNone) {
        Claimant_Company__c company = new Claimant_Company__c(
            Basic__c = BasicId,
            Address1__c = 'test',
            Address2__c = 'test',
            City__c = 'test',
            Country__c = 'test',
            Country_Type__c = 'US',
            CurrencyIsoCode = 'EUR',
            Postcode__c = '91000',
            From_Date__c = Date.today(),
            To_Date__c = Date.today(),
            Name = 'Company test'
        );

        if (isInsertOrNone) {
            insert company;
        }
        return company;
    }

    public static Claimant_Country_lived__c createCountryLived(Id BasicId, Boolean isInsertOrNone) {
        Claimant_Country_lived__c countryLived = new Claimant_Country_lived__c(
            Basic__c = BasicId,
            CurrencyIsoCode = 'EUR',
            Country_Type__c = 'US',
            From_date__c = Date.today(),
            To_Date__c = Date.today(),
            Name = 'Child test',
            Social_Security_Number__c = '123456789'
        );

        if (isInsertOrNone) {
            insert countryLived;
        }
        return countryLived;
    }

     public static Claimant_Company__c createCompanyPartner(Id BasicId, Boolean isInsertOrNone) {
        Claimant_Company__c countryLived = new Claimant_Company__c(
            Basic__c = BasicId,
            Address1__c = 'test',
            Address2__c = 'test',
            City__c = 'test',
            Country__c = 'test',
            Country_Type__c = 'US',
            CurrencyIsoCode = 'EUR',
            Postcode__c = '91000',
            From_Date__c = Date.today(),
            To_Date__c = Date.today(),
            Name = 'Company test',
            Is_Partner__c = true
        );

        if (isInsertOrNone) {
            insert countryLived;
        }
        return countryLived;
    }

     public static Claimant_Company__c createCompanyUkAddress(Id BasicId, Boolean isInsertOrNone) {
        Claimant_Company__c countryLived = new Claimant_Company__c(
          Basic__c = BasicId,
            Address1__c = 'test',
            Address2__c = 'test',
            City__c = 'test',
            Country__c = 'test',
            Country_Type__c = 'US',
            CurrencyIsoCode = 'EUR',
            Postcode__c = '91000',
            From_Date__c = Date.today(),
            To_Date__c = Date.today(),
            Name = 'Company test',
            Is_Addresses__c = true
        );

        if (isInsertOrNone) {
            insert countryLived;
        }
        return countryLived;
    }

    public static Basic_Payment__c createBP_Payment(Id applicationId, Boolean isInsertOrNone, Product2 product) {

        Basic_Payment__c newPayment = new Basic_Payment__c();
        newPayment.Basic__c    = applicationId;
        newPayment.Amount__c         = 10000;
        newPayment.Status__c         = 'Schedule';
        newPayment.Customer_Id__c    = 'cus_asdQWca12';
        newPayment.Payment_Method__c = 'pm_s4sfawfasd';
        newPayment.Payment_Intent__c = 'pi_87541124578415';
        newPayment.Product__c = product.Id;
        if (isInsertOrNone) {
            insert newPayment;
        }
        return newPayment;
    }
}