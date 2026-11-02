public with sharing class BP_PortalUtils {
    private static final Map<String, String> CURRENCY_SYMBOLS = new Map<String, String>{
    'EUR' => '€',
    'USD' => '$',
    'ZAR' => 'R',
    'CAD' => 'C$',
    'AUD' => 'A$'
    };

    public static final List<String> FIELDS_REQUIRED = new List<String>{
        'First_Name__c',
        'Last_Name__c',

        'Friend_First_Name__c',
        'Friend_Last_Name__c',
        'Friend_Phone__c',
        'Friend_Email__c',
        'Relationship__c',

        'Claimant_title__c',
        'Claimant_dob__c',
        'Phone__c',
        'Email__c',
        'Claimant_marital_Status__c',
        //'Claimant_nationality__c',       
        // 'Claimant_hasNino__c',

        'Current_Address_Abroad_Country_Name__c',
        'Eircode__c',
        'Claimant_address1__c',
        //'Claimant_address2__c',
        'Claimant_City__c',

        // 'Claimant_ever_Lived_UK__c',       
        // 'Claimant_Ever_Worked_UK__c',
        
        //'Claimant_has_Proof_Of_UK_Work__c',

        //'Claimant_Ever_Paid_Married_Woman_s_Stam__c',
        //'Claimant_Minded_Kids__c',

        
        //'Partner_Other_Name__c',      
        //'Partner_Maiden_Name__c',
       

        //'Partner_same_as_claimant__c',       
        //'Partner_Address2__c',
        

        //'Claimant_State_Pension__c',
        //'Claimant_Graduated_Retirement_Benefit__c',
        //'Claimant_Widows_Benefit__c',
        //'Claimant_Bereavement_Benefit__c',

        //'Partner_State_Pension__c',
        //'Partner_Graduated_Retirement_Benefit__c',
        //'Partner_Widows_Benefit__c',
        //'Partner_Bereavement_Benefit__c',

        //'Pension_Claiming_from_Today__c',
        
        //'Pension_Work_After_Pension_Age__c',
        //'Pension_Deferred_Pension__c',
        //'Pension_Imprisoned_Since_Pension_Age__c',

        //'Bank_Account_Type__c',
        'Bank_Account_Owner_Name__c',
        'Bank_Name__c',
        'Bank_Sort_Code__c',
        
        'Bank_Account__c',
        'Bank_Address__c',
        'Bank_City__c',
        'Bank_Country_Code__c',
        'Bank_Post_Code__c',
        'Owns_This_Account__c'

    };


    public static final List<String> FIELDS_CONDITIONAL = new List<String>{ 
        'Claimant_date_Of_Marriage__c', // Claimant_marital_Status__c: Married, Civil Pertnership
        'Claimant_date_Of_Bereavement__c',// Claimant_marital_Status__c: Widowed
        'Claimant_date_Of_Divorce__c',// Claimant_marital_Status__c: Divorced, Separated
        'Claimant_nino__c', // Claimant_hasNino__c
        'Claimant_lived_UK_From__c', // Claimant_ever_Lived_UK__c
        'Claimant_lived_UK_to__c',// Claimant_ever_Lived_UK__c
        'Claimant_worked_UK_From__c',// Claimant_Ever_Worked_UK__c
        'Claimant_worked_UK_To__c',// Claimant_Ever_Worked_UK__c
        'Pension_Start_Date__c', // Pension_Claiming_from_Today__c
        'Partner_Title__c', // Partner_Has_Nino__c not Single
        'Partner_Surname__c', // Partner_Has_Nino__c not Single
        'Partner_DOB__c', // Partner_Has_Nino__c not Single
        'Partner_Nino__c', // Partner_Has_Nino__c not Single
        'Partner_Has_Nino__c', // not Single
        'Partner_Country__c', // not Single
        'Partner_Postcode__c', // not Single
        'Partner_Address1__c', // not Single
        'Partner_City__c'// not Single
        

    };


    // public static String getMissingFields(Basic__c app) {
    //     Map<String, Schema.SObjectField> fieldMap =
    //         Basic__c.SObjectType.getDescribe().fields.getMap();

    //     List<String> missingLabels = new List<String>();

    //     for (String fieldName : fieldsToCheckRequired) {
    //         if (app.get(fieldName) == null) {
    //             missingLabels.add(
    //                 fieldMap.get(fieldName)
    //                     .getDescribe()
    //                     .getLabel()
    //             );
    //         }
    //     }

    //     return String.join(missingLabels, ', ');
    // }



    public static List<Basic__c> getApplication(String basicId) {
        List<Basic__c> appsData = new List<Basic__c>();
        if (basicId != null) {
            appsData = [SELECT Id, 
                Name, 
                Validation_Agent__c,
                CurrencyIsoCode,
                Stripe_Transaction_Id__c, 
                Stripe_Customer_Id__c, 
                Status__c, 
                Phone__c, 
                Payment_Method__c, 
                Last_Name__c, 
                First_Name__c, 
                Email__c, 
                Friend_Email__c,
                Friend_First_Name__c,
                Friend_Last_Name__c,
                Friend_Phone__c,
                Current_Address_Abroad_State__c, 
                Current_Address_Abroad_Country__c, 
                Claimant_City__c,
                Eircode__c, 
                Current_Address_Abroad_State_Name__c,
                Contact__c, 
                Full_Current_Ad__c, 
                Agent_Making_Sale__c, 
                Step__c, 
                Agent_Form_Step__c,
                Relationship__c,
                Claimant_title__c,
                Short_Agent_Link__c, 
                Current_Address_Abroad_Country_Name__c,
                Claimant_other_names__c, 
                Claimant_dob__c, 
                Claimant_maiden_Name__c,                 
                Claimant_marital_Status__c, 
                Claimant_nationality__c, 
                Claimant_date_Of_Marriage__c, 
                Claimant_date_Of_Bereavement__c, 
                Claimant_date_Of_Divorce__c, 
                Claimant_hasNino__c, 
                Claimant_nino__c, 
                Claimant_address1__c, 
                Claimant_address2__c, 
                Claimant_ever_Lived_UK__c, 
                Claimant_lived_UK_From__c, 
                Claimant_lived_UK_to__c, 
                Claimant_Ever_Worked_UK__c, 
                Claimant_worked_UK_From__c, 
                Claimant_worked_UK_To__c, 
                Claimant_has_Proof_Of_UK_Work__c, 
                Claimant_self_Employed_UK__c, 
                Claimant_Ever_Paid_Married_Woman_s_Stam__c, 
                Claimant_Minded_Kids__c,
                Claimant_Bereavement_Benefit__c,
                Claimant_Graduated_Retirement_Benefit__c,
                Claimant_State_Pension__c,
                Claimant_Widows_Benefit__c,
                Partner_Bereavement_Benefit__c,
                Partner_Graduated_Retirement_Benefit__c,
                Partner_State_Pension__c,
                Partner_Widows_Benefit__c,
                Partner_Address1__c,
                Partner_Address2__c,
                Partner_City__c,
                Partner_Country__c,
                Partner_Country_Code__c,
                Partner_DOB__c,
                Partner_Has_Nino__c,
                Partner_Maiden_Name__c,
                Partner_Nino__c,
                Partner_Other_Name__c,
                Partner_Postcode__c,
                Partner_Towns_Lived__c,
                Partner_same_as_claimant__c,
                Partner_Surname__c,
                Partner_Title__c,
                Partner_First_Name__c,
                Partner_Full_Name__c,
                Partner_State_Code__c,
                Partner_State_Name__c,
                Pension_Claiming_from_Today__c,
                Pension_Deferred_Pension__c,
                Pension_Imprisoned_Since_Pension_Age__c,
                Pension_Start_Date__c,
                Bank_Account__c,
                Bank_Account_Owner_Name__c,
                Bank_Account_Owner_Email__c,
                Bank_Account_Type__c,
                Bank_IBAN__c,
                Bank_Name__c,
                Bank_Sort_Code__c,
                Bank_Country__c,
                Bank_Country_Code__c,
                Bank_Post_Code__c,
                Bank_City__c,
                Bank_Address__c,
                Bank_BIC__c,
                Pension_Work_After_Pension_Age__c,
                Has_Nino__c,
                Partner_Has_Nino_values__c,
                Is_envelope_created__c,
                Track__c,
                Is_Partner_alive__c,
                Partner_Left_UK__c,
                PPS__c,
                Owns_This_Account__c,
                Missing_Info__c,
                Approx_Years_in_UK__c,
                Ever_Work_UK_approved__c,
                Ever_Live_In_UK_approved__c,
                Ever_Worked_UK_Use_Same_Dates__c,
                What_is_this_number__c,
                Paid_Interval__c,
                Claimant_is_Waiting_Uk_Benefits_text__c,
                Partner_is_Waiting_Uk_Benefits_text__c,
                Claimant_is_Waiting_Uk_Benefits__c,
                Partner_is_Waiting_Uk_Benefits__c,
                Verification_Details__c, Verification_Status__c, Verified_Reference__c, Was_Cleansed__c, Address_Validated__c,
                Partner_Verification_Details__c, Partner_Verification_Status__c, Partner_Verified_Reference__c, 
                Partner_Was_Cleansed__c, Partner_Address_Validated__c,
                Notes__c,
                Work_In_UK_during_2_years__c,
                Ever_Self_Employed_UK_after_1978__c,
                Ever_Pay_Reduced_UK_nino__c,
                Partner_Ever_Lived_UK__c,
                Partner_Ever_Worked_UK__c,
                DocuSign_Date__c,
                Claimant_Ever_Lived_UK_Notes__c,
                Partner_Ever_Lived_UK_Notes__c,
                Partner_Reference_on_Any_DWP_Letters__c,
                Partner_Claiming_UK_Pension__c,
                Accountant_Address__c,
                Accountant_Address_2__c,
                Accountant_City__c,
                Accountant_Country_Code__c,
                Accountant_Country_Name__c,
                Accountant_Name__c,
                Accountant_Phone__c,
                Accountant_PostCode__c,
                Accountant_State_Code__c,
                Accountant_State_Name__c,
                Do_you_have_an_accountant__c,
                Do_you_own_rent_any_UK_property__c,
                Are_you_self_assessed_for_tax__c,
                Age_Pension_now_or_next_year__c,
                Is_Your_Partner_Currently_Get_Pension__c,
                isYourPartnerCurrentlyGetPensionText__c,
                Claimant_Middle_Name__c,
                (SELECT Id, Address__c, Address_2__c, City__c, Name, Claim__c, PostCode__c  FROM Claimant_UK_Properties__r),
                (SELECT Id, Basic__c, From_date__c, Name, Country_Type__c, Social_Security_Number__c, To_Date__c, Is_Live_Here_Now__c FROM ClaimantCountrieslived__r),
                (SELECT Id, Basic__c, Dob__c, Name, Minded_From__c, Minded_To__c, Nino__c  FROM Clamant_Children__r),
                (SELECT Id, Basic__c, Address1__c, Address2__c, City__c, Country__c, Country_Type__c, 
                Name, From_Date__c, To_Date__c, Postcode__c, Is_Partner__c, Is_Addresses__c, Address_Validated__c,
                Verification_Details__c, Verification_Status__c, Verified_Reference__c, Was_Cleansed__c 
                FROM Claimant_Companies__r)
                FROM Basic__c
                WHERE Id = : basicId
            ];
            
        }
        return appsData;
    }

    public static List<Basic__c> getEnvApplication(String basicId) {
        List<Basic__c> appsData = new List<Basic__c>();
        if (basicId != null) {
            appsData = [SELECT Id, 
                Name, 
                Validation_Agent__c,
                CurrencyIsoCode,
                Stripe_Transaction_Id__c, 
                Stripe_Customer_Id__c, 
                Status__c, 
                Phone__c, 
                Payment_Method__c, 
                Last_Name__c, 
                First_Name__c, 
                Email__c, 
                Friend_Email__c,
                Friend_First_Name__c,
                Friend_Last_Name__c,
                Friend_Phone__c,
                Current_Address_Abroad_State__c, 
                Current_Address_Abroad_State_Name__c,
                Current_Address_Abroad_Country__c, 
                Claimant_City__c,
                Eircode__c, 
                Contact__c, 
                Full_Current_Ad__c, 
                Agent_Making_Sale__c, 
                Step__c, 
                Agent_Form_Step__c,
                Relationship__c,
                Claimant_title__c,
                Short_Agent_Link__c, 
                Current_Address_Abroad_Country_Name__c,
                Claimant_other_names__c, 
                Claimant_dob__c, 
                Claimant_maiden_Name__c,                 
                Claimant_marital_Status__c, 
                Claimant_nationality__c, 
                Claimant_date_Of_Marriage__c, 
                Claimant_date_Of_Bereavement__c, 
                Claimant_date_Of_Divorce__c, 
                Claimant_hasNino__c, 
                Claimant_nino__c, 
                Claimant_address1__c, 
                Claimant_address2__c, 
                Claimant_ever_Lived_UK__c, 
                Claimant_lived_UK_From__c, 
                Claimant_lived_UK_to__c, 
                Claimant_Ever_Worked_UK__c, 
                Claimant_worked_UK_From__c, 
                Claimant_worked_UK_To__c, 
                Claimant_has_Proof_Of_UK_Work__c, 
                Claimant_self_Employed_UK__c, 
                Claimant_Ever_Paid_Married_Woman_s_Stam__c, 
                Claimant_Minded_Kids__c,
                Claimant_Bereavement_Benefit__c,
                Claimant_Graduated_Retirement_Benefit__c,
                Claimant_State_Pension__c,
                Claimant_Widows_Benefit__c,
                Partner_Bereavement_Benefit__c,
                Partner_Graduated_Retirement_Benefit__c,
                Partner_State_Pension__c,
                Partner_Widows_Benefit__c,
                Partner_Address1__c,
                Partner_Address2__c,
                Partner_City__c,
                Partner_Country__c,
                Partner_Country_Code__c,
                Partner_DOB__c,
                Partner_Has_Nino__c,
                Partner_Maiden_Name__c,
                Partner_Nino__c,
                Partner_Other_Name__c,
                Partner_Postcode__c,
                Partner_same_as_claimant__c,
                Partner_Surname__c,
                Partner_Title__c,
                Partner_First_Name__c,
                Partner_Full_Name__c,
                Partner_State_Code__c,
                Partner_State_Name__c,
                Pension_Claiming_from_Today__c,
                Pension_Deferred_Pension__c,
                Pension_Imprisoned_Since_Pension_Age__c,
                Pension_Start_Date__c,
                Bank_Account__c,
                Bank_Account_Owner_Name__c,
                Bank_Account_Owner_Email__c,
                Bank_Account_Type__c,
                Bank_IBAN__c,
                Bank_Name__c,
                Bank_Sort_Code__c,
                Bank_Country__c,
                Bank_Country_Code__c,
                Bank_Post_Code__c,
                Bank_City__c,
                Bank_Address__c,
                Bank_BIC__c,
                Pension_Work_After_Pension_Age__c,
                Has_Nino__c,
                Partner_Has_Nino_values__c,
                Is_envelope_created__c,
                Track__c,
                Is_Partner_alive__c,
                Partner_Left_UK__c,
                PPS__c,
                Partner_Towns_Lived__c,
                Owns_This_Account__c,
                Approx_Years_in_UK__c,
                Ever_Work_UK_approved__c,
                Ever_Live_In_UK_approved__c,
                Ever_Worked_UK_Use_Same_Dates__c,
                What_is_this_number__c,
                Paid_Interval__c,
                Partner_Ever_Lived_UK__c,
                Partner_Ever_Worked_UK__c,
                Verification_Details__c, Verification_Status__c, Verified_Reference__c, Was_Cleansed__c, Address_Validated__c,
                Partner_Verification_Details__c, Partner_Verification_Status__c, Partner_Verified_Reference__c, 
                Partner_Was_Cleansed__c, Partner_Address_Validated__c,
                Notes__c,
                Work_In_UK_during_2_years__c,
                Ever_Self_Employed_UK_after_1978__c,
                Ever_Pay_Reduced_UK_nino__c,
                DocuSign_Date__c,
                Claimant_Ever_Lived_UK_Notes__c,
                Partner_Ever_Lived_UK_Notes__c,
                Partner_Reference_on_Any_DWP_Letters__c,
                Partner_Claiming_UK_Pension__c,
                Accountant_Address__c,
                Accountant_Address_2__c,
                Accountant_City__c,
                Accountant_Country_Code__c,
                Accountant_Country_Name__c,
                Accountant_Name__c,
                Accountant_Phone__c,
                Accountant_PostCode__c,
                Accountant_State_Code__c,
                Accountant_State_Name__c,
                Do_you_have_an_accountant__c,
                Do_you_own_rent_any_UK_property__c,
                Are_you_self_assessed_for_tax__c,
                Age_Pension_now_or_next_year__c,
                Is_Your_Partner_Currently_Get_Pension__c,
                isYourPartnerCurrentlyGetPensionText__c,
                Claimant_Middle_Name__c,
                (SELECT Id, Address__c, Address_2__c, City__c, Name, Claim__c, PostCode__c  FROM Claimant_UK_Properties__r),
                (SELECT Id, Basic__c, From_date__c, Name, Country_Type__c, Social_Security_Number__c, To_Date__c, Is_Partner__c, Is_Live_Here_Now__c FROM ClaimantCountrieslived__r ),
                (SELECT Id, Basic__c, Dob__c, Name, Minded_From__c, Minded_To__c, Nino__c  FROM Clamant_Children__r),
                (SELECT Id, Basic__c, Address1__c, Address2__c, City__c, Country__c, Country_Type__c, Name, From_Date__c, To_Date__c, Postcode__c, Is_Partner__c, Is_Addresses__c, Address_Validated__c,
                Verification_Details__c, Verification_Status__c, Verified_Reference__c, Was_Cleansed__c 
                FROM Claimant_Companies__r )
                FROM Basic__c
                WHERE Id = : basicId
            ];
            
        }
        return appsData;
    }

    public static void deleteOldClaimantRelation(String basicId) {
        List<Claimant_Child__c> childrenList= new List<Claimant_Child__c>();
        List<Claimant_Company__c> companiesList= new List<Claimant_Company__c>();
        List<Claimant_Country_lived__c> countryList= new List<Claimant_Country_lived__c>();
        List<Claimant_UK_Property__c> propertyUKList = new List<Claimant_UK_Property__c>();

        childrenList = [SELECT Id, Basic__c FROM Claimant_Child__c WHERE Basic__c =: basicId];
        companiesList = [SELECT Id, Basic__c, isFullForm__c FROM Claimant_Company__c WHERE Basic__c =: basicId AND isFullForm__c = true];
        countryList = [SELECT Id, Basic__c FROM Claimant_Country_lived__c WHERE Basic__c =: basicId AND Is_Partner__c = false];
        propertyUKList = [SELECT Id, Claim__c FROM Claimant_UK_Property__c WHERE Claim__c =: basicId];

        if(childrenList.size()>0) {
            delete childrenList;
        }
        if(companiesList.size()>0) {
            delete companiesList;
        }
        if(countryList.size()>0) {
            delete countryList;
        }
        if(propertyUKList.size()>0) {
            delete propertyUKList;
        }
    }

    public static void deleteOldEnvelopeClaimantRelation(String basicId) {
        List<Claimant_Company__c> companiesList= new List<Claimant_Company__c>();

        companiesList = [SELECT Id, Basic__c FROM Claimant_Company__c WHERE Basic__c =: basicId];

        if(companiesList.size()>0) {
            delete companiesList;
        }
    }

    public static void createNewClaimantRelation(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
        List<Claimant_Child__c> childrenList= new List<Claimant_Child__c>();
        List<Claimant_Company__c> companiesList= new List<Claimant_Company__c>();
        List<Claimant_Country_lived__c> countryList= new List<Claimant_Country_lived__c>();
        List<Claimant_UK_Property__c> uKPropertyList = new List<Claimant_UK_Property__c>();

        if(wrapper?.application?.otherInformation?.UkProperties != null && wrapper?.application?.otherInformation?.UkProperties.size()>0) {
            for(BP_RequestWrappers.UkPropertiesWrapper childItem : wrapper?.application?.otherInformation?.UkProperties) {
                Claimant_UK_Property__c childRecord = new Claimant_UK_Property__c(
                    Name = childItem.city,
                    City__c = childItem.city,
                    Address__c = childItem.address1,
                    Address_2__c = childItem.address2,
                    PostCode__c = childItem.postCode,
                    Claim__c = wrapper.applicationId
                );
                uKPropertyList.add(childRecord);
            }
        }

        if(wrapper?.application?.claimant?.children != null && wrapper?.application?.claimant?.children.size()>0) {
            for(BP_RequestWrappers.ChildrenWrapper childItem : wrapper.application.claimant.children) {
                Claimant_Child__c childRecord = new Claimant_Child__c(
                    Basic__c = wrapper.applicationId,
                    Dob__c = childItem?.dob != null ? BP_PortalUtils.dateFromString(childItem?.dob)  : null,
                    Minded_From__c = childItem?.mindedFromDate != null ? BP_PortalUtils.dateFromString(childItem?.mindedFromDate) : null,
                    Minded_To__c = childItem?.mindedToDate != null ? BP_PortalUtils.dateFromString(childItem?.mindedToDate) : null,
                    Name = childItem?.name,
                    Nino__c = childItem.nino
                    
                );
                childrenList.add(childRecord);
            }
        }

        if(wrapper?.application?.claimant?.ukCompanies != null && wrapper?.application?.claimant?.ukCompanies.size()>0) {
            if(wrapper.application.claimant.everWorkedUK) {
                for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.claimant.ukCompanies) {
                if(String.isNotBlank(companyItem?.name)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                            Claimant_Company__c companyRecord = new Claimant_Company__c(
                            Basic__c = wrapper.applicationId,
                            Address1__c = companyItem?.address1,
                            Address2__c = companyItem?.address2,
                            City__c = companyItem?.city,
                            Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Country_Type__c = companyItem?.country,
                            Postcode__c = companyItem?.postcode,
                            From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                            To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                            Name = companyItem?.name,
                            Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                            Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                            Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed,
                            isFullForm__c = true
                            //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                            //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails
                            );
                            companiesList.add(companyRecord);
                        }
                        
                    }
                }
            }
        }

        if(wrapper?.application?.claimant?.countriesLived != null && wrapper?.application?.claimant?.countriesLived.size()>0) {
            for(BP_RequestWrappers.CountryLivedWrapper countryItem : wrapper.application.claimant.countriesLived) {
                if(String.isNotBlank(countryItem?.socialSecurityNumber)) {
                    Claimant_Country_lived__c countryRecord = new Claimant_Country_lived__c(
                        Basic__c = wrapper.applicationId,
                        Social_Security_Number__c = countryItem?.socialSecurityNumber,
                        From_Date__c = countryItem?.fromDate != null ? BP_PortalUtils.dateFromString(countryItem?.fromDate) : null,  
                        Name = CountryCodeHelper.getCountryNameByIsoCode(countryItem?.country),
                        Country_Type__c = countryItem?.country,
                        Is_Live_Here_Now__c = countryItem?.isLiveHereNow
                    );
                    if(countryRecord.Is_Live_Here_Now__c) {
                        countryRecord.To_Date__c = null;
                    } else {
                        countryRecord.To_Date__c = countryItem?.toDate != null ? BP_PortalUtils.dateFromString(countryItem?.toDate) : null;
                    }
                    countryList.add(countryRecord);
                }
            }
        }

        if(childrenList.size()>0){
            insert childrenList;
        }
        if(companiesList.size()>0){
            insert companiesList;
        }
        if(countryList.size()>0){
            insert countryList;
        }
        if(uKPropertyList.size()>0){
            insert uKPropertyList;
        }
    }

    public static void createNewClaimantRelationTrackA(BP_RequestWrappers.ShortApplicationDataWrapper wrapper) {
        List<Claimant_Company__c> companiesList= new List<Claimant_Company__c>();

        if(wrapper?.application?.trackA?.employers != null && wrapper?.application?.trackA?.employers.size()>0) {
            for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.trackA.employers) {
                if(String.isNotBlank(companyItem?.name)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                        Claimant_Company__c companyRecord = new Claimant_Company__c(
                        Basic__c = wrapper.applicationId,
                        Address1__c = companyItem?.address1,
                        Address2__c = companyItem?.address2,
                        City__c = companyItem?.city,
                        Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                        Country_Type__c = companyItem?.country,
                        Postcode__c = companyItem?.postcode,
                        From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                        To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                        Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                        Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                        Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed,
                    //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                        //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails,
                        Name = companyItem?.name
                        );
                        companiesList.add(companyRecord);
                    }
                    
                }
            }
        }
        if(wrapper?.application?.trackA?.addresses != null && wrapper?.application?.trackA?.addresses.size()>0) {
            for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.trackA.addresses) {
                if(String.isNotBlank(companyItem?.country)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                        Claimant_Company__c companyRecord = new Claimant_Company__c(
                            Basic__c = wrapper.applicationId,
                            Address1__c = companyItem?.address1,
                            Address2__c = companyItem?.address2,
                            City__c = companyItem?.city,
                            Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Country_Type__c = companyItem?.country,
                            Postcode__c = companyItem?.postcode,
                            From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                            To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                            Name = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Is_Addresses__c = true,
                            Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                            Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                            Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed
                            //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                            //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails
                        );
                        companiesList.add(companyRecord);
                    }
                        
                }
            }
        }

        if(companiesList.size()>0){
            insert companiesList;
        }
    }

    public static void createNewClaimantRelationTrackB(BP_RequestWrappers.ShortApplicationDataWrapper wrapper) {
        List<Claimant_Company__c> companiesList= new List<Claimant_Company__c>();

        if(wrapper?.application?.trackB?.employers != null && wrapper?.application?.trackB?.employers.size()>0) {
            for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.trackB.employers) {
                if(String.isNotBlank(companyItem?.name)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                        Claimant_Company__c companyRecord = new Claimant_Company__c(
                        Basic__c = wrapper.applicationId,
                        Address1__c = companyItem?.address1,
                        Address2__c = companyItem?.address2,
                        City__c = companyItem?.city,
                        Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                        Country_Type__c = companyItem?.country,
                        Postcode__c = companyItem?.postcode,
                        From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                        To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                        Name = companyItem?.name,
                        Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                        Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                        Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed,
                        //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                        //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails,
                        Is_Partner__c = true
                        );
                        companiesList.add(companyRecord);
                    }   
                }
            }
        }

        if(wrapper?.application?.trackB?.addresses != null && wrapper?.application?.trackB?.addresses.size()>0) {
            for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.trackB.addresses) {
                if(String.isNotBlank(companyItem?.country)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                        Claimant_Company__c companyRecord = new Claimant_Company__c(
                            Basic__c = wrapper.applicationId,
                            Address1__c = companyItem?.address1,
                            Address2__c = companyItem?.address2,
                            City__c = companyItem?.city,
                            Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Country_Type__c = companyItem?.country,
                            Postcode__c = companyItem?.postcode,
                            From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                            To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                            Name = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                            Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                            Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed,
                            //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                            //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails,
                            Is_Partner__c = true,
                            Is_Addresses__c = true
                        );
                        companiesList.add(companyRecord);
                    }
                        
                }
            }
        }

        if(companiesList.size()>0){
            insert companiesList;
        }
    }

    public static void createNewClaimantRelationTrackC(BP_RequestWrappers.ShortApplicationDataWrapper wrapper) {
        List<Claimant_Company__c> companiesList= new List<Claimant_Company__c>();

        if(wrapper?.application?.trackC?.employers != null && wrapper?.application?.trackC?.employers.size()>0) {
            for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.trackC.employers) {
                if(String.isNotBlank(companyItem?.name)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                        Claimant_Company__c companyRecord = new Claimant_Company__c(
                        Basic__c = wrapper.applicationId,
                        Address1__c = companyItem?.address1,
                        Address2__c = companyItem?.address2,
                        City__c = companyItem?.city,
                        Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                        Country_Type__c = companyItem?.country,
                        Postcode__c = companyItem?.postcode,
                        From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                        To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                        Name = companyItem?.name,
                        Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                        Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                        Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed,
                        //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                        //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails,
                        Is_Partner__c = true
                        );
                        companiesList.add(companyRecord);
                    }
                    
                }
            }
        }

        if(wrapper?.application?.trackC?.addresses != null && wrapper?.application?.trackC?.addresses.size()>0) {
            for(BP_RequestWrappers.CompaniesWrapper companyItem : wrapper.application.trackC.addresses) {
                if(String.isNotBlank(companyItem?.country)) {
                    if(String.isNotBlank(companyItem?.fromDate)) {
                        Claimant_Company__c companyRecord = new Claimant_Company__c(
                            Basic__c = wrapper.applicationId,
                            Address1__c = companyItem?.address1,
                            Address2__c = companyItem?.address2,
                            City__c = companyItem?.city,
                            Country__c = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Country_Type__c = companyItem?.country,
                            Postcode__c = companyItem?.postcode,
                            From_Date__c = companyItem?.fromDate != null ? BP_PortalUtils.dateFromString(companyItem?.fromDate) : null,
                            To_Date__c = companyItem?.toDate != null ? BP_PortalUtils.dateFromString(companyItem?.toDate) : null,
                            Name = CountryCodeHelper.getCountryNameByIsoCode(companyItem?.country),
                            Is_Partner__c = true,
                            Is_Addresses__c = true,
                            Address_Validated__c = companyItem?.addressValidated == null ? false : companyItem?.addressValidated,
                            Verification_Status__c = companyItem?.verificationStatus == null ? '' : companyItem?.verificationStatus,
                            Was_Cleansed__c = companyItem?.wasCleansed == null ? false : companyItem?.wasCleansed
                            //Verified_Reference__c = companyItem?.verifiedReference == null ? false : companyItem?.verifiedReference,
                            //Verification_Details__c = companyItem?.verificationDetails == null ? false : companyItem?.verificationDetails
                    );
                    companiesList.add(companyRecord);
                    }
                        
                }
            }
        }

        if(companiesList.size()>0){
            insert companiesList;
        }
    }

    public static void reviewUpdate(List<Basic__c> apps, BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper ) {
        String nextStep = BP_PortalUtils.currentStep(apps[0].Step__c, wrapper?.currentStep);
        String address1 = '';
        String address2 = '';
        if(String.isNotBlank(wrapper?.application?.claimant?.address1)) {
            address1 = wrapper?.application?.claimant?.address1;
        }
        if(String.isNotBlank(wrapper?.application?.claimant?.address2)) {
            address2 = wrapper?.application?.claimant?.address2;
        }
        BP_PortalUtils.deleteOldClaimantRelation(wrapper?.applicationId);
        System.debug( wrapper?.application?.claimant?.livedUKFrom);
        System.debug( wrapper?.application?.claimant?.livedUKTo);
        Basic__c updatedApp = new Basic__c(
            Id = wrapper?.applicationId,
            Friend_First_Name__c = wrapper?.application?.contactCommunication?.firstName,
            Friend_Last_Name__c = wrapper?.application?.contactCommunication?.lastName,
            Friend_Phone__c = wrapper?.application?.contactCommunication?.tel,
            Friend_Email__c = wrapper?.application?.contactCommunication?.email,
            Relationship__c = wrapper?.application?.contactCommunication?.relationship,
            Validation_Agent__c = wrapper?.application?.agent,
            Claimant_address1__c = wrapper?.application?.claimant?.address1,
            Claimant_address2__c = wrapper?.application?.claimant?.address2,
            Claimant_City__c = wrapper?.application?.claimant?.city,
            Current_Address_Abroad_Country__c = wrapper?.application?.claimant?.country,
            Current_Address_Abroad_Country_Name__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.claimant?.country),
            Claimant_date_Of_Bereavement__c = wrapper?.application?.claimant?.dateOfBereavement != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfBereavement) : null,
            Claimant_date_Of_Divorce__c = wrapper?.application?.claimant?.dateOfDivorce != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfDivorce) : null,
            Claimant_date_Of_Marriage__c = wrapper?.application?.claimant?.dateOfMarriage != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfMarriage) : null,
            Claimant_dob__c = wrapper?.application?.claimant?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dob) : null,
            Email__c = wrapper?.application?.claimant?.email,
            Claimant_ever_Lived_UK__c = wrapper?.application?.claimant?.everLivedUK,
            Claimant_Ever_Paid_Married_Woman_s_Stam__c = wrapper?.application?.claimant?.marriedWomansStamp,
            Claimant_Ever_Worked_UK__c = wrapper?.application?.claimant?.everWorkedUK,
            Claimant_has_Proof_Of_UK_Work__c = wrapper?.application?.claimant?.hasProofOfUKWork,
            Claimant_hasNino__c = wrapper?.application?.claimant?.hasNino,
            Claimant_lived_UK_From__c = wrapper?.application?.claimant?.livedUKFrom != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.livedUKFrom) : null,
            Claimant_lived_UK_to__c = wrapper?.application?.claimant?.livedUKTo != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.livedUKTo) : null,
            Claimant_maiden_Name__c = wrapper?.application?.claimant?.maidenName,
            Claimant_marital_Status__c = wrapper?.application?.claimant?.maritalStatus,
            Claimant_Minded_Kids__c = wrapper?.application?.claimant?.mindedKids,
            Claimant_nationality__c = wrapper?.application?.claimant?.nationality,
            Claimant_nino__c = wrapper?.application?.claimant?.nino,
            Claimant_other_names__c = wrapper?.application?.claimant?.otherNames,
            Claimant_Ever_Lived_UK_Notes__c = wrapper?.application?.claimant?.everLivedUKNotes,
            Current_Address_Abroad_State_Name__c = wrapper?.application?.claimant?.stateName,
            Current_Address_Abroad_State__c = wrapper?.application?.claimant?.state,
            Partner_State_Name__c = wrapper?.application?.partner?.stateName,
            Partner_State_Code__c = wrapper?.application?.partner?.state,
            Phone__c = wrapper?.application?.claimant?.tel,
            Eircode__c = wrapper?.application?.claimant?.postcode,
            Claimant_self_Employed_UK__c = wrapper?.application?.claimant?.selfEmployedUK,
            Last_Name__c = wrapper?.application?.claimant?.surname,
            First_Name__c = wrapper?.application?.claimant?.firstName,
            Claimant_Middle_Name__c = wrapper?.application?.claimant?.middleName,
            Claimant_title__c = wrapper?.application?.claimant?.title,
            Claimant_worked_UK_From__c = wrapper?.application?.claimant?.workedUKFrom != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.workedUKFrom) : null,
            Claimant_worked_UK_To__c = wrapper?.application?.claimant?.workedUKTo != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.workedUKTo) : null,
            Partner_Title__c = wrapper?.application?.partner?.title,
            Partner_Surname__c = wrapper?.application?.partner?.surname,
            Partner_Other_Name__c = wrapper?.application?.partner?.otherNames,
            Partner_DOB__c = wrapper?.application?.partner?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.partner?.dob) : null,
            Partner_Maiden_Name__c = wrapper?.application?.partner?.maidenName,
            Partner_Has_Nino__c = wrapper?.application?.partner?.hasNino,
            Partner_Nino__c = wrapper?.application?.partner?.nino,
            Partner_same_as_claimant__c = wrapper?.application?.partner?.saveAsClaimant,
            Partner_Country__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.partner?.country),
            Partner_Country_Code__c = wrapper?.application?.partner?.country,
            Partner_Postcode__c = wrapper?.application?.partner?.postcode,
            Partner_Address1__c = wrapper?.application?.partner?.address1,
            Partner_Address2__c = wrapper?.application?.partner?.address2,
            Partner_City__c = wrapper?.application?.partner?.city,
            Partner_Ever_Lived_UK_Notes__c = wrapper?.application?.partner?.everLivedUKNotes,
            Partner_Ever_Lived_UK__c = wrapper?.application?.partner?.everLivedUK,
            Partner_Ever_Worked_UK__c = wrapper?.application?.partner?.everWorkedUK,
            Claimant_Graduated_Retirement_Benefit__c = wrapper?.application?.claimantBenefits?.graduatedRetirement,
            Claimant_Bereavement_Benefit__c = wrapper?.application?.claimantBenefits?.bereavement,
            Claimant_State_Pension__c = wrapper?.application?.claimantBenefits?.statePension,
            Claimant_Widows_Benefit__c = wrapper?.application?.claimantBenefits?.widows,
            Claimant_is_Waiting_Uk_Benefits_text__c = wrapper?.application?.claimantBenefits?.isWaitingUkBenefitsText,
            Claimant_is_Waiting_Uk_Benefits__c = wrapper?.application?.claimantBenefits?.isWaitingUkBenefits,
            Partner_Graduated_Retirement_Benefit__c = wrapper?.application?.partnerBenefits?.graduatedRetirement,
            Partner_Bereavement_Benefit__c = wrapper?.application?.partnerBenefits?.bereavement,
            Partner_State_Pension__c = wrapper?.application?.partnerBenefits?.statePension,
            Partner_Widows_Benefit__c = wrapper?.application?.partnerBenefits?.widows,
            Partner_is_Waiting_Uk_Benefits_text__c = wrapper?.application?.partnerBenefits?.isWaitingUkBenefitsText,
            Partner_is_Waiting_Uk_Benefits__c = wrapper?.application?.partnerBenefits?.isWaitingUkBenefits,
            Pension_Claiming_from_Today__c = wrapper?.application?.pension?.claimingFromToday,
            Pension_Deferred_Pension__c = wrapper?.application?.pension?.deferredPension,
            Pension_Imprisoned_Since_Pension_Age__c = wrapper?.application?.pension?.imprisonedSincePensionAge,
            Pension_Start_Date__c = wrapper?.application?.pension?.startDate != null ? BP_PortalUtils.dateFromString(wrapper?.application?.pension?.startDate) : null,
            Pension_Work_After_Pension_Age__c = wrapper?.application?.pension?.workAfterPensionAge,
            Bank_Account__c = wrapper?.application?.bank?.account,
            Bank_Account_Owner_Name__c = wrapper?.application?.bank?.accountOwnerName,
            Bank_Account_Owner_Email__c = wrapper?.application?.bank?.accountOwnerEmail,
            Bank_Account_Type__c = 'Current Account',
            Bank_IBAN__c = wrapper?.application?.bank?.iban,
            Bank_Name__c = wrapper?.application?.bank?.bankName,
            Bank_Sort_Code__c = wrapper?.application?.bank?.sortCode,
            Bank_Address__c = wrapper?.application?.bank?.address,
            Bank_City__c = wrapper?.application?.bank?.city,
            Bank_Country__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.bank?.country),
            Bank_Country_Code__c = wrapper?.application?.bank?.country,
            Bank_Post_Code__c = wrapper?.application?.bank?.postcode,
            Bank_BIC__c = wrapper?.application?.bank?.bic,
            Status__c = 'Form completed',
            Val_Form_Complete__c = String.isBlank(wrapper?.application?.agent ) ? false : true,
            Owns_This_Account__c = wrapper?.application?.bank?.ownsThisAccount,
            Notes__c = wrapper?.application?.otherInformation?.notes,
            Accountant_Address__c = wrapper?.application?.otherInformation?.accountantAddress1,
            Accountant_Address_2__c = wrapper?.application?.otherInformation?.accountantAddress2,
            Accountant_City__c = wrapper?.application?.otherInformation?.accountantCity,
            Accountant_Country_Code__c = wrapper?.application?.otherInformation?.accountantCountry,
            Accountant_Country_Name__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.otherInformation?.accountantCountry),
            Accountant_Name__c = wrapper?.application?.otherInformation?.accountantName,
            Accountant_Phone__c = wrapper?.application?.otherInformation?.accountantPhone,
            Accountant_PostCode__c = wrapper?.application?.otherInformation?.accountantPostCode,
            Accountant_State_Code__c = CountryCodeHelper.getCountryStateISOByName( wrapper?.application?.otherInformation?.accountantStateName),
            Accountant_State_Name__c = wrapper?.application?.otherInformation?.accountantStateCode,   
            Do_you_have_an_accountant__c = wrapper?.application?.otherInformation?.isAccountant!= null ? wrapper?.application?.otherInformation?.isAccountant : false,
            Do_you_own_rent_any_UK_property__c = wrapper?.application?.otherInformation?.isUKproperty != null ?  wrapper?.application?.otherInformation?.isUKproperty : false,
            Are_you_self_assessed_for_tax__c = wrapper?.application?.otherInformation?.isSelfAssesedTax!= null ? wrapper?.application?.otherInformation?.isSelfAssesedTax : false,
            Age_Pension_now_or_next_year__c = wrapper?.application?.otherInformation?.isAgePension!= null ? wrapper?.application?.otherInformation?.isAgePension : false,
            Work_In_UK_during_2_years__c = wrapper?.application?.pension?.workInUKduring2years,
            Ever_Self_Employed_UK_after_1978__c = wrapper?.application?.pension?.everSelfEmployedUKafter1978,
            Ever_Pay_Reduced_UK_nino__c = wrapper?.application?.pension?.everPayReducedUKnino,
            Approx_Years_in_UK__c = wrapper?.application?.claimant?.approxYearsInUK,
            Address_Validated__c = wrapper?.application?.claimant?.addressValidated == null ? false :wrapper?.application?.claimant?.addressValidated,
            Verification_Status__c = wrapper?.application?.claimant?.verificationStatus == null ? '' :wrapper?.application?.claimant?.verificationStatus,
            Was_Cleansed__c = wrapper?.application?.claimant?.wasCleansed == null ? false : wrapper?.application?.claimant?.wasCleansed,
            Partner_First_Name__c = wrapper?.application?.partner?.firstName,
            //Verified_Reference__c = wrapper?.application?.claimant?.verifiedReference == null ? false : wrapper?.application?.claimant?.verifiedReference,
            //Verification_Details__c = wrapper?.application?.claimant?.verificationDetails == null ? false : wrapper?.application?.claimant?.verificationDetails,
            Partner_Address_Validated__c = wrapper?.application?.partner?.addressValidated == null ? false :  wrapper?.application?.partner?.addressValidated,
            Partner_Verification_Status__c = wrapper?.application?.partner?.verificationStatus == null ? '' : wrapper?.application?.partner?.verificationStatus,
            Partner_Was_Cleansed__c = wrapper?.application?.partner?.wasCleansed == null ? false : wrapper?.application?.partner?.wasCleansed,
            //Partner_Verified_Reference__c = wrapper?.application?.partner?.verifiedReference == null ? false : wrapper?.application?.partner?.verifiedReference,
            //Partner_Verification_Details__c = wrapper?.application?.partner?.verificationDetails == null ? false : wrapper?.application?.partner?.verificationDetails
            Partner_Claiming_UK_Pension__c = wrapper?.application?.partner?.claimingUKPension,
            Partner_Reference_on_Any_DWP_Letters__c = wrapper?.application?.partner?.referenceOnAnyDWPLetters,
            Is_Your_Partner_Currently_Get_Pension__c = wrapper.application?.benefits?.isYourPartnerCurrentlyGetPension!= null ? wrapper.application?.benefits?.isYourPartnerCurrentlyGetPension : false,
            isYourPartnerCurrentlyGetPensionText__c = String.isNotBlank(wrapper.application?.benefits?.isYourPartnerCurrentlyGetPensionText) ? wrapper.application?.benefits?.isYourPartnerCurrentlyGetPensionText : ''
        );
        if(wrapper?.isAgentForm) {
            String nextStepAgent = BP_PortalUtils.currentStep(apps[0].Agent_Form_Step__c, wrapper?.currentStep);
            updatedApp.Agent_Form_Step__c = nextStep;
        } else {
            updatedApp.Step__c = nextStep;
        }
        update updatedApp;
        BP_PortalUtils.createNewClaimantRelation(wrapper);

    }

    public static void autoSaveShort(BP_RequestWrappers.ShortApplicationDataWrapper wrapper ) {
        Basic__c updatedApp = new Basic__c(
            Id = wrapper.applicationId,
            Track__c = wrapper?.application?.track,
            Claimant_title__c = wrapper?.application?.client?.title,
            First_Name__c = wrapper?.application?.client?.firstName,
            Claimant_Middle_Name__c = wrapper?.application?.client?.middleName,
            Last_Name__c = wrapper?.application?.client?.lastName,
            Claimant_maiden_Name__c = wrapper?.application?.client?.maidenName,
            Claimant_dob__c = wrapper?.application?.client?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.client?.dob) : null,
            Phone__c = wrapper?.application?.client?.tel,
            Email__c = wrapper?.application?.client?.email,
            Claimant_marital_Status__c = wrapper?.application?.client?.maritalStatus,
            Claimant_date_Of_Divorce__c = wrapper?.application?.client?.dateOfDivorce != null ? BP_PortalUtils.dateFromString(wrapper?.application?.client?.dateOfDivorce) : null,
            Current_Address_Abroad_Country__c =  wrapper?.application?.client?.country,
            Current_Address_Abroad_Country_Name__c = String.isNotBlank(wrapper?.application?.client?.country) ? CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.client?.country) : '',
            PPS__c = wrapper?.application?.client?.pps,
            Friend_Email__c = wrapper?.application?.client?.helperEmail,
            CC_Helper_on_All_Comms__c = String.isNotBlank(wrapper?.application?.client?.helperEmail) ? true : false,
            Eircode__c =  wrapper?.application?.client?.postcode,
            Claimant_Address1__c =  wrapper?.application?.client?.address1,
            Claimant_Address2__c =  wrapper?.application?.client?.address2,
            Claimant_City__c =  wrapper?.application?.client?.city,
            Claimant_ever_Lived_UK__c = wrapper?.application?.client?.everLivedUK,
            Ever_Live_In_UK_approved__c = true,
            Claimant_lived_UK_to__c = wrapper?.application?.client?.dateLeftUK != null ? BP_PortalUtils.dateFromString(wrapper?.application?.client?.dateLeftUK) : null,
            Address_Validated__c = wrapper?.application?.client?.addressValidated  == null ? false : wrapper?.application?.client?.addressValidated,
            Verification_Status__c = wrapper?.application?.client?.verificationStatus  == null ? '' : wrapper?.application?.client?.verificationStatus,
            Was_Cleansed__c = wrapper?.application?.client?.wasCleansed  == null ? false : wrapper?.application?.client?.wasCleansed,
            //Verified_Reference__c = wrapper?.application?.client?.verifiedReference  == null ? false : wrapper?.application?.client?.verifiedReference,
            //Verification_Details__c = wrapper?.application?.client?.verificationDetails  == null ? false : wrapper?.application?.client?.verificationDetails
            Claimant_nationality__c = wrapper?.application?.client?.nationality,
            Approx_Years_in_UK__c = wrapper?.application?.client?.approxYearsInUK,
            Current_Address_Abroad_State_Name__c = wrapper?.application?.client?.stateName,
            Current_Address_Abroad_State__c = wrapper?.application?.client?.state
        );
        if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'A') {
            updatedApp.Claimant_nino__c = wrapper?.application?.trackA?.nino;
            updatedApp.Has_Nino__c = wrapper?.application?.trackA?.hasNino;
            if(String.isNotBlank(wrapper?.application?.trackA?.hasNino)) {
                updatedApp.Claimant_hasNino__c = wrapper?.application?.trackA?.hasNino == 'Yes' ? true : false;
            }
            if(wrapper?.application?.trackA?.isGettingUKStatePensionNow!= null) {
                updatedApp.Claimant_State_Pension__c = wrapper?.application?.trackA?.isGettingUKStatePensionNow;
            }
            
        }
        if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'B') {
            updatedApp.Partner_State_Name__c = wrapper?.application?.trackB?.stateName;
            updatedApp.Partner_State_Code__c = wrapper?.application?.trackB?.state;
            updatedApp.Is_Partner_alive__c = String.isNotBlank(wrapper?.application?.trackB?.husbandAlive) && wrapper?.application?.trackB?.husbandAlive == 'Yes' ? true : false; 
            updatedApp.Claimant_State_Pension__c = wrapper?.application?.trackB?.youGettinStatePensionNow;
            updatedApp.Partner_State_Pension__c = wrapper?.application?.trackB?.husbandGettinStatePensionNow;
            updatedApp.Partner_Other_Name__c = wrapper?.application?.trackB?.husbandFullName;
            updatedApp.Partner_First_Name__c = wrapper?.application?.trackB?.husbandFirstName;
            updatedApp.Partner_Surname__c = wrapper?.application?.trackB?.husbandSurname;
            updatedApp.Partner_DOB__c = wrapper?.application?.trackB?.husbandDob != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackB?.husbandDob) : null;
            updatedApp.Claimant_date_Of_Marriage__c = wrapper?.application?.trackB?.marriageDate != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackB?.marriageDate) : null;
            updatedApp.Partner_Left_UK__c = wrapper?.application?.trackB?.husbandLeftUk != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackB?.husbandLeftUk) : null;
            updatedApp.Partner_same_as_claimant__c = wrapper?.application?.trackB?.sameAddress;
            updatedApp.Partner_Country__c = String.isNotBlank(wrapper?.application?.trackB?.country) ? CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.trackB?.country) : '';
            updatedApp.Partner_Country_Code__c = wrapper?.application?.trackB?.country;
            updatedApp.Partner_Postcode__c = wrapper?.application?.trackB?.postcode;
            updatedApp.Partner_Address1__c = wrapper?.application?.trackB?.address1;
            updatedApp.Partner_Address2__c = wrapper?.application?.trackB?.address2;
            updatedApp.Partner_City__c = wrapper?.application?.trackB?.city;
            updatedApp.Partner_Has_Nino_values__c = wrapper?.application?.trackB?.husbandHasNino;
            updatedApp.Partner_Has_Nino__c = String.isNotBlank(wrapper?.application?.trackB?.husbandHasNino) && wrapper?.application?.trackB?.husbandHasNino == 'Yes' ? true : false;
            updatedApp.Partner_Nino__c = wrapper?.application?.trackB?.husbandNino;
            updatedApp.Partner_Towns_Lived__c = wrapper?.application?.trackB?.country;
            updatedApp.Partner_Title__c = wrapper?.application?.trackB?.title;

            updatedApp.Partner_Address_Validated__c = wrapper?.application?.trackB?.addressValidated  == null ? false : wrapper?.application?.trackB?.addressValidated;
            updatedApp.Partner_Verification_Status__c = wrapper?.application?.trackB?.verificationStatus  == null ? '' : wrapper?.application?.trackB?.verificationStatus;
            updatedApp.Partner_Was_Cleansed__c = wrapper?.application?.trackB?.wasCleansed  == null ? false : wrapper?.application?.trackB?.wasCleansed;
            //updatedApp.Partner_Verified_Reference__c = wrapper?.application?.trackB?.verifiedReference  == null ? false : wrapper?.application?.trackB?.verifiedReference;
            // updatedApp.Partner_Verification_Details__c = wrapper?.application?.trackB?.verificationDetails  == null ? false : wrapper?.application?.trackB?.verificationDetails;
            
        }
        if(String.isNotBlank(wrapper?.application?.track) && wrapper?.application?.track == 'C') {
            updatedApp.Partner_DOB__c = wrapper?.application?.trackC?.wifeDob != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackC?.wifeDob) : null;
            updatedApp.Claimant_date_Of_Marriage__c = wrapper?.application?.trackC?.marriageDate != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackC?.marriageDate) : null;
            updatedApp.Partner_Left_UK__c = wrapper?.application?.trackC?.wifeLeftUK != null ? BP_PortalUtils.dateFromString( wrapper?.application?.trackC?.wifeLeftUK) : null;
            updatedApp.Partner_same_as_claimant__c = wrapper?.application?.trackC?.sameAddress;
            updatedApp.Partner_Country__c = String.isNotBlank(wrapper?.application?.trackC?.country) ? CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.trackC?.country) : '';
            updatedApp.Partner_Country_Code__c = wrapper?.application?.trackC?.country;
            updatedApp.Partner_Postcode__c = wrapper?.application?.trackC?.postcode;
            updatedApp.Partner_Address1__c = wrapper?.application?.trackC?.address1;
            updatedApp.Partner_Address2__c = wrapper?.application?.trackC?.address2;
            updatedApp.Partner_City__c = wrapper?.application?.trackC?.city;
            updatedApp.Partner_Has_Nino_values__c = wrapper?.application?.trackC?.wifeHasNino;
            updatedApp.Partner_Has_Nino__c = String.isNotBlank(wrapper?.application?.trackC?.wifeHasNino) && wrapper?.application?.trackC?.wifeHasNino == 'Yes' ? true : false;
            updatedApp.Partner_Nino__c = wrapper?.application?.trackC?.wifeNino;
            updatedApp.Partner_Address_Validated__c = wrapper?.application?.trackC?.addressValidated  == null ? false : wrapper?.application?.trackC?.addressValidated;
            updatedApp.Partner_Verification_Status__c = wrapper?.application?.trackC?.verificationStatus  == null ? '' : wrapper?.application?.trackC?.verificationStatus;
            updatedApp.Partner_Was_Cleansed__c = wrapper?.application?.trackC?.wasCleansed  == null ? false : wrapper?.application?.trackC?.wasCleansed;
            updatedApp.Partner_State_Name__c = wrapper?.application?.trackC?.stateName;
            updatedApp.Partner_State_Code__c = wrapper?.application?.trackC?.state;
            // updatedApp.Partner_Verified_Reference__c = wrapper?.application?.trackC?.verifiedReference  == null ? false : wrapper?.application?.trackC?.verifiedReference;
            //updatedApp.Partner_Verification_Details__c = wrapper?.application?.trackC?.verificationDetails  == null ? false : wrapper?.application?.trackC?.verificationDetails;
        }
        update updatedApp;
    }

    // Which Basic__c fields autoSave() writes from each section of the form payload.
    // A partial autosave (isPartial) only writes the fields of the sections it actually received.
    private static final Map<String, List<String>> AUTOSAVE_SECTION_FIELDS = new Map<String, List<String>>{
        'contactCommunication' => new List<String>{ 'Friend_First_Name__c', 'Friend_Last_Name__c', 'Friend_Phone__c', 'Friend_Email__c', 'Relationship__c' },
        'agent' => new List<String>{ 'Validation_Agent__c' },
        'claimant' => new List<String>{ 'Claimant_address1__c', 'Claimant_address2__c', 'Claimant_City__c', 'Current_Address_Abroad_Country__c', 'Current_Address_Abroad_Country_Name__c', 'Claimant_date_Of_Bereavement__c', 'Claimant_date_Of_Divorce__c', 'Claimant_date_Of_Marriage__c', 'Claimant_dob__c', 'Email__c', 'Claimant_ever_Lived_UK__c', 'Claimant_Ever_Paid_Married_Woman_s_Stam__c', 'Claimant_Ever_Worked_UK__c', 'Claimant_has_Proof_Of_UK_Work__c', 'Claimant_hasNino__c', 'Claimant_lived_UK_From__c', 'Claimant_lived_UK_to__c', 'Claimant_maiden_Name__c', 'Claimant_marital_Status__c', 'Claimant_Minded_Kids__c', 'Claimant_nationality__c', 'Claimant_nino__c', 'Claimant_other_names__c', 'Current_Address_Abroad_State_Name__c', 'Current_Address_Abroad_State__c', 'Phone__c', 'Eircode__c', 'Claimant_self_Employed_UK__c', 'Last_Name__c', 'First_Name__c', 'Claimant_Middle_Name__c', 'Claimant_title__c', 'Claimant_worked_UK_From__c', 'Claimant_worked_UK_To__c', 'Address_Validated__c', 'Verification_Status__c', 'Was_Cleansed__c' },
        'partner' => new List<String>{ 'Partner_State_Name__c', 'Partner_State_Code__c', 'Partner_Title__c', 'Partner_Surname__c', 'Partner_Other_Name__c', 'Partner_First_Name__c', 'Partner_DOB__c', 'Partner_Maiden_Name__c', 'Partner_Has_Nino__c', 'Partner_Nino__c', 'Partner_same_as_claimant__c', 'Partner_Country__c', 'Partner_Country_Code__c', 'Partner_Postcode__c', 'Partner_Address1__c', 'Partner_Address2__c', 'Partner_Claiming_UK_Pension__c', 'Partner_Reference_on_Any_DWP_Letters__c', 'Partner_City__c', 'Partner_Address_Validated__c', 'Partner_Verification_Status__c', 'Partner_Was_Cleansed__c' },
        'claimantBenefits' => new List<String>{ 'Claimant_Graduated_Retirement_Benefit__c', 'Claimant_Bereavement_Benefit__c', 'Claimant_State_Pension__c', 'Claimant_Widows_Benefit__c', 'Claimant_is_Waiting_Uk_Benefits_text__c', 'Claimant_is_Waiting_Uk_Benefits__c' },
        'partnerBenefits' => new List<String>{ 'Partner_Graduated_Retirement_Benefit__c', 'Partner_Bereavement_Benefit__c', 'Partner_State_Pension__c', 'Partner_Widows_Benefit__c', 'Partner_is_Waiting_Uk_Benefits_text__c', 'Partner_is_Waiting_Uk_Benefits__c' },
        'pension' => new List<String>{ 'Pension_Claiming_from_Today__c', 'Pension_Deferred_Pension__c', 'Pension_Imprisoned_Since_Pension_Age__c', 'Pension_Start_Date__c', 'Pension_Work_After_Pension_Age__c' },
        'bank' => new List<String>{ 'Bank_Account__c', 'Bank_Account_Owner_Name__c', 'Bank_Account_Owner_Email__c', 'Bank_IBAN__c', 'Bank_Name__c', 'Bank_Sort_Code__c', 'Bank_Address__c', 'Bank_City__c', 'Bank_Country__c', 'Bank_Country_Code__c', 'Bank_Post_Code__c', 'Bank_BIC__c', 'Owns_This_Account__c' },
        'otherInformation' => new List<String>{ 'Notes__c', 'Accountant_Address__c', 'Accountant_Address_2__c', 'Accountant_City__c', 'Accountant_Country_Code__c', 'Accountant_Country_Name__c', 'Accountant_Name__c', 'Accountant_Phone__c', 'Accountant_PostCode__c', 'Accountant_State_Code__c', 'Accountant_State_Name__c', 'Do_you_have_an_accountant__c', 'Do_you_own_rent_any_UK_property__c', 'Are_you_self_assessed_for_tax__c', 'Age_Pension_now_or_next_year__c' },
        'benefits' => new List<String>{ 'Is_Your_Partner_Currently_Get_Pension__c', 'isYourPartnerCurrentlyGetPensionText__c' }
    };

    private static Basic__c onlySentSections(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper, Basic__c fullUpdate) {
        if (wrapper.isPartial != true || wrapper.sentSections == null) {
            return fullUpdate;
        }
        Set<String> skipped = new Set<String>();
        for (String section : AUTOSAVE_SECTION_FIELDS.keySet()) {
            if (!wrapper.sentSections.contains(section)) {
                for (String fieldName : AUTOSAVE_SECTION_FIELDS.get(section)) {
                    skipped.add(fieldName.toLowerCase());
                }
            }
        }
        Basic__c partialUpdate = new Basic__c(Id = fullUpdate.Id);
        Map<String, Object> populated = fullUpdate.getPopulatedFieldsAsMap();
        for (String fieldName : populated.keySet()) {
            if (fieldName != 'Id' && !skipped.contains(fieldName.toLowerCase())) {
                partialUpdate.put(fieldName, populated.get(fieldName));
            }
        }
        return partialUpdate;
    }

    public static void autoSave(BP_RequestWrappers.ApplicationDetailsDataWrapper wrapper ) {
        String address1 = '';
        String address2 = '';
        if(String.isNotBlank(wrapper?.application?.claimant?.address1)) {
            address1 = wrapper?.application?.claimant?.address1;
        }
        if(String.isNotBlank(wrapper?.application?.claimant?.address2)) {
            address2 = wrapper?.application?.claimant?.address2;
        }
        Basic__c updatedApp = new Basic__c(
            Id = wrapper?.applicationId,
            Friend_First_Name__c = wrapper?.application?.contactCommunication?.firstName,
            Friend_Last_Name__c = wrapper?.application?.contactCommunication?.lastName,
            Friend_Phone__c = wrapper?.application?.contactCommunication?.tel,
            Friend_Email__c = wrapper?.application?.contactCommunication?.email,
            Relationship__c = wrapper?.application?.contactCommunication?.relationship,
            Validation_Agent__c = wrapper?.application?.agent,
            Claimant_address1__c = wrapper?.application?.claimant?.address1,
            Claimant_address2__c = wrapper?.application?.claimant?.address2,
            Claimant_City__c = wrapper?.application?.claimant?.city,
            Current_Address_Abroad_Country__c = wrapper?.application?.claimant?.country,
            Current_Address_Abroad_Country_Name__c = String.isNotBlank(wrapper?.application?.claimant?.country) ? CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.claimant?.country) : '',
            Claimant_date_Of_Bereavement__c = wrapper?.application?.claimant?.dateOfBereavement != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfBereavement) : null,
            Claimant_date_Of_Divorce__c = wrapper?.application?.claimant?.dateOfDivorce != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfDivorce) : null,
            Claimant_date_Of_Marriage__c = wrapper?.application?.claimant?.dateOfMarriage != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dateOfMarriage) : null,
            Claimant_dob__c = wrapper?.application?.claimant?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.dob) : null,
            Email__c = wrapper?.application?.claimant?.email,
            Claimant_ever_Lived_UK__c = wrapper?.application?.claimant?.everLivedUK,
            Claimant_Ever_Paid_Married_Woman_s_Stam__c = wrapper?.application?.claimant?.marriedWomansStamp,
            Claimant_Ever_Worked_UK__c = wrapper?.application?.claimant?.everWorkedUK,
            Claimant_has_Proof_Of_UK_Work__c = wrapper?.application?.claimant?.hasProofOfUKWork,
            Claimant_hasNino__c = wrapper?.application?.claimant?.hasNino,
            Claimant_lived_UK_From__c = wrapper?.application?.claimant?.livedUKFrom != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.livedUKFrom) : null,
            Claimant_lived_UK_to__c = wrapper?.application?.claimant?.livedUKTo != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.livedUKTo) : null,
            Claimant_maiden_Name__c = wrapper?.application?.claimant?.maidenName,
            Claimant_marital_Status__c = wrapper?.application?.claimant?.maritalStatus,
            Claimant_Minded_Kids__c = wrapper?.application?.claimant?.mindedKids,
            Claimant_nationality__c = wrapper?.application?.claimant?.nationality,
            Claimant_nino__c = wrapper?.application?.claimant?.nino,
            Claimant_other_names__c = wrapper?.application?.claimant?.otherNames,
            Current_Address_Abroad_State_Name__c = wrapper?.application?.claimant?.stateName,
            Current_Address_Abroad_State__c = wrapper?.application?.claimant?.state,
            Partner_State_Name__c = wrapper?.application?.partner?.stateName,
            Partner_State_Code__c = wrapper?.application?.partner?.state,
            Phone__c = wrapper?.application?.claimant?.tel,
            Eircode__c = wrapper?.application?.claimant?.postcode,
            Claimant_self_Employed_UK__c = wrapper?.application?.claimant?.selfEmployedUK,
            Last_Name__c = wrapper?.application?.claimant?.surname,
            First_Name__c = wrapper?.application?.claimant?.firstName,
            Claimant_Middle_Name__c = wrapper?.application?.claimant?.middleName,
            Claimant_title__c = wrapper?.application?.claimant?.title,
            Claimant_worked_UK_From__c = wrapper?.application?.claimant?.workedUKFrom != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.workedUKFrom) : null,
            Claimant_worked_UK_To__c = wrapper?.application?.claimant?.workedUKTo != null ? BP_PortalUtils.dateFromString(wrapper?.application?.claimant?.workedUKTo) : null,
            Partner_Title__c = wrapper?.application?.partner?.title,
            Partner_Surname__c = wrapper?.application?.partner?.surname,
            Partner_Other_Name__c = wrapper?.application?.partner?.otherNames,
            Partner_First_Name__c = wrapper?.application?.partner?.firstName,
            Partner_DOB__c = wrapper?.application?.partner?.dob != null ? BP_PortalUtils.dateFromString(wrapper?.application?.partner?.dob) : null,
            Partner_Maiden_Name__c = wrapper?.application?.partner?.maidenName,
            Partner_Has_Nino__c = wrapper?.application?.partner?.hasNino,
            Partner_Nino__c = wrapper?.application?.partner?.nino,
            Partner_same_as_claimant__c = wrapper?.application?.partner?.saveAsClaimant,
            Partner_Country__c =  String.isNotBlank(wrapper?.application?.partner?.country) ? CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.partner?.country) : '',
            Partner_Country_Code__c = wrapper?.application?.partner?.country,
            Partner_Postcode__c = wrapper?.application?.partner?.postcode,
            Partner_Address1__c = wrapper?.application?.partner?.address1,
            Partner_Address2__c = wrapper?.application?.partner?.address2,
            Partner_Claiming_UK_Pension__c = wrapper?.application?.partner?.claimingUKPension,
            Partner_Reference_on_Any_DWP_Letters__c = wrapper?.application?.partner?.referenceOnAnyDWPLetters,
            Partner_City__c = wrapper?.application?.partner?.city,
            Claimant_Graduated_Retirement_Benefit__c = wrapper?.application?.claimantBenefits?.graduatedRetirement,
            Claimant_Bereavement_Benefit__c = wrapper?.application?.claimantBenefits?.bereavement,
            Claimant_State_Pension__c = wrapper?.application?.claimantBenefits?.statePension,
            Claimant_Widows_Benefit__c = wrapper?.application?.claimantBenefits?.widows,
            Claimant_is_Waiting_Uk_Benefits_text__c = wrapper?.application?.claimantBenefits?.isWaitingUkBenefitsText,
            Claimant_is_Waiting_Uk_Benefits__c = wrapper?.application?.claimantBenefits?.isWaitingUkBenefits,
            Partner_Graduated_Retirement_Benefit__c = wrapper?.application?.partnerBenefits?.graduatedRetirement,
            Partner_Bereavement_Benefit__c = wrapper?.application?.partnerBenefits?.bereavement,
            Partner_State_Pension__c = wrapper?.application?.partnerBenefits?.statePension,
            Partner_Widows_Benefit__c = wrapper?.application?.partnerBenefits?.widows,
            Partner_is_Waiting_Uk_Benefits_text__c = wrapper?.application?.partnerBenefits?.isWaitingUkBenefitsText,
            Partner_is_Waiting_Uk_Benefits__c = wrapper?.application?.partnerBenefits?.isWaitingUkBenefits,
            Pension_Claiming_from_Today__c = wrapper?.application?.pension?.claimingFromToday,
            Pension_Deferred_Pension__c = wrapper?.application?.pension?.deferredPension,
            Pension_Imprisoned_Since_Pension_Age__c = wrapper?.application?.pension?.imprisonedSincePensionAge,
            Pension_Start_Date__c = wrapper?.application?.pension?.startDate != null ? BP_PortalUtils.dateFromString(wrapper?.application?.pension?.startDate) : null,
            Pension_Work_After_Pension_Age__c = wrapper?.application?.pension?.workAfterPensionAge,
            Bank_Account__c = wrapper?.application?.bank?.account,
            Bank_Account_Owner_Name__c = wrapper?.application?.bank?.accountOwnerName,
            Bank_Account_Owner_Email__c = wrapper?.application?.bank?.accountOwnerEmail,
            Bank_Account_Type__c = 'Current Account',
            Bank_IBAN__c = wrapper?.application?.bank?.iban,
            Bank_Name__c = wrapper?.application?.bank?.bankName,
            Bank_Sort_Code__c = wrapper?.application?.bank?.sortCode,
            Bank_Address__c = wrapper?.application?.bank?.address,
            Bank_City__c = wrapper?.application?.bank?.city,
            Bank_Country__c = String.isNotBlank(wrapper?.application?.bank?.country) ? CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.bank?.country) : '',
            Bank_Country_Code__c = wrapper?.application?.bank?.country,
            Bank_Post_Code__c = wrapper?.application?.bank?.postcode,
            Bank_BIC__c = wrapper?.application?.bank?.bic,
            Owns_This_Account__c = wrapper?.application?.bank?.ownsThisAccount,
            Address_Validated__c = wrapper?.application?.claimant?.addressValidated == null ? false :wrapper?.application?.claimant?.addressValidated,
            Verification_Status__c = wrapper?.application?.claimant?.verificationStatus == null ? '' :wrapper?.application?.claimant?.verificationStatus,
            Was_Cleansed__c = wrapper?.application?.claimant?.wasCleansed == null ? false : wrapper?.application?.claimant?.wasCleansed,
            Partner_Address_Validated__c = wrapper?.application?.partner?.addressValidated == null ? false :  wrapper?.application?.partner?.addressValidated,
            Partner_Verification_Status__c = wrapper?.application?.partner?.verificationStatus == null ? '' : wrapper?.application?.partner?.verificationStatus,
            Partner_Was_Cleansed__c = wrapper?.application?.partner?.wasCleansed == null ? false : wrapper?.application?.partner?.wasCleansed,
            Notes__c = wrapper?.application?.otherInformation?.notes,
            Accountant_Address__c = wrapper?.application?.otherInformation?.accountantAddress1,
            Accountant_Address_2__c = wrapper?.application?.otherInformation?.accountantAddress2,
            Accountant_City__c = wrapper?.application?.otherInformation?.accountantCity,
            Accountant_Country_Code__c = wrapper?.application?.otherInformation?.accountantCountry,
            Accountant_Country_Name__c = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.application?.otherInformation?.accountantCountry),
            Accountant_Name__c = wrapper?.application?.otherInformation?.accountantName,
            Accountant_Phone__c = wrapper?.application?.otherInformation?.accountantPhone,
            Accountant_PostCode__c = wrapper?.application?.otherInformation?.accountantPostCode,
            Accountant_State_Code__c = CountryCodeHelper.getCountryStateISOByName( wrapper?.application?.otherInformation?.accountantStateName),
            Accountant_State_Name__c = wrapper?.application?.otherInformation?.accountantStateCode,   
            Do_you_have_an_accountant__c = wrapper?.application?.otherInformation?.isAccountant != null ? wrapper?.application?.otherInformation?.isAccountant : false,
            Do_you_own_rent_any_UK_property__c = wrapper?.application?.otherInformation?.isUKproperty != null ?  wrapper?.application?.otherInformation?.isUKproperty : false,
            Are_you_self_assessed_for_tax__c = wrapper?.application?.otherInformation?.isSelfAssesedTax!= null ? wrapper?.application?.otherInformation?.isSelfAssesedTax : false,
            Age_Pension_now_or_next_year__c = wrapper?.application?.otherInformation?.isAgePension!= null ? wrapper?.application?.otherInformation?.isAgePension : false,
            Is_Your_Partner_Currently_Get_Pension__c = wrapper.application?.benefits?.isYourPartnerCurrentlyGetPension!= null ? wrapper.application?.benefits?.isYourPartnerCurrentlyGetPension : false,
            isYourPartnerCurrentlyGetPensionText__c = String.isNotBlank(wrapper.application?.benefits?.isYourPartnerCurrentlyGetPensionText) ? wrapper.application?.benefits?.isYourPartnerCurrentlyGetPensionText : ''
        );
        update onlySentSections(wrapper, updatedApp);
    }

    public static String currentStep(String currentStepBasic, Integer outputCurrentStep){
        if(outputCurrentStep!= null && outputCurrentStep == 1) {
            return 'About the Claimant';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 2) {
            return 'About your husband, wife or civil partner';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 3) {
            return 'About Partner';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 4) {
            return 'Have you (Claimant) Ever Claimed';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 5) {
            return 'Has Partner Ever Claimed';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 6) {
            return 'Are You Claiming Pension from Today?';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 7) {
            return 'Benefits';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 8) {
            return 'Bank Details';
        }
        if(outputCurrentStep!=null && outputCurrentStep == 9) {
            return 'Review';
        }
        return currentStepBasic;
    } 

    public static Integer outputCurrentStep (String currentStep) {
        if(currentStep == 'Friend / Family for Communication') {
            return 1;
        }
        if(currentStep == 'About the Claimant'){
            return 2;
        }
        if(currentStep == 'About your husband, wife or civil partner') {
            return 3;
        }
        if(currentStep == 'About Partner') {
            return 4;
        }
        if(currentStep == 'Have you (Claimant) Ever Claimed') {
            return 5;
        }
        if(currentStep == 'Has Partner Ever Claimed') {
            return 6;
        }
        if(currentStep == 'Are You Claiming Pension from Today?') {
            return 7;
        }
        if(currentStep == 'Benefits') {
            return 8;
        }
        if(currentStep == 'Bank Details') {
            return 9;
        }
        if(currentStep == 'Review') {
            return 10;
        }
        return 1;
    }

