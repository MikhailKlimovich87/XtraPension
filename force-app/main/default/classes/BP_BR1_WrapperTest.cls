@IsTest
public class BP_BR1_WrapperTest {

    // ============================================================
    // SETUP
    // ============================================================
    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account acc = TestDataFactory.createAccount(true);
        Contact con = [
            SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1
        ];
        Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);

        // Baseline values so we can assert most fields without null-checking
        app.First_Name__c                = 'John';
        app.Claimant_Middle_Name__c      = 'Q';
        app.Last_Name__c                 = 'Smith';
        app.Claimant_title__c            = 'Mr';
        app.Claimant_nino__c             = 'AB123456C';
        app.Phone__c                     = '0700000000';
        app.Claimant_dob__c              = Date.newInstance(1980, 1, 15);
        app.Claimant_address1__c         = '1 Main Street';
        app.Claimant_address2__c         = 'Apt 2';
        app.Claimant_City__c             = 'Dublin';
        app.Eircode__c                   = 'D01 AB12';
        app.Current_Address_Abroad_Country_Name__c = 'Ireland';
        app.Current_Address_Abroad_State_Name__c   = 'Leinster';
        app.Claimant_maiden_Name__c      = 'Brown';
        app.Claimant_other_names__c      = 'Johnny';
        app.Claimant_hasNino__c          = true;
        app.Has_Nino__c                  = 'Yes';
        app.Claimant_ever_Lived_UK__c    = true;
        app.Claimant_lived_UK_From__c    = Date.newInstance(2000, 1, 1);
        app.Claimant_lived_UK_to__c      = Date.newInstance(2010, 12, 31);
        app.Claimant_worked_UK_From__c   = Date.newInstance(2001, 1, 1);
        app.Claimant_worked_UK_To__c     = Date.newInstance(2009, 12, 31);
        app.Claimant_Ever_Worked_UK__c   = true;
        app.Claimant_has_Proof_Of_UK_Work__c = true;
        app.Claimant_marital_Status__c   = 'Single';
        app.Pension_Claiming_from_Today__c = true;
        app.Ever_Self_Employed_UK_after_1978__c = false;
        app.Ever_Pay_Reduced_UK_nino__c  = false;
        app.Work_In_UK_during_2_years__c = false;
        app.Claimant_Minded_Kids__c      = false;
        app.Is_Your_Partner_Currently_Get_Pension__c = false;
        app.Claimant_nationality__c      = 'Irish';
        app.DocuSign_Date__c             = Date.newInstance(2025, 1, 1);
        update app;
    }

    private static Basic__c getBasic() {
        return [
            SELECT Id, Name,
                   Claimant_title__c, First_Name__c, Claimant_Middle_Name__c, Last_Name__c,
                   Claimant_nino__c, Has_Nino__c, Claimant_hasNino__c,
                   Phone__c, Claimant_dob__c,
                   Claimant_address1__c, Claimant_address2__c, Claimant_City__c,
                   Eircode__c, Current_Address_Abroad_Country_Name__c,
                   Current_Address_Abroad_State_Name__c,
                   Claimant_maiden_Name__c, Claimant_other_names__c,
                   Claimant_ever_Lived_UK__c, Claimant_lived_UK_From__c, Claimant_lived_UK_to__c,
                   Claimant_worked_UK_From__c, Claimant_worked_UK_To__c,
                   Claimant_Ever_Worked_UK__c, Claimant_has_Proof_Of_UK_Work__c,
                   Claimant_marital_Status__c,
                   Partner_Surname__c, Partner_First_Name__c, Partner_Other_Name__c,
                   Partner_Maiden_Name__c, Partner_Nino__c,
                   Partner_Ever_Lived_UK__c, Partner_same_as_claimant__c,
                   Partner_Address1__c, Partner_Address2__c, Partner_City__c,
                   Partner_State_Name__c, Partner_Country__c, Partner_Postcode__c,
                   Partner_DOB__c, Claimant_date_Of_Marriage__c, Claimant_date_Of_Divorce__c,
                   Claimant_date_Of_Bereavement__c,
                   Partner_State_Pension__c, Partner_Graduated_Retirement_Benefit__c,
                   Partner_Widows_Benefit__c, Partner_Bereavement_Benefit__c,
                   Claimant_State_Pension__c, Claimant_Graduated_Retirement_Benefit__c,
                   Claimant_Widows_Benefit__c, Claimant_Bereavement_Benefit__c,
                   Pension_Claiming_from_Today__c, DocuSign_Date__c,
                   Ever_Self_Employed_UK_after_1978__c, Ever_Pay_Reduced_UK_nino__c,
                   Work_In_UK_during_2_years__c,
                   Claimant_Minded_Kids__c,
                   Is_Your_Partner_Currently_Get_Pension__c, isYourPartnerCurrentlyGetPensionText__c,
                   Claimant_nationality__c,
                   Claimant_Ever_Lived_UK_Notes__c, Partner_Ever_Lived_UK_Notes__c,
                   Partner_Reference_on_Any_DWP_Letters__c,
                   Claimant_is_Waiting_Uk_Benefits_text__c, Partner_is_Waiting_Uk_Benefits_text__c,
                   Notes__c,
                   (SELECT Id, Name, Dob__c, Minded_From__c, Minded_To__c, Nino__c
                      FROM Clamant_Children__r),
                   (SELECT Id, Name, Address1__c, Address2__c, City__c, Country__c, Country_Type__c,
                           From_Date__c, To_Date__c, Postcode__c, Is_Partner__c, Is_Addresses__c
                      FROM Claimant_Companies__r),
                   (SELECT Id, Name, From_date__c, To_Date__c, Is_Live_Here_Now__c,
                           Social_Security_Number__c
                      FROM ClaimantCountrieslived__r)
            FROM Basic__c LIMIT 1
        ];
    }

    private static Basic__c getBasicWith(String fields, Id id) {
        return (Basic__c) Database.query(
            'SELECT ' + fields + ' FROM Basic__c WHERE Id = :id LIMIT 1'
        );
    }

    // ============================================================
    // TESTS — field mapping
    // ============================================================
    @IsTest
    static void testSimpleFieldMapping() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('Mr',         w.q1);
        System.assertEquals('John',       w.q2);
        System.assertEquals('Q',          w.q3);
        System.assertEquals('Smith',      w.q4);
        System.assertEquals('AB123456C',  w.q5);
        System.assertEquals('0700000000', w.q8);
        System.assertEquals('15/01/1980', w.q10);
        System.assertEquals('Irish',      w.q55);
        System.assertEquals(b.Name,       w.name);
    }

    @IsTest
    static void testAddressLine1And2Present() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('1 Main Street', w.q6a);
        System.assertEquals('Apt 2',         w.q6b);
        System.assert(w.q6c.contains('Dublin'));
        System.assert(w.q6c.contains('D01 AB12'));
        System.assertEquals('Ireland',       w.q6d);
    }

    @IsTest
    static void testAddressLine2BlankShiftsFields() {
        Basic__c b = getBasic();
        b.Claimant_address2__c = null;
        update b;

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('1 Main Street', w.q6a);
        // When address2 is blank, city+postcode+state gets pushed to q6b
        System.assert(w.q6b.contains('Dublin'));
        System.assertEquals('Ireland', w.q6c);
        System.assertEquals('',        w.q6d);
    }

    @IsTest
    static void testMaidenAndOtherNames() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('Brown, Johnny', w.q7);
    }

    @IsTest
    static void testMaidenNameBlankUsesOnlyOtherNames() {
        Basic__c b = getBasic();
        b.Claimant_maiden_Name__c = null;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('Johnny', w.q7);
    }


    // ============================================================
    // TESTS — formatDate
    // ============================================================
    @IsTest
    static void testFormatDateNullReturnsEmpty() {
        Basic__c b = getBasic();
        b.Claimant_dob__c = null;
        b.Claimant_lived_UK_From__c = null;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('', w.q10);
        System.assertEquals('', w.q16a);
    }

    @IsTest
    static void testFormatDatePadsDayAndMonth() {
        Basic__c b = getBasic();
        b.Claimant_dob__c = Date.newInstance(2005, 3, 7);
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('07/03/2005', w.q10);
    }


    // ============================================================
    // TESTS — NINO logic
    // ============================================================
    @IsTest
    static void testNinoNeverHadSetsNo() {
        Basic__c b = getBasic();
        b.Has_Nino__c = 'Never Had';
        b.Claimant_hasNino__c = false;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q5a_no);
        System.assertEquals(null, w.q5a_yes);
    }

    @IsTest
    static void testNinoForgotSetsYes() {
        Basic__c b = getBasic();
        b.Has_Nino__c = 'Forgot';
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q5a_yes);
        System.assertEquals(null, w.q5a_no);
    }

    @IsTest
    static void testNinoHasNinoFalseSetsNo() {
        Basic__c b = getBasic();
        b.Has_Nino__c = null;
        b.Claimant_hasNino__c = false;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q5a_no);
    }


    // ============================================================
    // TESTS — UK lived / worked flags
    // ============================================================
    @IsTest
    static void testEverLivedUKTrue() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q14_yes);
        System.assertEquals(false, w.q14_no);
    }

    @IsTest
    static void testEverLivedUKFalse() {
        Basic__c b = getBasic();
        b.Claimant_ever_Lived_UK__c = false;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q14_no);
        System.assertEquals(false, w.q14_yes);
    }

    @IsTest
    static void testEverWorkedUKFlags() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q18_yes);
        System.assertEquals(false, w.q18_no);
        System.assertEquals(true,  w.q19_yes);
        System.assertEquals(false, w.q19_no);
    }


    // ============================================================
    // TESTS — marital status
    // ============================================================
    @IsTest
    static void testSingleMaritalStatus() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q20_single);
        System.assertEquals(false, w.q20_married);
        // Partner block skipped
        System.assertEquals(null, w.q21);
        System.assertEquals(null, w.q27);
    }

    @IsTest
    static void testCivilPartnerMapsToMarried() {
        Basic__c b = getBasic();
        b.Claimant_marital_Status__c = 'Civil Partner';
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q20_married);
        System.assertEquals(false, w.q20_single);
    }

    @IsTest
    static void testDivorcedSetsQ32Yes() {
        Basic__c b = getBasic();
        b.Claimant_marital_Status__c = 'Divorced';
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q20_divorced);
        System.assertEquals(true, w.q32_yes);
    }

    @IsTest
    static void testWidowedSetsQ33Yes() {
        Basic__c b = getBasic();
        b.Claimant_marital_Status__c = 'Widowed';
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q20_widowed);
        System.assertEquals(true, w.q33_yes);
    }

    @IsTest
    static void testMarriedWithPartnerAddress() {
        Basic__c b = getBasic();
        b.Claimant_marital_Status__c = 'Married';
        b.Partner_Surname__c       = 'Smith';
        b.Partner_First_Name__c    = 'Anna';
        b.Partner_Other_Name__c    = 'Marie';
        b.Partner_Maiden_Name__c   = 'Brown';
        b.Partner_Nino__c          = 'AB654321C';
        b.Partner_Ever_Lived_UK__c = true;
        b.Partner_same_as_claimant__c = false;
        b.Partner_Address1__c      = 'Partner Street 1';
        b.Partner_Address2__c      = 'Flat 3';
        b.Partner_City__c          = 'Cork';
        b.Partner_State_Name__c    = 'Munster';
        b.Partner_Country__c       = 'Ireland';
        b.Partner_Postcode__c      = 'T12 XY34';
        b.Partner_DOB__c           = Date.newInstance(1985, 5, 20);
        b.Claimant_date_Of_Marriage__c = Date.newInstance(2010, 6, 1);
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('Smith',   w.q21);
        System.assertEquals('Anna Marie', w.q22);
        System.assertEquals('Brown',   w.q23);
        System.assertEquals('AB654321C', w.q24);
        System.assertEquals(true,  w.q25_yes);
        System.assertEquals(false, w.q25_no);
        System.assertEquals('Partner Street 1', w.q26a);
        System.assertEquals('Flat 3',           w.q26b);
        System.assert(w.q26c.contains('Cork'));
        System.assert(w.q26c.contains('Munster'));
        System.assert(w.q26c.contains('Ireland'));
        System.assertEquals('T12 XY34', w.q26d);
        System.assertEquals('20/05/1985', w.q27);
        System.assertEquals('01/06/2010', w.q28);
    }


    // ============================================================
    // TESTS — pension / benefits flags
    // ============================================================
    @IsTest
    static void testClaimingFromTodayTrue() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q46_yes);
        System.assertEquals(false, w.q46_no);
        System.assertEquals('01/01/2025', w.q46a);
    }

    @IsTest
    static void testClaimingFromTodayFalse() {
        Basic__c b = getBasic();
        b.Pension_Claiming_from_Today__c = false;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q46_no);
        System.assertEquals(false, w.q46_yes);
    }

    @IsTest
    static void testSelfEmployedUKSetsQ47Yes() {
        Basic__c b = getBasic();
        b.Ever_Self_Employed_UK_after_1978__c = true;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true,  w.q47_yes);
        System.assertEquals(false, w.q47_no);
    }

    @IsTest
    static void testReducedNinoAndWorkFlags() {
        Basic__c b = getBasic();
        b.Ever_Pay_Reduced_UK_nino__c = true;
        b.Work_In_UK_during_2_years__c = true;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q48_yes);
        System.assertEquals(true, w.q49_yes);
    }

    @IsTest
    static void testSingleBenefitStatePension() {
        Basic__c b = getBasic();
        b.Claimant_State_Pension__c = true;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(true, w.q51_yes);
        System.assertEquals('State Pension', w.q51a);
        System.assertEquals(true,  w.q51b_you);
        System.assertEquals(false, w.q51b_partner);
    }

    @IsTest
    static void testThreeBenefitsFillAllSlots() {
        Basic__c b = getBasic();
        b.Claimant_State_Pension__c = true;
        b.Claimant_Widows_Benefit__c = true;
        b.Claimant_Bereavement_Benefit__c = true;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertNotEquals(null, w.q51a);
        System.assertNotEquals(null, w.q51d);
        System.assertNotEquals(null, w.q51g);
    }

    // ============================================================
    // TESTS — country lived
    // ============================================================
    @IsTest
    static void testCountryLivedAustralia() {
        Basic__c b = getBasic();

        insert new Claimant_Country_lived__c(
            Basic__c = b.Id,
            Name = 'Australia',
            From_date__c = Date.newInstance(2015, 1, 1),
            To_Date__c = Date.newInstance(2020, 1, 1),
            Is_Live_Here_Now__c = false,
            Social_Security_Number__c = 'SSN-AU'
        );

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('Australia', w.q56);
        System.assert(w.q59.contains('Services Australia'));
    }

    @IsTest
    static void testCountryLivedIrelandCurrentlyLive() {
        Basic__c b = getBasic();

        insert new Claimant_Country_lived__c(
            Basic__c = b.Id,
            Name = 'Ireland',
            From_date__c = Date.newInstance(2018, 1, 1),
            To_Date__c = null,
            Is_Live_Here_Now__c = true,
            Social_Security_Number__c = 'SSN-IE'
        );

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('Ireland', w.q56);
        System.assertEquals('CURRENT', w.q57a);
        System.assertEquals(true,  w.q58_yes);
        System.assertEquals(false, w.q58_no);
        System.assert(w.q59.contains('Dept of Social Protection'));
    }


    // ============================================================
    // TESTS — notes aggregation
    // ============================================================
    @IsTest
    static void testNotesIncludeStandardBlock() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Please note:'));
        System.assert(w.q64.contains('first-time claim'));
        System.assert(w.q64.contains('XtraPension Ltd'));
    }

    @IsTest
    static void testNotesAppendClaimNotesField() {
        Basic__c b = getBasic();
        b.Notes__c = 'Extra claimant note.';
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Extra claimant note.'));
    }

    @IsTest
    static void testAdditionalInfoAggregatedIntoNotes() {
        Basic__c b = getBasic();
        b.Claimant_Ever_Lived_UK_Notes__c = 'Lived in Manchester.';
        b.Partner_Ever_Lived_UK_Notes__c  = 'Partner lived in Leeds.';
        b.Claimant_is_Waiting_Uk_Benefits_text__c = 'Waiting for pension.';
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Lived in Manchester.'));
        System.assert(w.q64.contains('Partner lived in Leeds.'));
        System.assert(w.q64.contains('Waiting for pension.'));
    }

    @IsTest
    static void testQ67AlwaysFalse() {
        Basic__c b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals(false, w.q67);
    }


    // ============================================================
    // TESTS — children notes
    // ============================================================
    @IsTest
    static void testChildrenAddNotes() {
        Basic__c b = getBasic();

        insert new Claimant_Child__c(
            Basic__c = b.Id,
            Name = 'Child One',
            Dob__c = Date.newInstance(2015, 5, 5),
            Minded_From__c = Date.newInstance(2018, 1, 1),
            Minded_To__c = Date.newInstance(2020, 1, 1),
            Nino__c = 'CH123456C'
        );

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Q53 - Additional Info'));
        System.assert(w.q64.contains('Child One'));
    }


    // ============================================================
    // TESTS — companies
    // ============================================================
    @IsTest
    static void testClaimantCompaniesFillQ18() {
        Basic__c b = getBasic();

        insert new List<Claimant_Company__c>{
            new Claimant_Company__c(
                Basic__c = b.Id, Name = 'Acme Ltd',
                Address1__c = '1 Office Rd', Address2__c = 'Suite 2',
                City__c = 'London', Country__c = 'UK', Postcode__c = 'EC1A',
                From_Date__c = Date.newInstance(2001, 1, 1),
                To_Date__c = Date.newInstance(2005, 1, 1),
                Is_Partner__c = false, Is_Addresses__c = false
            ),
            new Claimant_Company__c(
                Basic__c = b.Id, Name = 'Beta Ltd',
                Address1__c = '2 Office Rd',
                City__c = 'Leeds', Country__c = 'UK', Postcode__c = 'LS1',
                From_Date__c = Date.newInstance(2005, 1, 1),
                To_Date__c = Date.newInstance(2010, 1, 1),
                Is_Partner__c = false, Is_Addresses__c = false
            )
        };

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q18a.contains('Acme Ltd'));
        System.assert(w.q18h.contains('Beta Ltd'));
    }

    @IsTest
    static void testPartnerCompaniesFillQ50() {
        Basic__c b = getBasic();

        insert new Claimant_Company__c(
            Basic__c = b.Id, Name = 'Partner Co',
            Address1__c = '3 Partner Rd', Address2__c = 'Flat 1',
            City__c = 'Cork', Country__c = 'Ireland', Postcode__c = 'T12',
            From_Date__c = Date.newInstance(2010, 1, 1),
            To_Date__c = Date.newInstance(2015, 1, 1),
            Is_Partner__c = true, Is_Addresses__c = false
        );

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('3 Partner Rd', w.q50a);
        System.assertEquals('Flat 1',       w.q50b);
        System.assert(w.q50c.contains('Cork'));
        System.assert(w.q50c.contains('Ireland'));
    }

    @IsTest
    static void testAddressCompaniesFillQ15() {
        Basic__c b = getBasic();

        insert new Claimant_Company__c(
            Basic__c = b.Id, Name = 'Old Address',
            Address1__c = '10 Old St', Address2__c = 'Apt 9',
            City__c = 'Galway', Country__c = 'Ireland', Postcode__c = 'H91',
            From_Date__c = Date.newInstance(1995, 1, 1),
            To_Date__c = Date.newInstance(2000, 1, 1),
            Is_Partner__c = false, Is_Addresses__c = true
        );

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assertEquals('10 Old St', w.q15a);
        System.assertEquals('Apt 9',     w.q15b);
        System.assert(w.q15c.contains('Galway'));
        System.assert(w.q15c.contains('Ireland'));
    }

    @IsTest
    static void testMoreThanTwoCompaniesGoesToNotes() {
        Basic__c b = getBasic();

        List<Claimant_Company__c> many = new List<Claimant_Company__c>();
        for (Integer i = 1; i <= 4; i++) {
            many.add(new Claimant_Company__c(
                Basic__c = b.Id, Name = 'Company ' + i,
                Address1__c = i + ' Road', City__c = 'City ' + i,
                Country__c = 'UK', Postcode__c = 'PC' + i,
                From_Date__c = Date.newInstance(2000 + i, 1, 1),
                To_Date__c = Date.newInstance(2005 + i, 1, 1),
                Is_Partner__c = false, Is_Addresses__c = false
            ));
        }
        insert many;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Q18 - Additional Info'));
        System.assert(w.q64.contains('Employer 3'));
        System.assert(w.q64.contains('Employer 4'));
    }


    // ============================================================
    // TESTS — cityWithCountry edge cases
    // ============================================================
    @IsTest
    static void testCompanyWithNoCityStillPrintsCountry() {
        Basic__c b = getBasic();

        insert new Claimant_Company__c(
            Basic__c = b.Id, Name = 'NoCity Co',
            Address1__c = '5 Road', Address2__c = 'Suite 1',
            City__c = null, Country__c = 'UK', Postcode__c = 'AB1',
            From_Date__c = Date.newInstance(2000, 1, 1),
            To_Date__c = Date.newInstance(2005, 1, 1),
            Is_Partner__c = false, Is_Addresses__c = false
        );

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        // q18c should be 'UK' — not 'null, UK'
        System.assertEquals('UK', w.q18c);
    }


    // ============================================================
    // TESTS — country lived >2 goes to notes
    // ============================================================
    @IsTest
    static void testMoreThanTwoCountriesGoesToNotes() {
        Basic__c b = getBasic();

        insert new List<Claimant_Country_lived__c>{
            new Claimant_Country_lived__c(
                Basic__c = b.Id, Name = 'Ireland',
                From_date__c = Date.newInstance(2010, 1, 1),
                To_Date__c = Date.newInstance(2015, 1, 1),
                Is_Live_Here_Now__c = false),
            new Claimant_Country_lived__c(
                Basic__c = b.Id, Name = 'UK',
                From_date__c = Date.newInstance(2015, 1, 1),
                To_Date__c = Date.newInstance(2018, 1, 1),
                Is_Live_Here_Now__c = false),
            new Claimant_Country_lived__c(
                Basic__c = b.Id, Name = 'France',
                From_date__c = Date.newInstance(2018, 1, 1),
                To_Date__c = Date.newInstance(2020, 1, 1),
                Is_Live_Here_Now__c = false)
        };

        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Q55 - Additional Info'));
        System.assert(w.q64.contains('France'));
    }

    @IsTest
    static void testMoreThanThreeBenefitsGoesToNotes() {
        Basic__c b = getBasic();
        b.Claimant_State_Pension__c = true;
        b.Claimant_Graduated_Retirement_Benefit__c = true;
        b.Claimant_Widows_Benefit__c = true;
        b.Claimant_Bereavement_Benefit__c = true;
        update b;
        b = getBasic();

        Test.startTest();
        BP_BR1_Wrapper.ApplicationDataWrapper w =
            new BP_BR1_Wrapper.ApplicationDataWrapper(b);
        Test.stopTest();

        System.assert(w.q64.contains('Q51 - Additional Info'));
        System.assert(w.q64.contains('Bereavement Benefit'));
    }


    // ============================================================
    // TESTS — BenefitWrapper inner class
    // ============================================================
    @IsTest
    static void testBenefitWrapperStoresValues() {
        Test.startTest();
        BP_BR1_Wrapper.BenefitWrapper bw =
            new BP_BR1_Wrapper.BenefitWrapper('Test Benefit', true, false);
        Test.stopTest();

        System.assertEquals('Test Benefit', bw.name);
        System.assertEquals(true,  bw.you);
        System.assertEquals(false, bw.partner);
    }
}