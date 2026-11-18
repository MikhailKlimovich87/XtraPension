/**
 * Claims form fixes of 10/11/2026 (first real claim, C05500): lists kept by the autosave, countries without a number
 * and employers without dates kept, Send to Validation stage from Missing Info, HM Forces (BR1 Q17), employer rule,
 * Stage 1 pack never sent twice / never for a test claim, the Claim page button and the validation agent on the
 * internal sale email. 11/11/2026: notes for validation (field + one Note) and "Wants a helper?".
 */
@IsTest
private class XpClaimFormFixesTest {

    private static Integer people = 0;

    private static Basic__c claim(Map<String, Object> fields) {
        people++;
        // One contact per claim (the org's duplicate rule refuses a second Snow with the same email)
        Contact c = new Contact(LastName = 'Snow' + people, Email = 'john.snow' + people + '@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'john.snow@example.com';
        for (String f : fields.keySet()) b.put(f, fields.get(f));
        insert b;
        return b;
    }

    // Everything Missing Info asks for, so the claim is complete
    private static Map<String, Object> completeFields() {
        return new Map<String, Object>{
            'Claimant_dob__c' => Date.newInstance(1950, 1, 26),
            'Claimant_hasNino__c' => true, 'Claimant_nino__c' => 'WK055184A',
            'Current_Address_Abroad_Country_Name__c' => 'Ireland', 'Current_Address_Abroad_Country__c' => 'IE',
            'Claimant_ever_Lived_UK__c' => true,
            'Claimant_lived_UK_From__c' => Date.newInstance(1974, 9, 15), 'Claimant_lived_UK_to__c' => Date.newInstance(1975, 3, 31),
            'Claimant_Ever_Worked_UK__c' => false,
            'Pension_Claiming_from_Today__c' => true,
            'Bank_Country__c' => 'Ireland', 'Bank_Country_Code__c' => 'IE',
            'Bank_IBAN__c' => 'IE29AIBK93115212345678', 'Bank_BIC__c' => 'AIBKIE2D',
            'Bank_Account_Owner_Name__c' => 'Ross Cooper', 'Owns_This_Account__c' => 'Claimant',
            'Bank_Name__c' => 'AIB', 'Bank_Address__c' => '1 Main St', 'Bank_City__c' => 'Dublin', 'Bank_Post_Code__c' => 'D04',
            // no helper at all (optional); the factory's half helper would be asked for
            'Friend_Phone__c' => null, 'Relationship__c' => null
        };
    }

    private static void addCountry(Id claimId) {
        insert new Claimant_Country_lived__c(Basic__c = claimId, Name = 'Ireland', Country_Type__c = 'IE',
            From_date__c = Date.newInstance(1975, 4, 1), Is_Live_Here_Now__c = true, Social_Security_Number__c = '2845261K');
    }

    // What the form sends: every section with its defaults (all the Yes/No answers set), plus the test's values
    private static Map<String, Object> defaults() {
        return (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(new BP_RequestWrappers.ApplicationFullWrapper()));
    }

    private static Map<String, Object> section(String name, Map<String, Object> values) {
        Map<String, Object> base = (Map<String, Object>) defaults().get(name);
        base = base == null ? new Map<String, Object>() : base;
        base.putAll(values);
        return base;
    }

    private static BP_RequestWrappers.ApplicationDetailsDataWrapper payload(Id claimId, Map<String, Object> application, Boolean partial, Integer step) {
        Map<String, Object> body = new Map<String, Object>{
            'applicationId' => claimId, 'currentStep' => step, 'isAgentForm' => true,
            'isAutoSave' => partial, 'isPartial' => partial, 'application' => application
        };
        return new BP_RequestWrappers.ApplicationDetailsDataWrapper(JSON.serialize(body));
    }

    // ---------------------------------------------------------------- lists

    @IsTest
    static void autosaveKeepsCountriesTypedOnTheSummary() {
        Basic__c b = claim(new Map<String, Object>());
        Map<String, Object> claimant = section('claimant', new Map<String, Object>{
            'firstName' => 'Ross', 'everWorkedUK' => true,
            'countriesLived' => new List<Object>{
                new Map<String, Object>{ 'country' => 'IE', 'socialSecurityNumber' => '2845261K', 'fromDate' => '1989-01-01T00:00:00.000Z', 'isLiveHereNow' => true },
                new Map<String, Object>{ 'country' => 'BE', 'fromDate' => '1989-06-01T00:00:00.000Z', 'toDate' => '1991-12-31T00:00:00.000Z', 'isLiveHereNow' => false },
                new Map<String, Object>{ 'country' => '' }
            },
            'ukCompanies' => new List<Object>{ new Map<String, Object>{ 'name' => 'Ford', 'country' => 'GBR' } }
        });
        Test.startTest();
        BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{ 'claimant' => claimant }, true, 9));
        Test.stopTest();
        List<Claimant_Country_lived__c> countries = [SELECT Name, Social_Security_Number__c, To_Date__c, Is_Live_Here_Now__c FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id ORDER BY Country_Type__c];
        System.assertEquals(2, countries.size(), 'both countries, the empty row dropped');
        System.assertEquals(null, countries[0].Social_Security_Number__c, 'Belgium kept without a number');
        System.assertEquals(Date.newInstance(1991, 12, 31), countries[0].To_Date__c);
        System.assertEquals(null, countries[1].To_Date__c, 'living there now: no end date');
        List<Claimant_Company__c> employers = [SELECT Name, From_Date__c, isFullForm__c FROM Claimant_Company__c WHERE Basic__c = :b.Id];
        System.assertEquals(1, employers.size());
        System.assertEquals(null, employers[0].From_Date__c, 'employer kept without dates');
        Basic__c after = [SELECT Ever_Work_UK_approved__c FROM Basic__c WHERE Id = :b.Id];
        System.assert(after.Ever_Work_UK_approved__c, 'a Yes/No given on the Summary sticks');
    }

    @IsTest
    static void emptyListsNeverWipeWhatTheClaimHas() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true });
        addCountry(b.Id);
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Short form employer', isFullForm__c = false);
        insert new Claimant_Child__c(Basic__c = b.Id, Name = 'Ann');
        insert new Claimant_UK_Property__c(Claim__c = b.Id, Name = 'Leeds', City__c = 'Leeds');
        Map<String, Object> claimant = section('claimant', new Map<String, Object>{
            'everWorkedUK' => true,
            'countriesLived' => new List<Object>{ new Map<String, Object>{ 'country' => '' } },
            'ukCompanies' => new List<Object>{ new Map<String, Object>{ 'name' => '' } },
            'children' => new List<Object>()
        });
        Map<String, Object> other = new Map<String, Object>{ 'UkProperties' => new List<Object>() };
        BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{ 'claimant' => claimant, 'otherInformation' => other }, true, 9));
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Child__c WHERE Basic__c = :b.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_UK_Property__c WHERE Claim__c = :b.Id]);
    }

    @IsTest
    static void autosaveWithoutTheClaimantSectionLeavesTheLists() {
        Basic__c b = claim(new Map<String, Object>());
        addCountry(b.Id);
        BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{ 'bank' => new Map<String, Object>{ 'bankName' => 'AIB' } }, true, 9));
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id]);
    }

    @IsTest
    static void namedEmployersReplaceEveryClaimantEmployerButNotAddressesOrSpouse() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Old', isFullForm__c = false);
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Addresses__c = true);
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Husband job', Is_Partner__c = true);
        Map<String, Object> claimant = new Map<String, Object>{
            'everWorkedUK' => true,
            'ukCompanies' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Old', 'fromDate' => '1974-09-15T00:00:00.000Z', 'toDate' => '1975-03-31T00:00:00.000Z', 'country' => 'GBR' },
                new Map<String, Object>{ 'name' => 'New', 'country' => 'GBR' }
            }
        };
        BP_PortalUtils.createNewClaimantRelation(payload(b.Id, new Map<String, Object>{ 'claimant' => claimant }, false, 2));
        Set<String> names = new Set<String>();
        for (Claimant_Company__c co : [SELECT Name FROM Claimant_Company__c WHERE Basic__c = :b.Id]) names.add(co.Name);
        System.assertEquals(new Set<String>{ 'Old', 'New', 'United Kingdom', 'Husband job' }, names, 'no duplicate "Old"');
        System.assertEquals(4, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id]);
    }

    @IsTest
    static void formResponseListsOnlyTheClaimantsEmployersAndHmForces() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_HM_Forces__c' => true, 'Claimant_HM_Forces_Service__c' => 'RAF',
            'Claimant_HM_Forces_Enlisted__c' => Date.newInstance(1968, 1, 2) });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Ford');
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Addresses__c = true);
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Husband job', Is_Partner__c = true);
        BP_ResponseWrappers.ApplicationDataWrapper w = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(1, w.claimant.ukCompanies.size());
        System.assertEquals(true, w.claimant.hmForces);
        System.assertEquals('RAF', w.claimant.hmForcesService);
        System.assert(w.claimant.hmForcesEnlisted.startsWith('1968-01-02'));
    }

    // ---------------------------------------------------------------- HM Forces + extras

    @IsTest
    static void hmForcesFromTheFormAndOnlyWhenSent() {
        Basic__c target = new Basic__c(Claimant_HM_Forces__c = true, Claimant_HM_Forces_Service__c = 'Army');
        BP_RequestWrappers.ClaimantWrapper notAsked = new BP_RequestWrappers.ClaimantWrapper(JSON.serialize(new Map<String, Object>{ 'firstName' => 'Ross' }));
        BP_PortalUtils.putHmForces(target, notAsked);
        System.assertEquals('Army', target.Claimant_HM_Forces_Service__c, 'a form that does not ask leaves the Claim page value');

        BP_RequestWrappers.ClaimantWrapper served = new BP_RequestWrappers.ClaimantWrapper(JSON.serialize(new Map<String, Object>{
            'hmForces' => true, 'hmForcesService' => 'raf', 'hmForcesEnlisted' => '1968-01-02T00:00:00.000Z',
            'hmForcesDischarged' => '1972-05-06', 'hmForcesDischargedWhere' => 'Aldershot', 'hmForcesRegiment' => 'RAF Regiment',
            'hmForcesServiceNumber' => '123', 'hmForcesRank' => 'Corporal', 'everWorkedUKuseSameDates' => true, 'everWorkedUK' => false }));
        Basic__c t2 = new Basic__c();
        BP_PortalUtils.putClaimantExtras(t2, served);
        System.assertEquals('RAF', t2.Claimant_HM_Forces_Service__c);
        System.assertEquals(Date.newInstance(1972, 5, 6), t2.Claimant_HM_Forces_Discharged__c);
        System.assertEquals('Corporal', t2.Claimant_HM_Forces_Rank__c);
        System.assertEquals(true, t2.Ever_Worked_UK_Use_Same_Dates__c);
        System.assertEquals(true, t2.Ever_Work_UK_approved__c);

        BP_RequestWrappers.ClaimantWrapper odd = new BP_RequestWrappers.ClaimantWrapper(JSON.serialize(new Map<String, Object>{ 'hmForces' => true, 'hmForcesService' => 'Marines' }));
        Basic__c t3 = new Basic__c();
        BP_PortalUtils.putHmForces(t3, odd);
        System.assertEquals(null, t3.Claimant_HM_Forces_Service__c, 'a value off the picklist is left blank, not a failed save');

        BP_RequestWrappers.ClaimantWrapper no = new BP_RequestWrappers.ClaimantWrapper(JSON.serialize(new Map<String, Object>{ 'hmForces' => false, 'hmForcesRank' => 'x' }));
        Basic__c t4 = new Basic__c();
        BP_PortalUtils.putHmForces(t4, no);
        System.assertEquals(false, t4.Claimant_HM_Forces__c);
        System.assertEquals(null, t4.Claimant_HM_Forces_Rank__c);
    }

    @IsTest
    static void blankCountryCodeIsNotAshmoreIslands() {
        System.assertEquals(null, BP_PortalUtils.countryName(null));
        System.assertEquals(null, BP_PortalUtils.countryName(''));
    }

    @IsTest
    static void br1PrintsHmForcesAndTheTwoLongestJobs() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true, 'Claimant_HM_Forces__c' => true,
            'Claimant_HM_Forces_Service__c' => 'Navy', 'Claimant_HM_Forces_Enlisted__c' => Date.newInstance(1968, 1, 2),
            'Claimant_HM_Forces_Discharged__c' => Date.newInstance(1972, 5, 6), 'Claimant_HM_Forces_Rank__c' => 'Able Seaman' });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'First', From_Date__c = Date.newInstance(1965, 1, 1), To_Date__c = Date.newInstance(1967, 1, 1));
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Tiny', From_Date__c = Date.newInstance(1968, 1, 1), To_Date__c = Date.newInstance(1968, 2, 1));
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'No dates');
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Long', From_Date__c = Date.newInstance(1970, 1, 1), To_Date__c = Date.newInstance(1979, 1, 1));
        BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(true, w.q17_yes);
        System.assertEquals(false, w.q17_no);
        System.assertEquals(true, w.q17b);
        System.assertEquals(false, w.q17a);
        System.assertEquals('02/01/1968', w.q17d);
        System.assertEquals('Able Seaman', w.q17i);
        // The two longest in the two slots, in their own order; Tiny and No dates go to Other information
        System.assert(w.q18a.startsWith('First'), w.q18a);
        System.assert(w.q18h.startsWith('Long'), w.q18h);
        System.assert(w.q64.contains('Tiny') && w.q64.contains('No dates'), 'the others go to Other information');

    }

    @IsTest
    static void br1SaysNoForACountryWhereNiWasPaidInTheUk() {
        Basic__c b = claim(new Map<String, Object>());
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Ireland', Country_Type__c = 'IE', From_date__c = Date.newInstance(1975, 4, 1), To_Date__c = Date.newInstance(1989, 5, 31), Social_Security_Number__c = '2845261K');
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Belgium', Country_Type__c = 'BE', From_date__c = Date.newInstance(1989, 6, 1), To_Date__c = Date.newInstance(1991, 12, 31), Social_Security_Number__c = 'N/A');
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'France', Country_Type__c = 'FR', From_date__c = Date.newInstance(1992, 1, 1), Is_Live_Here_Now__c = true, Social_Security_Number__c = 'n/a');
        BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(true, w.q58_yes, 'a real number: paid there');
        System.assertEquals(false, w.q58_no);
        System.assertEquals(false, w.q62_yes, 'N/A: NI paid in the UK');
        System.assertEquals(true, w.q62_no);
        System.assertEquals('N/A', w.q62a);
        System.assert(w.q64.contains('that country? - No, n/a'), w.q64);
    }

    // ---------------------------------------------------------------- the devs' fields of 11/11/2026

    @IsTest
    static void longFormSavesAndReturnsTheSpouseEmployers() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Own job');
        // The husband's employer from the Short Form, sent back by the form: replaced, not doubled
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Ford', Is_Partner__c = true);
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Partner__c = true, Is_Addresses__c = true);
        Map<String, Object> partner = section('partner', new Map<String, Object>{
            'claimingUKPension' => true,
            'ukCompanies' => new List<Object>{
                new Map<String, Object>{ 'name' => 'Ford', 'city' => 'Dagenham', 'fromDate' => '1960-01-01' },
                new Map<String, Object>{ 'name' => 'Vauxhall' },
                new Map<String, Object>{ 'name' => '' }
            }
        });
        BP_PortalUtils.saveListsFromAutosave(payload(b.Id, new Map<String, Object>{ 'partner' => partner }, true, 9));
        List<Claimant_Company__c> rows = [SELECT Name, City__c, isFullForm__c FROM Claimant_Company__c
                                          WHERE Basic__c = :b.Id AND Is_Partner__c = true AND Is_Addresses__c = false ORDER BY Name];
        System.assertEquals(2, rows.size(), 'Ford replaced, Vauxhall kept without dates, the blank row left out');
        System.assertEquals('Dagenham', rows[0].City__c);
        System.assertEquals(true, rows[1].isFullForm__c);
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Is_Partner__c = false AND Name = 'Own job']);
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Is_Addresses__c = true], 'address untouched');
        // The form reads them back under the spouse, and the claimant's list keeps only the claimant's own
        BP_ResponseWrappers.ApplicationDataWrapper r = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(2, r.partner.ukCompanies.size());
        System.assertEquals(1, r.claimant.ukCompanies.size());
        // A form that sends the spouse's list empty (the box ticked off) deletes nothing
        BP_PortalUtils.saveListsFromAutosave(payload(b.Id, new Map<String, Object>{
            'partner' => section('partner', new Map<String, Object>{ 'claimingUKPension' => false, 'ukCompanies' => new List<Object>() }) }, true, 9));
        System.assertEquals(2, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Is_Partner__c = true AND Is_Addresses__c = false]);
    }

    @IsTest
    static void shortFormKeepsTheWifeOnAUkPension() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'C' });
        String body = JSON.serialize(new Map<String, Object>{
            'applicationId' => b.Id,
            'application' => new Map<String, Object>{
                'track' => 'C',
                'client' => new Map<String, Object>{ 'firstName' => 'Mary', 'lastName' => 'Snow', 'email' => 'john.snow@example.com', 'maritalStatus' => 'Married', 'everLivedUK' => true },
                'trackC' => new Map<String, Object>{
                    'wifeGettinStatePensionNow' => true,
                    'sameAddress' => true, 'wifeHasNino' => 'Yes', 'wifeNino' => 'AB123456C',
                    'employers' => new List<Object>{ new Map<String, Object>{ 'name' => 'Marks and Spencer', 'country' => 'GB' } }
                }
            }
        });
        BP_RequestWrappers.ShortApplicationDataWrapper wrapper = new BP_RequestWrappers.ShortApplicationDataWrapper(body);
        System.assertEquals(true, wrapper.application.trackC.wifeGettinStatePensionNow);
        BP_PortalUtils.autoSaveShort(wrapper);
        System.assertEquals(true, [SELECT Partner_State_Pension__c FROM Basic__c WHERE Id = :b.Id].Partner_State_Pension__c);
        // The Save keeps the list too (11/11/2026 17h13); Finish then rebuilds it from the form
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Saved_By_Short_Form__c = true]);
        BP_PortalUtils.deleteOldEnvelopeClaimantRelation(b.Id);
        BP_PortalUtils.createNewClaimantRelationTrackC(wrapper);
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Is_Partner__c = true AND Name = 'Marks and Spencer'],
            'the wife\'s employer is kept without dates');
        BP_ResponseWrappers.ShortApplicationDataWrapper r = new BP_ResponseWrappers.ShortApplicationDataWrapper(BP_PortalUtils.getEnvApplication(b.Id));
        System.assertEquals(true, r.trackC.wifeGettinStatePensionNow, 'the Short Form shows the answer again');
        // Missing Info: the wife is on a UK pension and one of her employers is listed, so nothing is asked about them
        System.assert(!texts(b.Id).contains(', UK employers: none listed'), texts(b.Id));
    }

    // ---------------------------------------------------------------- audit of 11/11/2026

    @IsTest
    static void aSentFormReopensOnTheSummary() {
        System.assertEquals(9, BP_PortalUtils.outputCurrentStep('Review'), 'not the empty step 10');
        System.assertEquals('Review', BP_PortalUtils.currentStep(null, 9));
    }

    @IsTest
    static void sendKeepsAListTheFormSentEmpty() {
        Basic__c b = claim(new Map<String, Object>());
        insert new Claimant_UK_Property__c(Claim__c = b.Id, Address__c = '1 High St', City__c = 'Leeds');
        addCountry(b.Id);
        // The form swapped the loaded property for one blank row and sent no countries
        Map<String, Object> app = new Map<String, Object>{
            'claimant' => section('claimant', new Map<String, Object>{ 'countriesLived' => new List<Object>() }),
            'otherInformation' => section('otherInformation', new Map<String, Object>{
                'UkProperties' => new List<Object>{ new Map<String, Object>{ 'address1' => '', 'city' => '', 'postcode' => '' } } })
        };
        BP_PortalUtils.deleteListsBeingReplaced(payload(b.Id, app, false, 9));
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_UK_Property__c WHERE Claim__c = :b.Id], 'property kept');
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id], 'country kept');
        // A real row replaces the list
        app.put('otherInformation', section('otherInformation', new Map<String, Object>{
            'UkProperties' => new List<Object>{ new Map<String, Object>{ 'address1' => '2 Low St', 'city' => 'York', 'postcode' => 'YO1' } } }));
        BP_PortalUtils.deleteListsBeingReplaced(payload(b.Id, app, false, 9));
        System.assertEquals(0, [SELECT COUNT() FROM Claimant_UK_Property__c WHERE Claim__c = :b.Id], 'old property goes, the save inserts the new one');
    }

    @IsTest
    static void autosaveSavesWhatSendSaves() {
        Basic__c b = claim(new Map<String, Object>{ 'Partner_Ever_Lived_UK__c' => true });
        BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{
            'claimant' => section('claimant', new Map<String, Object>{ 'approxYearsInUK' => 4, 'everLivedUKNotes' => 'Leeds then London' }),
            'pension' => section('pension', new Map<String, Object>{ 'everSelfEmployedUKafter1978' => true, 'workInUKduring2years' => true })
        }, true, 9));
        Basic__c after = [SELECT Approx_Years_in_UK__c, Claimant_Ever_Lived_UK_Notes__c, Ever_Self_Employed_UK_after_1978__c,
                                 Work_In_UK_during_2_years__c, Partner_Ever_Lived_UK__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(4, after.Approx_Years_in_UK__c);
        System.assertEquals('Leeds then London', after.Claimant_Ever_Lived_UK_Notes__c);
        System.assertEquals(true, after.Ever_Self_Employed_UK_after_1978__c);
        System.assertEquals(true, after.Work_In_UK_during_2_years__c);
        System.assertEquals(true, after.Partner_Ever_Lived_UK__c, 'spouse section not sent: left alone');
    }

    @IsTest
    static void aHalfGivenHelperDoesNotHoldTheClaim() {
        Map<String, Object> fields = completeFields();
        fields.put('Friend_Email__c', 'daughter@example.com');
        Basic__c b = claim(fields);
        addCountry(b.Id);
        Boolean listedAsOptional = false;
        for (BP_MissingInfo.Item i : BP_MissingInfo.check(BP_MissingInfo.load(b.Id))) {
            if (i.agentText.startsWith('Helper: ') && i.optional == true) listedAsOptional = true;
        }
        System.assert(listedAsOptional, 'the agent still sees what is missing about the helper');
        System.assert(!texts(b.Id).contains('Helper'), 'but it does not hold the claim: ' + texts(b.Id));
        System.assertEquals('Form completed', BP_PortalUtils.settleAfterSubmit(b.Id));
    }

    @IsTest
    static void aSpouseNinoFoundEndsTheTrace() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B', 'Claimant_marital_Status__c' => 'Married', 'Claimant_title__c' => 'Mrs',
            'Partner_Title__c' => 'Mr', 'Partner_Has_Nino_values__c' => 'Forgot', 'Partner_Nino__c' => 'AB123456C',
            'Partner_State_Pension__c' => false, 'Partner_Claiming_UK_Pension__c' => false });
        System.assert(!texts(b.Id).contains('Husband, UK employers'), texts(b.Id));
        update new Basic__c(Id = b.Id, Partner_Nino__c = null);
        System.assert(texts(b.Id).contains('Husband, UK employers: none listed'), texts(b.Id));
    }

    @IsTest
    static void theShortFormShowsTheValidationAgent() {
        Basic__c b = claim(new Map<String, Object>{ 'Validation_Agent__c' => 'Sean B' });
        Basic__c saved = [SELECT Validation_Agent_Name__c FROM Basic__c WHERE Id = :b.Id];
        BP_ResponseWrappers.ShortApplicationDataWrapper r = new BP_ResponseWrappers.ShortApplicationDataWrapper(BP_PortalUtils.getEnvApplication(b.Id));
        System.assert(String.isNotBlank(r.agent), 'the last page reads application.agent');
        System.assertEquals(saved.Validation_Agent_Name__c, r.agent);
    }

    // ---------------------------------------------------------------- Missing Info + Send to Validation

    @IsTest
    static void missingInfoAsksForEmployersAndForcesDetails() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true, 'Claimant_HM_Forces__c' => true });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Addresses__c = true);
        String lines = String.join(BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(b.Id))), ' | ');
        System.assert(lines.contains('UK employers: none listed'), lines);
        System.assert(lines.contains('HM Forces: service, date enlisted and date discharged'), lines);
        // Only self-employed in the UK: not asked for an employer
        Basic__c selfEmployed = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true, 'Ever_Self_Employed_UK_after_1978__c' => true });
        String se = String.join(BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(selfEmployed.Id))), ' | ');
        System.assert(!se.contains('UK employers: none listed'), se);
        // A UK home address row reads as an address
        System.assert(lines.contains('UK home address 1'), lines);
    }

    @IsTest
    static void spouseEmployersOnlyWhenNoNinoOrAlreadyOnAUkPension() {
        Map<String, Object> married = new Map<String, Object>{ 'Track__c' => 'B', 'Claimant_marital_Status__c' => 'Married',
            'Claimant_title__c' => 'Mrs', 'Partner_Title__c' => 'Mr', 'Partner_Has_Nino_values__c' => 'Yes', 'Partner_Has_Nino__c' => true,
            'Partner_Nino__c' => 'AB123456C', 'Partner_State_Pension__c' => false, 'Partner_Claiming_UK_Pension__c' => false };
        // His NINO and no UK pension: not asked (John, 11/11/2026)
        Basic__c known = claim(married);
        System.assert(!texts(known.Id).contains('UK employers: none listed'), texts(known.Id));
        // Already on a UK State Pension with his NINO on the claim: not asked either (John and Fernando, 17/11/2026)
        Map<String, Object> onPensionWithNino = married.clone();
        onPensionWithNino.put('Partner_State_Pension__c', true);
        Basic__c paidKnown = claim(onPensionWithNino);
        System.assert(!texts(paidKnown.Id).contains('UK employers: none listed'), texts(paidKnown.Id));
        Map<String, Object> longFormPension = married.clone();
        longFormPension.put('Partner_Claiming_UK_Pension__c', true);
        System.assert(!texts(claim(longFormPension).Id).contains('UK employers: none listed'));
        // On a UK State Pension and no NINO on the claim: asked, under the husband
        Map<String, Object> onPension = married.clone();
        // he has one, but it is not on the claim yet
        onPension.putAll(new Map<String, Object>{ 'Partner_State_Pension__c' => true, 'Partner_Nino__c' => null });
        Basic__c paid = claim(onPension);
        System.assert(texts(paid.Id).contains('Husband, UK employers: none listed'), texts(paid.Id));
        // One of his employers listed: no longer asked (a UK home address row does not count)
        insert new Claimant_Company__c(Basic__c = paid.Id, Name = 'United Kingdom', Is_Partner__c = true, Is_Addresses__c = true);
        System.assert(texts(paid.Id).contains('Husband, UK employers: none listed'), 'an address is not an employer');
        insert new Claimant_Company__c(Basic__c = paid.Id, Name = 'Ford', Is_Partner__c = true);
        System.assert(!texts(paid.Id).contains('UK employers: none listed'), texts(paid.Id));
        // NINO forgotten: asked
        Map<String, Object> forgot = married.clone();
        forgot.putAll(new Map<String, Object>{ 'Partner_Has_Nino_values__c' => 'Forgot', 'Partner_Has_Nino__c' => false, 'Partner_Nino__c' => null });
        System.assert(texts(claim(forgot).Id).contains('Husband, UK employers: none listed'));
        // Own record (track A): the spouse's employers are never asked
        Map<String, Object> own = onPension.clone();
        own.put('Track__c', 'A');
        System.assert(!texts(claim(own).Id).contains('Husband, UK employers'));
    }

    private static String texts(Id claimId) {
        return String.join(BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(claimId))), ' | ');
    }

    @IsTest
    static void sendWithMissingInfoGoesToPendingClient() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_IBAN__c' => null });
        Test.startTest();
        String status = BP_PortalUtils.settleAfterSubmit(b.Id);
        Test.stopTest();
        Basic__c after = [SELECT Status__c, Missing_Info__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Pending Client', status);
        System.assertEquals('Pending Client', after.Status__c);
        System.assertNotEquals(BP_MissingInfo.COMPLETE, after.Missing_Info__c);
    }

    @IsTest
    static void completeSendGoesToFormCompleted() {
        Basic__c b = claim(completeFields());
        addCountry(b.Id);
        List<String> left = BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(b.Id)));
        System.assert(left.isEmpty(), 'test claim should be complete: ' + String.join(left, ' | '));
        System.assertEquals('Form completed', BP_PortalUtils.settleAfterSubmit(b.Id));
        System.assertEquals(BP_MissingInfo.COMPLETE, [SELECT Missing_Info__c FROM Basic__c WHERE Id = :b.Id].Missing_Info__c);
    }

    @IsTest
    static void summarySubmitUsesTheMissingInfoRule() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_IBAN__c' => null });
        BP_PortalApplicationHelper.runSubmitInTests = true;
        Map<String, Object> application = defaults();
        application.put('agent', 'Becky');
        application.put('claimant', section('claimant', new Map<String, Object>{ 'firstName' => 'John', 'surname' => 'Snow', 'country' => 'IE', 'everWorkedUK' => false, 'everLivedUK' => false }));
        application.put('pension', section('pension', new Map<String, Object>{ 'claimingFromToday' => true }));
        application.put('otherInformation', new Map<String, Object>{ 'isAccountant' => false });
        Test.startTest();
        Map<String, Object> result = BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, application, false, 9));
        Test.stopTest();
        System.assertEquals('success', result.get('status'), String.valueOf(result));
        Basic__c after = [SELECT Status__c, Bank_Country__c, Accountant_Country_Name__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Pending Client', after.Status__c);
        System.assertEquals(null, after.Bank_Country__c, 'no country chosen = blank, not Ashmore and Cartier Islands');
        System.assertEquals(null, after.Accountant_Country_Name__c);
    }

    @IsTest
    static void claimPageButtonPreviewsAndSends() {
        Basic__c b = claim(new Map<String, Object>{ 'Bank_IBAN__c' => null });
        XpClaimSendToValidation.State s = XpClaimSendToValidation.preview(b.Id);
        System.assert(s.allowed);
        System.assertEquals(false, s.complete);
        System.assertEquals('Pending Client', s.nextStatus);
        System.assertNotEquals(null, s.validationAgent, 'the trigger picked an agent');
        XpClaimSendToValidation.State sent = XpClaimSendToValidation.send(b.Id);
        System.assertEquals('Pending Client', sent.nextStatus);
        System.assertEquals('Pending Client', [SELECT Status__c FROM Basic__c WHERE Id = :b.Id].Status__c);
        // From Pending Client it can be sent again (the client sent the rest)
        System.assert(XpClaimSendToValidation.preview(b.Id).allowed);
    }

    @IsTest
    static void claimPageButtonIsBlockedAfterValidation() {
        Basic__c b = claim(new Map<String, Object>{ 'Status__c' => 'Agent Check' });
        System.assertEquals(false, XpClaimSendToValidation.preview(b.Id).allowed);
        Boolean refused = false;
        try {
            XpClaimSendToValidation.send(b.Id);
        } catch (AuraHandledException e) {
            refused = true;
        }
        System.assert(refused);
    }

    // ---------------------------------------------------------------- audit of 10/11/2026

    @IsTest
    static void spouseCountriesNeverReachTheClaimantsList() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_marital_Status__c' => 'Married' });
        addCountry(b.Id);
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Spain', Country_Type__c = 'ES', Is_Partner__c = true);
        BP_ResponseWrappers.ApplicationDataWrapper w = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(1, w.claimant.countriesLived.size(), 'only the claimant own country');
        System.assertEquals('IE', w.claimant.countriesLived[0].country);
    }

    @IsTest
    static void aFormLeftOpenKeepsRowsAddedOnTheClaimPage() {
        Basic__c b = claim(new Map<String, Object>());
        addCountry(b.Id); // Ireland, added on the Claim page (not by the form)
        // The form, opened before, sends France; a minute later the agent corrects it to Belgium
        BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{ 'claimant' => section('claimant', new Map<String, Object>{
            'countriesLived' => new List<Object>{ new Map<String, Object>{ 'country' => 'FR', 'isLiveHereNow' => false } } }) }, true, 9));
        BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{ 'claimant' => section('claimant', new Map<String, Object>{
            'countriesLived' => new List<Object>{ new Map<String, Object>{ 'country' => 'BE', 'isLiveHereNow' => false } } }) }, true, 9));
        Set<String> codes = new Set<String>();
        for (Claimant_Country_lived__c c : [SELECT Country_Type__c FROM Claimant_Country_lived__c WHERE Basic__c = :b.Id]) codes.add(c.Country_Type__c);
        System.assertEquals(new Set<String>{ 'IE', 'BE' }, codes, 'Claim page row kept, the form own France replaced by Belgium');
    }

    @IsTest
    static void aFailedListSaveLeavesEverythingAsItWas() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Old', isFullForm__c = true);
        Map<String, Object> claimant = section('claimant', new Map<String, Object>{ 'firstName' => 'Changed', 'everWorkedUK' => true,
            'ukCompanies' => new List<Object>{ new Map<String, Object>{ 'name' => 'X'.repeat(300) } } });
        Boolean failed = false;
        try {
            BP_PortalUtils.autoSave(payload(b.Id, new Map<String, Object>{ 'claimant' => claimant }, true, 9));
        } catch (Exception e) {
            failed = true;
        }
        System.assert(failed, 'a 300-character employer name cannot be saved');
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Name = 'Old'], 'old rows not deleted');
        System.assertEquals('John', [SELECT First_Name__c FROM Basic__c WHERE Id = :b.Id].First_Name__c, 'nothing half saved');
    }

    @IsTest
    static void pendingClientWithoutDocumentsIsNotBuilt() {
        Basic__c pending = claim(new Map<String, Object>{ 'Status__c' => 'Pending Client' });
        Basic__c completed = claim(new Map<String, Object>{ 'Status__c' => 'Form completed' });
        System.assert(new BP_RegeneratePackQueueable(pending.Id).waitsForSend());
        System.assert(!new BP_RegeneratePackQueueable(completed.Id).waitsForSend());
        insert new ContentVersion(Title = 'John Snow_C1_D5_IPCBR1_Wet_Signature', PathOnClient = 'w.pdf', VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = pending.Id);
        System.assert(new BP_RegeneratePackQueueable(pending.Id).waitsForSend(), 'the Short Form signature page is not the BR1');
        insert new ContentVersion(Title = 'John Snow_C1_IPCBR1', PathOnClient = 'x.pdf', VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = pending.Id);
        System.assert(!new BP_RegeneratePackQueueable(pending.Id).waitsForSend(), 'documents exist (a voided DocuSign): regenerate');
    }

    @IsTest
    static void workedInUkChangedOnTheClaimCountsAsAnswered() {
        Basic__c b = claim(new Map<String, Object>{ 'Claimant_Ever_Worked_UK__c' => true });
        System.assert(![SELECT Ever_Work_UK_approved__c FROM Basic__c WHERE Id = :b.Id].Ever_Work_UK_approved__c);
        update new Basic__c(Id = b.Id, Claimant_Ever_Worked_UK__c = false);
        System.assert([SELECT Ever_Work_UK_approved__c FROM Basic__c WHERE Id = :b.Id].Ever_Work_UK_approved__c);
    }

    @IsTest
    static void agentsDocumentsAreBuiltThroughTheEvent() {
        // Pending Client without documents: the regeneration the event queues stops at once (no callouts in the test)
        Basic__c b = claim(new Map<String, Object>{ 'Status__c' => 'Pending Client' });
        XpClaimDocs.forceEvent = true;
        Test.startTest();
        System.assert(XpClaimDocs.request(b.Id, XpClaimDocs.REGENERATE), 'published');
        System.assert(!XpClaimDocs.request(null, XpClaimDocs.REGENERATE));
        Test.getEventBus().deliver();
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'BP_RegeneratePackQueueable'], 'the trigger queued the job');
        XpClaimDocs.forceEvent = false;
        System.assert(BasicTriggerHandler.queuePackRegeneration(b.Id), 'an admin queues it directly');
    }

    // ---------------------------------------------------------------- Stage 1 pack + test claims

    private static void addStage1Files(Id claimId) {
        List<ContentVersion> files = new List<ContentVersion>();
        for (String t : new List<String>{ 'X_IPC1394_Wet_Signature', 'X_IPCBR1_Wet_Signature', 'X_Pink', 'X_Yellow', 'X_DWP_Authority', 'X_IPC1394_Payment_Notes' }) {
            files.add(new ContentVersion(Title = t, PathOnClient = t + '.pdf', VersionData = Blob.valueOf('pdf'), FirstPublishLocationId = claimId));
        }
        insert files;
    }

    @IsTest
    static void testClaimsAreMarkedAndNeverQueuedForThePrinter() {
        Basic__c t = claim(new Map<String, Object>{ 'Email__c' => 'fernando+ross@xtrapension.com' });
        Basic__c real = claim(new Map<String, Object>());
        System.assert([SELECT Is_Test_Claim__c FROM Basic__c WHERE Id = :t.Id].Is_Test_Claim__c);
        System.assert(![SELECT Is_Test_Claim__c FROM Basic__c WHERE Id = :real.Id].Is_Test_Claim__c);
        addStage1Files(t.Id);
        addStage1Files(real.Id);
        Test.startTest();
        BP_PortalUtils.generateZipArchiveAfterCreatedClaim(t.Id);
        BP_PortalUtils.generateZipArchiveAfterCreatedClaim(real.Id);
        Test.stopTest();
        System.assertEquals(false, [SELECT Claim_Created_ZIP_for_UPLOAD__c FROM Basic__c WHERE Id = :t.Id].Claim_Created_ZIP_for_UPLOAD__c);
        System.assertEquals(true, [SELECT Claim_Created_ZIP_for_UPLOAD__c FROM Basic__c WHERE Id = :real.Id].Claim_Created_ZIP_for_UPLOAD__c);
    }

    @IsTest
    static void stage1IsNotRebuiltOnceSent() {
        Basic__c b = claim(new Map<String, Object>());
        System.assertEquals(false, BP_GenerateZipArchiveQueueable.stage1AlreadySent(b.Id));
        update new Basic__c(Id = b.Id, FTP_Claim_Created_Send_Date__c = Date.today());
        System.assertEquals(true, BP_GenerateZipArchiveQueueable.stage1AlreadySent(b.Id));
        Test.startTest();
        System.enqueueJob(new BP_GenerateZipArchiveQueueable(b.Id, true));
        Test.stopTest();
        System.assertEquals(0, BP_GenerateZipArchiveQueueable.builds, 'an automatic path never rebuilds a pack already sent');
        new BP_GenerateZipArchiveQueueable(b.Id).execute(null);
        System.assertEquals(1, BP_GenerateZipArchiveQueueable.builds, 'the manual path still can');
        Basic__c fresh = claim(new Map<String, Object>());
        new BP_GenerateZipArchiveQueueable(fresh.Id, true).execute(null);
        System.assertEquals(2, BP_GenerateZipArchiveQueueable.builds, 'not sent yet: built');
    }

    @IsTest
    static void testEmailPatterns() {
        System.assert(BasicTriggerHandler.isTestEmail('Mihail.Klimovich@outlook.com'));
        System.assert(BasicTriggerHandler.isTestEmail('ann+test@gmail.com'));
        System.assert(!BasicTriggerHandler.isTestEmail('rrcooper@outlook.com'));
        System.assert(!BasicTriggerHandler.isTestEmail(null));
    }

    @IsTest
    static void saleEmailNamesTheValidationAgent() {
        Basic__c b = claim(new Map<String, Object>());
        Messaging.SingleEmailMessage m = BP_PortalUtils.saleEmail(b.Id);
        System.assertNotEquals(null, m, 'the sale email is built (XtraPension_Settings Configuration)');
        String agent = [SELECT Validation_Agent__c FROM Basic__c WHERE Id = :b.Id].Validation_Agent__c;
        System.assert(m.getHtmlBody().contains('Validation agent ' + agent), m.getHtmlBody());
    }

    // ---------------------------------------------------------------- notes for validation + wants a helper (11/11/2026)

    private static final String SALES_NOTES = 'AIB staff number = 12345\nWife\'s PPS = 1234567T <ask "Mary"> & call after 5';

    private static Map<String, Object> notesSection(Object notes) {
        return new Map<String, Object>{ 'otherInformation' => new Map<String, Object>{ 'validationNotes' => notes } };
    }

    private static List<ContentDocumentLink> formNotes(Id claimId) {
        String title = BP_PortalUtils.VALIDATION_NOTE_TITLE;
        return [SELECT ContentDocumentId FROM ContentDocumentLink
                WHERE LinkedEntityId = :claimId AND ContentDocument.FileType = 'SNOTE' AND ContentDocument.Title = :title];
    }

    // Every Note and file on the claim, for the message of a failed assert
    private static String linked(Id claimId) {
        List<String> out = new List<String>();
        for (ContentDocumentLink l : [SELECT ContentDocument.Title, ContentDocument.FileType FROM ContentDocumentLink WHERE LinkedEntityId = :claimId]) {
            out.add(l.ContentDocument.FileType + ' "' + l.ContentDocument.Title + '"');
        }
        return String.join(out, ' | ');
    }

    // What the form save recorded as failed (Application_Form_Error__c), for the message of a failed assert
    private static String formErrors() {
        List<String> out = new List<String>();
        for (Application_Form_Error__c e : [SELECT Error_Body__c FROM Application_Form_Error__c]) out.add(e.Error_Body__c);
        return String.join(out, ' | ');
    }

    private static String noteHtml(Id noteId) {
        return [SELECT Content FROM ContentNote WHERE Id = :noteId].Content.toString();
    }

    private static String savedNotes(Id claimId) {
        String text = [SELECT Validation_Notes__c FROM Basic__c WHERE Id = :claimId].Validation_Notes__c;
        return text == null ? null : text.replace('\r\n', '\n');
    }

    private static BP_ResponseWrappers.ApplicationDataWrapper saved(Map<String, Object> result) {
        System.assertEquals('success', result.get('status'), String.valueOf(result));
        return (BP_ResponseWrappers.ApplicationDataWrapper) result.get('application');
    }

    @IsTest
    static void validationNotesAreSavedReturnedAndKeptInOneNote() {
        Basic__c b = claim(new Map<String, Object>());
        BP_ResponseWrappers.ApplicationDataWrapper back = saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, notesSection(SALES_NOTES), true, 9)));
        System.assertEquals(SALES_NOTES, back.otherInformation.validationNotes.replace('\r\n', '\n'), 'the form gets its notes back');
        System.assertEquals(SALES_NOTES, savedNotes(b.Id));
        List<ContentDocumentLink> notes = formNotes(b.Id);
        System.assertEquals(1, notes.size(), 'one Note on the claim');
        String html = noteHtml(notes[0].ContentDocumentId);
        System.assert(html.contains('AIB staff number = 12345'), html);
        System.assert(html.contains('<br>'), 'line breaks kept: ' + html);
        System.assert(html.contains('&lt;ask') && !html.contains('<ask'), 'the text is escaped: ' + html);

        // Internal: /details gives the notes back to the form, but the same wrapper as the PDF service gets it (IPC1394
        // wet signature) and the fill-* endpoints never carry them
        BP_RequestWrappers.ApplicationDetailsDataWrapper ask = payload(b.Id, new Map<String, Object>(), false, 1);
        System.assert(JSON.serialize(BP_PortalApplicationHelper.getApplicationDetail(ask)).contains('AIB staff number'), 'details');
        System.assertEquals(null, new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)).otherInformation.validationNotes);
        String fill = JSON.serialize(BP_PortalApplicationHelper.getApplicationFill(ask));
        System.assert(fill.contains('"validationNotes":null') && !fill.contains('AIB staff number'), 'fill-* endpoints: ' + fill);

        // The usual autosave, same text: nothing is written and nothing is queried
        BP_RequestWrappers.ApplicationDetailsDataWrapper sameText = payload(b.Id, notesSection(SALES_NOTES), true, 9);
        Basic__c before = BP_PortalUtils.getApplication(b.Id)[0];
        Integer dml = Limits.getDmlStatements();
        Integer queries = Limits.getQueries();
        BP_PortalUtils.saveValidationNotes(before, sameText);
        System.assertEquals(dml, Limits.getDmlStatements(), 'no DML when the text did not change');
        System.assertEquals(queries, Limits.getQueries(), 'no query when the text did not change');

        // New text: the Note is made again with it, never a second Note
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, notesSection('Staff number is 99'), true, 9)));
        System.assertEquals('Staff number is 99', savedNotes(b.Id));
        System.assertEquals('', formErrors(), 'no failure recorded');
        System.assertEquals('replaced', BP_PortalUtils.validationNoteOutcome);
        notes = formNotes(b.Id);
        System.assertEquals(1, notes.size(), 'still one Note: ' + linked(b.Id));
        String now = noteHtml(notes[0].ContentDocumentId);
        System.assert(now.contains('Staff number is 99') && !now.contains('AIB'), now);
    }

    @IsTest
    static void notesEmptiedOnTheFormClearTheFieldAndTheNote() {
        Basic__c b = claim(new Map<String, Object>());
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, notesSection('Staff number 12345'), true, 9)));
        System.assertEquals('created', BP_PortalUtils.validationNoteOutcome);
        BP_ResponseWrappers.ApplicationDataWrapper back = saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, notesSection(''), true, 9)));
        System.assertEquals(null, back.otherInformation.validationNotes);
        System.assertEquals(null, savedNotes(b.Id), 'an empty string clears the field');
        System.assertEquals('', formErrors(), 'no failure recorded');
        System.assertEquals('removed', BP_PortalUtils.validationNoteOutcome);
        System.assertEquals(0, formNotes(b.Id).size(), 'the Note goes too: ' + linked(b.Id));

        // Emptied with no Note yet: none is made
        Basic__c other = claim(new Map<String, Object>{ 'Validation_Notes__c' => 'Typed on the Claim page' });
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(other.Id, notesSection(''), true, 9)));
        System.assertEquals(null, savedNotes(other.Id));
        System.assertEquals('nothing to do', BP_PortalUtils.validationNoteOutcome);
        System.assertEquals(0, formNotes(other.Id).size());
    }

    @IsTest
    static void aFormThatDoesNotSendTheNewKeysNeverWipesThem() {
        Basic__c b = claim(new Map<String, Object>{ 'Validation_Notes__c' => 'Keep me', 'Wants_Helper__c' => 'No' });
        // An older form build: the sections come without the new keys
        BP_ResponseWrappers.ApplicationDataWrapper back = saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, new Map<String, Object>{
            'otherInformation' => new Map<String, Object>{ 'notes' => 'For the IPCBR1' },
            'contactCommunication' => new Map<String, Object>{ 'firstName' => 'Ann' } }, true, 1)));
        Basic__c after = [SELECT Validation_Notes__c, Wants_Helper__c, Notes__c, Friend_First_Name__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Keep me', after.Validation_Notes__c, 'an absent key leaves the notes');
        System.assertEquals('No', after.Wants_Helper__c, 'an absent key leaves the answer');
        System.assertEquals('For the IPCBR1', after.Notes__c, 'the rest of the section is saved');
        System.assertEquals('Ann', after.Friend_First_Name__c);
        System.assertEquals('Keep me', back.otherInformation.validationNotes);
        System.assertEquals(false, back.contactCommunication.wantsHelper);

        // The keys sent as null (nothing typed, not answered)
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, new Map<String, Object>{
            'otherInformation' => new Map<String, Object>{ 'validationNotes' => null },
            'contactCommunication' => new Map<String, Object>{ 'wantsHelper' => null } }, true, 1)));
        // A partial autosave of another section
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, new Map<String, Object>{
            'bank' => new Map<String, Object>{ 'bankName' => 'AIB' } }, true, 8)));
        // Next on the helper page (not an autosave)
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, new Map<String, Object>{
            'contactCommunication' => new Map<String, Object>{ 'firstName' => 'Ann' } }, false, 1)));
        after = [SELECT Validation_Notes__c, Wants_Helper__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Keep me', after.Validation_Notes__c);
        System.assertEquals('No', after.Wants_Helper__c);
        System.assertEquals(0, formNotes(b.Id).size(), 'the text never changed: no Note was written');
    }

    @IsTest
    static void aNoteThatCannotBeWrittenNeverFailsTheSave() {
        Basic__c b = claim(new Map<String, Object>());
        BP_PortalUtils.failValidationNoteInTest = true;
        Map<String, Object> application = notesSection('Staff number 12345');
        application.put('bank', new Map<String, Object>{ 'bankName' => 'AIB Galway' });
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, application, true, 9)));
        Basic__c after = [SELECT Validation_Notes__c, Bank_Name__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Staff number 12345', after.Validation_Notes__c, 'the notes are on the claim');
        System.assertEquals('AIB Galway', after.Bank_Name__c, 'and so is the rest of the save');
        System.assertEquals(0, formNotes(b.Id).size());
        List<Application_Form_Error__c> errors = [SELECT Error_Body__c FROM Application_Form_Error__c];
        System.assertEquals(1, errors.size(), 'the failure is recorded');
        System.assert(errors[0].Error_Body__c.contains('Notes for validation') && errors[0].Error_Body__c.contains(String.valueOf(b.Id)), errors[0].Error_Body__c);
    }

    @IsTest
    static void notesEndingWithAQuoteDoNotBreakTheSave() {
        Basic__c b = claim(new Map<String, Object>());
        String quoted = 'Client said "call after 5"';
        BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper = payload(b.Id, new Map<String, Object>{
            'otherInformation' => new Map<String, Object>{ 'validationNotes' => quoted, 'notes' => 'He said "no"', 'accountantName' => '' } }, true, 9);
        System.assertEquals(true, wrapper.validationNotesSent);
        System.assertEquals(quoted, wrapper.validationNotes);
        System.assertEquals('He said "no"', wrapper.application.otherInformation.notes);
        System.assertEquals(null, wrapper.application.otherInformation.accountantName, 'an empty string is still read as null');
        saved(BP_PortalApplicationHelper.updateApplicationDetails(wrapper));
        System.assertEquals(quoted, savedNotes(b.Id));
        // Longer than the field: cut, not a failed save
        saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, notesSection('x'.repeat(10050)), true, 9)));
        System.assertEquals(10000, savedNotes(b.Id).length());
    }

    @IsTest
    static void wantsAHelperIsSavedReturnedAndOnlyWhenAnswered() {
        Basic__c target = new Basic__c(Wants_Helper__c = 'Yes');
        BP_PortalUtils.putWantsHelper(target, new BP_RequestWrappers.ApplicationContactCommunication(JSON.serialize(new Map<String, Object>{ 'firstName' => 'Ann' })));
        System.assertEquals('Yes', target.Wants_Helper__c, 'not asked: left alone');

        Basic__c b = claim(new Map<String, Object>());
        // Not answered, no notes: both keys are in the response, as null (the form looks for the keys)
        String body = JSON.serialize(BP_PortalApplicationHelper.getApplicationDetail(payload(b.Id, new Map<String, Object>(), false, 1)));
        System.assert(body.contains('"wantsHelper":null'), body);
        System.assert(body.contains('"validationNotes":null'), body);

        // Doesn't want a helper (autosave of the helper page)
        BP_ResponseWrappers.ApplicationDataWrapper back = saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, new Map<String, Object>{
            'contactCommunication' => new Map<String, Object>{ 'wantsHelper' => false } }, true, 1)));
        System.assertEquals('No', [SELECT Wants_Helper__c FROM Basic__c WHERE Id = :b.Id].Wants_Helper__c);
        System.assertEquals(false, back.contactCommunication.wantsHelper);

        // Wants one after all (Next on the helper page)
        back = saved(BP_PortalApplicationHelper.updateApplicationDetails(payload(b.Id, new Map<String, Object>{
            'contactCommunication' => new Map<String, Object>{ 'wantsHelper' => true, 'firstName' => 'Ann', 'email' => 'ann@example.com' } }, false, 1)));
        Basic__c after = [SELECT Wants_Helper__c, Friend_First_Name__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Yes', after.Wants_Helper__c);
        System.assertEquals('Ann', after.Friend_First_Name__c);
        System.assertEquals(true, back.contactCommunication.wantsHelper);
    }

    private static List<BP_MissingInfo.Item> helperItems(Id claimId) {
        List<BP_MissingInfo.Item> out = new List<BP_MissingInfo.Item>();
        for (BP_MissingInfo.Item i : BP_MissingInfo.check(BP_MissingInfo.load(claimId))) {
            if (i.agentText.startsWith('Helper')) out.add(i);
        }
        return out;
    }

    @IsTest
    static void aClientWhoDoesNotWantAHelperIsNotAskedForOne() {
        Basic__c b = claim(completeFields()); // no helper at all
        addCountry(b.Id);
        // Not asked yet: as before, the helper is the optional item of the email
        System.assertEquals(1, helperItems(b.Id).size());
        System.assertEquals(true, helperItems(b.Id)[0].optional);
        System.assertEquals(1, (Integer) BP_MissingInfo.refresh(b.Id, false).get('optional'));

        // Doesn't want a helper: nothing about a helper, for the agent or for the client
        update new Basic__c(Id = b.Id, Wants_Helper__c = 'No');
        System.assertEquals(0, helperItems(b.Id).size());
        Map<String, Object> view = BP_MissingInfo.refresh(b.Id, false);
        System.assertEquals(0, (Integer) view.get('optional'));
        System.assertEquals(0, (Integer) view.get('clientCount'), 'nothing left to ask the client');
        System.assertEquals('', texts(b.Id), 'and nothing holds the claim');

        // Even with the email the sale page left
        update new Basic__c(Id = b.Id, Friend_Email__c = 'daughter@example.com');
        System.assertEquals(0, helperItems(b.Id).size());

        // Wants a helper: what is missing about the helper is listed again, still optional
        update new Basic__c(Id = b.Id, Wants_Helper__c = 'Yes');
        System.assertEquals(1, helperItems(b.Id).size());
        System.assertEquals(true, helperItems(b.Id)[0].optional);
        System.assert(!texts(b.Id).contains('Helper'), 'and it still does not hold the claim: ' + texts(b.Id));
    }

    // ---------------------------------------------------------------- call of 11/11/2026 17h13 (docs/claims-call-1111b/CONTRACT.md)

    @IsTest
    static void remarriedForgotAndAddressNotKnownAreSavedAndReadBack() {
        Basic__c b = claim(new Map<String, Object>{ 'Marriage_Notes__c' => 'From the Short Form', 'Partner_same_as_claimant__c' => true });
        Map<String, Object> app = new Map<String, Object>{
            'claimant' => section('claimant', new Map<String, Object>{
                'firstName' => 'Barbara', 'maritalStatus' => 'Remarried', 'previousMarriageEnded' => 'divorced',
                'dateOfMarriage' => '1969-04-19T00:00:00.000Z', 'dateOfDivorce' => '1985-06-01T00:00:00.000Z',
                'dateOfRemarriage' => '2016-05-01T00:00:00.000Z', 'currentSpouseFirstName' => 'John J', 'currentSpouseLastName' => 'O\'Brien',
                'currentSpouseDob' => '1944-01-02', 'currentSpouseNino' => 'ab 12 34 56 c', 'marriageNotes' => 'Separated about 8 months after',
                'hasNinoValue' => 'Forgot', 'hasNino' => false, 'approxYearsInUK' => 2.5 }),
            'partner' => section('partner', new Map<String, Object>{ 'hasNinoValue' => 'Forgot', 'addressUnknown' => true, 'saveAsClaimant' => true })
        };
        BP_PortalUtils.autoSave(payload(b.Id, app, false, 9));
        Basic__c after = [SELECT Claimant_marital_Status__c, Previous_Marriage_Ended__c, Date_Of_Remarriage__c, Current_Spouse_First_Name__c,
            Current_Spouse_Last_Name__c, Current_Spouse_DOB__c, Current_Spouse_Nino__c, Marriage_Notes__c, Has_Nino__c, Claimant_hasNino__c,
            Partner_Has_Nino_values__c, Partner_Has_Nino__c, Partner_Address_Unknown__c, Partner_same_as_claimant__c, Approx_Years_in_UK__c
            FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Remarried', after.Claimant_marital_Status__c);
        System.assertEquals('Divorced', after.Previous_Marriage_Ended__c);
        System.assertEquals(Date.newInstance(2016, 5, 1), after.Date_Of_Remarriage__c);
        System.assertEquals('O\'Brien', after.Current_Spouse_Last_Name__c);
        System.assertEquals(Date.newInstance(1944, 1, 2), after.Current_Spouse_DOB__c);
        System.assertEquals('AB123456C', after.Current_Spouse_Nino__c);
        System.assertEquals('Separated about 8 months after', after.Marriage_Notes__c);
        System.assertEquals('Forgot', after.Has_Nino__c);
        System.assertEquals(false, after.Claimant_hasNino__c, 'Short Form rule: true only for Yes');
        System.assertEquals('Forgot', after.Partner_Has_Nino_values__c);
        System.assertEquals(false, after.Partner_Has_Nino__c);
        System.assertEquals(true, after.Partner_Address_Unknown__c);
        System.assertEquals(false, after.Partner_same_as_claimant__c, 'not known is not the claimant\'s address');
        System.assertEquals(2.5, after.Approx_Years_in_UK__c);

        BP_ResponseWrappers.ApplicationDataWrapper r = new BP_ResponseWrappers.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals('Forgot', r.claimant.hasNinoValue);
        System.assertEquals('Divorced', r.claimant.previousMarriageEnded);
        System.assert(r.claimant.dateOfRemarriage.startsWith('2016-05-01'), r.claimant.dateOfRemarriage);
        System.assertEquals('John J', r.claimant.currentSpouseFirstName);
        System.assert(r.claimant.currentSpouseDob.startsWith('1944-01-02'), r.claimant.currentSpouseDob);
        System.assertEquals('Separated about 8 months after', r.claimant.marriageNotes);
        System.assertEquals(2.5, r.claimant.approxYearsInUK);
        System.assertEquals('Forgot', r.partner.hasNinoValue);
        System.assertEquals(true, r.partner.addressUnknown);

        // An older form build (no new keys): nothing it does not send is blanked
        Map<String, Object> old = new Map<String, Object>{ 'claimant' => section('claimant', new Map<String, Object>{ 'firstName' => 'Barbara', 'maritalStatus' => 'Remarried' }) };
        BP_PortalUtils.autoSave(payload(b.Id, old, true, 9));
        Basic__c kept = [SELECT Marriage_Notes__c, Previous_Marriage_Ended__c, Current_Spouse_Last_Name__c, Has_Nino__c, Partner_Address_Unknown__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Separated about 8 months after', kept.Marriage_Notes__c);
        System.assertEquals('Divorced', kept.Previous_Marriage_Ended__c);
        System.assertEquals('O\'Brien', kept.Current_Spouse_Last_Name__c);
        System.assertEquals('Forgot', kept.Has_Nino__c);
        System.assertEquals(true, kept.Partner_Address_Unknown__c);

        // "" sent clears; a value off the picklist is left blank, never a failed save
        Map<String, Object> cleared = new Map<String, Object>{ 'claimant' => section('claimant', new Map<String, Object>{ 'marriageNotes' => '', 'previousMarriageEnded' => 'annulled', 'hasNinoValue' => 'No' }) };
        BP_PortalUtils.autoSave(payload(b.Id, cleared, true, 9));
        Basic__c c2 = [SELECT Marriage_Notes__c, Previous_Marriage_Ended__c, Has_Nino__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(null, c2.Marriage_Notes__c);
        System.assertEquals(null, c2.Previous_Marriage_Ended__c);
        System.assertEquals('Never Had', c2.Has_Nino__c);
    }

    @IsTest
    static void shortFormSavesTheRemarriage() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B' });
        Map<String, Object> client = new Map<String, Object>{ 'firstName' => 'Barbara', 'lastName' => 'O\'Brien', 'email' => 'john.snow@example.com',
            'maritalStatus' => 'Remarried', 'previousMarriageEnded' => 'Widowed', 'dateOfRemarriage' => '2016-05-01T00:00:00.000Z',
            'marriageNotes' => 'First husband died in 2010', 'approxYearsInUK' => 1.5, 'everLivedUK' => true };
        BP_PortalUtils.autoSaveShort(new BP_RequestWrappers.ShortApplicationDataWrapper(JSON.serialize(new Map<String, Object>{
            'applicationId' => b.Id, 'application' => new Map<String, Object>{ 'track' => 'A', 'client' => client } })));
        Basic__c after = [SELECT Claimant_marital_Status__c, Previous_Marriage_Ended__c, Date_Of_Remarriage__c, Marriage_Notes__c, Approx_Years_in_UK__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Remarried', after.Claimant_marital_Status__c);
        System.assertEquals('Widowed', after.Previous_Marriage_Ended__c);
        System.assertEquals(Date.newInstance(2016, 5, 1), after.Date_Of_Remarriage__c);
        System.assertEquals('First husband died in 2010', after.Marriage_Notes__c);
        System.assertEquals(1.5, after.Approx_Years_in_UK__c);
        BP_ResponseWrappers.ShortApplicationDataWrapper r = new BP_ResponseWrappers.ShortApplicationDataWrapper(BP_PortalUtils.getEnvApplication(b.Id));
        System.assertEquals('Widowed', r.client.previousMarriageEnded);
        System.assert(r.client.dateOfRemarriage.startsWith('2016-05-01'), r.client.dateOfRemarriage);
        System.assertEquals('First husband died in 2010', r.client.marriageNotes);

        // an older Short Form build (no keys) leaves them
        client.remove('previousMarriageEnded');
        client.remove('dateOfRemarriage');
        client.remove('marriageNotes');
        BP_PortalUtils.autoSaveShort(new BP_RequestWrappers.ShortApplicationDataWrapper(JSON.serialize(new Map<String, Object>{
            'applicationId' => b.Id, 'application' => new Map<String, Object>{ 'track' => 'A', 'client' => client } })));
        System.assertEquals('First husband died in 2010', [SELECT Marriage_Notes__c FROM Basic__c WHERE Id = :b.Id].Marriage_Notes__c);
    }

    @IsTest
    static void br1RemarriedPutsTheCurrentSpouseInQ21AndTheFormerInOtherInformation() {
        Basic__c b = claim(new Map<String, Object>{
            'Claimant_title__c' => 'Mrs', 'Claimant_marital_Status__c' => 'Remarried', 'Previous_Marriage_Ended__c' => 'Divorced',
            'Claimant_date_Of_Marriage__c' => Date.newInstance(1969, 4, 19), 'Claimant_date_Of_Divorce__c' => Date.newInstance(1985, 6, 1),
            'Claimant_date_Of_Bereavement__c' => Date.newInstance(2010, 3, 3), 'Date_Of_Remarriage__c' => Date.newInstance(2016, 5, 1),
            'Current_Spouse_First_Name__c' => 'John J', 'Current_Spouse_Last_Name__c' => 'O\'Brien', 'Current_Spouse_DOB__c' => Date.newInstance(1944, 1, 2),
            'Partner_Title__c' => 'Mr', 'Partner_First_Name__c' => 'Desmond', 'Partner_Other_Name__c' => 'Desmond Victor Waters',
            'Partner_Surname__c' => 'Waters', 'Partner_DOB__c' => Date.newInstance(1945, 10, 7), 'Partner_Nino__c' => null,
            'Partner_Has_Nino_values__c' => 'Forgot', 'Partner_Address_Unknown__c' => true,
            'Marriage_Notes__c' => 'Separated about 8 months after the wedding.'
        });
        BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(true, w.q20_married, 'Q20 is the current status');
        System.assertEquals(false, w.q20_divorced);
        System.assertEquals('O\'Brien', w.q21);
        System.assertEquals('John J', w.q22);
        System.assertEquals('02/01/1944', w.q27);
        System.assertEquals('01/05/2016', w.q28);
        System.assertEquals('', w.q29);
        System.assertEquals('', w.q30);
        System.assertEquals(true, w.q31_yes);
        System.assertEquals(true, w.q32_yes, 'the first marriage ended in divorce');
        System.assertEquals(false, w.q33_yes);
        System.assert(w.q64.contains('Former husband: Mr Desmond Victor Waters, born 07/10/1945, National Insurance number: not known.'), w.q64);
        System.assert(w.q64.contains('We married on 19/04/1969.'), w.q64);
        System.assert(w.q64.contains('We divorced on 01/06/1985.'), w.q64);
        System.assert(w.q64.contains('He died on 03/03/2010.'), w.q64);
        System.assert(w.q64.contains('His address is not known.'), w.q64);
        System.assert(w.q64.contains('I remarried on 01/05/2016.'), w.q64);
        System.assert(w.q64.contains('former husband\'s National Insurance record'), w.q64);
        System.assert(w.q64.contains('Separated about 8 months after the wedding.'), w.q64);
    }

    @IsTest
    static void br1DivorcedWithADeathAndAnUnknownAddress() {
        Basic__c b = claim(new Map<String, Object>{
            'Claimant_title__c' => 'Mrs', 'Claimant_marital_Status__c' => 'Divorced', 'Claimant_date_Of_Divorce__c' => Date.newInstance(1985, 6, 1),
            'Claimant_date_Of_Bereavement__c' => Date.newInstance(2010, 3, 3), 'Partner_Title__c' => 'Mr', 'Partner_Surname__c' => 'Waters',
            'Partner_same_as_claimant__c' => false, 'Partner_Address1__c' => '12 The Meadow', 'Partner_Address_Unknown__c' => true
        });
        BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(true, w.q20_divorced);
        System.assertEquals('Waters', w.q21);
        System.assertEquals('01/06/1985', w.q29);
        System.assertEquals('', w.q30, 'Q30 is for widows');
        System.assertEquals('Not known', w.q26a);
        System.assertEquals('', w.q26b);
        System.assert(w.q64.contains('My former husband died on 03/03/2010.'), w.q64);

        // a married claim with marriage notes only: its own block, no previous marriage
        Basic__c m = claim(new Map<String, Object>{ 'Claimant_marital_Status__c' => 'Married', 'Marriage_Notes__c' => 'Married in London' });
        BP_BR1_Wrapper.ApplicationDataWrapper wm = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(m.Id)[0]);
        System.assert(wm.q64.contains('Marriage - Additional Info') && wm.q64.contains('Married in London'), wm.q64);
        System.assert(!wm.q64.contains('Previous marriage'), wm.q64);
    }

    // 12/11/2026 pack audit: the whole name in Middle Name(s) (C05502) printed "Desmond Desmond Victor Waters" in Q22
    @IsTest
    static void br1Q22NeverRepeatsTheFirstNameOrTheSurname() {
        // expected Q22, first name, middle name(s)
        List<List<String>> cases = new List<List<String>>{
            new List<String>{ 'Desmond Victor', 'Desmond', 'Desmond Victor Waters' },
            new List<String>{ 'Desmond Victor', 'Desmond', 'Victor' },
            new List<String>{ 'Desmond', 'Desmond', null },
            new List<String>{ 'Desmond Victor', null, 'Desmond Victor Waters' },
            new List<String>{ '', null, null }
        };
        for (List<String> c : cases) {
            Basic__c b = claim(new Map<String, Object>{ 'Claimant_marital_Status__c' => 'Divorced', 'Partner_Surname__c' => 'Waters',
                'Partner_First_Name__c' => c[1], 'Partner_Other_Name__c' => c[2] });
            BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
            System.assertEquals(c[0], w.q22, String.valueOf(c));
            System.assertEquals('Waters', w.q21);
        }
    }

    @IsTest
    static void shortFormSaveKeepsItsListsAndTheClaimPageRows() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B' });
        insert new Claimant_Company__c(Basic__c = b.Id, Name = 'Added on the Claim page', Is_Partner__c = true);
        Map<String, Object> trackB = new Map<String, Object>{
            'husbandAlive' => 'No', 'sameAddress' => true, 'addressUnknown' => true, 'youGettinStatePensionNow' => false, 'husbandGettinStatePensionNow' => false,
            'employers' => new List<Object>{ new Map<String, Object>{ 'name' => 'Ford Dagenham', 'country' => 'GB', 'fromDate' => '1968-07-05' } },
            'addresses' => new List<Object>{ new Map<String, Object>{ 'country' => 'GB', 'city' => 'London', 'postcode' => 'N7', 'fromDate' => '1968-07-05', 'toDate' => '1970-12-31' } }
        };
        Map<String, Object> client = new Map<String, Object>{ 'firstName' => 'Barbara', 'email' => 'john.snow@example.com', 'maritalStatus' => 'Remarried', 'everLivedUK' => true };
        String body = JSON.serialize(new Map<String, Object>{ 'applicationId' => b.Id, 'isAutoSave' => true,
            'application' => new Map<String, Object>{ 'track' => 'B', 'client' => client, 'trackB' => trackB } });
        BP_PortalUtils.autoSaveShort(new BP_RequestWrappers.ShortApplicationDataWrapper(body));
        BP_PortalUtils.autoSaveShort(new BP_RequestWrappers.ShortApplicationDataWrapper(body)); // the next autosave replaces, never doubles
        List<Claimant_Company__c> rows = [SELECT Name, Is_Addresses__c, Is_Partner__c, Saved_By_Short_Form__c, City__c FROM Claimant_Company__c WHERE Basic__c = :b.Id ORDER BY Name];
        System.assertEquals(3, rows.size(), rows);
        Integer claimPage = 0;
        for (Claimant_Company__c row : rows) {
            if (row.Saved_By_Short_Form__c) continue;
            claimPage++;
            System.assertEquals('Added on the Claim page', row.Name);
        }
        System.assertEquals(1, claimPage, 'the Claim page row stays, the saved ones are not doubled');
        System.assertEquals(1, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id AND Is_Addresses__c = true AND Is_Partner__c = true AND City__c = 'London']);
        Basic__c after = [SELECT Partner_Address_Unknown__c, Partner_same_as_claimant__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(true, after.Partner_Address_Unknown__c);
        System.assertEquals(false, after.Partner_same_as_claimant__c, 'Not known is not the same address');
        BP_ResponseWrappers.ShortApplicationDataWrapper r = new BP_ResponseWrappers.ShortApplicationDataWrapper(BP_PortalUtils.getEnvApplication(b.Id));
        System.assertEquals(2, r.trackB.employers.size(), 'a reload shows the saved employer and the Claim page one');
        System.assertEquals(1, r.trackB.addresses.size());

        // empty lists never wipe
        trackB.put('employers', new List<Object>());
        trackB.put('addresses', new List<Object>());
        BP_PortalUtils.autoSaveShort(new BP_RequestWrappers.ShortApplicationDataWrapper(JSON.serialize(new Map<String, Object>{ 'applicationId' => b.Id, 'isAutoSave' => true,
            'application' => new Map<String, Object>{ 'track' => 'B', 'client' => client, 'trackB' => trackB } })));
        System.assertEquals(3, [SELECT COUNT() FROM Claimant_Company__c WHERE Basic__c = :b.Id]);
    }

    // ---------------------------------------------------------------- audit of 12/11/2026 (through the portal's REST router)

    private static Map<String, Object> portal(String uri, Map<String, Object> body) {
        RestRequest req = new RestRequest();
        req.requestURI = uri;
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();
        BP_PortalService.postRouter();
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    private static Map<String, Object> shortFormTrackB() {
        return new Map<String, Object>{
            'track' => 'B',
            'client' => new Map<String, Object>{ 'title' => 'Mrs', 'firstName' => 'Barbara', 'lastName' => 'Snow', 'email' => 'john.snow@example.com',
                'maritalStatus' => 'Remarried', 'previousMarriageEnded' => 'Divorced', 'dateOfDivorce' => '1985-06-01', 'dateOfRemarriage' => '2016-05-01',
                'everLivedUK' => true, 'approxYearsInUK' => 2.5 },
            'trackB' => new Map<String, Object>{ 'husbandAlive' => 'No', 'husbandGettinStatePensionNow' => false, 'youGettinStatePensionNow' => false,
                'title' => 'Mr', 'husbandFirstName' => 'Desmond', 'husbandSurname' => 'Waters', 'husbandOtherName' => 'Victor', 'husbandDob' => '1945-10-07',
                'marriageDate' => '1969-04-19', 'sameAddress' => false, 'addressUnknown' => true, 'country' => '', 'husbandHasNino' => 'Forgot',
                'townsLived' => 'London 1968-1970, Ealing',
                'employers' => new List<Object>{ new Map<String, Object>{ 'name' => 'Ford Dagenham', 'country' => 'GB', 'fromDate' => '1968-07-05' } },
                'addresses' => new List<Object>() }
        };
    }

    // Short Form Save kept neither his middle name(s) (it read husbandFullName, never sent) nor the towns he lived in (it
    // saved the address country code), and a reload lost "Not known" for his address, so the next Save wiped it
    @IsTest
    static void shortFormKeepsHisMiddleNameTownsAndUnknownAddress() {
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B' });
        Map<String, Object> saved = portal('/api/v4/application/details-short-update',
            new Map<String, Object>{ 'applicationId' => b.Id, 'isAutoSave' => true, 'application' => shortFormTrackB() });
        System.assertEquals('success', saved.get('status'), String.valueOf(saved));
        Basic__c after = [SELECT Partner_Other_Name__c, Partner_Towns_Lived__c, Partner_Address_Unknown__c FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals('Victor', after.Partner_Other_Name__c);
        System.assertEquals('London 1968-1970, Ealing', after.Partner_Towns_Lived__c);
        System.assertEquals(true, after.Partner_Address_Unknown__c);

        Map<String, Object> back = portal('/api/v4/application/details-short', new Map<String, Object>{ 'applicationId' => b.Id });
        Map<String, Object> trackB = (Map<String, Object>) ((Map<String, Object>) back.get('application')).get('trackB');
        System.assertEquals('Victor', trackB.get('husbandOtherName'));
        System.assertEquals('London 1968-1970, Ealing', trackB.get('townsLived'));
        System.assertEquals(true, trackB.get('addressUnknown'), 'a reload keeps "Not known"');

        // a claim saved before the fix has the country code in the towns: the reload shows an empty box, not "IE"
        update new Basic__c(Id = b.Id, Partner_Towns_Lived__c = 'IE', Partner_Country_Code__c = 'IE');
        BP_ResponseWrappers.ShortApplicationDataWrapper old = new BP_ResponseWrappers.ShortApplicationDataWrapper(BP_PortalUtils.getEnvApplication(b.Id));
        System.assertEquals('', old.trackB.townsLived);
    }

    // The long form keeps sending the old spouse section after the status changes to Single: the record keeps it, the
    // BR1 and Missing Info do not use it (Q21-Q28, Q13, Q15 and Q50, spouse notes, spouse rows)
    @IsTest
    static void singleNeverUsesWhatTheRecordStillHoldsAboutASpouse() {
        Basic__c b = claim(new Map<String, Object>{
            'Claimant_marital_Status__c' => 'Single', 'Track__c' => 'B', 'Partner_Title__c' => 'Mr', 'Partner_First_Name__c' => 'Desmond',
            'Partner_Surname__c' => 'Waters', 'Partner_Has_Nino_values__c' => 'Forgot', 'Partner_State_Pension__c' => true,
            'Partner_Ever_Lived_UK_Notes__c' => 'He lived in Leeds', 'Partner_Reference_on_Any_DWP_Letters__c' => 'DWP ref 123'
        });
        insert new List<Claimant_Company__c>{
            new Claimant_Company__c(Basic__c = b.Id, Name = 'His employer', Is_Partner__c = true),
            new Claimant_Company__c(Basic__c = b.Id, Name = 'United Kingdom', Is_Partner__c = true, Is_Addresses__c = true, Address1__c = 'Hornsey Road', City__c = 'London')
        };
        insert new Claimant_Country_lived__c(Basic__c = b.Id, Name = 'Spain', Country_Type__c = 'ES', Is_Partner__c = true);

        BP_BR1_Wrapper.ApplicationDataWrapper w = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals(true, w.q20_single);
        System.assert(String.isBlank(w.q21) && String.isBlank(w.q22) && String.isBlank(w.q27), 'Q21-Q28 empty: ' + w.q21 + ' ' + w.q22 + ' ' + w.q27);
        System.assertEquals(null, w.q13a, 'no spouse benefits');
        System.assertEquals(null, w.q50a, 'no spouse employer');
        System.assertNotEquals('Hornsey Road', w.q15a, 'his UK address is not the client\'s');
        System.assertNotEquals('Spain', w.q56, 'his country is not the client\'s');
        System.assertNotEquals(true, w.q51b_partner, 'no spouse benefit in Q51');
        System.assert(w.q64 == null || (!w.q64.contains('He lived in Leeds') && !w.q64.contains('DWP ref 123')), w.q64);

        String asked = String.join(BP_MissingInfo.agentTexts(BP_MissingInfo.check(BP_MissingInfo.load(b.Id))), ' | ');
        System.assert(!asked.contains('His employer'), asked);
        System.assert(!asked.contains('Spain'), asked);
        System.assert(!asked.contains('UK home address'), asked);
        for (BP_MissingInfo.Item i : BP_MissingInfo.check(BP_MissingInfo.load(b.Id))) {
            System.assertNotEquals('spouse', i.groupKey, 'a spouse item for a single client: ' + i.agentText);
        }

        // the same record as Married uses them again (nothing was deleted)
        update new Basic__c(Id = b.Id, Claimant_marital_Status__c = 'Married');
        BP_BR1_Wrapper.ApplicationDataWrapper m = new BP_BR1_Wrapper.ApplicationDataWrapper(BP_PortalUtils.getApplication(b.Id)[0]);
        System.assertEquals('Waters', m.q21);
        System.assertEquals(true, m.q13a);
        System.assert(m.q64.contains('He lived in Leeds'), m.q64);
    }

    @IsTest
    static void shortFormFinishKeepsTheTownsHeLivedIn() {
        insert new XtraPension_Data__c(BP_Registration_template__c = 'TestTemplate', BP_Pdf_File_Link__c = 'test', BP_Pdf_File_IPC1394_Link__c = 'test',
            BP_PDF_IPCBR1_Wet__c = 'test', BP_PDF_IPC1394_Wet__c = 'test', BP_Form_Link__c = 'https://claim.xtrapension.com/form/');
        Basic__c b = claim(new Map<String, Object>{ 'Track__c' => 'B' });
        Map<String, Object> done = portal('/api/v4/application/details-short-update',
            new Map<String, Object>{ 'applicationId' => b.Id, 'isAutoSave' => false, 'application' => shortFormTrackB() });
        System.assertEquals('success', done.get('status'), String.valueOf(done));
        Basic__c after = [SELECT Is_envelope_created__c, Claimant_marital_Status__c, Partner_Other_Name__c, Partner_Towns_Lived__c, Partner_Address_Unknown__c, Approx_Years_in_UK__c
                          FROM Basic__c WHERE Id = :b.Id];
        System.assertEquals(true, after.Is_envelope_created__c);
        System.assertEquals('Remarried', after.Claimant_marital_Status__c);
        System.assertEquals('Victor', after.Partner_Other_Name__c);
        System.assertEquals('London 1968-1970, Ealing', after.Partner_Towns_Lived__c);
        System.assertEquals(true, after.Partner_Address_Unknown__c);
        System.assertEquals(2.5, after.Approx_Years_in_UK__c);
    }
}