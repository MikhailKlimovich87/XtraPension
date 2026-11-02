public with sharing class BP_ClientSummaryPdfController {

    public Basic__c client { get; private set; }
    public List<String> addressLines { get; private set; }
    public String ninoString {get; private set; }

    public BP_ClientSummaryPdfController() {

        String recordId =
            ApexPages.currentPage()
                     .getParameters()
                     .get('id');

        if (String.isBlank(recordId)) {
            return;
        }

        client = getApplication(recordId)[0];
        ninoString = '';
        if(String.isNotBlank(client.Has_Nino__c) &&  client.Has_Nino__c != 'Yes') {
            ninoString = client.Has_Nino__c;
        } else {
            ninoString = client.Claimant_nino__c;
            if(String.isBlank(ninoString)) {
                ninoString = 'N/A';
            }
        }
              
        List<String> allAddress = new List<String>();
        if(String.isNotBlank(client.Claimant_address1__c)) {
            allAddress.add(client.Claimant_address1__c);
        }
        if(String.isNotBlank(client.Claimant_address2__c)) {
            allAddress.add(client.Claimant_address2__c);
        }
        if(String.isNotBlank(client.Claimant_City__c)) {
            allAddress.add(client.Claimant_City__c);
        }
        if(String.isNotBlank(client.Current_Address_Abroad_State_Name__c)) {
            allAddress.add(client.Current_Address_Abroad_State_Name__c);
        }
        if(String.isNotBlank(client.Eircode__c)) {
            allAddress.add(client.Eircode__c);
        }
        if(String.isNotBlank(client.Current_Address_Abroad_Country_Name__c)) {
            allAddress.add(client.Current_Address_Abroad_Country_Name__c);
        }
        Integer counterStr = 0;
        String addressLine = '';
        addressLines = new List<String>();
        for(String item :allAddress) {
            addressLine = addressLine + item + ', ';
            counterStr = counterStr + addressLine.length();
            if(counterStr>50) {
                counterStr = 0;
                System.debug(addressLine);
                addressLines.add(addressLine);
                addressLine = '';
            }
        }
        if(String.isNotBlank(addressLine)) {
            addressLines.add(addressLine);
        }
        if(addressLines.size()>0) {
            Integer lastIndex = addressLines.size() - 1;
            addressLines[lastIndex] = addressLines[lastIndex].replaceAll(',\\s*$', '');
        }
    }

    public static List<Basic__c> getApplication(String basicId) {

        

        return [

            SELECT
                Id,
                Name,
                Deposit_Payment_Date__c,
                Friend_First_Name__c,
                Friend_Last_Name__c,
                Friend_Phone__c,
                Friend_Email__c,
                Relationship__c,

                Claimant_title__c,
                First_Name__c,
                Claimant_Middle_Name__c,
                Last_Name__c,
                Claimant_other_names__c,
                Claimant_dob__c,
                Claimant_maiden_Name__c,
                Phone__c,
                Email__c,
                Claimant_marital_Status__c,
                Claimant_nationality__c,
                Claimant_date_Of_Marriage__c,
                Claimant_date_Of_Bereavement__c,
                Claimant_date_Of_Divorce__c,
                Claimant_hasNino__c,
                Claimant_nino__c,
                Has_Nino__c,
                Current_Address_Abroad_State__c,
                Claimant_address1__c,
                Claimant_address2__c,
                Claimant_City__c,
                Current_Address_Abroad_State_Name__c,
                Eircode__c,
                Current_Address_Abroad_Country_Name__c,

                Claimant_ever_Lived_UK__c,
                Claimant_lived_UK_From__c,
                Claimant_lived_UK_to__c,

                Claimant_Ever_Worked_UK__c,
                Claimant_worked_UK_From__c,
                Claimant_worked_UK_To__c,

                Claimant_has_Proof_Of_UK_Work__c,
                Claimant_self_Employed_UK__c,
                Ever_Self_Employed_UK_after_1978__c,
                Claimant_Ever_Paid_Married_Woman_s_Stam__c,
                Claimant_Minded_Kids__c,

                Partner_Title__c,
                Partner_Surname__c,
                Partner_Other_Name__c,
                Partner_DOB__c,
                Partner_Maiden_Name__c,
                Partner_Has_Nino__c,
                Partner_Nino__c,
                Partner_same_as_claimant__c,
                Partner_Country__c,
                Partner_City__c,
                Partner_Address1__c,
                Partner_Address2__c,
                Partner_Postcode__c,
                Partner_First_Name__c,
                Partner_State_Name__c,

                Claimant_State_Pension__c,
                Claimant_Graduated_Retirement_Benefit__c,
                Claimant_Widows_Benefit__c,
                Claimant_Bereavement_Benefit__c,

                Partner_State_Pension__c,
                Partner_Graduated_Retirement_Benefit__c,
                Partner_Widows_Benefit__c,
                Partner_Bereavement_Benefit__c,

                Pension_Claiming_from_Today__c,
                Pension_Start_Date__c,
                Pension_Work_After_Pension_Age__c,
                Pension_Deferred_Pension__c,
                Pension_Imprisoned_Since_Pension_Age__c,

                Bank_Account_Type__c,
                Bank_Account_Owner_Name__c,
                Bank_Name__c,
                Bank_Sort_Code__c,
                Bank_IBAN__c,
                Bank_Account__c,
                Bank_BIC__c,

                (
                    SELECT
                        Id,
                        Name,
                        Country_Type__c,
                        From_Date__c,
                        To_Date__c,
                        Social_Security_Number__c,
                        Is_Partner__c
                    FROM ClaimantCountrieslived__r
                    WHERE Is_Partner__c = false
                ),

                (
                    SELECT
                        Id,
                        Name,
                        Dob__c,
                        Minded_From__c,
                        Minded_To__c,
                        Nino__c
                    FROM Clamant_Children__r
                ),

                (
                    SELECT
                        Id,
                        Name,
                        Address1__c,
                        Address2__c,
                        City__c,
                        Country__c,
                        Postcode__c,
                        From_Date__c, 
                        To_Date__c,
                        Is_Partner__c,
                        Is_Addresses__c
                    FROM Claimant_Companies__r
                    WHERE Is_Partner__c = false AND Is_Addresses__c = false
                )

            FROM Basic__c
            WHERE Id = :basicId
            LIMIT 1
        ];
    }
}