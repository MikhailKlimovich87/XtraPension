@IsTest
private class XpClientSummaryAddressTest {
    // The Yellow page, the DWP letter and the client summary print the address from BP_ClientSummaryPdfController.addressLines
    @IsTest
    static void aTownThatIsAlsoTheCountyIsPrintedOnce() {
        Contact c = new Contact(LastName = 'Cooper', Email = 'xp.address.test@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'xp.address.test@example.com';
        b.Claimant_address1__c = '46 WILFIELD PARK';
        b.Claimant_address2__c = null;
        b.Claimant_City__c = 'Dublin';
        b.Current_Address_Abroad_State_Name__c = 'DUBLIN';
        b.Eircode__c = 'D04 HX07';
        b.Current_Address_Abroad_Country_Name__c = 'Ireland';
        insert b;
        Test.setCurrentPage(Page.BP_Yellow);
        ApexPages.currentPage().getParameters().put('id', b.Id);
        BP_ClientSummaryPdfController ctrl = new BP_ClientSummaryPdfController();
        String address = String.join(ctrl.addressLines, '');
        System.assertEquals(1, address.toLowerCase().countMatches('dublin'), address);
        System.assert(address.contains('46 WILFIELD PARK') && address.contains('D04 HX07') && address.contains('Ireland'), address);
    }

    private static BP_ClientSummaryPdfController summaryOf(Map<String, Object> fields) {
        Contact c = new Contact(LastName = 'Waters', Email = 'xp.summary.nino@example.com');
        insert c;
        Basic__c b = BP_TestDataFactory.createBasic(c.Id, false);
        b.Email__c = 'xp.summary.nino@example.com';
        for (String f : fields.keySet()) b.put(f, fields.get(f));
        insert b;
        Test.setCurrentPage(Page.BP_Client_Summary);
        ApexPages.currentPage().getParameters().put('id', b.Id);
        return new BP_ClientSummaryPdfController();
    }

    // 12/11/2026: "Forgot" (had a NINO, number not known) is a Yes on the summary, like BR1 Q5a and the IPC1394, and the
    // DWP letter prints words, not the picklist values
    @IsTest
    static void forgotIsAYesWithTheNumberNotKnown() {
        BP_ClientSummaryPdfController ctrl = summaryOf(new Map<String, Object>{
            'Has_Nino__c' => 'Forgot', 'Claimant_hasNino__c' => false, 'Claimant_nino__c' => null,
            'Partner_Has_Nino_values__c' => 'Forgot', 'Partner_Has_Nino__c' => false, 'Partner_Nino__c' => null
        });
        System.assertEquals(true, ctrl.claimantHadNino);
        System.assertEquals('Not known', ctrl.claimantNinoText);
        System.assertEquals(true, ctrl.partnerHadNino);
        System.assertEquals('Not known', ctrl.partnerNinoText);
        System.assertEquals('Not known', ctrl.ninoString, 'DWP letter');
    }

    @IsTest
    static void neverHadIsANoAndNoneOnTheDwpLetter() {
        BP_ClientSummaryPdfController ctrl = summaryOf(new Map<String, Object>{
            'Has_Nino__c' => 'Never Had', 'Claimant_hasNino__c' => false, 'Claimant_nino__c' => null,
            'Partner_Has_Nino_values__c' => 'Never Had', 'Partner_Has_Nino__c' => false, 'Partner_Nino__c' => null
        });
        System.assertEquals(false, ctrl.claimantHadNino);
        System.assertEquals(null, ctrl.claimantNinoText);
        System.assertEquals(false, ctrl.partnerHadNino);
        System.assertEquals('None', ctrl.ninoString);
    }

    @IsTest
    static void aKnownNumberIsPrintedAsItIs() {
        BP_ClientSummaryPdfController ctrl = summaryOf(new Map<String, Object>{
            'Has_Nino__c' => 'Yes', 'Claimant_hasNino__c' => true, 'Claimant_nino__c' => 'AB123456C',
            'Partner_Has_Nino_values__c' => 'Yes', 'Partner_Has_Nino__c' => true, 'Partner_Nino__c' => 'ZX987654D'
        });
        System.assertEquals(true, ctrl.claimantHadNino);
        System.assertEquals('AB123456C', ctrl.claimantNinoText);
        System.assertEquals('ZX987654D', ctrl.partnerNinoText);
        System.assertEquals('AB123456C', ctrl.ninoString);
    }

    // Remarried rows and the marriage notes read fields the query must select (the page renders only outside tests)
    @IsTest
    static void remarriedFieldsAreReadForThePage() {
        BP_ClientSummaryPdfController ctrl = summaryOf(new Map<String, Object>{
            'Claimant_marital_Status__c' => 'Remarried', 'Previous_Marriage_Ended__c' => 'Divorced',
            'Date_Of_Remarriage__c' => Date.newInstance(2016, 5, 1), 'Current_Spouse_First_Name__c' => 'John J',
            'Current_Spouse_Last_Name__c' => 'O\'Brien', 'Current_Spouse_DOB__c' => Date.newInstance(1944, 1, 2),
            'Marriage_Notes__c' => 'Separated about 8 months after the wedding.',
            'Partner_First_Name__c' => 'Desmond', 'Partner_Other_Name__c' => 'Desmond Victor Waters', 'Partner_Surname__c' => 'Waters'
        });
        System.assertEquals('Divorced', ctrl.client.Previous_Marriage_Ended__c);
        System.assertEquals(Date.newInstance(2016, 5, 1), ctrl.client.Date_Of_Remarriage__c);
        System.assertEquals('John J', ctrl.client.Current_Spouse_First_Name__c);
        System.assertEquals('O\'Brien', ctrl.client.Current_Spouse_Last_Name__c);
        System.assertEquals(Date.newInstance(1944, 1, 2), ctrl.client.Current_Spouse_DOB__c);
        System.assertEquals('Separated about 8 months after the wedding.', ctrl.client.Marriage_Notes__c);
        System.assertEquals('Desmond Victor', ctrl.partnerOtherNames);
    }

    @IsTest
    static void otherNamesInFullNeverRepeatAName() {
        System.assertEquals('Desmond Victor', BP_ClientSummaryPdfController.otherNamesInFull('Desmond', 'Desmond Victor Waters', 'Waters'));
        System.assertEquals('Desmond Victor', BP_ClientSummaryPdfController.otherNamesInFull('Desmond', 'Victor', 'Waters'));
        System.assertEquals('Desmond Victor', BP_ClientSummaryPdfController.otherNamesInFull(null, 'Desmond Victor Waters', 'Waters'));
        System.assertEquals('Desmond', BP_ClientSummaryPdfController.otherNamesInFull('Desmond', null, 'Waters'));
        System.assertEquals('', BP_ClientSummaryPdfController.otherNamesInFull(null, ' ', 'Waters'));
    }

    @IsTest
    static void differentPartsAreAllKept() {
        List<String> parts = new List<String>();
        BP_ClientSummaryPdfController.addPart(parts, '1 Main St');
        BP_ClientSummaryPdfController.addPart(parts, ' ');
        BP_ClientSummaryPdfController.addPart(parts, 'Sydney');
        BP_ClientSummaryPdfController.addPart(parts, 'NSW');
        BP_ClientSummaryPdfController.addPart(parts, 'sydney ');
        System.assertEquals(new List<String>{ '1 Main St', 'Sydney', 'NSW' }, parts);
    }
}