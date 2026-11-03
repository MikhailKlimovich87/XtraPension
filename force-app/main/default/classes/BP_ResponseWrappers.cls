public with sharing class BP_ResponseWrappers {
    public class ApplicationDataWrapper {
        @AuraEnabled public ContactCommunicationWrapper contactCommunication;
        @AuraEnabled public ClaimantWrapper claimant;
        @AuraEnabled public ClaimantBenefitsWrapper claimantBenefits;
        @AuraEnabled public PartnerBenefitsWrapper partnerBenefits;
        @AuraEnabled public PartnerWrapper partner;
        @AuraEnabled public PensionWrapper pension;
        @AuraEnabled public ClientWrapper client;
        @AuraEnabled public BankWrapper bank;
        @AuraEnabled public OtherWrapper otherInformation;
        @AuraEnabled public String applicationId;
        @AuraEnabled public String agent;
        @AuraEnabled public String name;
        @AuraEnabled public String headerTitle;
        @AuraEnabled public BenefitsWrapper benefits;
        public ApplicationDataWrapper(Basic__c app) {
            this.contactCommunication = new ContactCommunicationWrapper(app);
            this.claimant = new ClaimantWrapper(app);
            this.claimantBenefits = new ClaimantBenefitsWrapper(app);
            this.partnerBenefits = new PartnerBenefitsWrapper(app);
            this.partner = new PartnerWrapper(app);
            this.pension = new PensionWrapper(app);
            this.client = new ClientWrapper(app);
            this.bank = new BankWrapper(app);
            this.benefits = new BenefitsWrapper(app);
            this.otherInformation = new OtherWrapper(app);
            this.applicationId = app.Id;
            this.agent = app.Validation_Agent__c;
            this.name = app.Name;
            String header = '';
            if(String.isNotBlank(app.Name)) {
                header = app.Name;
            }
            header+= ' - ';
            if(String.isNotBlank(app.First_Name__c)) {
                header += app.First_Name__c +' ';
            }
             if(String.isNotBlank(app.Last_Name__c)) {
                header += app.Last_Name__c;
            }
            this.headerTitle = header;
        }
        public ApplicationDataWrapper(List<Basic__c> appList) {
            this.contactCommunication = new ContactCommunicationWrapper(appList[0]);
            this.claimant = new ClaimantWrapper(appList[0]);
            this.claimantBenefits = new ClaimantBenefitsWrapper(appList[0]);
            this.partnerBenefits = new PartnerBenefitsWrapper(appList[0]);
            this.partner = new PartnerWrapper(appList[0]);
            this.pension = new PensionWrapper(appList[0]);
            this.client = new ClientWrapper(appList[0]);
            this.bank = new BankWrapper(appList[0]);
            this.benefits = new BenefitsWrapper(appList[0]);
            this.otherInformation = new OtherWrapper(appList[0]);
            this.applicationId = appList[0].Id;
            this.agent = appList[0].Validation_Agent__c;
            this.name = appList[0].Name;
            String header = '';
            if(String.isNotBlank(appList[0].Name)) {
                header = appList[0].Name;
            }
            header+= ' - ';
            if(String.isNotBlank(appList[0].First_Name__c)) {
                header += appList[0].First_Name__c + ' ';
            }
             if(String.isNotBlank(appList[0].Last_Name__c)) {
                header += appList[0].Last_Name__c;
            }
            this.headerTitle = header;
        }
    }

    public class ContactCommunicationWrapper {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String tel;
        @AuraEnabled public String email;
        @AuraEnabled public String relationship;
        public ContactCommunicationWrapper(Basic__c app) {
            this.firstName = app.Friend_First_Name__c;
            this.lastName = app.Friend_Last_Name__c;
            this.tel = app.Friend_Phone__c;
            this.email = app.Friend_Email__c;
            this.relationship = app.Relationship__c;
        }
        
    }

    public class ClientWrapper {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String agent;
        @AuraEnabled public ClientAddress address;
        public ClientWrapper(Basic__c app) {
            this.firstName = app.First_Name__c;
            this.lastName = app.Last_Name__c;
            this.email = app.Email__c;
            this.phone = app.Phone__c;
            this.agent = app.Agent_Making_Sale__c;
            this.address = new ClientAddress(app);

        }

    }

    public class ClientAddress {
        @AuraEnabled public String state;
        @AuraEnabled public String country;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String stateCode;
        @AuraEnabled public String countryCode;
        @AuraEnabled public String stateName;
        public ClientAddress(Basic__c app) {
            this.state = app.Current_Address_Abroad_State__c;
            this.country = app.Current_Address_Abroad_Country__c;
            this.street = app.Claimant_address1__c;
            if(String.isNotBlank(app.Claimant_address2__c)) {
                this.street =  this.street + ' , ' + app.Claimant_address2__c;
            }
            this.city = app.Claimant_City__c;
            this.postalCode = app.Eircode__c;
            this.stateName = app.Current_Address_Abroad_State_Name__c;
        }

    }

    public class ClaimantWrapper {
        @AuraEnabled public String title;
        @AuraEnabled public String firstName;
        @AuraEnabled public String surname;
        @AuraEnabled  public String otherNames;
        @AuraEnabled public String middleName;
        @AuraEnabled public String dob;
        @AuraEnabled public String maidenName;
        @AuraEnabled public String tel;
        @AuraEnabled public String email;
        @AuraEnabled public String maritalStatus;
        @AuraEnabled public String nationality;
        @AuraEnabled public String dateOfMarriage;
        @AuraEnabled public String dateOfBereavement;
        @AuraEnabled public String dateOfDivorce;
        @AuraEnabled public Boolean hasNino;
        @AuraEnabled public String nino;
        //Address
        @AuraEnabled public String country;
        @AuraEnabled public String countryName;
        @AuraEnabled public String postcode;
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        // UK History
        @AuraEnabled public Boolean everLivedUK;
        @AuraEnabled public String livedUKFrom;
        @AuraEnabled public String livedUKTo;
        @AuraEnabled public Boolean everWorkedUK;
        @AuraEnabled public String workedUKFrom;
        @AuraEnabled public String workedUKTo;
        @AuraEnabled public Boolean hasProofOfUKWork;
        
        // Married / Widowed section
        @AuraEnabled public Boolean selfEmployedUK;
        @AuraEnabled public Boolean marriedWomansStamp;
        @AuraEnabled public Boolean mindedKids;
        // Dynamic lists
        @AuraEnabled public List<CountryLivedWrapper> countriesLived;
        @AuraEnabled public List<CompaniesWrapper> ukCompanies;
        @AuraEnabled public List<ChildrenWrapper> children;
        @AuraEnabled public List<CompaniesWrapper> ukCompaniesClaim;
        @AuraEnabled public List<CompaniesWrapper> ukCompaniesPartner;
        @AuraEnabled public List<CompaniesWrapper> ukHadAddress; 

        @AuraEnabled public Boolean addressValidated;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public Boolean wasCleansed;
        @AuraEnabled public Boolean everWorkedUKuseSameDates;
        @AuraEnabled public String phoneType;
        @AuraEnabled public Integer approxYearsInUK;
        @AuraEnabled public String everLivedUKNotes;
        @AuraEnabled public String state;
        @AuraEnabled public String stateName;
        //@AuraEnabled public Boolean verifiedReference;
        //@AuraEnabled public Boolean verificationDetails; 

        public ClaimantWrapper(Basic__c app) {
            this.firstName = app.First_Name__c;
            this.addressValidated = app.Address_Validated__c;
            this.verificationStatus = app.Verification_Status__c;
            this.wasCleansed = app.Was_Cleansed__c;
            this.phoneType = app.What_is_this_number__c;
            this.approxYearsInUK = app.Approx_Years_in_UK__c != null ?  app.Approx_Years_in_UK__c.intValue() : null;
            this.everLivedUKNotes = app.Claimant_Ever_Lived_UK_Notes__c;
            //this.verifiedReference = app.Verified_Reference__c;
            //this.verificationDetails = app.Verification_Details__c;
            this.state = app.Current_Address_Abroad_State__c;
            this.stateName = app.Current_Address_Abroad_State_Name__c;
            this.title = app.Claimant_title__c;
            this.surname = app.Last_Name__c;
            this.otherNames = app.Claimant_other_names__c;
            this.dob = app.Claimant_dob__c != null ? String.valueOf(app.Claimant_dob__c) + 'T00:00:00.000Z': '';
            this.maidenName = app.Claimant_maiden_Name__c;
            this.tel = app.Phone__c;
            this.email = app.Email__c;
            this.maritalStatus = app.Claimant_marital_Status__c;
            this.nationality = app.Claimant_nationality__c;
            this.dateOfMarriage = app.Claimant_date_Of_Marriage__c != null ? String.valueOf(app.Claimant_date_Of_Marriage__c) + 'T00:00:00.000Z' : '';
            this.dateOfBereavement = app.Claimant_date_Of_Bereavement__c != null ? String.valueOf(app.Claimant_date_Of_Bereavement__c) + 'T00:00:00.000Z': '';
            this.dateOfDivorce = app.Claimant_date_Of_Divorce__c != null ? String.valueOf(app.Claimant_date_Of_Divorce__c) + 'T00:00:00.000Z': '';
            this.hasNino = app.Claimant_hasNino__c;
            this.nino = app.Claimant_nino__c;
            this.country = app.Current_Address_Abroad_Country__c;
            this.countryName = app.Current_Address_Abroad_Country_Name__c;
            this.postcode = app.Eircode__c;
            this.address1 = app.Claimant_address1__c;
            this.address2 = app.Claimant_address2__c;
            this.city = app.Claimant_City__c;
            this.everLivedUK = app.Claimant_ever_Lived_UK__c;
            this.livedUKFrom = app.Claimant_lived_UK_From__c != null ? String.valueOf(app.Claimant_lived_UK_From__c) + 'T00:00:00.000Z': '';
            this.livedUKTo = app.Claimant_lived_UK_to__c != null ? String.valueOf(app.Claimant_lived_UK_to__c)+ 'T00:00:00.000Z': '';
            this.everWorkedUK = app.Ever_Work_UK_approved__c == false ? true :  app.Claimant_Ever_Worked_UK__c;
            this.workedUKFrom = app.Claimant_worked_UK_From__c != null ? String.valueOf(app.Claimant_worked_UK_From__c)+ 'T00:00:00.000Z': '';
            this.workedUKTo = app.Claimant_worked_UK_To__c != null ? String.valueOf(app.Claimant_worked_UK_To__c) + 'T00:00:00.000Z': '';
            this.hasProofOfUKWork = app.Claimant_has_Proof_Of_UK_Work__c;
            this.selfEmployedUK = app.Claimant_self_Employed_UK__c;
            this.marriedWomansStamp = app.Claimant_Ever_Paid_Married_Woman_s_Stam__c;
            this.mindedKids = app.Claimant_Minded_Kids__c;
            this.everWorkedUKuseSameDates = app.Ever_Worked_UK_Use_Same_Dates__c;
            this.middleName = app.Claimant_Middle_Name__c;
            this.countriesLived = new List<CountryLivedWrapper>();
            this.ukCompanies = new List<CompaniesWrapper>();
            this.ukCompaniesClaim = new List<CompaniesWrapper>(); 
            this.ukCompaniesPartner = new List<CompaniesWrapper>(); 
            this.ukHadAddress = new List<CompaniesWrapper>(); 
            this.children = new List<ChildrenWrapper>();
            if(app.ClaimantCountrieslived__r != null && app.ClaimantCountrieslived__r.size()>0) {    
                for(Claimant_Country_lived__c itemwrap : app.ClaimantCountrieslived__r) {
                    this.countriesLived.add(new CountryLivedWrapper(itemwrap));
                }
            }
            if(app.Clamant_Children__r != null && app.Clamant_Children__r.size()>0) {    
                for(Claimant_Child__c itemwrap : app.Clamant_Children__r) {
                    this.children.add(new ChildrenWrapper(itemwrap));
                }
            }
            if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {    
                for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                    this.ukCompanies.add(new CompaniesWrapper(itemwrap));
                    if(itemwrap.Is_Partner__c && !itemwrap.Is_Addresses__c) {
                        this.ukCompaniesPartner.add(new CompaniesWrapper(itemwrap));
                    } else if(itemwrap.Is_Addresses__c) {
                        this.ukHadAddress.add(new CompaniesWrapper(itemwrap));
                    } else {
                        this.ukCompaniesClaim.add(new CompaniesWrapper(itemwrap));
                    }
                }
            }
        }
    }

    public class CountryLivedWrapper {
        @AuraEnabled public String country;
        @AuraEnabled public String countryName;
        @AuraEnabled public String fromDate;
        @AuraEnabled public String toDate;
        @AuraEnabled public String socialSecurityNumber;
        @AuraEnabled public Boolean isLiveHereNow;
        @AuraEnabled public String recordId;
        public CountryLivedWrapper(Claimant_Country_lived__c countryApp) {
            this.country = countryApp.Country_Type__c;
            this.countryName = countryApp.Name;
            this.fromDate = countryApp.From_date__c != null ? String.valueOf(countryApp.From_date__c) + 'T00:00:00.000Z': '';
            this.socialSecurityNumber = countryApp.Social_Security_Number__c;
            this.isLiveHereNow = countryApp.Is_Live_Here_Now__c;
            this.toDate = countryApp.To_Date__c != null ? String.valueOf(countryApp.To_Date__c) + 'T00:00:00.000Z': '';
            this.toDate = countryApp.Is_Live_Here_Now__c ? String.valueOf(Date.today()) : this.toDate;
            this.recordId = countryApp.Id;
        }
    }
    public class CompaniesWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String address;
        @AuraEnabled public String country;
        @AuraEnabled public String countryName;
        @AuraEnabled public String postcode;
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        @AuraEnabled public String fromDate;
        @AuraEnabled public String toDate;

        @AuraEnabled public Boolean addressValidated;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public Boolean wasCleansed;
        @AuraEnabled public Boolean isPartner;
        //@AuraEnabled public Boolean verifiedReference;
        //@AuraEnabled public Boolean verificationDetails;

         public CompaniesWrapper(Claimant_Company__c company) {
            this.name = company.Name;
            this.fromDate = company.From_Date__c != null ? String.valueOf(company.From_Date__c) + 'T00:00:00.000Z': '';
            this.toDate = company.To_Date__c != null ? String.valueOf(company.To_Date__c) + 'T00:00:00.000Z': '';
            this.country = company.Country_Type__c;
            this.countryName = company.Country__c;
            this.postcode = company.Postcode__c;
            this.address1 = company.Address1__c;
            this.address2 = company.Address2__c;
            this.city = company.City__c;

            this.addressValidated = company.Address_Validated__c;
            this.verificationStatus = company.Verification_Status__c;
            this.wasCleansed = company.Was_Cleansed__c;
            this.isPartner = company.Is_Partner__c;
            //this.verifiedReference = company.Verified_Reference__c;
            //this.verificationDetails = company.Verification_Details__c;

        }
    }
    public class ChildrenWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String dob;
        @AuraEnabled public String mindedFromDate;
        @AuraEnabled public String mindedToDate;
        @AuraEnabled public String nino;

        public ChildrenWrapper(Claimant_Child__c child) {
            this.name = child.Name;
            this.dob = child.Dob__c != null ? String.valueOf(child.Dob__c) + 'T00:00:00.000Z': '';
            this.mindedFromDate = child.Minded_From__c != null ? String.valueOf(child.Minded_From__c) + 'T00:00:00.000Z': '';
            this.mindedToDate = child.Minded_To__c != null ? String.valueOf(child.Minded_To__c) + 'T00:00:00.000Z': '';
            this.nino = child.Nino__c;
        }
    }

    public class ClaimantBenefitsWrapper {
        @AuraEnabled public Boolean bereavement;
        @AuraEnabled public Boolean graduatedRetirement;
        @AuraEnabled public Boolean statePension;
        @AuraEnabled public Boolean widows;
        @AuraEnabled public Boolean isWaitingUkBenefits;
        @AuraEnabled public String isWaitingUkBenefitsText;

        public ClaimantBenefitsWrapper(Basic__c app) {
            this.bereavement = app.Claimant_Bereavement_Benefit__c;
            this.graduatedRetirement = app.Claimant_Graduated_Retirement_Benefit__c;
            this.statePension = app.Claimant_State_Pension__c;
            this.widows = app.Claimant_Widows_Benefit__c;
            this.isWaitingUkBenefits = app.Claimant_is_Waiting_Uk_Benefits__c;
            this.isWaitingUkBenefitsText = app.Claimant_is_Waiting_Uk_Benefits_text__c;
        }
    }

    public class PartnerBenefitsWrapper {
        @AuraEnabled public Boolean bereavement;
        @AuraEnabled public Boolean graduatedRetirement;
        @AuraEnabled public Boolean statePension;
        @AuraEnabled public Boolean widows;
        @AuraEnabled public Boolean isWaitingUkBenefits;
        @AuraEnabled public String isWaitingUkBenefitsText;
        public PartnerBenefitsWrapper(Basic__c app) {
            this.bereavement = app.Partner_Bereavement_Benefit__c;
            this.graduatedRetirement = app.Partner_Graduated_Retirement_Benefit__c;
            this.statePension = app.Partner_State_Pension__c;
            this.widows = app.Partner_Widows_Benefit__c;
            this.isWaitingUkBenefits = app.Partner_is_Waiting_Uk_Benefits__c;
            this.isWaitingUkBenefitsText = app.Partner_is_Waiting_Uk_Benefits_text__c;
        }
    }

    public class PartnerWrapper {
        @AuraEnabled public String title;
        @AuraEnabled public String surname;
        @AuraEnabled public String firstName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String otherNames;
        @AuraEnabled public String dob;
        @AuraEnabled public String maidenName;
        @AuraEnabled public Boolean hasNino;
        @AuraEnabled public String nino;
        @AuraEnabled public Boolean saveAsClaimant;
        @AuraEnabled public String country;
        @AuraEnabled public String countryName;
        @AuraEnabled public String postcode;
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String stateName;
        @AuraEnabled public Boolean addressValidated;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public Boolean wasCleansed;
        @AuraEnabled public Boolean everLivedUK;
        @AuraEnabled public Boolean everWorkedUK;
        @AuraEnabled public String everLivedUKNotes;
        //@AuraEnabled public Boolean verifiedReference;
        //@AuraEnabled public Boolean verificationDetails;
        @AuraEnabled public Boolean claimingUKPension;
        @AuraEnabled public String referenceOnAnyDWPLetters;

        public PartnerWrapper(Basic__c app) {
            this.title = app.Partner_Title__c;
            this.surname = app.Partner_Surname__c;
            this.firstName = app.Partner_First_Name__c;
            this.otherNames = app.Partner_Other_Name__c;
            this.fullName = app.Partner_Full_Name__c;
            this.dob = app.Partner_DOB__c != null ? String.valueOf(app.Partner_DOB__c) + 'T00:00:00.000Z': '';
            this.maidenName = app.Partner_Maiden_Name__c;
            this.hasNino = app.Partner_Has_Nino__c;
            this.nino = app.Partner_Nino__c;
            this.saveAsClaimant = app.Partner_same_as_claimant__c;
            this.country = app.Partner_Country_Code__c;
            this.countryName = app.Partner_Country__c;
            this.postcode = app.Partner_Postcode__c;
            this.address1 = app.Partner_Address1__c;
            this.address2 = app.Partner_Address2__c;
            this.city = app.Partner_City__c;
            this.state = app.Partner_State_Code__c;
            this.stateName = app.Partner_State_Name__c;
            this.addressValidated = app.Partner_Address_Validated__c;
            this.verificationStatus = app.Partner_Verification_Status__c;
            this.wasCleansed = app.Partner_Was_Cleansed__c;
            this.everLivedUK = app.Partner_Ever_Lived_UK__c;
            this.everWorkedUK = app.Partner_Ever_Worked_UK__c;
            this.everLivedUKNotes = app.Partner_Ever_Lived_UK_Notes__c;
            //this.verifiedReference = app.Partner_Verified_Reference__c;
            //this.verificationDetails = app.Partner_Verification_Details__c;
            this.claimingUKPension = app.Partner_Claiming_UK_Pension__c;
            this.referenceOnAnyDWPLetters = app.Partner_Reference_on_Any_DWP_Letters__c;
        }

    }

    public class PensionWrapper {
        @AuraEnabled public Boolean claimingFromToday;
        @AuraEnabled public String startDate;
        @AuraEnabled public Boolean workAfterPensionAge;
        @AuraEnabled public Boolean deferredPension;
        @AuraEnabled public Boolean imprisonedSincePensionAge;
        @AuraEnabled public Boolean workInUKduring2years;
        @AuraEnabled public Boolean everSelfEmployedUKafter1978;
        @AuraEnabled public Boolean everPayReducedUKnino;

        public PensionWrapper(Basic__c app) {
            this.claimingFromToday = app.Pension_Claiming_from_Today__c;
            this.startDate = app.Pension_Start_Date__c != null ? String.valueOf(app.Pension_Start_Date__c) + 'T00:00:00.000Z': '';
            this.workAfterPensionAge = app.Pension_Work_After_Pension_Age__c;
            this.deferredPension = app.Pension_Deferred_Pension__c == null ? true : app.Pension_Deferred_Pension__c;
            this.imprisonedSincePensionAge = app.Pension_Imprisoned_Since_Pension_Age__c;
            this.workInUKduring2years = app.Work_In_UK_during_2_years__c;
            this.everSelfEmployedUKafter1978 = app.Ever_Self_Employed_UK_after_1978__c;
            this.everPayReducedUKnino = app.Ever_Pay_Reduced_UK_nino__c;
        }
    }

    public class BankWrapper {
        @AuraEnabled public String account;
        @AuraEnabled public String accountOwnerName;
        @AuraEnabled public String accountType;
        @AuraEnabled public String bankName;
        @AuraEnabled public String iban;
        @AuraEnabled public String sortCode;
        @AuraEnabled public String address;
        @AuraEnabled public String city;
        @AuraEnabled public String country;
        @AuraEnabled public String countryName;
        @AuraEnabled public String postcode;
        @AuraEnabled public String bic;
        @AuraEnabled public String ownsThisAccount;
        @AuraEnabled public String accountOwnerEmail;
        @AuraEnabled public Boolean is4weeks;

        public BankWrapper(Basic__c app) {
            this.account = app.Bank_Account__c;
            this.accountOwnerName =  app.Bank_Account_Owner_Name__c;
            this.accountOwnerEmail = app.Bank_Account_Owner_Email__c;
            this.accountType =  app.Bank_Account_Type__c;
            this.bankName =  app.Bank_Name__c;
            this.iban =  app.Bank_IBAN__c;
            this.sortCode =  app.Bank_Sort_Code__c;
            this.address = app.Bank_Address__c;
            this.city = app.Bank_City__c;
            this.countryName = app.Bank_Country__c;
            this.country = app.Bank_Country_Code__c;
            this.postcode = app.Bank_Post_Code__c;
            this.bic = app.Bank_BIC__c;
            this.ownsThisAccount = app.Owns_This_Account__c;
            this.is4weeks = app.Paid_Interval__c  == '4 weeks' ?  true : false;
            
        }
    }

    public class OtherWrapper {
        @AuraEnabled public String notes;
        @AuraEnabled public String docuSignDate;
        @AuraEnabled public Boolean isUKproperty;
        @AuraEnabled public Boolean isAccountant;
        @AuraEnabled public Boolean isSelfAssesedTax;
        @AuraEnabled public Boolean isAgePension;
        @AuraEnabled public String accountantAddress1;
        @AuraEnabled public String accountantAddress2;
        @AuraEnabled public String accountantCity;
        @AuraEnabled public String accountantCountryName;
        @AuraEnabled public String accountantCountry;
        @AuraEnabled public String accountantStateName;
        @AuraEnabled public String accountantStateCode;
        @AuraEnabled public String accountantPhone;
        @AuraEnabled public String accountantPostcode;
        @AuraEnabled public String accountantName;
        @AuraEnabled public List<UkPropertiesWrapper> UkProperties;
        public OtherWrapper(Basic__c app) {
            this.notes = String.isBlank(app.Notes__c) ? '' : app.Notes__c;
            this.docuSignDate = app.DocuSign_Date__c != null ? String.valueOf(app.DocuSign_Date__c) + 'T00:00:00.000Z': '';
            this.isUKproperty = app.Do_you_own_rent_any_UK_property__c;
            this.isAccountant = app.Do_you_have_an_accountant__c;
            this.isSelfAssesedTax = app.Are_you_self_assessed_for_tax__c;
            this.isAgePension = app.Age_Pension_now_or_next_year__c;
            this.UkProperties = new List<UkPropertiesWrapper>();
            this.accountantAddress1 = app.Accountant_Address__c;
            this.accountantAddress2 = app.Accountant_Address_2__c;
            this.accountantCity = app.Accountant_City__c;
            this.accountantCountryName = app.Accountant_Country_Name__c;
            this.accountantCountry = app.Accountant_Country_Code__c;
            this.accountantStateName = app.Accountant_State_Name__c;
            this.accountantStateCode = app.Accountant_State_Code__c;
            this.accountantPhone = app.Accountant_Phone__c;
            this.accountantPostcode = app.Accountant_PostCode__c;
            this.accountantName = app.Accountant_Name__c;

            if(app.Claimant_UK_Properties__r != null && app.Claimant_UK_Properties__r.size()>0) {    
                for(Claimant_UK_Property__c itemwrap : app.Claimant_UK_Properties__r) {
                    this.UkProperties.add(new UkPropertiesWrapper(itemwrap));
                }
            }
        }
    }

    public class UkPropertiesWrapper {
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        @AuraEnabled public String postcode;

        public UkPropertiesWrapper(Claimant_UK_Property__c child) {
            this.address1 = child.Address__c;
            this.address2 = child.Address_2__c;
            this.city = child.City__c;
            this.postcode = child.Postcode__c;
        }
    }


    public class ShortApplicationDataWrapper {
        @AuraEnabled public String applicationId;
        @AuraEnabled public Boolean hasEnvelope;
        @AuraEnabled public ClientEnvWrapper client;
        @AuraEnabled public String track;
        @AuraEnabled public TrackAWrapper trackA;
        @AuraEnabled public TrackBWrapper trackB;
        @AuraEnabled public TrackCWrapper trackC;

        public ShortApplicationDataWrapper(Basic__c app) {
            this.applicationId = app.Id;
            this.hasEnvelope = app.Is_envelope_created__c;
            this.client = new ClientEnvWrapper(app);
            this.track = app.Track__c;
            this.trackA = new TrackAWrapper(app);
            this.trackB = new TrackBWrapper(app);
            this.trackC = new TrackCWrapper(app);
        }
        public ShortApplicationDataWrapper(List<Basic__c> appList) {
            this.applicationId = appList[0].Id;
            this.hasEnvelope = appList[0].Is_envelope_created__c;
            this.client = new ClientEnvWrapper(appList[0]);
            this.track = appList[0].Track__c;
            this.trackA = new TrackAWrapper(appList[0]);
            this.trackB = new TrackBWrapper(appList[0]);
            this.trackC = new TrackCWrapper(appList[0]);
        }
    }

    public class ClientEnvWrapper {
        @AuraEnabled public String title;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String maidenName;
        @AuraEnabled public String middleName;
        @AuraEnabled public String maritalStatus;
        @AuraEnabled public String dateOfDivorce;
        @AuraEnabled public String country;
        @AuraEnabled public String countryName;
        @AuraEnabled public String state;
        @AuraEnabled public String stateName;
        @AuraEnabled public String postcode;
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        @AuraEnabled public String tel;
        @AuraEnabled public String dob;

        @AuraEnabled public String email;    
        @AuraEnabled public string pps;
        @AuraEnabled public String helperEmail;
        @AuraEnabled public Boolean everLivedUK;
        @AuraEnabled public String dateLeftUK;

        @AuraEnabled public Boolean addressValidated;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public Boolean wasCleansed;
        //@AuraEnabled public Boolean verifiedReference;
        //@AuraEnabled public Boolean verificationDetails;

        @AuraEnabled public String nationality;
        @AuraEnabled public Integer approxYearsInUK;

        public ClientEnvWrapper(Basic__c app) {
            this.title = app.Claimant_title__c;
            this.firstName = app.First_Name__c;
            this.lastName = app.Last_Name__c;
            this.maidenName = app.Claimant_maiden_Name__c;
            this.middleName = app.Claimant_Middle_Name__c;
            this.maritalStatus = app.Claimant_marital_Status__c;
            this.dateOfDivorce = app.Claimant_date_Of_Divorce__c != null ? String.valueOf(app.Claimant_date_Of_Divorce__c) + 'T00:00:00.000Z': '';
            this.country = app.Current_Address_Abroad_Country__c;
            this.countryName = app.Current_Address_Abroad_Country_Name__c;
            this.postcode = app.Eircode__c;
            this.address1 = app.Claimant_Address1__c;
            this.address2 = app.Claimant_Address2__c;
            this.city = app.Claimant_City__c;
            this.tel = app.Phone__c;
            this.dob = app.Claimant_dob__c != null ? String.valueOf(app.Claimant_dob__c) + 'T00:00:00.000Z': '';
            this.email = app.Email__c;
            this.pps = app.PPS__c;
            this.helperEmail = app.Friend_Email__c;
            this.state = app.Current_Address_Abroad_State__c;
            this.stateName = app.Current_Address_Abroad_State_Name__c;
            if(String.isNotBlank(app.Current_Address_Abroad_Country_Name__c) && app.Current_Address_Abroad_Country_Name__c == 'United Kingdom' 
            && app.Ever_Live_In_UK_approved__c == false) {
                 this.everLivedUK = true;
            } else {
                this.everLivedUK =  app.Claimant_ever_Lived_UK__c;
            }
            
            this.dateLeftUK = app.Claimant_lived_UK_to__c != null ? String.valueOf(app.Claimant_lived_UK_to__c) + 'T00:00:00.000Z': '';

            this.addressValidated = app.Address_Validated__c;
            this.verificationStatus = app.Verification_Status__c;
            this.wasCleansed = app.Was_Cleansed__c;
            //this.verifiedReference = app.Verified_Reference__c;
            //this.verificationDetails = app.Verification_Details__c;

            this.nationality = app.Claimant_nationality__c;
            this.approxYearsInUK = app.Approx_Years_in_UK__c != null ?  app.Approx_Years_in_UK__c.intValue() : null;
            
            
        }
    }

    public class BenefitsWrapper {
        @AuraEnabled public Boolean isYourPartnerCurrentlyGetPension;
        @AuraEnabled public String isYourPartnerCurrentlyGetPensionText;

        public BenefitsWrapper(Basic__c app) {
            this.isYourPartnerCurrentlyGetPension = app.Is_Your_Partner_Currently_Get_Pension__c;
            this.isYourPartnerCurrentlyGetPensionText = app.isYourPartnerCurrentlyGetPensionText__c;
        }
    }

    public class TrackAWrapper {
        @AuraEnabled public Boolean isGettingUKStatePensionNow;
        @AuraEnabled public String hasNino;
        @AuraEnabled public String nino;
        @AuraEnabled public List<CompaniesWrapper> employers;
        @AuraEnabled public List<CompaniesWrapper> addresses;

        public TrackAWrapper(Basic__c app) {
            this.employers = new List<CompaniesWrapper>();
            this.addresses = new List<CompaniesWrapper>();
            this.isGettingUKStatePensionNow = app.Claimant_State_Pension__c;
            this.hasNino = app.Has_Nino__c;
            this.nino = app.Claimant_nino__c;
            if(String.isNotBlank(app.Track__c) && app.Track__c == 'A') {
                if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {    
                    for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                        if(itemwrap.Is_Addresses__c) {
                            this.addresses.add(new CompaniesWrapper(itemwrap));
                        }
                        
                    }
                }
            
                if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {  
                    for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                        if(!itemwrap.Is_Addresses__c) {
                            this.employers.add(new CompaniesWrapper(itemwrap));
                        }
                    }
                }
            }
        }
    }

    public class TrackBWrapper {
        @AuraEnabled public String husbandAlive;
        @AuraEnabled public String husbandFullName;
        @AuraEnabled public Boolean husbandGettinStatePensionNow;
        @AuraEnabled public Boolean youGettinStatePensionNow;
        @AuraEnabled public String husbandDob;
        @AuraEnabled public String marriageDate;
        @AuraEnabled public String husbandLeftUk;
        @AuraEnabled public Boolean sameAddress;
        @AuraEnabled public String country;
        @AuraEnabled public String postcode;
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        @AuraEnabled public String husbandHasNino;
        @AuraEnabled public String husbandNino;
        @AuraEnabled public List<CompaniesWrapper> employers;
        @AuraEnabled public List<CompaniesWrapper> addresses;
        @AuraEnabled public String townsLived;
        @AuraEnabled public String husbandFirstName;
        @AuraEnabled public String husbandSurname;
        @AuraEnabled public String husbandOtherName;

        @AuraEnabled public Boolean addressValidated;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public Boolean wasCleansed;
        @AuraEnabled public String title;
        @AuraEnabled public String state;
        @AuraEnabled public String stateName;
        //@AuraEnabled public Boolean verifiedReference;
        //@AuraEnabled public Boolean verificationDetails;

        public TrackBWrapper(Basic__c app) {
            this.employers = new List<CompaniesWrapper>();
            this.addresses = new List<CompaniesWrapper>();
            this.husbandAlive = app.Is_Partner_alive__c ? 'Yes' : 'No';
            this.husbandGettinStatePensionNow = app.Partner_State_Pension__c;
            this.youGettinStatePensionNow = app.Claimant_State_Pension__c;
            this.husbandFullName = app.Partner_Full_Name__c;
            this.husbandFirstName = app.Partner_First_Name__c;
            this.husbandSurname = app.Partner_Surname__c;
            this.husbandOtherName = app.Partner_Other_Name__c;
            this.husbandDob = app.Partner_DOB__c != null ? String.valueOf(app.Partner_DOB__c) + 'T00:00:00.000Z': '';
            this.marriageDate = app.Claimant_date_Of_Marriage__c != null ? String.valueOf(app.Claimant_date_Of_Marriage__c) + 'T00:00:00.000Z': '';
            this.husbandLeftUk = app.Partner_Left_UK__c != null ? String.valueOf(app.Partner_Left_UK__c) + 'T00:00:00.000Z': '';
            this.sameAddress = app.Partner_same_as_claimant__c;
            this.country = app.Partner_Country__c;
            this.postcode = app.Partner_Postcode__c;
            this.address1 = app.Partner_Address1__c;
            this.address2 = app.Partner_Address2__c;
            this.city = app.Partner_City__c;
            this.husbandHasNino = app.Partner_Has_Nino_values__c;
            this.husbandNino = app.Partner_Nino__c;

            this.addressValidated = app.Partner_Address_Validated__c;
            this.verificationStatus = app.Partner_Verification_Status__c;
            this.wasCleansed = app.Partner_Was_Cleansed__c;
            this.title = app.Partner_Title__c;
            this.state = app.Partner_State_Code__c;
            this.stateName = app.Partner_State_Name__c;
            //this.verifiedReference = app.Partner_Verified_Reference__c;
            //this.verificationDetails = app.Partner_Verification_Details__c;

            if(String.isNotBlank(app.Track__c) && app.Track__c == 'B') {
                if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {    
                    for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                        if(itemwrap.Is_Addresses__c) {
                            this.addresses.add(new CompaniesWrapper(itemwrap));
                        }
                        
                    }
                }
            
                if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {  
                    for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                        if(!itemwrap.Is_Addresses__c) {
                            this.employers.add(new CompaniesWrapper(itemwrap));
                        }
                    }
                }
            }
            this.townsLived = app.Partner_Towns_Lived__c;
        }
    }

    public class TrackCWrapper {
        @AuraEnabled public String wifeDob;
        @AuraEnabled public Boolean gateResult;
        @AuraEnabled public Boolean gatePassed;
        @AuraEnabled public String spaDate;
        @AuraEnabled public String marriageDate;
        @AuraEnabled public String wifeLeftUk;
        @AuraEnabled public Boolean sameAddress;
        @AuraEnabled public String country;
        @AuraEnabled public String postcode;
        @AuraEnabled public String address1;
        @AuraEnabled public String address2;
        @AuraEnabled public String city;
        @AuraEnabled public String wifeHasNino;
        @AuraEnabled public String wifeNino;
        @AuraEnabled public List<CompaniesWrapper> employers;
        @AuraEnabled public List<CompaniesWrapper> addresses;
        @AuraEnabled public String state;
        @AuraEnabled public String stateName;
        @AuraEnabled public Boolean addressValidated;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public Boolean wasCleansed;
        //@AuraEnabled public Boolean verifiedReference;
        //@AuraEnabled public Boolean verificationDetails;

        public TrackCWrapper (Basic__c app) {
            this.employers = new List<CompaniesWrapper>();
            this.addresses = new List<CompaniesWrapper>();
            this.wifeDob = app.Partner_DOB__c != null ? String.valueOf(app.Partner_DOB__c) + 'T00:00:00.000Z': '';
            this.marriageDate = app.Claimant_date_Of_Marriage__c != null ? String.valueOf(app.Claimant_date_Of_Marriage__c) + 'T00:00:00.000Z': '';
            this.wifeLeftUk = app.Partner_Left_UK__c != null ? String.valueOf(app.Partner_Left_UK__c) + 'T00:00:00.000Z': '';
            this.sameAddress = app.Partner_same_as_claimant__c;
            this.country = app.Partner_Country__c;
            this.postcode = app.Partner_Postcode__c;
            this.address1 = app.Partner_Address1__c;
            this.address2 = app.Partner_Address2__c;
            this.city = app.Partner_City__c;
            this.state = app.Partner_State_Code__c;
            this.stateName = app.Partner_State_Name__c;

            this.addressValidated = app.Partner_Address_Validated__c;
            this.verificationStatus = app.Partner_Verification_Status__c;
            this.wasCleansed = app.Partner_Was_Cleansed__c;
            //this.verifiedReference = app.Partner_Verified_Reference__c;
            //this.verificationDetails = app.Partner_Verification_Details__c;

            this.wifeHasNino = app.Partner_Has_Nino_values__c;
            this.wifeNino = app.Partner_Nino__c;
            if(String.isNotBlank(app.Track__c) && app.Track__c == 'C') {
                if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {    
                    for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                        if(itemwrap.Is_Addresses__c) {
                            this.addresses.add(new CompaniesWrapper(itemwrap));
                        }
                        
                    }
                }
            
                if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {  
                    for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                        if(!itemwrap.Is_Addresses__c) {
                            this.employers.add(new CompaniesWrapper(itemwrap));
                        }
                    }
                }
            }
        }
    }      
}