public static void sendValidationEmail(String basicId, List<String> ListStringField) {
    String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
    Basic__c app = [SELECT Id, Contact__c, Email__c, First_Name__c, Friend_Email__c,  CC_Helper_on_All_Comms__c, CurrencyIsoCode FROM Basic__c WHERE Id =: basicId];
    OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
    ];  
    String targetEmail = app.Email__c;
    String ccEmail = '';
    if(app.CC_Helper_on_All_Comms__c) {
        ccEmail = app.Friend_Email__c;
    }

        String missingItems = '';

    for (String item : listStringField) {
        missingItems += '<li>' + item.escapeHtml4() + '</li>';
    }

    String htmlBody =
        '<html>' +
        '<body style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#333;">' +

        '<p>Hi <b>' + app.First_Name__c + '</b>,</p>' +

        '<p>As discussed, to proceed with your claim, we need a bit more information from you.</p>' +

        '<div style="padding:15px;margin:20px 0;">' +
            '<b>Send us via WhatsApp:</b> +353 (0)83 123 4000<br/><br/>' +
            'or <b>Just Reply to This Email!</b>' +
        '</div>' +

        '<p style="font-size:16px;">' +
            '<b>*** WE URGENTLY NEED YOUR…</b>' +
        '</p>' +

        '<hr/>' +
        '<ul>' +
            missingItems +
        '</ul>' +

        '<hr/>' +

        '<p>If you have questions / problems, just reply to this email.</p>' +

        '<br/>' +

        '<p>' +
            'Best wishes,<br/>' +
            '<b>Client Support</b>' +
        '</p>' +

        '<p>' +
            '<b>XtraPension Ltd</b><br/>' +
            'Galway, Ireland<br/><br/>' +

            'M-F: 8am – 6pm | Sat: 9am – 3pm<br/>' + 

            '<a href="https://xtrapension.com">xtrapension.com</a><br/>' +
            '<b>Tel:</b> +353 (0)91 335 583<br/>' +
            '<b>Email:</b> clients@xtrapension.com<br/>' +
            '<b>WhatsApp:</b>  +353 (0)83 123 4000' +
        '</p>' +

        '</body>' +
        '</html>';

    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{targetEmail});

    if (String.isNotBlank(ccEmail)) {
        mail.setCcAddresses(new List<String>{ccEmail});
    }

    mail.setSubject('XtraPension outstanding info');
    mail.setHtmlBody(htmlBody);
    if (owea.size() > 0) {
        mail.setOrgWideEmailAddressId(owea.get(0).Id);
    }
    if(!Test.isRunningTest()) {
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
    


}
    // Templated e-mails need a target Contact. Claims created outside application/create (e.g. by hand) can have
    // no Contact__c, so fall back to the contact with the claim's e-mail address and remember it on the claim.
    // Returns null (and logs why) when there is none, so the failure is visible instead of an exception in a future call.
    public static Id resolveEmailContactId(Id claimId, String emailKind) {
        List<Basic__c> claims = [SELECT Id, Name, Contact__c, Email__c FROM Basic__c WHERE Id = :claimId LIMIT 1];
        if (claims.isEmpty()) {
            return null;
        }
        Basic__c claim = claims[0];
        if (claim.Contact__c != null) {
            return claim.Contact__c;
        }
        if (String.isNotBlank(claim.Email__c)) {
            List<Contact> matches = [
                SELECT Id FROM Contact WHERE Email = :claim.Email__c ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!matches.isEmpty()) {
                update new Basic__c(Id = claim.Id, Contact__c = matches[0].Id);
                return matches[0].Id;
            }
        }
        insert new Application_Form_Error__c(
            Error_Body__c = emailKind + ' e-mail was not sent for claim ' + claim.Name + ' (' + claim.Id
                + '): the claim has no Contact and no Contact matches its e-mail address.',
            Error_Date__c = Date.today()
        );
        return null;
    }

    public static void sendPaidEmail(String basicId) {
    String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> claimEmailTemplate = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = 'BP_Claim'
        ];
        List<EmailTemplate> claimEmailTemplateEU = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = 'BP_EU_Claim'
        ];

        List<EmailTemplate> claimEmailTemplateAU = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = 'BP_AU_Claim'
        ];

        Basic__c app = [SELECT Id, Contact__c, Email__c, Friend_Email__c,  CurrencyIsoCode FROM Basic__c WHERE Id =: basicId];
        Id contactId = resolveEmailContactId(app.Id, 'Paid');
        if (contactId == null) {
            return;
        }
        // The Paid template is related to the deposit payment; without one (claim created by hand) there is nothing to send
        List<Basic_Payment__c> basePayments = Test.isRunningTest()
            ? [SELECT Id FROM Basic_Payment__c LIMIT 1]
            : [SELECT Id FROM Basic_Payment__c WHERE Basic__c =: app.Id AND Product__r.Name = 'Claim - Deposit' LIMIT 1];
        if (basePayments.isEmpty()) {
            insert new Application_Form_Error__c(
                Error_Body__c = 'Paid e-mail was not sent for claim ' + app.Id + ': it has no "Claim - Deposit" payment.',
                Error_Date__c = Date.today()
            );
            return;
        }
        Id whatId = basePayments[0].Id;

        Messaging.SingleEmailMessage messageClaim = new Messaging.SingleEmailMessage();
        messageClaim.setTargetObjectId(contactId);
        if(app.Friend_Email__c != null) {
            messageClaim.setCcAddresses(new List<String>{app.Friend_Email__c});
        }
        messageClaim.setUseSignature(false);
        messageClaim.setBccSender(false);
        messageClaim.setSaveAsActivity(true);
        if (claimEmailTemplate.size() > 0 && app.CurrencyIsoCode == 'AUD') {
            messageClaim.setTemplateID(claimEmailTemplateAU[0].Id);
        } else if (claimEmailTemplateEU.size() > 0 && app.CurrencyIsoCode == 'EUR') {
            messageClaim.setTemplateID(claimEmailTemplateEU[0].Id);
        } else {
            messageClaim.setTemplateID(claimEmailTemplate[0].Id);
        }
        messageClaim.setWhatId(whatId);
        if (owea.size() > 0) {
            messageClaim.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        if(!Test.isRunningTest()) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> { messageClaim};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
}
public static void sendRegistrationEmail(String basicId) {
        String BP_REGISTRATION_EMAIL_TEMPLATE_NAME = XtraPension_Data__c.getInstance().BP_Registration_template__c;
        String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> registrationEmailTemplate = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :BP_REGISTRATION_EMAIL_TEMPLATE_NAME
        ];
        
        Basic__c app = [SELECT Id, Contact__c, Email__c, Friend_Email__c,  CurrencyIsoCode FROM Basic__c WHERE Id =: basicId];
        Id contactId = resolveEmailContactId(app.Id, 'Registration');
        if (contactId == null) {
            return;
        }
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(contactId);
        if(app.Friend_Email__c != null) {
            if(app.Friend_Email__c != app.Email__c) {
                message.setCcAddresses(new List<String>{app.Friend_Email__c});
            }         
        }
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        if (registrationEmailTemplate.size() > 0) {
            message.setTemplateID(registrationEmailTemplate[0].Id);
        }
        message.setWhatId(app.Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        if(!Test.isRunningTest()) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    public static void sendFriendEmail(String basicId) {
        String ORG_WIDE_EMAIL_ADDRESS = 'clients@xtrapension.com';
        
        
        Basic__c app = [SELECT Id, Contact__c, Email__c, Friend_Email__c,  CurrencyIsoCode FROM Basic__c WHERE Id =: basicId];
        if(app.Friend_Email__c == null) {
            return;
        }
        Id contactId = resolveEmailContactId(app.Id, 'Helper welcome');
        if (contactId == null) {
            return;
        }
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
        ];
        List<EmailTemplate> friendEmailTemplate = [
            SELECT
                Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :'BP_Helper_Welcome'
        ];
        
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(contactId);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (friendEmailTemplate.size() > 0) {
            message.setTemplateID(friendEmailTemplate[0].Id);
        }
        message.setToAddresses(new String[] {
            app.Friend_Email__c
        });
        message.setWhatId(app.Id);
        if (owea.size() > 0) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        Messaging.SingleEmailMessage messageForFriend = new Messaging.SingleEmailMessage();
        if(!Test.isRunningTest()) {
            Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
            Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        }
    }

    public static List<String> generateValidationEmail(String basicId) {
        List<String> missingFields = new List<String>();
        List<Basic__c> appList =  getApplication(basicId);
        Basic__c app = appList[0];
        missingFields =  getEmptyFieldLabels(app, FIELDS_REQUIRED); 
        List<String> missingConditional = getEmptyFieldsConditionalLabel(app);
        missingFields.addAll(missingConditional);
        return missingFields;    
    }

    

    public static ContentVersion createContentVersion(String base64, String fileName, String fileType) {
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.VersionData = EncodingUtil.base64Decode(base64);
        contentVersion.Title = fileName;
        contentVersion.PathOnClient = fileName + '.' + fileType;
        insert contentVersion;

        return contentVersion;
    }

    public static ContentDocumentLink createContentLink(String contentVersionId, String recordId) {
        if (contentVersionId == null || recordId == null) {
            return null;
        }
        ContentDocumentLink contentDocumentLink = new ContentDocumentLink();
        contentDocumentLink.ContentDocumentId = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
        ].ContentDocumentId;
        contentDocumentLink.LinkedEntityId = recordId;
        contentDocumentLink.ShareType = 'V';
        System.debug(contentDocumentLink);
        insert contentDocumentLink;
        return contentDocumentLink;
    }
    public static Date dateFromString(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        return Date.valueOf(dateString.substringBefore('T'));
    }

    public static String getCurrencySymbol(String isoCode) {
    return CURRENCY_SYMBOLS.containsKey(isoCode)
        ? CURRENCY_SYMBOLS.get(isoCode)
        : '$';
    }

    public static List<String> getEmptyFieldLabels( SObject record, List<String> fieldNames) {
        List<String> emptyFields = new List<String>();

        Map<String, Schema.SObjectField> fieldsMap =
            record.getSObjectType().getDescribe().fields.getMap();

        for (String fieldName : fieldNames) {
            Object value = record.get(fieldName);

            Boolean isEmpty = value == null ||(value instanceof String && String.isBlank((String)value));

            if (isEmpty) {
                String helpText = '';
                helpText = fieldsMap.get(fieldName).getDescribe().getInlineHelpText();
                if(String.isBlank(helpText)) {
                    emptyFields.add(fieldsMap.get(fieldName).getDescribe().getLabel());
                } else {
                    emptyFields.add(helpText);
                }   
            }
        }

        return emptyFields;
    }

    // Labels for fields the caller has already decided are missing. Unlike getEmptyFieldLabels it does not
    // re-test the value, so checkbox fields (never null) such as Is_Live_Here_Now__c can be reported.
    public static List<String> getFieldLabels(SObject record, List<String> fieldNames) {
        List<String> labels = new List<String>();
        Map<String, Schema.SObjectField> fieldsMap = record.getSObjectType().getDescribe().fields.getMap();
        for (String fieldName : fieldNames) {
            Schema.DescribeFieldResult describe = fieldsMap.get(fieldName).getDescribe();
            String helpText = describe.getInlineHelpText();
            labels.add(String.isBlank(helpText) ? describe.getLabel() : helpText);
        }
        return labels;
    }

    private static List<String> labelsForRecord(String recordName, Integer totalRecords, SObject record, List<String> missingFieldNames) {
        List<String> labels = getFieldLabels(record, missingFieldNames);
        if (totalRecords > 1) {
            for (Integer i = 0; i < labels.size(); i++) {
                labels[i] = recordName + ': ' + labels[i];
            }
        }
        return labels;
    }

    public static List<String> getEmptyFieldsConditionalLabel(Basic__c record) {
        List<String> missingFields = new List<String>();
         List<String> emptyClaimFields = new List<String>();
        if(record.ClaimantCountrieslived__r.size() == 0) {
            missingFields.add('Other Country Lived');
        } else {
            Integer position = 0;
            for(Claimant_Country_lived__c item : record.ClaimantCountrieslived__r) {
                position++;
                List<String> emptyFieldsCountryLived = new List<String>();
                if(String.isBlank(item.Country_Type__c)) {
                    emptyFieldsCountryLived.add('Country_Type__c');
                }
                if(item.From_date__c == null) {
                    emptyFieldsCountryLived.add('From_date__c');
                }
                if(String.isBlank(item.Social_Security_Number__c)) {
                    emptyFieldsCountryLived.add('Social_Security_Number__c');
                }
                if(item.To_Date__c == null && !item.Is_Live_Here_Now__c) {
                    emptyFieldsCountryLived.add('Is_Live_Here_Now__c');
                }
                missingFields.addAll(labelsForRecord('Country lived ' + position, record.ClaimantCountrieslived__r.size(), item, emptyFieldsCountryLived));
            }
        }
        if(record.Claimant_Companies__r.size() == 0) {
             //missingFields.add('UK Company Worked In');
        } else {
            Integer position = 0;
            for(Claimant_Company__c item : record.Claimant_Companies__r) {
                position++;
                List<String> emptyFieldsCompanies = new List<String>();
                if(String.isBlank(item.Address1__c)) {
                    emptyFieldsCompanies.add('Address1__c');
                }
                if(String.isBlank(item.City__c)) {
                    emptyFieldsCompanies.add('City__c');
                }
                if(String.isBlank(item.Country__c)) {
                    emptyFieldsCompanies.add('Country__c');
                }
                if(String.isBlank(item.Postcode__c)) {
                    emptyFieldsCompanies.add('Postcode__c');
                }
                if(item.From_Date__c == null) {
                    emptyFieldsCompanies.add('From_Date__c');
                }
                if(item.To_Date__c == null) {
                    emptyFieldsCompanies.add('To_Date__c');
                }
                missingFields.addAll(labelsForRecord('Company ' + position, record.Claimant_Companies__r.size(), item, emptyFieldsCompanies));
            }
        }
        if(record.Claimant_Minded_Kids__c) {
            if(record.Clamant_Children__r.size() == 0) {
                missingFields.add('Child Details');
            } else {
                Integer position = 0;
                for(Claimant_Child__c item : record.Clamant_Children__r) {
                    position++;
                    List<String> emptyFieldsChildren = new List<String>();
                    if(item.Dob__c == null) {
                        emptyFieldsChildren.add('Dob__c');
                    }
                    if(item.Minded_From__c == null) {
                        emptyFieldsChildren.add('Minded_From__c');
                    }
                    if(item.Minded_To__c == null) {
                        emptyFieldsChildren.add('Minded_To__c');
                    }
                    missingFields.addAll(labelsForRecord('Child ' + position, record.Clamant_Children__r.size(), item, emptyFieldsChildren));
                }
            }
        }

        if(record.Claimant_date_Of_Marriage__c == null &&  (record.Claimant_marital_Status__c == 'Married' || record.Claimant_marital_Status__c == 'Civil Partner')) {
            emptyClaimFields.add('Claimant_date_Of_Marriage__c');
        }
        if(record.Claimant_date_Of_Bereavement__c == null && record.Claimant_marital_Status__c == 'Widowed' ) {
            emptyClaimFields.add('Claimant_date_Of_Bereavement__c');
        }
        if(record.Claimant_date_Of_Divorce__c == null && (record.Claimant_marital_Status__c == 'Divorced' || record.Claimant_marital_Status__c == 'Separated')) {
            emptyClaimFields.add('Claimant_date_Of_Divorce__c');
        }
        if(record.Claimant_hasNino__c && String.isBlank(record.Claimant_nino__c)) {
            emptyClaimFields.add('Claimant_nino__c');
        }
        if(record.Claimant_ever_Lived_UK__c) {
            if(record.Claimant_lived_UK_From__c == null) {
                emptyClaimFields.add('Claimant_lived_UK_From__c');
            }
            if(record.Claimant_lived_UK_to__c == null) {
                emptyClaimFields.add('Claimant_lived_UK_to__c');
            }
        }
        if(record.Claimant_Ever_Worked_UK__c) {
            if(record.Claimant_worked_UK_From__c == null) {
                emptyClaimFields.add('Claimant_worked_UK_From__c');
            }
            if(record.Claimant_worked_UK_To__c == null) {
                emptyClaimFields.add('Claimant_worked_UK_To__c');
            }
        }
        if(String.isNotBlank(record.Claimant_marital_Status__c) && record.Claimant_marital_Status__c != 'Single') {
            if(String.isBlank(record.Partner_Title__c)) {
                emptyClaimFields.add('Partner_Title__c');
            }
            if(String.isBlank(record.Partner_Surname__c)) {
                emptyClaimFields.add('Partner_Surname__c');
            }
            if(record.Partner_DOB__c == null) {
                emptyClaimFields.add('Partner_DOB__c');
            }
            if(record.Partner_Has_Nino__c && String.isBlank(record.Partner_Nino__c)) {
                emptyClaimFields.add('Partner_Nino__c');
            }
            if(String.isBlank(record.Partner_Country__c)) {
                emptyClaimFields.add('Partner_Country__c');
            }
            if(String.isBlank(record.Partner_Postcode__c)) {
                emptyClaimFields.add('Partner_Postcode__c');
            }
            if(String.isBlank(record.Partner_Address1__c)) {
                emptyClaimFields.add('Partner_Address1__c');
            }
            if(String.isBlank(record.Partner_City__c)) {
                emptyClaimFields.add('Partner_City__c');
            }
        }
        if(record.Pension_Claiming_from_Today__c == false) {
            if(record.Pension_Start_Date__c == null) {
                emptyClaimFields.add('Pension_Claiming_from_Today__c');
            }
        }
        if(String.isNotBlank(record.Bank_Country__c) && record.Bank_Country__c != 'Australia') {
            if(record.Bank_IBAN__c == null) {
                emptyClaimFields.add('Bank_IBAN__c');
            }
            if(record.Bank_BIC__c == null) {
                emptyClaimFields.add('Bank_BIC__c');
            }
        }
        if(emptyClaimFields.size()>0) {
            missingFields.addAll(getFieldLabels(record, emptyClaimFields));
        }
        return missingFields;
    }

    @AuraEnabled
    public static void generateZipArchiveAfterCreatedClaim(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        List<Basic__c> apps = [
            SELECT
                First_Name__c,
                Last_Name__c,
                Name
            FROM Basic__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if(apps.size() == 0) return;
        Basic__c currentApplication = apps[0];
        List<ContentDocumentLink> cdls = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId AND (
                  ContentDocument.Title LIKE '%IPC1394_Wet_Signature' OR
                  ContentDocument.Title LIKE '%IPCBR1_Wet_Signature' OR
                  ContentDocument.Title LIKE '%_Pink' OR
                  ContentDocument.Title LIKE '%_Yellow' OR
                  ContentDocument.Title LIKE '%DWP_Authority%' OR
                  ContentDocument.Title LIKE '%Payment_Notes%'
                )
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Map<String, ContentDocumentLink> fileKeyWordByLink = new Map<String, ContentDocumentLink>();
        for (ContentDocumentLink link : cdls) {
            if (link.ContentDocument.Title.contains('IPC1394_Wet_Signature') && fileKeyWordByLink.get('IPC1394_Wet_Signature') == null) {
                fileKeyWordByLink.put('IPC1394_Wet_Signature', link);
            } else if (link.ContentDocument.Title.contains('IPCBR1_Wet_Signature') && fileKeyWordByLink.get('IPCBR1_Wet_Signature') == null) {
                fileKeyWordByLink.put('IPCBR1_Wet_Signature', link);
            } else if (link.ContentDocument.Title.contains('_Pink') && fileKeyWordByLink.get('_Pink') == null) {
                fileKeyWordByLink.put('_Pink', link);
            } else if (link.ContentDocument.Title.contains('_Yellow') && fileKeyWordByLink.get('_Yellow') == null) {
                fileKeyWordByLink.put('_Yellow', link);
            } else if (link.ContentDocument.Title.contains('DWP_Authority') && fileKeyWordByLink.get('DWP_Authority') == null) {
                fileKeyWordByLink.put('DWP_Authority', link);
            } else if (link.ContentDocument.Title.contains('Payment_Notes') && fileKeyWordByLink.get('Payment_Notes') == null) {
                fileKeyWordByLink.put('Payment_Notes', link);
            }
        }
        String errorMessage = '';
        if (fileKeyWordByLink.get('IPC1394_Wet_Signature') == null) {
            errorMessage += 'IPC1394 Wet.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('IPCBR1_Wet_Signature') == null) {
            errorMessage += 'IPCBR1 Wet.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('_Pink') == null) {
            errorMessage += 'Pink Page.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('_Yellow') == null) {
            errorMessage += 'Yellow Page.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('DWP_Authority') == null) {
            errorMessage += 'DWP Authority.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('Payment_Notes') == null) {
            errorMessage += 'Payment_Notes.pdf file is missing. \n';
        }
        if (String.isNotBlank(errorMessage)) {
            update new Basic__c(
                Id = applicationId,
                FTP_Claim_Created_ZIP_Error__c = errorMessage
            );
            return;
        }
        Compression.ZipWriter writer = new Compression.ZipWriter();

        Set<Id> contentDocumentIds = new Set<Id>();
        contentDocumentIds.add(fileKeyWordByLink.get('IPC1394_Wet_Signature').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('IPCBR1_Wet_Signature').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('_Pink').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('_Yellow').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('DWP_Authority').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('Payment_Notes').ContentDocumentId);
        

        Map<String, Id> currVers = new Map<String, Id>();
        for ( ContentVersion cv : [SELECT PathOnClient, Versiondata, ContentDocument.Title, ContentDocument.FileExtension
                                   FROM ContentVersion
                                   WHERE ContentDocumentId IN :contentDocumentIds
                                   ORDER BY CreatedDate DESC]) {
            String docName = cv.ContentDocument.Title + '.' + cv.ContentDocument.FileExtension;
            if(currVers.get(docName) == null) {
                writer.addEntry(docName, cv.versiondata);
                currVers.put(docName, cv.Id);
            }
        }
        try {
            blob zipAttachment = writer.getArchive();
            List<ContentDocumentLink> zipDoc =[
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId AND
                      ContentDocument.Title LIKE '%Stage 1%'
            ];
            update new Basic__c(Id = applicationId, FTP_Claim_Created_Send_Date__c = null, Claim_Created_ZIP_for_UPLOAD__c = true);
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Last_Name__c + '_' +
            currentApplication.Name +  '_Stage 1';
            if (zipDoc.size() != 0) {
                insert new ContentVersion (
                    ContentDocumentId = zipDoc[0].ContentDocumentId,
                    VersionData = zipAttachment,
                    PathOnClient = finalTitle + '.zip'
                );
            } else {
                ContentVersion conVer = new ContentVersion();
                conVer.ContentLocation = 'S';
                conVer.PathOnClient = finalTitle + '.zip';
                conVer.Title = finalTitle;
                conVer.VersionData = zipAttachment;
                insert conVer;
                ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

                ContentDocumentLink conDocLink = new ContentDocumentLink();
                conDocLink.LinkedEntityId = applicationId;
                conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
                conDocLink.shareType = 'I';
                conDocLink.Visibility = 'AllUsers';
                insert conDocLink;
            }
        } catch (HandledException ex) {
            update new Basic__c(
                Id = applicationId,
                FTP_Claim_Created_ZIP_Error__c = 'Error creating zip archive for application - ' + currentApplication.Name + '. Please compress PRSI file.'
            );
        }
    }

    @AuraEnabled
    public static void generateZipArchiveFullFormClaim(Id applicationId) {
        if (applicationId == null) {
            return;
        }
        List<Basic__c> apps = [
            SELECT
                First_Name__c,
                Last_Name__c,
                Name
            FROM Basic__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if(apps.size() == 0) return;
        Basic__c currentApplication = apps[0];
        List<String> missingInfo = generateValidationEmail(applicationId);
        if (!missingInfo.isEmpty()) {
            update new Basic__c(
                Id = applicationId,
                FTP_Claim_Full_Form_ZIP_Error__c = ('Full form ZIP not created, missing info: ' + String.join(missingInfo, '; ')).abbreviate(250)
            );
            return;
        }
        List<ContentDocumentLink> cdls = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :applicationId 
            AND (
                (ContentDocument.Title LIKE '%IPC1394' AND (NOT ContentDocument.Title LIKE '%IPC1394_Wet_Signature') AND (NOT ContentDocument.Title LIKE '%Payment_Notes%'))
                OR 
                (ContentDocument.Title LIKE '%IPCBR1' AND (NOT ContentDocument.Title LIKE '%IPCBR1_Wet_Signature'))
            )
            ORDER BY ContentDocument.CreatedDate DESC
        ];
        Map<String, ContentDocumentLink> fileKeyWordByLink = new Map<String, ContentDocumentLink>();
        for (ContentDocumentLink link : cdls) {
            if (link.ContentDocument.Title.contains('IPC1394') && fileKeyWordByLink.get('IPC1394') == null) {
                fileKeyWordByLink.put('IPC1394', link);
            } else if (link.ContentDocument.Title.contains('IPCBR1') && fileKeyWordByLink.get('IPCBR1') == null) {
                fileKeyWordByLink.put('IPCBR1', link);
            }
        }
        
        String errorMessage = '';
        if (fileKeyWordByLink.get('IPC1394') == null) {
            errorMessage += 'IPC1394.pdf file is missing. \n';
        }
        if (fileKeyWordByLink.get('IPCBR1') == null) {
            errorMessage += 'IPCBR1.pdf file is missing. \n';
        }
        if (String.isNotBlank(errorMessage)) {
            update new Basic__c(
                Id = applicationId,
                FTP_Claim_Full_Form_ZIP_Error__c = errorMessage
            );
            return;
        }
        Compression.ZipWriter writer = new Compression.ZipWriter();

        Set<Id> contentDocumentIds = new Set<Id>();
        contentDocumentIds.add(fileKeyWordByLink.get('IPC1394').ContentDocumentId);
        contentDocumentIds.add(fileKeyWordByLink.get('IPCBR1').ContentDocumentId);

        

        Map<String, Id> currVers = new Map<String, Id>();
        for ( ContentVersion cv : [SELECT PathOnClient, Versiondata, ContentDocument.Title, ContentDocument.FileExtension
                                   FROM ContentVersion
                                   WHERE ContentDocumentId IN :contentDocumentIds
                                   ORDER BY CreatedDate DESC]) {
            String docName = cv.ContentDocument.Title + '.' + cv.ContentDocument.FileExtension;
            if(currVers.get(docName) == null) {
                writer.addEntry(docName, cv.versiondata);
                currVers.put(docName, cv.Id);
            }
        }
        try {
            blob zipAttachment = writer.getArchive();
            List<ContentDocumentLink> zipDoc =[
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :applicationId AND
                      ContentDocument.Title LIKE '%_Stage 2%'
            ];
            update new Basic__c(
                Id = applicationId,
                FTP_Claim_Full_Form_Created_Send_Date__c = null,
               // Claim_Full_Form_ZIP_for_UPLOAD__c = true,
                FTP_Claim_Full_Form_ZIP_Error__c = null
            );
            String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Last_Name__c + '_' +
            currentApplication.Name +  '_Stage 2';
            if (zipDoc.size() != 0) {
                insert new ContentVersion (
                    ContentDocumentId = zipDoc[0].ContentDocumentId,
                    VersionData = zipAttachment,
                    PathOnClient = finalTitle + '.zip'
                );
            } else {
                ContentVersion conVer = new ContentVersion();
                conVer.ContentLocation = 'S';
                conVer.PathOnClient = finalTitle + '.zip';
                conVer.Title = finalTitle;
                conVer.VersionData = zipAttachment;
                insert conVer;
                ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

                ContentDocumentLink conDocLink = new ContentDocumentLink();
                conDocLink.LinkedEntityId = applicationId;
                conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
                conDocLink.shareType = 'I';
                conDocLink.Visibility = 'AllUsers';
                insert conDocLink;
            }
        } catch (HandledException ex) {
            update new Basic__c(
                Id = applicationId,
                FTP_Claim_Full_Form_ZIP_Error__c = 'Error creating zip archive for application - ' + currentApplication.Name + '. Please compress PRSI file.'
            );
        }
    }

    @AuraEnabled
    public static List<String> setMissing(String basicId) {
        List<String> missingFields = new List<String>();
        List<Basic__c> appList =  getApplication(basicId);
        Basic__c app = appList[0];
        missingFields =  getEmptyFieldLabels(app, FIELDS_REQUIRED); 
        List<String> missingConditional = getEmptyFieldsConditionalLabel(app);
        missingFields.addAll(missingConditional);
        String missingField = '';
        if(missingFields.size()>0) {
            for(String item : missingFields) {
                missingField = missingField  + item +  '; ';
            }
            missingField = missingField.removeEnd('; ');
        } else {
            missingField = 'Form Fully Completed';
        }
        update new Basic__c(Id = basicId, Missing_Info__c = missingField);
        return missingFields;
    }

    @AuraEnabled
    public static List<String> getMissing(String basicId) {
        List<String> missingFields = new List<String>();
        List<Basic__c> appList =  getApplication(basicId);
        Basic__c app = appList[0];
        missingFields =  getEmptyFieldLabels(app, FIELDS_REQUIRED); 
        List<String> missingConditional = getEmptyFieldsConditionalLabel(app);
        missingFields.addAll(missingConditional);
        String missingField = '';
        if(missingFields.size()>0) {
            for(String item : missingFields) {
                missingField = missingField  + item +  '; ';
            }
            missingField = missingField.removeEnd('; ');
        } else {
            missingField = 'Form Fully Completed';
        }
        return missingFields;
    }

    public static List<Basic__c> getDDMandateBasicData(String basicId) {
        List<Basic__c> basicData = new List<Basic__c>();
        if (basicId != null) {
            basicData = [
                SELECT 
                    First_Name__c,
                    Last_Name__c,
                    Bank_IBAN__c,
                    Bank_BIC__c,
                    Bank_Name__c,
                    BSB_Number__c,
                    Claimant_address1__c,
                    Claimant_address2__c,
                    Claimant_City__c,
                    Eircode__c,
                    Current_Address_Abroad_Country_Name__c,
                    Current_Address_Abroad_State_Name__c,
                    Bank_Account__c,
                    Bank_Sort_Code__c,
                    Name,
                    CurrencyIsoCode,
                    Bank_Account_Owner_Name__c
                FROM Basic__c
                WHERE Id = :basicId
            ];

        }
        return basicData;
    }
}