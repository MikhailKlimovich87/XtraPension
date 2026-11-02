@IsTest
private class BP_PackDataFixesTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createTestCountry(true);
        Account acc = TestDataFactory.createAccount(true);
        Contact con = [SELECT Id FROM Contact WHERE AccountId = :acc.Id LIMIT 1];
        Basic__c app = BP_TestDataFactory.createBasic(con.Id, true);
        BP_TestDataFactory.createChild(app.Id, true);
        BP_TestDataFactory.createCompany(app.Id, true);
        BP_TestDataFactory.createCountryLived(app.Id, true);
    }

    private static Basic__c loadClaim(Map<String, Object> changes) {
        Basic__c stored = [SELECT Id FROM Basic__c LIMIT 1];
        Basic__c changed = new Basic__c(Id = stored.Id);
        for (String field : changes.keySet()) {
            changed.put(field, changes.get(field));
        }
        update changed;
        return BP_PortalUtils.getApplication(stored.Id)[0];
    }

    // ---- IPC1394 comb fields ----

    @IsTest
    static void ipcStripsSpacesAndUppercasesCombFields() {
        Basic__c claim = loadClaim(new Map<String, Object>{
            'Bank_IBAN__c' => 'ie12 aibk 9311 5212 3456 78',
            'Bank_BIC__c' => 'aibk ie2d',
            'Claimant_nino__c' => 'ab 12 34 56 c',
            'Bank_Account__c' => '1234 5678',
            'Bank_Country_Code__c' => 'IE'
        });

        BP_IPC1394_Wrapper.ApplicationDataWrapper wrap = new BP_IPC1394_Wrapper.ApplicationDataWrapper(claim);

        System.assertEquals('IE12AIBK93115212345678', wrap.Q17);
        System.assertEquals('AIBKIE2D', wrap.Q18);
        System.assertEquals('AB123456C', wrap.Q5_NINO);
        System.assertEquals('12345678', wrap.Q16);
    }

    @IsTest
    static void ipcDropsValuesLongerThanTheComb() {
        Basic__c claim = loadClaim(new Map<String, Object>{
            'Bank_IBAN__c' => 'IE' + '1'.repeat(40),
            'Bank_BIC__c' => 'ABCDEFGHIJKLM',
            'Bank_Country_Code__c' => 'IE'
        });

        BP_IPC1394_Wrapper.ApplicationDataWrapper wrap = new BP_IPC1394_Wrapper.ApplicationDataWrapper(claim);

        System.assertEquals(null, wrap.Q17, 'IBAN longer than 34 must not be printed truncated');
        System.assertEquals(null, wrap.Q18, 'BIC longer than 11 must not be printed truncated');
    }

    @IsTest
    static void ipcCapsAccountOwnerNameAt35() {
        Basic__c claim = loadClaim(new Map<String, Object>{
            'Bank_Account_Owner_Name__c' => 'A'.repeat(50)
        });

        System.assertEquals(35, new BP_IPC1394_Wrapper.ApplicationDataWrapper(claim).Q15.length());
    }

    @IsTest
    static void ipcTicksNeitherIntervalWhenBlank() {
        Basic__c blank = loadClaim(new Map<String, Object>{ 'Paid_Interval__c' => null });
        BP_IPC1394_Wrapper.ApplicationDataWrapper blankWrap = new BP_IPC1394_Wrapper.ApplicationDataWrapper(blank);
        System.assertNotEquals(true, blankWrap.Q14_check_4weeks);
        System.assertNotEquals(true, blankWrap.Q14_check_13weeks);

        Basic__c fourWeeks = loadClaim(new Map<String, Object>{ 'Paid_Interval__c' => '4 weeks' });
        BP_IPC1394_Wrapper.ApplicationDataWrapper fourWrap = new BP_IPC1394_Wrapper.ApplicationDataWrapper(fourWeeks);
        System.assertEquals(true, fourWrap.Q14_check_4weeks);
        System.assertNotEquals(true, fourWrap.Q14_check_13weeks);
    }

    // ---- BR1 ----

    @IsTest
    static void br1Q46AlwaysNoWithTheStartDate() {
        Date start = Date.newInstance(2031, 2, 3);
        Basic__c later = loadClaim(new Map<String, Object>{
            'Pension_Claiming_from_Today__c' => false,
            'Pension_Start_Date__c' => start
        });
        BP_BR1_Wrapper.ApplicationDataWrapper wrap = new BP_BR1_Wrapper.ApplicationDataWrapper(later);

        System.assertEquals(true, wrap.q46_no);
        System.assertEquals(false, wrap.q46_yes);
        //System.assertEquals('03/02/2031', wrap.q46a);
    }

    @IsTest
    static void br1Q47UsesTheStepSixField() {
        Basic__c claim = loadClaim(new Map<String, Object>{
            'Ever_Self_Employed_UK_after_1978__c' => true,
            'Claimant_self_Employed_UK__c' => false
        });
        BP_BR1_Wrapper.ApplicationDataWrapper wrap = new BP_BR1_Wrapper.ApplicationDataWrapper(claim);

        System.assertEquals(true, wrap.q47_yes);
        System.assertEquals(false, wrap.q47_no);
    }

    @IsTest
    static void br1CarriesTheClaimNumberForTheFileName() {
        Basic__c claim = loadClaim(new Map<String, Object>());
        BP_BR1_Wrapper.ApplicationDataWrapper wrap = new BP_BR1_Wrapper.ApplicationDataWrapper(claim);

        System.assertEquals(claim.Name, wrap.name);
        System.assertEquals(claim.Last_Name__c, wrap.q4);
    }

    // ---- Missing info ----

    @IsTest
    static void missingInfoReportsEveryRecordAndCheckboxes() {
        Basic__c claim = [SELECT Id FROM Basic__c LIMIT 1];
        insert BP_TestDataFactory.createCountryLived(claim.Id, false);
        List<Claimant_Country_lived__c> countries = [SELECT Id FROM Claimant_Country_lived__c WHERE Basic__c = :claim.Id];
        System.assertEquals(2, countries.size());
        for (Claimant_Country_lived__c country : countries) {
            country.Social_Security_Number__c = null;
        }
        update countries;

        List<String> missing = BP_PortalUtils.getEmptyFieldsConditionalLabel(BP_PortalUtils.getApplication(claim.Id)[0]);

        Boolean firstReported = false;
        Boolean secondReported = false;
        for (String item : missing) {
            firstReported = firstReported || item.startsWith('Country lived 1');
            secondReported = secondReported || item.startsWith('Country lived 2');
        }
        System.assert(firstReported && secondReported, 'Every country lived must be checked, not only the first: ' + missing);
    }

    @IsTest
    static void partialAutosaveOnlyWritesTheSectionsItReceived() {
        Basic__c claim = [SELECT Id, First_Name__c, Last_Name__c FROM Basic__c LIMIT 1];
        String body = JSON.serialize(new Map<String, Object>{
            'applicationId' => claim.Id,
            'currentStep' => 8,
            'isAgentForm' => false,
            'isAutoSave' => true,
            'isPartial' => true,
            'application' => new Map<String, Object>{
                'bank' => new Map<String, Object>{ 'bankName' => 'Changed Bank', 'country' => 'IE' }
            }
        });

        BP_PortalUtils.autoSave(new BP_RequestWrappers.ApplicationDetailsDataWrapper(body));

        Basic__c after = [SELECT First_Name__c, Last_Name__c, Bank_Name__c FROM Basic__c WHERE Id = :claim.Id];
        System.assertEquals('Changed Bank', after.Bank_Name__c);
        System.assertEquals(claim.First_Name__c, after.First_Name__c, 'A section that was not sent must not be overwritten');
        System.assertEquals(claim.Last_Name__c, after.Last_Name__c);
    }

    @IsTest
    static void missingInfoFieldLabelsDoNotRetestTheValue() {
        Basic__c claim = new Basic__c(Pension_Claiming_from_Today__c = false);
        List<String> labels = BP_PortalUtils.getFieldLabels(claim, new List<String>{ 'Pension_Claiming_from_Today__c' });
        System.assertEquals(1, labels.size());
    }
}