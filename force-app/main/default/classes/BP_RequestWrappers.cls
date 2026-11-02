public with sharing class BP_RequestWrappers {
    public class ApplicationCreateDataWrapper {
        public String id;
        public String currencyCode;
        public Decimal amount;
        public String email;
        public String friendFamilyEmail;
        public String phone;
        public String name;
        public AddressDataWrapper address;
        public String firstName;
        public String lastName;
        public String paymentMethod;
        public String customer;
        public String latest_charge;
        public String latestCharge;
        public String howDidYouHearAboutUs;
        public String agent;
        public String title;
        public String friendLastName;
        public String friendTel;
        public String friendRelationship;
        public String friendFirstName;

        public ApplicationCreateDataWrapper(String inputData) {
            ApplicationCreateDataWrapper wrapper = (ApplicationCreateDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationCreateDataWrapper.class);
            this.id = wrapper.id;
            this.amount = wrapper.amount;
            this.email = wrapper.email;
            this.phone = wrapper.phone;
            this.name = wrapper.name;
            this.address = wrapper.address;
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.paymentMethod = wrapper.paymentMethod;
            this.customer = wrapper.customer;
            this.currencyCode = wrapper.currencyCode;
            this.latestCharge = wrapper.latestCharge;
            this.howDidYouHearAboutUs = wrapper.howDidYouHearAboutUs;
            this.agent = wrapper.agent;
            this.latest_charge = wrapper.latest_charge;
            this.friendFamilyEmail = wrapper.friendFamilyEmail;
            this.title = wrapper.title;
            this.friendLastName = wrapper.friendLastName;
            this.friendTel = wrapper.friendTel;
            this.friendRelationship = wrapper.friendRelationship;
            this.friendFirstName = wrapper.friendFirstName;
        }
    }

    public class AddressDataWrapper {
        public String street;
        public String postalCode;
        public String state;
        public String city;
        public String country;
        public String countryCode;
    }

    public class ApplicationDetailsDataWrapper {
        public String applicationId;
        public Integer currentStep;
        public ApplicationFullWrapper application;
        public Boolean isAgentForm;
        public Boolean isAutoSave;
        // Partial autosave: only the form sections the client changed are in the payload
        public Boolean isPartial;
        public Set<String> sentSections;
         public ApplicationDetailsDataWrapper(String inputData) {
            ApplicationDetailsDataWrapper wrapper = (ApplicationDetailsDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationDetailsDataWrapper.class);
            this.applicationId = wrapper.applicationId;
            this.currentStep = wrapper.currentStep;
            this.isAgentForm = wrapper.isAgentForm;
            this.isAutoSave = wrapper.isAutoSave != null ? wrapper.isAutoSave : false;
            this.isPartial = this.isAutoSave && wrapper.isPartial == true;
            if (this.isPartial) {
                // The typed wrapper replaces absent sections with empty objects, so read the raw keys
                this.sentSections = new Set<String>();
                Object rawApplication = ((Map<String, Object>) JSON.deserializeUntyped(inputData)).get('application');
                if (rawApplication instanceof Map<String, Object>) {
                    this.sentSections.addAll(((Map<String, Object>) rawApplication).keySet());
                }
            }
            if (wrapper.application != null) {
                this.application = new ApplicationFullWrapper(JSON.serialize(wrapper.application));
            } else {
                this.application = new ApplicationFullWrapper();
            }  
         }
    }

    public class ApplicationFullWrapper {
        public ApplicationContactCommunication contactCommunication;
        public ClaimantWrapper claimant;
        public ClaimantBenefitsWrapper claimantBenefits;
        public PartnerBenefitsWrapper partnerBenefits;
        public PartnerWrapper partner;
        public PensionWrapper pension;
        public BankWrapper bank;
        public String agent;
        public OtherWrapper otherInformation;
        public BenefitsWrapper benefits;

        public ApplicationFullWrapper(String inputData) {
            ApplicationFullWrapper wrapper = (ApplicationFullWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationFullWrapper.class);
            if(wrapper.contactCommunication != null) {
                this.contactCommunication = new ApplicationContactCommunication(JSON.serialize(wrapper.contactCommunication));
            } else {
                this.contactCommunication = new ApplicationContactCommunication();
            }
            if(wrapper.claimant != null) {
                this.claimant = new ClaimantWrapper(JSON.serialize(wrapper.claimant));
            } else {
                this.claimant = new ClaimantWrapper();
            }
            if(wrapper.claimantBenefits !=null) {
                this.claimantBenefits = new ClaimantBenefitsWrapper(JSON.serialize(wrapper.claimantBenefits));
            } else {
                this.claimantBenefits = new ClaimantBenefitsWrapper();
            }
            if(wrapper.partnerBenefits !=null) {
                this.partnerBenefits = new PartnerBenefitsWrapper(JSON.serialize(wrapper.partnerBenefits));
            } else {
                this.partnerBenefits = new PartnerBenefitsWrapper();
            }
            if(wrapper.partner !=null) {
                this.partner = new PartnerWrapper(JSON.serialize(wrapper.partner));
            } else {
                this.partner = new PartnerWrapper();
            }
            if(wrapper.pension !=null) {
                this.pension = new PensionWrapper(JSON.serialize(wrapper.pension));
            } else {
                this.pension = new PensionWrapper();
            }
            if(wrapper.bank !=null) {
                this.bank = new BankWrapper(JSON.serialize(wrapper.bank));
            } else {
                this.bank = new BankWrapper();
            }
            if(wrapper.agent !=null) {
                this.agent = wrapper.agent;
            } else {
                this.agent = '';
            }
            if(wrapper.otherInformation !=null) {
                this.otherInformation = wrapper.otherInformation;
            } else {
                this.otherInformation = new OtherWrapper();
            }
            if(wrapper.benefits !=null) {
                this.benefits = wrapper.benefits;
            } else {
                this.benefits = new BenefitsWrapper();
            }
        }
        public ApplicationFullWrapper() {
            this.contactCommunication = new ApplicationContactCommunication();
            this.claimant = new ClaimantWrapper();
            this.claimantBenefits = new ClaimantBenefitsWrapper();
            this.partnerBenefits = new PartnerBenefitsWrapper();
            this.partner = new PartnerWrapper();
            this.pension = new PensionWrapper();
            this.bank = new BankWrapper();
            this.agent = '';
        }
    }

    public class ApplicationContactCommunication {
        public String firstName;
        public String lastName;
        public String tel;
        public String email;
        public String relationship;
        public ApplicationContactCommunication(String inputData) {
            ApplicationContactCommunication wrapper = (ApplicationContactCommunication) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationContactCommunication.class);
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.tel = wrapper.tel;
            this.email = wrapper.email;
            this.relationship = wrapper.relationship;
        }
        public ApplicationContactCommunication() {
            this.firstName = '';
            this.lastName = '';
            this.tel = '';
            this.email = '';
            this.relationship = '';
        }
    }

    public class ClaimantWrapper {
        public String title;
        public String surname;
        public String otherNames;
        public String dob;
        public String maidenName;
        public String middleName;
        public String tel;
        public String email;
        public String maritalStatus;
        public String nationality;
        public String dateOfMarriage;
        public String dateOfBereavement;
        public String dateOfDivorce;
        public Boolean hasNino;
        public String nino;
        //Address
        public String country;
        public String countryName;
        public String postcode;
        public String address1;
        public String address2;
        public String city;
        // UK History
        public Boolean everLivedUK;
        public String livedUKFrom;
        public String livedUKTo;
        public Boolean everWorkedUK;
        public String workedUKFrom;
        public String workedUKTo;
        public Boolean hasProofOfUKWork;
        // Dynamic lists
        public List<CountryLivedWrapper> countriesLived;
        public List<CompaniesWrapper> ukCompanies;
        // Married / Widowed section
        public Boolean selfEmployedUK;
        public Boolean marriedWomansStamp;
        public Boolean mindedKids;
        public List<ChildrenWrapper> children;
        //// Verification status
        public Boolean addressValidated;
        public String verificationStatus;
        public Boolean wasCleansed;
        public Boolean everWorkedUKuseSameDates;
        public String phoneType;
        public Integer approxYearsInUK;
        public String everLivedUKNotes;
        public String firstName;
        public String state;
        public String stateName;
        //public Boolean verifiedReference;
        //public Boolean verificationDetails;

        public ClaimantWrapper(String inputData) {
            System.debug(inputData);
            ClaimantWrapper wrapper = (ClaimantWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ClaimantWrapper.class);
            this.addressValidated = wrapper.addressValidated;
            //this.verificationDetails = wrapper.verificationDetails;
            this.wasCleansed = wrapper.wasCleansed;
            //this.verifiedReference = wrapper.verifiedReference;
            this.verificationStatus = wrapper.verificationStatus;
            this.title = wrapper.title;
            this.surname = wrapper.surname;
            this.otherNames = wrapper.otherNames;
            this.dob = wrapper.dob;
            this.maidenName = wrapper.maidenName;
            this.tel = wrapper.tel;
            this.email = wrapper.email;
            this.maritalStatus = wrapper.maritalStatus;
            this.nationality = wrapper.nationality;
            this.dateOfMarriage = wrapper.dateOfMarriage;
            this.dateOfBereavement = wrapper.dateOfBereavement;
            this.dateOfDivorce = wrapper.dateOfDivorce;
            this.hasNino = wrapper.hasNino;
            this.nino = wrapper.nino;
            this.country = wrapper.country;
            this.countryName = wrapper.countryName;
            this.postcode = wrapper.postcode;
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.everLivedUK = wrapper.everLivedUK;
            this.livedUKFrom = wrapper.livedUKFrom;
            this.livedUKTo = wrapper.livedUKTo;
            this.everWorkedUK = wrapper.everWorkedUK;
            this.workedUKFrom = wrapper.workedUKFrom;
            this.workedUKTo = wrapper.workedUKTo;
            this.hasProofOfUKWork = wrapper.hasProofOfUKWork;
            this.selfEmployedUK = wrapper.selfEmployedUK;
            this.marriedWomansStamp = wrapper.marriedWomansStamp;
            this.mindedKids = wrapper.mindedKids;
            this.everWorkedUKuseSameDates = wrapper.everWorkedUKuseSameDates;
            this.phoneType = wrapper.phoneType;
            this.approxYearsInUK = wrapper.approxYearsInUK;
            this.everLivedUKNotes = wrapper.everLivedUKNotes;
            this.countriesLived = new List<CountryLivedWrapper>();
            this.firstName = wrapper.firstName;
            this.state = wrapper.state == 'IE' ? wrapper.state : CountryCodeHelper.getCountryStateISOByName(wrapper.state);
            this.stateName = wrapper.state;
            this.middleName = wrapper.middleName;

            System.debug(this.stateName);
            if(wrapper.countriesLived != null) {    
                for(CountryLivedWrapper itemwrap : wrapper.countriesLived) {
                    this.countriesLived.add(new CountryLivedWrapper(JSON.serialize(itemwrap)));
                }
            }
            this.ukCompanies = new List<CompaniesWrapper>();
            if(wrapper.ukCompanies != null) {    
                for(CompaniesWrapper itemwrap : wrapper.ukCompanies) {
                    this.ukCompanies.add(new CompaniesWrapper(JSON.serialize(itemwrap)));
                }
            }
            this.children = new List<ChildrenWrapper>();
            if(wrapper.children != null) {    
                for(ChildrenWrapper itemwrap : wrapper.children) {
                    this.children.add(new ChildrenWrapper(JSON.serialize(itemwrap)));
                }
            }

        }
        public ClaimantWrapper() {
            this.addressValidated = false;
            //this.verificationDetails = false;
            this.wasCleansed = false;
            //this.verifiedReference = false;
            this.verificationStatus = '';
            this.title = '';
            this.surname = '';
            this.otherNames = '';
            this.dob = '';
            this.maidenName = '';
            this.tel = '';
            this.email = '';
            this.maritalStatus = '';
            this.nationality = '';
            this.dateOfMarriage = '';
            this.dateOfBereavement = '';
            this.dateOfDivorce = '';
            this.hasNino = false;
            this.nino = '';
            this.country = '';
            this.countryName = '';
            this.postcode = '';
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.everLivedUK  = false;
            this.livedUKFrom = '';
            this.livedUKTo = '';
            this.everWorkedUK = false;
            this.workedUKFrom = '';
            this.workedUKTo = '';
            this.hasProofOfUKWork = false;
            this.countriesLived = new List<CountryLivedWrapper>();
            this.ukCompanies = new List<CompaniesWrapper>();
            this.selfEmployedUK = false;
            this.marriedWomansStamp = false;
            this.mindedKids = false;
            this.children = new List<ChildrenWrapper>();
            this.everWorkedUKuseSameDates = false;
            this.phoneType = '';
            this.approxYearsInUK = 0;
            this.everLivedUKNotes = '';
            this.state = '';
            this.stateName = '';
            this.middleName = '';
        }

    }

    public class CountryLivedWrapper {
        public String country;
        public String countryName;
        public String fromDate;
        public String toDate;
        public String socialSecurityNumber;
        public Boolean isLiveHereNow;
        public CountryLivedWrapper(String inputData) {
            CountryLivedWrapper wrapper = (CountryLivedWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), CountryLivedWrapper.class);
            this.country = wrapper.country;
            this.countryName = wrapper.countryName;
            this.fromDate = wrapper.fromDate;
            this.toDate = wrapper.toDate;
            this.socialSecurityNumber = wrapper.socialSecurityNumber;
            this.isLiveHereNow = wrapper.isLiveHereNow;
        }
        public CountryLivedWrapper() {
            this.country = '';
            this.countryName = '';
            this.fromDate = '';
            this.toDate = '';
            this.socialSecurityNumber = '';
            this.isLiveHereNow = false;
        }
    }

    public class CompaniesWrapper {
        public String name;
        public String address;
        public String country;
        public String countryName;
        public String postcode;
        public String address1;
        public String address2;
        public String city;
        public String fromDate;
        public String toDate;
        public Boolean addressValidated;
        public String verificationStatus;
        public Boolean wasCleansed;
        //public Boolean verifiedReference;
        //public Boolean verificationDetails;
        

         public CompaniesWrapper(String inputData) {
            CompaniesWrapper wrapper = (CompaniesWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), CompaniesWrapper.class);
            this.name = wrapper.name;
            this.fromDate = wrapper.fromDate;
            this.toDate = wrapper.toDate;
            this.country = wrapper.country;
            this.countryName = wrapper.countryName;
            this.postcode = wrapper.postcode;
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.addressValidated = wrapper.addressValidated;
            //this.verificationDetails = wrapper.verificationDetails;
            this.wasCleansed = wrapper.wasCleansed;
            //this.verifiedReference = wrapper.verifiedReference;
            this.verificationStatus = wrapper.verificationStatus;

        }

        public CompaniesWrapper() {
            this.name = '';
            this.fromDate = '';
            this.toDate = '';
            this.country = '';
            this.countryName = '';
            this.postcode = '';
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.addressValidated = false;
            //this.verificationDetails = false;
            this.wasCleansed = false;
            //this.verifiedReference = false;
            this.verificationStatus = '';
        }

    }

    public class ChildrenWrapper {
        public String name;
        public String dob;
        public String mindedFromDate;
        public String mindedToDate;
        public String nino;

        public ChildrenWrapper(String inputData) {
            ChildrenWrapper wrapper = (ChildrenWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ChildrenWrapper.class);
            this.name = wrapper.name;
            this.dob = wrapper.dob;
            this.mindedFromDate = wrapper.mindedFromDate;
            this.mindedToDate = wrapper.mindedToDate;
            this.nino = wrapper.nino;
        }
            public ChildrenWrapper() {
            this.name = '';
            this.dob = '';
            this.mindedFromDate = '';
            this.mindedToDate = '';
            this.nino = '';
        }

    }

    public class ClaimantBenefitsWrapper {
        public Boolean bereavement;
        public Boolean graduatedRetirement;
        public Boolean statePension;
        public Boolean widows;
        public Boolean isWaitingUkBenefits;
        public String isWaitingUkBenefitsText;

        public ClaimantBenefitsWrapper(String inputData) {
            ClaimantBenefitsWrapper wrapper = (ClaimantBenefitsWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ClaimantBenefitsWrapper.class);
            this.bereavement = wrapper.bereavement;
            this.graduatedRetirement = wrapper.graduatedRetirement;
            this.statePension = wrapper.statePension;
            this.widows = wrapper.widows;
            this.isWaitingUkBenefits = wrapper.isWaitingUkBenefits;
            this.isWaitingUkBenefitsText = wrapper.isWaitingUkBenefitsText;
        }
         public ClaimantBenefitsWrapper() {
            this.bereavement = false;
            this.graduatedRetirement = false;
            this.statePension = false;
            this.widows = false;
            this.isWaitingUkBenefits = false;
            this.isWaitingUkBenefitsText = '';
        }

    }

    public class PartnerBenefitsWrapper {
        public Boolean bereavement;
        public Boolean graduatedRetirement;
        public Boolean statePension;
        public Boolean widows;
        public Boolean isWaitingUkBenefits;
        public String isWaitingUkBenefitsText;

        public PartnerBenefitsWrapper(String inputData) {
            PartnerBenefitsWrapper wrapper = (PartnerBenefitsWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), PartnerBenefitsWrapper.class);
            this.bereavement = wrapper.bereavement;
            this.graduatedRetirement = wrapper.graduatedRetirement;
            this.statePension = wrapper.statePension;
            this.widows = wrapper.widows;
            this.isWaitingUkBenefits = wrapper.isWaitingUkBenefits;
            this.isWaitingUkBenefitsText = wrapper.isWaitingUkBenefitsText;
        }
         public PartnerBenefitsWrapper() {
            this.bereavement = false;
            this.graduatedRetirement = false;
            this.statePension = false;
            this.widows = false;
            this.isWaitingUkBenefits = false;
            this.isWaitingUkBenefitsText = '';
        }

    }

    public class PartnerWrapper {
        public String title;
        public String surname;
        public String otherNames;
        public String dob;
        public String maidenName;
        public Boolean hasNino;
        public String nino;
        public Boolean saveAsClaimant;
        public String country;
        public String countryName;
        public String postcode;
        public String address1;
        public String address2;
        public String city;
        public Boolean addressValidated;
        public String verificationStatus;
        public Boolean wasCleansed;
        public Boolean everLivedUK;
        public Boolean everWorkedUK;
        public String everLivedUKNotes;
        public String firstName;
        public String fullName;
        public Boolean claimingUKPension;
        public String referenceOnAnyDWPLetters;
        public String state;
        public String stateName;

       // public Boolean verifiedReference;
        //public Boolean verificationDetails;

        public PartnerWrapper(String inputData) {
            PartnerWrapper wrapper = (PartnerWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), PartnerWrapper.class);
            this.title = wrapper.title;
            this.surname = wrapper.surname;
            this.firstName = wrapper.firstName;
            this.fullName = wrapper.fullName;
            this.otherNames = wrapper.otherNames;
            this.dob = wrapper.dob;
            this.maidenName = wrapper.maidenName;
            this.hasNino = wrapper.hasNino;
            this.nino = wrapper.nino;
            this.saveAsClaimant = wrapper.saveAsClaimant;
            this.country = wrapper.country;
            this.countryName = wrapper.countryName;
            this.postcode = wrapper.postcode;
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.addressValidated = wrapper.addressValidated;
            //this.verificationDetails = wrapper.verificationDetails;
            this.wasCleansed = wrapper.wasCleansed;
            //this.verifiedReference = wrapper.verifiedReference;
            this.verificationStatus = wrapper.verificationStatus;
            this.everLivedUK = wrapper.everLivedUK;
            this.everWorkedUK = wrapper.everWorkedUK;
            this.everLivedUKNotes = wrapper.everLivedUKNotes;
            this.claimingUKPension = wrapper.claimingUKPension;
            this.referenceOnAnyDWPLetters = wrapper.referenceOnAnyDWPLetters;
            this.state = wrapper.state == 'IE' ? wrapper.state : CountryCodeHelper.getCountryStateISOByName(wrapper.state);
            this.stateName = wrapper.state;
        }
         public PartnerWrapper() {
            this.title = '';
            this.firstName = '';
            this.fullName = '';
            this.surname = '';
            this.otherNames = '';
            this.dob = '';
            this.maidenName = '';
            this.hasNino = false;
            this.nino = '';
            this.saveAsClaimant = false;
            this.country = '';
            this.countryName = '';
            this.postcode = '';
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.addressValidated = false;
            //this.verificationDetails = false;
            this.wasCleansed = false;
            //this.verifiedReference = false;
            this.verificationStatus = '';
            this.everLivedUK = false;
            this.everWorkedUK = false;
            this.everLivedUKNotes = '';
            this.claimingUKPension = false;
            this.referenceOnAnyDWPLetters = '';
            this.state = '';
            this.stateName = '';
        }
    }

    public class PensionWrapper {
        public Boolean claimingFromToday;
        public String startDate;
        public Boolean workAfterPensionAge;
        public Boolean deferredPension;
        public Boolean imprisonedSincePensionAge;
        public Boolean workInUKduring2years;
        public Boolean everSelfEmployedUKafter1978;
        public Boolean everPayReducedUKnino;

        public PensionWrapper(String inputData) {
            PensionWrapper wrapper = (PensionWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), PensionWrapper.class);
            this.claimingFromToday = wrapper.claimingFromToday;
            this.startDate = wrapper.startDate;
            this.workAfterPensionAge = wrapper.workAfterPensionAge;
            this.deferredPension = wrapper.deferredPension;
            this.imprisonedSincePensionAge = wrapper.imprisonedSincePensionAge;
            this.workInUKduring2years = wrapper.workInUKduring2years;
            this.everSelfEmployedUKafter1978 = wrapper.everSelfEmployedUKafter1978;
            this.everPayReducedUKnino = wrapper.everPayReducedUKnino;
        }

        public PensionWrapper() {
            this.claimingFromToday = false;
            this.startDate = '';
            this.workAfterPensionAge = false;
            this.deferredPension = true;
            this.imprisonedSincePensionAge = false;
            this.workInUKduring2years = false;
            this.everSelfEmployedUKafter1978 = false;
            this.everPayReducedUKnino = false;
        }
    }

    public class BankWrapper {
        public String account;
        public String accountOwnerName;
        public String accountOwnerEmail;
        public String accountType;
        public String bankName;
        public String iban;
        public String sortCode;
        public String address;
        public String city;
        public String country;
        public String countryName;
        public String postcode;
        public String bic;
        public String ownsThisAccount;
        public Boolean is4weeks;

        public BankWrapper(String inputData) {
            BankWrapper wrapper = (BankWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), BankWrapper.class);
            this.account = wrapper.account;
            this.accountOwnerName = wrapper.accountOwnerName;
            this.accountOwnerEmail = wrapper.accountOwnerEmail;
            this.accountType = wrapper.accountType;
            this.bankName = wrapper.bankName;
            this.iban = wrapper.iban;
            this.sortCode = wrapper.sortCode;
            this.address = wrapper.address;
            this.city = wrapper.city;
            this.country = wrapper.country;
            this.countryName = wrapper.countryName;
            this.postcode = wrapper.postcode;
            this.bic = wrapper.bic;
            this.ownsThisAccount = wrapper.ownsThisAccount;
            this.is4weeks = wrapper.is4weeks;
        }

        public BankWrapper() {
            this.account = '';
            this.accountOwnerEmail = '';
            this.accountOwnerName = '';
            this.accountType = '';
            this.bankName = '';
            this.iban = '';
            this.sortCode = '';
            this.address = '';
            this.city = '';
            this.country = '';
            this.postcode = '';
            this.countryName = '';
            this.bic = '';
            this.ownsThisAccount = '';
            this.is4weeks = true;

        }
    }

    public class UploadDocumentDataWrapper {
        public String recordId;
        public String base64;
        public String fileType;
        public String fileName;

        public UploadDocumentDataWrapper(String jsonString) {
            UploadDocumentDataWrapper wrapper = (UploadDocumentDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), UploadDocumentDataWrapper.class);
            this.recordId = wrapper.recordId;
            this.base64 = wrapper.base64;
            this.fileType = wrapper.fileType;
            this.fileName = wrapper.fileName;
        }

        public UploadDocumentDataWrapper(String recordId, String base64, String fileType, String fileName) {
            this.recordId = recordId;
            this.base64 = base64;
            this.fileType = fileType;
            this.fileName = fileName;
        }

    }

    public class ShortApplicationDataWrapper {
        public String applicationId;
        public Boolean hasEnvelope;
        public FormDataWrapper application;
        public Boolean isAutoSave;
        

        public ShortApplicationDataWrapper(String inputData) {
            ShortApplicationDataWrapper wrapper = (ShortApplicationDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ShortApplicationDataWrapper.class);
            this.applicationId = wrapper.applicationId;
            if(wrapper.application != null) {
                this.application = new FormDataWrapper(JSON.serialize(wrapper.application));
            } else {
                  this.application = new FormDataWrapper();
            } 
             this.isAutoSave = wrapper.isAutoSave != null ? wrapper.isAutoSave : false;
            
        }
        public ShortApplicationDataWrapper() {
            this.application = new FormDataWrapper();
            this.hasEnvelope = false;
            this.applicationId = '';
        }
    }

    // public class ApplicationWrapper {
    //     public FormDataWrapper formData;

    //     public ApplicationWrapper(String inputData) {
    //         ApplicationWrapper wrapper = (ApplicationWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationWrapper.class);
    //         if(wrapper.formData != null) {
    //             this.formData = new FormDataWrapper(JSON.serialize(wrapper.formData));
    //         } else {
    //             this.formData = new FormDataWrapper();
    //         }
    //     }

    //      public ApplicationWrapper() {
    //          this.formData = new FormDataWrapper();
    //      }
       

    // }

    public class FormDataWrapper {
        
        public ClientWrapper client;
        public String track;
        public TrackAWrapper trackA;
        public TrackBWrapper trackB;
        public TrackCWrapper trackC;

        public FormDataWrapper(String inputData) {
            FormDataWrapper wrapper = (FormDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), FormDataWrapper.class);
            if(wrapper.client != null) {
                this.client = new ClientWrapper(JSON.serialize(wrapper.client));
            } else {
                this.client = new ClientWrapper();
            }
            if(String.isNotBlank(wrapper.track)) {
                this.track = wrapper.track;
            } else {
                this.track = '';
            }
            if(wrapper.trackA != null) {
                this.trackA = new TrackAWrapper(JSON.serialize(wrapper.trackA));
            } else {
                this.trackA = new TrackAWrapper();
            }
            if(wrapper.trackB != null) {
                this.trackB = new TrackBWrapper(JSON.serialize(wrapper.trackB));
            } else {
                this.trackB = new TrackBWrapper();
            }
            if(wrapper.trackC != null) {
                this.trackC = new TrackCWrapper(JSON.serialize(wrapper.trackC));
            } else {
                this.trackC = new TrackCWrapper();
            }
            
        }


        public FormDataWrapper() {
            this.client = new ClientWrapper();
            this.track = '';
            this.trackA = new TrackAWrapper();
            this.trackB = new TrackBWrapper();
            this.trackC = new TrackCWrapper();
        }
        
    }

    public class ClientWrapper {
        public String title;
        public String firstName;
        public String lastName;
        public String maidenName;
        public String middleName;
        public String dob;
        public String maritalStatus;
        public String dateOfDivorce;
        public String country;
        public String countryName;
        public String postcode;
        public String address1;
        public String address2;
        public String city;
        public String tel;
        public String email;
        public string pps;
        public String helperEmail;
        public Boolean everLivedUK;
        public String dateLeftUK;

        public Boolean addressValidated;
        public String verificationStatus;
        public Boolean wasCleansed;
        public String nationality;
        public Integer approxYearsInUK;
        public String state;
        public String stateName;
        //public Boolean verifiedReference;
        //public Boolean verificationDetails;
      
        public ClientWrapper(String inputData) {
            ClientWrapper wrapper = (ClientWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ClientWrapper.class);
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.maidenName = wrapper.maidenName;
            this.title = wrapper.title;
            this.maritalStatus = wrapper.maritalStatus;
            this.dateOfDivorce = wrapper.dateOfDivorce;
            this.country = wrapper.country;
            this.countryName = wrapper.countryName;
            this.postcode = wrapper.postcode;
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.tel = wrapper.tel;
            this.dob = wrapper.dob;
            this.email = wrapper.email;
            this.pps = wrapper.pps;
            this.helperEmail = wrapper.helperEmail;
            this.everLivedUK = wrapper.everLivedUK;
            this.dateLeftUK = wrapper.dateLeftUK;
            this.middleName = wrapper.middleName;
            this.addressValidated = wrapper.addressValidated;
            //this.verificationDetails = wrapper.verificationDetails;
            this.wasCleansed = wrapper.wasCleansed;
            //this.verifiedReference = wrapper.verifiedReference;
            this.verificationStatus = wrapper.verificationStatus;
            this.nationality = wrapper.nationality;
            this.approxYearsInUK = wrapper.approxYearsInUK;
            this.state = wrapper.state == 'IE' ? wrapper.state : CountryCodeHelper.getCountryStateISOByName(wrapper.state);
            this.stateName = wrapper.state;
            
        }

        public ClientWrapper() {
            this.firstName = '';
            this.lastName = '';
            this.maidenName = '';
            this.title = '';
            this.middleName = '';

            this.country = '';
            this.countryName = '';
            this.postcode = '';
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.tel = '';
            this.dob = '';
            
            this.maritalStatus = '';
            this.dateOfDivorce = '';
            this.email = '';
            this.pps = '';
            this.helperEmail = '';
            this.everLivedUK = false;
            this.dateLeftUK = '';

            this.addressValidated = false;
            //this.verificationDetails = false;
            this.wasCleansed = false;
            //this.verifiedReference = false;
            this.verificationStatus = '';

            this.nationality = '';
            this.approxYearsInUK = null;

            this.state = '';
            this.stateName = '';
            
        }
    }

    public class TrackAWrapper {
        public Boolean isGettingUKStatePensionNow;
        public String hasNino;
        public String nino;
        public List<CompaniesWrapper> employers;
        public List<CompaniesWrapper> addresses;

        public TrackAWrapper(String inputData) {
            TrackAWrapper wrapper = (TrackAWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), TrackAWrapper.class);
            this.isGettingUKStatePensionNow = wrapper.isGettingUKStatePensionNow;
            this.hasNino = wrapper.hasNino;
            this.nino = wrapper.nino;
            this.employers = wrapper.employers;
            this.addresses = wrapper.addresses;
        }

        public TrackAWrapper() {
            this.isGettingUKStatePensionNow = false;
            this.hasNino = '';
            this.nino = '';
            this.employers = new List<CompaniesWrapper>();
            this.addresses = new List<CompaniesWrapper>();
        }
    }

    public class TrackBWrapper {
        public String title;
        public String husbandAlive;
        public String husbandFullName;
        public String husbandFirstName;
        public String husbandSurname;
        public String husbandOtherName;
        public Boolean husbandGettinStatePensionNow;
        public Boolean youGettinStatePensionNow;
        public String husbandDob;
        public String marriageDate;
        public String husbandLeftUk;
        public Boolean sameAddress;
        public String country;
        public String postcode;
        public String address1;
        public String address2;
        public String city;
        public String husbandHasNino;
        public String husbandNino;
        public List<CompaniesWrapper> employers;
        public List<CompaniesWrapper> addresses;
        public String townsLived;

        public Boolean addressValidated;
        public String verificationStatus;
        public Boolean wasCleansed;
        //public Boolean verifiedReference;
        //public Boolean verificationDetails;
        public String state;
        public String stateName;

        public TrackBWrapper(String inputData) {
            TrackBWrapper wrapper = (TrackBWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), TrackBWrapper.class);
            this.husbandAlive = wrapper.husbandAlive;
            this.husbandFullName = wrapper.husbandFullName;
            this.husbandFirstName = wrapper.husbandFirstName;
            this.husbandSurname = wrapper.husbandSurname;
            this.husbandOtherName = wrapper.husbandOtherName;
            this.husbandDob = wrapper.husbandDob;
            this.husbandGettinStatePensionNow = wrapper.husbandGettinStatePensionNow;
            this.youGettinStatePensionNow = wrapper.youGettinStatePensionNow;
            this.marriageDate = wrapper.marriageDate;
            this.husbandLeftUk = wrapper.husbandLeftUk;
            this.sameAddress = wrapper.sameAddress;
            this.country = wrapper.country;
            this.postcode = wrapper.postcode;
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.husbandHasNino = wrapper.husbandHasNino;
            this.husbandNino = wrapper.husbandNino;
            this.employers = wrapper.employers;
            this.addresses = wrapper.addresses;
            this.townsLived = wrapper.townsLived;

            this.addressValidated = wrapper.addressValidated;
            //this.verificationDetails = wrapper.verificationDetails;
            this.wasCleansed = wrapper.wasCleansed;
            //this.verifiedReference = wrapper.verifiedReference;
            this.verificationStatus = wrapper.verificationStatus;
            this.title = wrapper.title;
            this.state = wrapper.state == 'IE' ? wrapper.state : CountryCodeHelper.getCountryStateISOByName(wrapper.state);
            this.stateName = wrapper.state;
        }

        public TrackBWrapper() {
            this.husbandAlive = '';
            this.husbandFullName = '';
            this.husbandFirstName =  '';
            this.husbandSurname =  '';
            this.husbandOtherName =  '';
            this.husbandGettinStatePensionNow = false;
            this.youGettinStatePensionNow = false;
            this.husbandDob = '';
            this.marriageDate = '';
            this.husbandLeftUk = '';
            this.sameAddress = false;
            this.country = '';
            this.postcode = '';
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.husbandHasNino = '';
            this.husbandNino = '';
            this.employers = new List<CompaniesWrapper>();
            this.addresses = new List<CompaniesWrapper>();
            this.townsLived = '';

            this.addressValidated = false;
            //this.verificationDetails = false;
            this.wasCleansed = false;
            //this.verifiedReference = false;
            this.verificationStatus = '';
            this.title = '';
            this.state = '';
            this.stateName = '';
        }
    }

    public class TrackCWrapper {
        public String wifeDob;
        public Boolean gateResult;
        public Boolean gatePassed;
        public String spaDate;
        public String marriageDate;
        public String wifeLeftUk;
        public Boolean sameAddress;
        public String country;
        public String postcode;
        public String address1;
        public String address2;
        public String city;
        public String wifeHasNino;
        public String wifeNino;
        public List<CompaniesWrapper> employers;
        public List<CompaniesWrapper> addresses;

        public Boolean addressValidated;
        public String verificationStatus;
        public Boolean wasCleansed;
        //public Boolean verifiedReference;
        //public Boolean verificationDetails;
        public String state;
        public String stateName;

        public TrackCWrapper (String inputData) {
            TrackCWrapper wrapper = (TrackCWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), TrackCWrapper.class);
            this.wifeDob = wrapper.wifeDob;
            this.gateResult = wrapper.gateResult;
            this.gatePassed = wrapper.gatePassed;
            this.spaDate = wrapper.spaDate;
            this.marriageDate = wrapper.marriageDate;
            this.wifeLeftUk = wrapper.wifeLeftUk;
            this.sameAddress = wrapper.sameAddress;
            this.country = wrapper.country;
            this.postcode = wrapper.postcode;
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.wifeHasNino = wrapper.wifeHasNino;
            this.wifeNino = wrapper.wifeNino;
            this.employers = wrapper.employers;
            this.addresses = wrapper.addresses;

            this.addressValidated = wrapper.addressValidated;
            //this.verificationDetails = wrapper.verificationDetails;
            this.wasCleansed = wrapper.wasCleansed;
            //this.verifiedReference = wrapper.verifiedReference;
            this.verificationStatus = wrapper.verificationStatus;
            this.state = wrapper.state == 'IE' ? wrapper.state : CountryCodeHelper.getCountryStateISOByName(wrapper.state);
            this.stateName = wrapper.state;
        }
        public TrackCWrapper() {
            this.wifeDob = '';
            this.gateResult = false;
            this.gatePassed = false;
            this.spaDate = '';
            this.marriageDate = '';
            this.wifeLeftUk = '';
            this.sameAddress = false;
            this.country = '';
            this.postcode = '';
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.wifeHasNino = '';
            this.wifeNino = '';
            this.employers = new List<CompaniesWrapper>();
            this.addresses = new List<CompaniesWrapper>();

            this.addressValidated = false;
            //this.verificationDetails = false;
            this.wasCleansed = false;
            //this.verifiedReference = false;
            this.verificationStatus = '';
            this.state = '';
            this.stateName = '';
        }
    }

    public class OtherWrapper {
        public String notes;
        public String docuSignDate;
        public Boolean isUKproperty;
        public Boolean isAccountant;
        public Boolean isSelfAssesedTax;
        public Boolean isAgePension;
        public String accountantAddress1;
        public String accountantAddress2;
        public String accountantCity;
        public String accountantCountry;
        public String accountantCountryName;
        public String accountantStateName;
        public String accountantStateCode;
        public String accountantPhone;
        public String accountantPostCode;
        public String accountantName;
        public List<UkPropertiesWrapper> UkProperties;
        public OtherWrapper (String inputData) {
            OtherWrapper wrapper = (OtherWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), OtherWrapper.class);
            this.notes = wrapper.notes;
            this.isUKproperty = wrapper.isUKproperty;
            this.isAccountant = wrapper.isAccountant;
            this.isSelfAssesedTax = wrapper.isSelfAssesedTax;
            this.isAgePension = wrapper.isAgePension;
            this.accountantAddress1 = wrapper.accountantAddress1;
            this.accountantAddress2 = wrapper.accountantAddress2;
            this.accountantCity = wrapper.accountantCity;
            this.accountantCountryName = wrapper.accountantCountryName;
            this.accountantCountry = wrapper.accountantCountry;
            this.accountantStateName = wrapper.accountantStateName;
            this.accountantStateCode = wrapper.accountantStateCode;
            this.accountantPhone = wrapper.accountantPhone;
            this.accountantPostcode = wrapper.accountantPostcode;
            this.accountantName = wrapper.accountantName;
            if (wrapper.UkProperties != null) {
                for(UkPropertiesWrapper itemwrap : wrapper.UkProperties) {
                    this.UkProperties.add(new UkPropertiesWrapper(JSON.serialize(itemwrap)));
                }  
            } else {
                this.UkProperties = new  List<UkPropertiesWrapper>();
            } 

        }
        public OtherWrapper () {
            this.notes = '';
            this.docuSignDate = '';
            this.isUKproperty = false;
            this.isAccountant = false;
            this.isSelfAssesedTax = false;
            this.isAgePension = false;
            this.UkProperties = new List<UkPropertiesWrapper>();
            this.accountantAddress1 = '';
            this.accountantAddress2 = '';
            this.accountantCity = '';
            this.accountantCountryName = '';
            this.accountantCountry = '';
            this.accountantStateName = '';
            this.accountantStateCode = '';
            this.accountantPhone = '';
            this.accountantPostcode = '';
            this.accountantName = '';
        }
    }


     public class UkPropertiesWrapper {
        public String address1;
        public String address2;
        public String city;
        public String postcode;

        public UkPropertiesWrapper(String inputData) {
            UkPropertiesWrapper wrapper = (UkPropertiesWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), UkPropertiesWrapper.class);
            this.address1 = wrapper.address1;
            this.address2 = wrapper.address2;
            this.city = wrapper.city;
            this.postcode = wrapper.postcode;
        }
        public UkPropertiesWrapper() {
            this.address1 = '';
            this.address2 = '';
            this.city = '';
            this.postcode = '';
        }
    }

    public class BenefitsWrapper {
        public Boolean isYourPartnerCurrentlyGetPension;
        public String isYourPartnerCurrentlyGetPensionText;
        public BenefitsWrapper(String inputData) {
            BenefitsWrapper wrapper = (BenefitsWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), BenefitsWrapper.class);
            this.isYourPartnerCurrentlyGetPension = wrapper.isYourPartnerCurrentlyGetPension;
            this.isYourPartnerCurrentlyGetPensionText = wrapper.isYourPartnerCurrentlyGetPensionText;
        }
        public BenefitsWrapper() {
            this.isYourPartnerCurrentlyGetPension = false;
            this.isYourPartnerCurrentlyGetPensionText = '';
        }

    }

    public class DDMandateDataWrapper {
        public String customer;
        public String nameOfAccountHiolder;
        public String iban;
        public String bankAccountNumber;
        public String bic;
        public String customerAddress;
        public String reference;
        public String bsb1;
        public String bsb2;

        public DDMandateDataWrapper(Basic__c currBasic) {
            this.customer = currBasic.First_Name__c + ' ' + currBasic.Last_Name__c;
            this.nameOfAccountHiolder = currBasic.Bank_Account_Owner_Name__c;
            this.bic = currBasic.Bank_BIC__c;
            this.bankAccountNumber = currBasic.Bank_Account__c;
            this.iban = currBasic.Bank_IBAN__c;
            this.customerAddress = '';
            if (currBasic.Claimant_address1__c != null)                   this.customerAddress += currBasic.Claimant_address1__c;
            if (currBasic.Claimant_address2__c != null)                   this.customerAddress += ', ' + currBasic.Claimant_address2__c;
            if (currBasic.Claimant_City__c != null)                       this.customerAddress += ', ' + currBasic.Claimant_City__c;
            if (currBasic.Current_Address_Abroad_State_Name__c != null)   this.customerAddress += ', ' + currBasic.Current_Address_Abroad_State_Name__c;
            if (currBasic.Eircode__c != null)                             this.customerAddress += ', ' + currBasic.Eircode__c;
            if (currBasic.Current_Address_Abroad_Country_Name__c != null) this.customerAddress += ', ' + currBasic.Current_Address_Abroad_Country_Name__c;
            String bsb = currBasic.Bank_Sort_Code__c != null ? currBasic.Bank_Sort_Code__c.replaceAll('[-\\s]', '') : '';     
            if (String.isNotBlank(bsb) && bsb.length() >= 6) {
                this.bsb1 = bsb.substring(0, 3);
                this.bsb2 = bsb.substring(3, 6);
            }          
            this.reference = currBasic.Name;
        }

        public DDMandateDataWrapper() {
            this.customer = '';
            this.nameOfAccountHiolder = '';
            this.iban = '';
            this.bic = '';
            this.customerAddress = '';
            this.reference = '';
            this.bankAccountNumber = '';
            this.bsb1 = '';
            this.bsb2 = '';
        }
    }



}