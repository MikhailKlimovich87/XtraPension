@isTest
public class RE_ResponseWrapperTest {
    
    @TestSetup
    static void makeData() {
        TestDataFactory.createProductsWithPrices();
        TestDataFactory.createTestCountry(true);
        Account account = TestDataFactory.createAccount(true);
        List<Contact> currentContact = [
            SELECT Id, AccountId FROM Contact WHERE AccountId = :account.Id LIMIT 1
        ];
        Id personContactId = currentContact[0].Id;
        Application__c testApplication = TestDataFactory.createApplication(personContactId, true);
        TestDataFactory.createEmployer(testApplication.Id, 'UK Work', '', true);
        TestDataFactory.createEmployer(testApplication.Id, 'Work After UK', 'Career Break', true);
        TestDataFactory.createReapplyRecord(testApplication.Id, true);
        TestDataFactory.createXtraPensionDataCustomSetting(true);
    }
    
    // =========================================================
    // SHARED STRIPE MOCK
    // =========================================================
    private class StripePaymentMethodMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            HTTPResponse response = new HTTPResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(
                '{"id":"pm_test123","object":"payment_method","card":{' +
                '"brand":"visa","last4":"4242","exp_month":12,"exp_year":2025}}'
            );
            return response;
        }
    }
    
    // =========================================================
    // HELPER: returns a fully-populated reapply in memory
    // =========================================================
    private static Reapply__c getFullReapply() {
        return [
            SELECT Id, Salutation__c, First_Name__c, Second_Name__c, Former_Name__c,
                   Email__c, Phone__c, NINO__c, Date_of_birth__c, CurrencyIsoCode, Name,
                   Live_in_UK__c, NINO_contribution_pay__c,
                   Where_you_receiving_JSA_before_left_UK__c, Last_received_JSA_date__c,
                   Where_you_receiving_Child_Benefit__c, Last_received_Child_Benefit_date__c,
                   NINO_contributions_in_tax_years__c, Submit_Form__c,
                   UK_Address__Street__s, UK_Address__City__s, UK_Address__PostalCode__s,
                   Address_abroad__Street__s, Address_abroad__City__s,
                   Address_abroad__PostalCode__s, Address_abroad__StateCode__s,
                   Address_abroad__CountryCode__s,
                   What_date_did_or_will_you_leave_the_UK__c,
                   Countries_names_with_dates__c,
                   Are_you_currently_living_outside_the_UK__c,
                   Prefer_contact_address__c,
                   living_working_abroad_current_tax_year__c,
                   Resident_in_rhe_UK_before_left__c,
                   Pay_voluntary_contributions__c,
                   employment_status_before_left_UK__c,
                   Stopped_working_for_last_UK_employer__c,
                   Last_employment_ended_date__c,
                   Last_employer_Name__c,
                   Last_employer_Address__Street__s, Last_employer_Address__City__s,
                   Last_employer_Address__PostalCode__s,
                   Has_your_UK_self_employment_ended__c,
                   Uk_self_employment_ended_date__c,
                   Is_previously_worked_abroad_as_an_emp__c,
                   Employer_abroad_Name__c,
                   Employer_abroad_Address__Street__s, Employer_abroad_Address__City__s,
                   Employer_abroad_Address__StateCode__s, Employer_abroad_Address__PostalCode__s,
                   Employer_abroad_Address__CountryCode__s,
                   Start_employment_date__c, Employment_ceased_end_date__c,
                   Employer_an_overseas_gov_international__c,
                   Self_employer_work_before_left_UK__c,
                   Employer_s_UK_address__Street__s, Employer_s_UK_address__City__s,
                   Employer_s_UK_address__PostalCode__s,
                   Employer_hold_your_contract_of_service__c,
                   Any_other_employments_abroad__c,
                   Self_employed_abroad__c,
                   Start_self_employment_abroad_date__c,
                   End_self_employment_abroad_date__c,
                   Wish_to_pay_by__c, Direct_debit_chosen__c,
                   Class_2_Class_3_2024_2025_2025_2026__c,
                   Best_time_to_call__c,
                   Is_this_the_address_where_we_can_send_yo__c,
                   Abroad_for_the_full_2026_2027_taxYear__c,
                   employer_be_paying_your_NI_contr_abroad__c,
                   annual_payment_details_sent_to_someone_e__c,
                   Stripe_Customer_Id__c, Payment_Method_Id__c,
                   Application__c, Application__r.Status__c,
                   Application__r.PK_Portal_User_Active__c,
                   Application__r.Years_Of_Work_In_The_UK__c,
                   toLabel(Address_abroad__CountryCode__s) CountryCode
            FROM Reapply__c LIMIT 1
        ];
    }
    
    // =========================================================
    // ApplicationDataWrapper
    // =========================================================
    
    @isTest
    static void testApplicationDataWrapper_AllBranches() {
        Reapply__c reapply = getFullReapply();
        reapply.Live_in_UK__c = 5;
        reapply.NINO_contribution_pay__c = 3;
        reapply.Where_you_receiving_JSA_before_left_UK__c = true;
        reapply.Last_received_JSA_date__c = Date.valueOf('2023-01-15');
        reapply.Where_you_receiving_Child_Benefit__c = true;
        reapply.Last_received_Child_Benefit_date__c = Date.valueOf('2023-01-15');
        reapply.NINO_contributions_in_tax_years__c = '2024 to 2025;2025 to 2026';
        reapply.Submit_Form__c = true;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.ApplicationDataWrapper w =
            new RE_ResponseWrapper.ApplicationDataWrapper(fresh);
        Test.stopTest();
        
        System.assertNotEquals(null, w);
        System.assertEquals('5', w.ukYears);
        System.assertEquals('3', w.payNationalInsuranceYears);
        System.assertEquals(true, w.receivedJobSeekersAllowance);
        System.assertNotEquals(null, w.receiveJSALastDate);
        System.assertEquals(true, w.receivedChildBenefit);
        System.assertNotEquals(null, w.receiveChildBenefitLastDate);
        System.assertEquals(true, w.isApr2024);
        System.assertEquals(true, w.isApr2025);
        System.assertEquals(true, w.isSubmit);
        System.assertEquals(false, w.isShowUKYears); // both populated
    }
    
    // @isTest
    // static void testApplicationDataWrapper_NullSafeFields() {
    //     // Reapply with null fields to hit the fallback branches
    //     Reapply__c reapply = getFullReapply();
    //     reapply.Live_in_UK__c = null;
    //     reapply.NINO_contribution_pay__c = null;
    //     reapply.Where_you_receiving_JSA_before_left_UK__c = null;
    //     reapply.Last_received_JSA_date__c = null;
    //     reapply.Where_you_receiving_Child_Benefit__c = null;
    //     reapply.Last_received_Child_Benefit_date__c = null;
    //     reapply.NINO_contributions_in_tax_years__c = null;
    //     update reapply;
        
    //     Reapply__c fresh = getFullReapply();
        
    //     Test.startTest();
    //     RE_ResponseWrapper.ApplicationDataWrapper w =
    //         new RE_ResponseWrapper.ApplicationDataWrapper(fresh);
    //     Test.stopTest();
        
    //     System.assertNotEquals(null, w);
    //     System.assertEquals(true, w.isShowUKYears); // one is null
    //     System.assertEquals(false, w.receivedJobSeekersAllowance);
    //     System.assertEquals(false, w.receivedChildBenefit);
    //     System.assertEquals(false, w.isApr2024);
    //     System.assertEquals(false, w.isApr2025);
    //     System.assertEquals(false, w.isSubmit);
    //     System.assertEquals(null, w.receiveJSALastDate);
    //     System.assertEquals(null, w.receiveChildBenefitLastDate);
    // }
    
    @isTest
    static void testApplicationDataWrapper_NullReapply() {
        Test.startTest();
        RE_ResponseWrapper.ApplicationDataWrapper w =
            new RE_ResponseWrapper.ApplicationDataWrapper(null);
        Test.stopTest();
        System.assertNotEquals(null, w);
        System.assertEquals(null, w.firstName);
    }
    
    @isTest
    static void testApplicationDataWrapper_AnnualServiceStatus() {
        Reapply__c reapply = getFullReapply();
        Application__c app = [
            SELECT Id, Status__c FROM Application__c WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'Annual Service';
        update app;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.ApplicationDataWrapper w =
            new RE_ResponseWrapper.ApplicationDataWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals(true, w.isAnnualOrNotAnnualApp);
    }
    
    @isTest
    static void testApplicationDataWrapper_NoAnnualStatus() {
        Reapply__c reapply = getFullReapply();
        Application__c app = [
            SELECT Id, Status__c FROM Application__c WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'No Annual';
        update app;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.ApplicationDataWrapper w =
            new RE_ResponseWrapper.ApplicationDataWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals(true, w.isAnnualOrNotAnnualApp);
    }
    
    // =========================================================
    // AddressDataWrapper
    // =========================================================
    
    // @isTest
    // static void testAddressDataWrapper_NullReapply() {
    //     Test.startTest();
    //     RE_ResponseWrapper.AddressDataWrapper w =
    //         new RE_ResponseWrapper.AddressDataWrapper(null);
    //     Test.stopTest();
    //     System.assertNotEquals(null, w);
    //     System.assertEquals(null, w.street);
    // }
    
    @isTest
    static void testAddressDataWrapper_WithValues() {
        Reapply__c reapply = getFullReapply();
        reapply.Address_abroad__Street__s = '10 Downing St';
        reapply.Address_abroad__City__s = 'London';
        reapply.Address_abroad__PostalCode__s = 'SW1A 2AA';
        reapply.Address_abroad__StateCode__s = null;
        reapply.Address_abroad__CountryCode__s = 'GB';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.AddressDataWrapper w =
            new RE_ResponseWrapper.AddressDataWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals('10 Downing St', w.street);
        System.assertEquals('London', w.city);
        System.assertEquals('SW1A 2AA', w.postalCode);
        System.assertEquals('GB', w.countryCode);
        System.assertNotEquals(null, w.country);
    }
    
    // =========================================================
    // CardDataWrapper
    // =========================================================
    
    @isTest
    static void testCardDataWrapper_AllFields() {
        Map<String, Object> data = new Map<String, Object>{
            'last4' => '4242',
            'brand' => 'visa',
            'exp_month' => 12,
            'exp_year' => 2025
        };
        
        Test.startTest();
        RE_ResponseWrapper.CardDataWrapper w = new RE_ResponseWrapper.CardDataWrapper(data);
        Test.stopTest();
        
        System.assertEquals('4242', w.last4Digits);
        System.assertEquals('visa', w.cardBrand);
        System.assertEquals(12, w.expireMonth);
        System.assertEquals(2025, w.expireYear);
    }
    
    // @isTest
    // static void testCardDataWrapper_NullMap() {
    //     Test.startTest();
    //     RE_ResponseWrapper.CardDataWrapper w = new RE_ResponseWrapper.CardDataWrapper(null);
    //     Test.stopTest();
    //     System.assertNotEquals(null, w);
    //     System.assertEquals(null, w.last4Digits);
    // }
    
    @isTest
    static void testCardDataWrapper_EmptyMap() {
        Test.startTest();
        RE_ResponseWrapper.CardDataWrapper w = new RE_ResponseWrapper.CardDataWrapper(new Map<String, Object>());
        Test.stopTest();
        System.assertNotEquals(null, w);
        System.assertEquals(null, w.last4Digits);
        System.assertEquals(null, w.cardBrand);
        System.assertEquals(null, w.expireYear);
        System.assertEquals(null, w.expireMonth);
    }
    
    // @isTest
    // static void testCardDataWrapper_NumericAsString() {
    //     // Sometimes JSON numbers come through as strings
    //     Map<String, Object> data = new Map<String, Object>{
    //         'last4' => '1111',
    //         'brand' => 'mastercard',
    //         'exp_month' => '06',
    //         'exp_year' => '2030'
    //     };
        
    //     Test.startTest();
    //     RE_ResponseWrapper.CardDataWrapper w = new RE_ResponseWrapper.CardDataWrapper(data);
    //     Test.stopTest();
        
    //     System.assertEquals(6, w.expireMonth);
    //     System.assertEquals(2030, w.expireYear);
    // }
    
    // =========================================================
    // CurrentApplicationDataWrapper
    // =========================================================
    
    // @isTest
    // static void testCurrentApplicationDataWrapper_NullReapply() {
    //     Test.startTest();
    //     RE_ResponseWrapper.CurrentApplicationDataWrapper w =
    //         new RE_ResponseWrapper.CurrentApplicationDataWrapper(null);
    //     Test.stopTest();
    //     System.assertNotEquals(null, w);
    //     System.assertEquals(null, w.applicationId);
    // }
    
    @isTest
    static void testCurrentApplicationDataWrapper_NoPaymentMethod() {
        // No Stripe mock needed because paymentMethod is blank
        Reapply__c reapply = getFullReapply();
        reapply.Payment_Method_Id__c = null;
        reapply.Stripe_Customer_Id__c = null;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.CurrentApplicationDataWrapper w =
            new RE_ResponseWrapper.CurrentApplicationDataWrapper(fresh);
        Test.stopTest();
        
        System.assertNotEquals(null, w);
        System.assertEquals(null, w.paymentMethod);
        System.assertEquals(null, w.cardData); // never queried Stripe
    }
    
    @isTest
    static void testCurrentApplicationDataWrapper_AnnualService() {
        Reapply__c reapply = getFullReapply();
        Application__c app = [
            SELECT Id, Status__c FROM Application__c WHERE Id = :reapply.Application__c
        ];
        app.Status__c = 'Annual Service';
        update app;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.CurrentApplicationDataWrapper w =
            new RE_ResponseWrapper.CurrentApplicationDataWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals(true, w.isAnnualOrNotAnnualApp);
    }
    
    @isTest
    static void testCurrentApplicationDataWrapper_StripeReturnsCardInNestedMap() {
        Reapply__c reapply = getFullReapply();
        reapply.Payment_Method_Id__c = 'pm_test123';
        reapply.Stripe_Customer_Id__c = 'cus_test123';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.setMock(HttpCalloutMock.class, new StripePaymentMethodMock());
        
        Test.startTest();
        RE_ResponseWrapper.CurrentApplicationDataWrapper w =
            new RE_ResponseWrapper.CurrentApplicationDataWrapper(fresh);
        Test.stopTest();
        
        System.assertNotEquals(null, w.cardData);
        System.assertEquals('4242', w.cardData.last4Digits);
        System.assertEquals('visa', w.cardData.cardBrand);
    }
    
    // =========================================================
    // FullReapplyDataWrapper — comprehensive coverage
    // =========================================================
    
    @isTest
    static void testFullReapplyDataWrapper_EmployedBranch() {
        Reapply__c reapply = getFullReapply();
        reapply.Salutation__c = 'Mr';
        reapply.employment_status_before_left_UK__c = 'employed';
        reapply.Stopped_working_for_last_UK_employer__c = true;
        reapply.Last_employment_ended_date__c = Date.valueOf('2023-01-15');
        reapply.Last_employer_Name__c = 'Test Employer';
        reapply.Last_employer_Address__Street__s = '123 Employer St';
        reapply.Last_employer_Address__City__s = 'London';
        reapply.Last_employer_Address__PostalCode__s = 'EC1 1AA';
        reapply.Last_employer_Address__StateCode__s = null;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, true);
        Test.stopTest();
        
        System.assertEquals(true, w.employedEmplStatus);
        System.assertEquals(true, w.stopWorkLastUKEmpl);
        System.assertEquals(false, w.notStopWorkLastUKEmployer);
        System.assertEquals('15', w.endLastEmplDay);
        System.assertEquals('01', w.endLastEmplMonth);
        System.assertEquals('2023', w.endLastEmplYear);
        System.assertEquals('Test Employer', w.lastEmployerName);
        System.assertEquals('123 Employer St, London', w.lastEmployerAddressLine1);
        System.assertEquals('EC1 1AA', w.lastEmployerAddressLine4);
        System.assertNotEquals(null, w.signDay); // isDocusign = true
    }
    
    @isTest
    static void testFullReapplyDataWrapper_EmployedNotStopped() {
        Reapply__c reapply = getFullReapply();
        reapply.employment_status_before_left_UK__c = 'employed';
        reapply.Stopped_working_for_last_UK_employer__c = false;
        reapply.Last_employment_ended_date__c = null;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.notStopWorkLastUKEmployer);
        System.assertEquals(null, w.endLastEmplDay);
        System.assertEquals(null, w.signDay); // isDocusign = false
    }
    
    @isTest
    static void testFullReapplyDataWrapper_SelfEmployedBranch() {
        Reapply__c reapply = getFullReapply();
        reapply.employment_status_before_left_UK__c = 'self_employed';
        reapply.Has_your_UK_self_employment_ended__c = true;
        reapply.Uk_self_employment_ended_date__c = Date.valueOf('2022-06-30');
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.selfEmploedEmplStatus);
        System.assertEquals(true, w.endedSelfEmployment);
        System.assertEquals(false, w.notEndedSelfEmployment);
        System.assertEquals('30', w.selfEmplEndDay);
        System.assertEquals('06', w.selfEmplEndMonth);
        System.assertEquals('2022', w.selfEmplEndYear);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_SelfEmployedNotEnded() {
        Reapply__c reapply = getFullReapply();
        reapply.employment_status_before_left_UK__c = 'self_employed';
        reapply.Has_your_UK_self_employment_ended__c = false;
        reapply.Uk_self_employment_ended_date__c = null;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.notEndedSelfEmployment);
        System.assertEquals(null, w.selfEmplEndDay);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_NeitherBranch() {
        Reapply__c reapply = getFullReapply();
        reapply.employment_status_before_left_UK__c = 'neither_employed_nor_self_employed';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.neitherEmplStatus);
        System.assertEquals(null, w.employedEmplStatus);
        System.assertEquals(null, w.selfEmploedEmplStatus);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_JSAAndChildBenefit() {
        Reapply__c reapply = getFullReapply();
        reapply.Where_you_receiving_JSA_before_left_UK__c = true;
        reapply.Last_received_JSA_date__c = Date.valueOf('2020-03-01');
        reapply.Where_you_receiving_Child_Benefit__c = true;
        reapply.Last_received_Child_Benefit_date__c = Date.valueOf('2021-08-15');
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.receiveJSA);
        System.assertEquals(false, w.notReceiveJSA);
        System.assertEquals('01', w.receiveJSALastDay);
        System.assertEquals('03', w.receiveJSALastMonth);
        System.assertEquals('2020', w.receiveJSALastYear);
        
        System.assertEquals(true, w.receiveChildBenefit);
        System.assertEquals('15', w.receiveChildBenefitLastDay);
        System.assertEquals('08', w.receiveChildBenefitLastMonth);
        System.assertEquals('2021', w.receiveChildBenefitLastYear);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_WorkedAbroadAsEmployee() {
        Reapply__c reapply = getFullReapply();
        reapply.Is_previously_worked_abroad_as_an_emp__c = true;
        reapply.Employer_abroad_Name__c = 'Foreign Employer';
        reapply.Employer_abroad_Address__Street__s = '456 Abroad St';
        reapply.Employer_abroad_Address__City__s = 'Paris';
        reapply.Employer_abroad_Address__StateCode__s = null;
        reapply.Employer_abroad_Address__PostalCode__s = '75001';
        reapply.Employer_abroad_Address__CountryCode__s = 'FR';
        reapply.Start_employment_date__c = Date.valueOf('2020-01-01');
        reapply.Employment_ceased_end_date__c = Date.valueOf('2022-12-31');
        reapply.Employer_an_overseas_gov_international__c = true;
        reapply.Self_employer_work_before_left_UK__c = true;
        reapply.Employer_s_UK_address__Street__s = '789 UK St';
        reapply.Employer_s_UK_address__City__s = 'London';
        reapply.Employer_s_UK_address__PostalCode__s = 'WC1 1AA';
        reapply.Employer_hold_your_contract_of_service__c = true;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.workedAsEmployee);
        System.assertEquals(false, w.notWorkedAsEmployee);
        System.assertEquals('Foreign Employer', w.abrdEmployerName);
        System.assertEquals('456 Abroad St, Paris, 75001', w.abrdEmplAddressLine1);
        System.assertEquals('FR', w.abrdEmplAddressLine4);
        System.assertEquals('01', w.startEmplDay);
        System.assertEquals('01', w.startEmplMonth);
        System.assertEquals('2020', w.startEmplYear);
        System.assertEquals('31', w.ceasedEmplEndDay);
        System.assertEquals('12', w.ceasedEmplEndMonth);
        System.assertEquals('2022', w.ceasedEmplEndYear);
        System.assertEquals(true, w.overseasGovernmentEmpl);
        System.assertEquals(false, w.notOverseasGovernmentEmpl);
        System.assertEquals(true, w.workForEmplBeforeLeftUK);
        System.assertEquals(false, w.notWorkForEmplBeforeLeftUK);
        System.assertEquals('789 UK St', w.emplUKAddressLine1);
        System.assertEquals('London', w.emplUKAddressLine2);
        System.assertEquals('WC1 1AA', w.emplUKAddressLine4);
        System.assertEquals(true, w.emplHoldContract);
        System.assertEquals(false, w.emplNotHoldContract);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_NotWorkedAbroadAsEmployee() {
        Reapply__c reapply = getFullReapply();
        reapply.Is_previously_worked_abroad_as_an_emp__c = false;
        reapply.Any_other_employments_abroad__c = true;
        reapply.Self_employed_abroad__c = true;
        reapply.Start_self_employment_abroad_date__c = Date.valueOf('2019-05-10');
        reapply.End_self_employment_abroad_date__c = Date.valueOf('2021-11-20');
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.notWorkedAsEmployee);
        System.assertEquals(true, w.haveOtherEmplAbroad);
        System.assertEquals(false, w.notHaveOtherEmplAbroad);
        System.assertEquals(true, w.selfEmplAbroad);
        System.assertEquals(false, w.notSelfEmplAbroad);
        System.assertEquals('10', w.selfEmplAbroadStartDay);
        System.assertEquals('05', w.selfEmplAbroadStartMonth);
        System.assertEquals('2019', w.selfEmplAbroadStartYear);
        System.assertEquals('20', w.selfEmplAbrdEndDay);
        System.assertEquals('11', w.selfEmplAbroadEndMonth);
        System.assertEquals('2021', w.selfEmplAbroadEndYear);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_PaymentPreferences() {
        Reapply__c reapply = getFullReapply();
        reapply.Wish_to_pay_by__c = 'Direct Debit';
        reapply.Direct_debit_chosen__c = 'Direct Debit';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.payByDirectDebit);
        System.assertEquals(false, w.payByAnnualPayment);
        System.assertEquals(false, w.payByAgent);
        System.assertEquals(true, w.payGapsUseDirectDebit);
        System.assertEquals(false, w.payGapsUseSterlingCheque);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_PayByAnnualPayment() {
        Reapply__c reapply = getFullReapply();
        reapply.Wish_to_pay_by__c = 'Annual payment';
        reapply.Direct_debit_chosen__c = 'Sterling cheque';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(false, w.payByDirectDebit);
        System.assertEquals(true, w.payByAnnualPayment);
        System.assertEquals(false, w.payByAgent);
        System.assertEquals(false, w.payGapsUseDirectDebit);
        System.assertEquals(true, w.payGapsUseSterlingCheque);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_PayByAgent() {
        Reapply__c reapply = getFullReapply();
        reapply.Wish_to_pay_by__c = 'Agent';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(false, w.payByDirectDebit);
        System.assertEquals(false, w.payByAnnualPayment);
        System.assertEquals(true, w.payByAgent);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_VoluntaryContributionBranches() {
        // Test ongoing periods
        Reapply__c reapply = getFullReapply();
        reapply.Pay_voluntary_contributions__c = 'ongoing periods (for future years)';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.payVolContOngoingPeriod);
        System.assertEquals(false, w.gapInNI);
        System.assertEquals(false, w.bothOngoingPeriodAndGaps);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_GapInNIBranch() {
        Reapply__c reapply = getFullReapply();
        reapply.Pay_voluntary_contributions__c =
            'gaps in your National Insurance record, for example shortfalls for previous years';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(false, w.payVolContOngoingPeriod);
        System.assertEquals(true, w.gapInNI);
        System.assertEquals(false, w.bothOngoingPeriodAndGaps);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_BothOngoingAndGaps() {
        Reapply__c reapply = getFullReapply();
        reapply.Pay_voluntary_contributions__c = 'both ongoing periods and gaps for previous years';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(false, w.payVolContOngoingPeriod);
        System.assertEquals(false, w.gapInNI);
        System.assertEquals(true, w.bothOngoingPeriodAndGaps);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_AddressPreferences() {
        Reapply__c reapply = getFullReapply();
        reapply.Are_you_currently_living_outside_the_UK__c = true;
        reapply.Prefer_contact_address__c = 'UK';
        reapply.living_working_abroad_current_tax_year__c = true;
        reapply.Resident_in_rhe_UK_before_left__c = true;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.chLiveOutsideUK);
        System.assertEquals(false, w.unchLiveOutside);
        System.assertEquals(true, w.preferUseUKAddress);
        System.assertEquals(false, w.preferUseAbroadAddress);
        System.assertEquals(true, w.workingAbrdFullCurrTawYear);
        System.assertEquals(false, w.notWorkingAbrdFullCurrTawYear);
        System.assertEquals(true, w.ordinalyResidentUK);
        System.assertEquals(false, w.notOrdinalyResidentUK);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_PreferAbroadAddress() {
        Reapply__c reapply = getFullReapply();
        reapply.Are_you_currently_living_outside_the_UK__c = false;
        reapply.Prefer_contact_address__c = 'Abroad';
        reapply.living_working_abroad_current_tax_year__c = false;
        reapply.Resident_in_rhe_UK_before_left__c = false;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(false, w.chLiveOutsideUK);
        System.assertEquals(true, w.unchLiveOutside);
        System.assertEquals(false, w.preferUseUKAddress);
        System.assertEquals(true, w.preferUseAbroadAddress);
        System.assertEquals(false, w.workingAbrdFullCurrTawYear);
        System.assertEquals(true, w.notWorkingAbrdFullCurrTawYear);
        System.assertEquals(false, w.ordinalyResidentUK);
        System.assertEquals(true, w.notOrdinalyResidentUK);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_TaxYears24To25Only() {
        Reapply__c reapply = getFullReapply();
        reapply.NINO_contributions_in_tax_years__c = '2024 to 2025';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(true, w.x24To25Years);
        System.assertEquals(false, w.x25To26TaxYears);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_TaxYears25To26Only() {
        Reapply__c reapply = getFullReapply();
        reapply.NINO_contributions_in_tax_years__c = '2025 to 2026';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        System.assertEquals(false, w.x24To25Years);
        System.assertEquals(true, w.x25To26TaxYears);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_DateOfBirthAndNIFormatting() {
        Reapply__c reapply = getFullReapply();
        reapply.Date_of_birth__c = Date.valueOf('1985-03-09');
        reapply.NINO__c = 'AB123456C';
        reapply.What_date_did_or_will_you_leave_the_UK__c = Date.valueOf('2023-04-05');
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, false);
        Test.stopTest();
        
        // DOB split
        System.assertEquals('09', w.dayOfBirth);
        System.assertEquals('03', w.monthOfBirth);
        System.assertEquals('1985', w.yearOfBirth);
        
        // NINO split (9 chars: AB 12 34 56 C)
        System.assertEquals('AB', w.nino12);
        System.assertEquals('12', w.nino34);
        System.assertEquals('34', w.nino56);
        System.assertEquals('56', w.nino67);
        System.assertEquals('C', w.nino8);
        
        // Leave UK
        System.assertEquals('05', w.leaveUKDay);
        System.assertEquals('04', w.leaveUKMonth);
        System.assertEquals('2023', w.leaveUKYear);
    }
    
    @isTest
    static void testFullReapplyDataWrapper_SignDatePopulatedWhenDocusign() {
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.FullReapplyDataWrapper w =
            new RE_ResponseWrapper.FullReapplyDataWrapper(fresh, true);
        Test.stopTest();
        
        System.assertNotEquals(null, w.signDay);
        System.assertNotEquals(null, w.signMonth);
        System.assertNotEquals(null, w.signYear);
    }
    
    // =========================================================
    // RVN_FormWrapper — comprehensive coverage
    // =========================================================
    
    @isTest
    static void testRVN_FormWrapper_AllYes() {
        Reapply__c reapply = getFullReapply();
        reapply.Class_2_Class_3_2024_2025_2025_2026__c = true;
        reapply.Best_time_to_call__c = 'Morning';
        reapply.Is_this_the_address_where_we_can_send_yo__c = true;
        reapply.Abroad_for_the_full_2026_2027_taxYear__c = true;
        reapply.employer_be_paying_your_NI_contr_abroad__c = true;
        reapply.Wish_to_pay_by__c = 'Direct Debit';
        reapply.annual_payment_details_sent_to_someone_e__c = true;
        reapply.Date_of_birth__c = Date.valueOf('1990-01-01');
        reapply.Salutation__c = 'Mr';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.RVN_FormWrapper w = new RE_ResponseWrapper.RVN_FormWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals('No', w.paid2025To2026TaxYears);
        System.assertEquals('Mr ' + fresh.First_Name__c + ' ' + fresh.Second_Name__c, w.fullName);
        System.assertEquals('01/01/1990', w.dob);
        System.assertEquals('Morning', w.bestTimeToCall);
        System.assertEquals('Yes', w.isThisAddressWhereWeCanSendYou);
        System.assertEquals('Yes', w.willYouBeLiving2026To2027Year);
        System.assertEquals('Yes', w.willYourEmplBePayingNI);
        System.assertEquals('Direct Debit', w.payYourVoluntaryClass3Contributions);
        System.assertEquals('Yes', w.annualPaymentDetailsSentToSomeoneElse);
        System.assertEquals(null, w.currAddress);
    }
    
    @isTest
    static void testRVN_FormWrapper_AllNo() {
        Reapply__c reapply = getFullReapply();
        reapply.Class_2_Class_3_2024_2025_2025_2026__c = false;
        reapply.Is_this_the_address_where_we_can_send_yo__c = false;
        reapply.Abroad_for_the_full_2026_2027_taxYear__c = false;
        reapply.employer_be_paying_your_NI_contr_abroad__c = false;
        reapply.annual_payment_details_sent_to_someone_e__c = false;
        reapply.Date_of_birth__c = null;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.RVN_FormWrapper w = new RE_ResponseWrapper.RVN_FormWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals('No', w.paid2025To2026TaxYears);
        System.assertEquals(null, w.dob);
        System.assertEquals('No', w.isThisAddressWhereWeCanSendYou);
        System.assertEquals('No', w.willYouBeLiving2026To2027Year);
        System.assertEquals('No', w.willYourEmplBePayingNI);
        System.assertEquals('No', w.annualPaymentDetailsSentToSomeoneElse);
    }
    
    @isTest
    static void testRVN_FormWrapper_AddressConcatenation_AllFields() {
        Reapply__c reapply = getFullReapply();
        reapply.Address_abroad__Street__s = '1 Main St';
        reapply.Address_abroad__City__s = 'Paris';
        reapply.Address_abroad__StateCode__s = null;
        reapply.Address_abroad__PostalCode__s = '75001';
        reapply.Address_abroad__CountryCode__s = 'FR';
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.RVN_FormWrapper w = new RE_ResponseWrapper.RVN_FormWrapper(fresh);
        Test.stopTest();
        
        System.assertNotEquals(null, w.currAddress);
        System.assert(w.currAddress.contains('1 Main St'), 'Should contain street');
        System.assert(w.currAddress.contains('Paris'), 'Should contain city');
        System.assert(w.currAddress.contains('75001'), 'Should contain postal');
        System.assert(w.currAddress.contains('FR'), 'Should contain country code');
    }
    
    @isTest
    static void testRVN_FormWrapper_AddressOnlyStreet() {
        Reapply__c reapply = getFullReapply();
        reapply.Address_abroad__Street__s = 'Only Street';
        reapply.Address_abroad__City__s = null;
        reapply.Address_abroad__StateCode__s = null;
        reapply.Address_abroad__PostalCode__s = null;
        reapply.Address_abroad__CountryCode__s = null;
        update reapply;
        
        Reapply__c fresh = getFullReapply();
        
        Test.startTest();
        RE_ResponseWrapper.RVN_FormWrapper w = new RE_ResponseWrapper.RVN_FormWrapper(fresh);
        Test.stopTest();
        
        System.assertEquals('Only Street', w.currAddress);
    }
}