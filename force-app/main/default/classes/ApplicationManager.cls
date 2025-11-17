@RestResource(UrlMapping='/api/v1/*')
global with sharing class ApplicationManager {

    @HttpPost
    global static void createApplication() {
        RestRequest request = RestContext.request;
        String reqURI = request.requestURI;
        RestResponse response = RestContext.response;
        String requestBody = request.requestBody.toString();
        Map<String, Object> result = new Map<String, Object>();
        String stripeId = request.params.get('id');
        if (reqURI == '/api/v1/form/create-app') {
            RequestDataWrapper requestData = (RequestDataWrapper) JSON.deserialize(requestBody, RequestDataWrapper.class);
            response.responseBody = Blob.valueOf(JSON.serialize(ApplicationManagerHandler.createApplication(requestData)));
        } else if(reqURI == '/api/v1/form/send-app') {
            String stepName = (String)((Map<String, Object>) JSON.deserializeUntyped(requestBody)).get('stepName');
            if (String.isNotBlank(stripeId) && stepName == 'Personal Details') {
                ApplicationPersonalStepWrapper requestData = (ApplicationPersonalStepWrapper) JSON.deserialize(requestBody.replace('""', 'null'), ApplicationPersonalStepWrapper.class);
                result = ApplicationManagerHandler.setApplicationPersonalDetails(requestData, stripeId, false);
            } else if (String.isNotBlank(stripeId) && stepName == 'Relationship') {
                RelationshipStepWrapper requestDataRelationship = (RelationshipStepWrapper) JSON.deserialize(requestBody.replace('""', 'null'), RelationshipStepWrapper.class);
                result = ApplicationManagerHandler.setApplicationRelationshipDetails(requestDataRelationship, stripeId, false);
            } else if (String.isNotBlank(stripeId) && stepName == 'UK Work') {
                UkWorkStepWrapper requestDataUKWork = (UkWorkStepWrapper) JSON.deserialize(requestBody.replace('""', 'null'), UkWorkStepWrapper.class);
                result = ApplicationManagerHandler.setApplicationUkWorkDetails(requestDataUKWork, stripeId, false);
            } else if (String.isNotBlank(stripeId) && stepName == 'Work After UK') {
                WorkAfterUKStepWrapper requestDataWorkAfterUK = (WorkAfterUKStepWrapper) JSON.deserialize(requestBody.replace('""', 'null'), WorkAfterUKStepWrapper.class);
                result = ApplicationManagerHandler.setApplicationWorkAfterUKDetails(requestDataWorkAfterUK, stripeId, false);
            } else if(String.isNotBlank(stripeId) && stepName == 'Documents') {
                DocumentsStepWrapper requestDataDocuments = (DocumentsStepWrapper) JSON.deserialize(requestBody.replace('""', 'null'), DocumentsStepWrapper.class);
                result = ApplicationManagerHandler.setApplicationDocumentsDetails(requestDataDocuments, stripeId);
                result.put('status', 'Success');
            } else {
                result.put('error', 'Id Not Found');
            }
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } else if(reqURI == '/api/v1/payment/getPaymentInfo') {
            String paymentId = (String)((Map<String, Object>)JSON.deserializeUntyped(requestBody)).get('id');
            result = ApplicationManagerHandler.getPaymentData(paymentId);
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } else if(reqURI == '/api/v1/payment/sendPaymentInfo') {
            PaymentDataWrapper paymentData = (PaymentDataWrapper) JSON.deserialize(requestBody.replace('""', 'null'), PaymentDataWrapper.class);
            result = ApplicationManagerHandler.changeStatusFailedPayment(paymentData);
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } else if(reqURI == '/api/v1/full-form/send-app') {
            FormDataWrapper formData = (FormDataWrapper) JSON.deserialize(requestBody.replace('""', 'null'), FormDataWrapper.class);
            result = ApplicationManagerHandler.setFullFormData(formData, stripeId);
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } else if(reqURI == '/api/v1/mobile-form/send-app') {
            MobileDataWrapper mobileData = (MobileDataWrapper) JSON.deserialize(requestBody.replace('""', 'null'), MobileDataWrapper.class);
            result = ApplicationManagerHandler.setMobileFormData(mobileData, stripeId);
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } else if(reqURI == '/api/v1/form/change-app-stage') {
            result = ApplicationManagerHandler.setFirstStatusApp(stripeId);
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        }
        List<Application__c> createdApp = [
            SELECT Id
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
            LIMIT 1
        ];
        if(createdApp.size() != 0) {
            insert new Heroku_Request__c(
                Request_URL__c = reqURI,
                RequestBody__c = requestBody,
                Application__c = createdApp[0].Id
            );
        }
    }

    //api/v1/form/get-app get Id (stripeId => application)

    @HttpGet
    global static void doGet() {
        RestResponse response = RestContext.response;
        String reqURI = RestContext.request.requestURI;

        if (reqURI == '/api/v1/form/get-app') {

            String stripeId = RestContext.request.params.get('id');
            Boolean isFullForm = Boolean.valueOf(RestContext.request.params.get('isFullForm'));

            Map<String, Object> result = new Map<String, Object>();

            if (String.isNotBlank(stripeId)) {
                result = ApplicationManagerHandler.getApplication(stripeId, result, isFullForm);
                Application__c app = (Application__c) result.get('formData');
                if (app != null) {
                    FormDataWrapper formData = new FormDataWrapper();
                    ApplicationPersonalStepWrapper personalData = new ApplicationPersonalStepWrapper();
                    personalData.salutation                    = app.Salutation__c;
                    personalData.firstName                     = app.First_Name__c;
                    personalData.secondName                    = app.Second_Name__c;
                    personalData.dateOfBirth                   = String.valueOf(app.Date_Of_Birth__c);
                    personalData.insuranceNumber               = app.National_Insurance_Number__c;
                    personalData.workOrPayUKNationalInsurance  = app.Work_Or_Pay_UK_National_Insurance__c;
                    personalData.privateUKPension              = app.Private_UK_Pension__c;
                    personalData.approxValue                   = app.Approx_Value_Of_UK_Pension__c;
                    personalData.currentOccupation             = app.Current_Occupation__c;
                    personalData.isKnowNationalInsuranceNumber = app.Is_Know_National_Insurance_Number__c;
                    personalData.currentlyGettingUKPension     = app.Getting_UK_Pension_Now__c;

                    currentAddressAbroad currentAddressAbroadData = new currentAddressAbroad();
                    if (app.Current_Address_Abroad__Street__s == null) {
                        currentAddressAbroadData.country = 'IE';
                    } else currentAddressAbroadData.country = app.Current_Address_Abroad__CountryCode__s;
                    currentAddressAbroadData.street         = app.Current_Address_Abroad__Street__s ;
                    currentAddressAbroadData.city           = app.Current_Address_Abroad__City__s;
                    currentAddressAbroadData.state          = app.Current_Address_Abroad__StateCode__s;
                    currentAddressAbroadData.postcode       = app.Current_Address_Abroad__PostalCode__s;

                    personalData.currentAddressAbroad = currentAddressAbroadData;

                    lastUKHomeAddress lastUKHomeAddressData = new lastUKHomeAddress();
                    lastUKHomeAddressData.country  = 'GB';
                    lastUKHomeAddressData.street   = app.Previous_UK_Address_1__Street__s;
                    lastUKHomeAddressData.city     = app.Previous_UK_Address_1__City__s;
                    lastUKHomeAddressData.state    = app.Previous_UK_Address_1__StateCode__s;
                    lastUKHomeAddressData.postcode = app.Previous_UK_Address_1__PostalCode__s;
                    lastUKHomeAddressData.fromDate = app.Previous_UK_Address_Start_Date_1__c;
                    lastUKHomeAddressData.toDate   = app.Previous_UK_Address_End_Date_1__c;

                    personalData.lastUKHomeAddress = lastUKHomeAddressData;

                    lastUKHomeAddress lastUKHomeAddressData2 = new lastUKHomeAddress();
                    lastUKHomeAddressData2.country  = 'GB';
                    lastUKHomeAddressData2.street   = app.Previous_UK_Address_2__Street__s;
                    lastUKHomeAddressData2.city     = app.Previous_UK_Address_2__City__s;
                    lastUKHomeAddressData2.state    = app.Previous_UK_Address_2__StateCode__s;
                    lastUKHomeAddressData2.postcode = app.Previous_UK_Address_2__PostalCode__s;
                    lastUKHomeAddressData2.fromDate = app.Previous_UK_Address_Start_Date_2__c;
                    lastUKHomeAddressData2.toDate   = app.Previous_UK_Address_End_Date_2__c;

                    personalData.lastUKHomeAddress2 = lastUKHomeAddressData2;

                    lastUKHomeAddress lastUKHomeAddressData3 = new lastUKHomeAddress();
                    lastUKHomeAddressData3.country  = 'GB';
                    lastUKHomeAddressData3.street   = app.Previous_UK_Address_3__Street__s;
                    lastUKHomeAddressData3.city     = app.Previous_UK_Address_3__City__s;
                    lastUKHomeAddressData3.state    = app.Previous_UK_Address_3__StateCode__s;
                    lastUKHomeAddressData3.postcode = app.Previous_UK_Address_3__PostalCode__s;
                    lastUKHomeAddressData3.fromDate = app.Previous_UK_Address_Start_Date_3__c;
                    lastUKHomeAddressData3.toDate   = app.Previous_UK_Address_End_Date_3__c;

                    personalData.lastUKHomeAddress3 = lastUKHomeAddressData3;

                    // List<previousUKAddress> previousUKAddressData = new List<previousUKAddress>();
                    // for (Integer i = 1; i <= 5; i++) {
                    //     if (app.get('Previous_UK_Address_' + i + '__Street__s') != null) {
                    //         previousUKAddress currentPreviousUKAddress = new previousUKAddress();
                    //         currentPreviousUKAddress.country  = (String) app.get('Previous_UK_Address_' + i + '__CountryCode__s');
                    //         currentPreviousUKAddress.street   = (String) app.get('Previous_UK_Address_' + i + '__Street__s');
                    //         currentPreviousUKAddress.city     = (String) app.get('Previous_UK_Address_' + i + '__City__s');
                    //         currentPreviousUKAddress.state    = (String) app.get('Previous_UK_Address_' + i + '__StateCode__s');
                    //         currentPreviousUKAddress.postcode = (String) app.get('Previous_UK_Address_' + i + '__PostalCode__s');
                    //         previousUKAddressData.add(currentPreviousUKAddress);
                    //     }
                    // }
                    // personalData.previousUKAddress = previousUKAddressData;
                    formData.personal = personalData;

                    RelationshipStepWrapper relationData    = new RelationshipStepWrapper();
                    relationData.changeYouName              = app.Did_You_Change_Name__c;
                    relationData.dateOfMarriedOrPartnership = app.Date_Of_Marriage_Or_Civil_Partnership__c;
                    relationData.divorcedOrwidowed          = app.Are_You_Divorced__c;
                    relationData.fullMaindenOrPreviousName  = app.Full_Maiden_Previous_Name__c;
                    relationData.single                     = app.Are_You_Single__c;
                    relationData.exactDate                  = app.Divorce_Date__c;

                    formData.relationship = relationData;

                    Employer__c ukEmployer = new Employer__c();
                    for (Employer__c employer : app.Employers__r) {
                        if (employer.Type__c == 'UK Work') {
                            ukEmployer = employer;
                            break;
                        }
                    }
                    UkWorkStepWrapper ukWorkData = new UkWorkStepWrapper();
                    ukWorkData.dateOfLeavingLastUKEmployment = app.Date_Of_Leaving_Last_UK__c;
                    ukWorkData.workInUKBeforeLeaving         = app.Type_Of_Employment__c;
                    ukWorkData.yearsWorkInUK                 = app.Years_Of_Work_In_The_UK__c;
                    ukWorkData.endDateOfLastUKEmployer   = app.Last_UK_Employer_End_Date__c;
                    ukWorkData.nameOfLastUKEmployer      = app.Last_UK_Employer_Name__c;
                    ukWorkData.startDateOfLastUKEmployer = app.Last_UK_Employer_Start_Date__c;

                    LastUKEmployerAddress lastUKEmployerAddressData = new LastUKEmployerAddress();
                    lastUKEmployerAddressData.city     = app.Last_UK_Employer_Address__City__s;
                    lastUKEmployerAddressData.country  = 'GB';
                    lastUKEmployerAddressData.postcode = app.Last_UK_Employer_Address__PostalCode__s;
                    lastUKEmployerAddressData.street   = app.Last_UK_Employer_Address__Street__s;
                    lastUKEmployerAddressData.state    = app.Last_UK_Employer_Address__StateCode__s;
                    ukWorkData.lastUKEmployerAddress   = lastUKEmployerAddressData;

                    formData.ukwork = ukWorkData;

                    List<AfterUKEmployerWrapper> workAfterUKData = new List<AfterUKEmployerWrapper>();

                    for (Employer__c employer : app.Employers__r) {
                        if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Career Break') {
                            AfterUKEmployerWrapper currentCareerBreakWrapper       = new AfterUKEmployerWrapper();
                            currentCareerBreakWrapper.startDate                = employer.Start_Date__c;
                            currentCareerBreakWrapper.endDate                  = employer.End_Date__c;
                            currentCareerBreakWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            currentCareerBreakWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(currentCareerBreakWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Employed') {
                            AfterUKEmployerWrapper currentEmployedWrapper = new AfterUKEmployerWrapper();
                            currentEmployedWrapper.nameOfYourEmployerAbroad = employer.Employer_Name__c;
                            currentEmployedWrapper.country                  = employer.Employers_Address__CountryCode__s;
                            currentEmployedWrapper.street                   = employer.Employers_Address__Street__s;
                            currentEmployedWrapper.city                     = employer.Employers_Address__City__s;
                            currentEmployedWrapper.state                    = employer.Employers_Address__StateCode__s;
                            currentEmployedWrapper.postcode                 = employer.Employers_Address__PostalCode__s;
                            currentEmployedWrapper.startDate                = employer.Start_Date__c;
                            currentEmployedWrapper.endDate                  = employer.End_Date__c;
                            currentEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            currentEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(currentEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                            AfterUKEmployerWrapper selfEmployedWrapper = new AfterUKEmployerWrapper();
                            selfEmployedWrapper.startDate                = employer.Start_Date__c;
                            selfEmployedWrapper.endDate                  = employer.End_Date__c;
                            selfEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            selfEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(selfEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Unemployed') {
                            AfterUKEmployerWrapper unemployedEmployedWrapper = new AfterUKEmployerWrapper();
                            unemployedEmployedWrapper.startDate                = employer.Start_Date__c;
                            unemployedEmployedWrapper.endDate                  = employer.End_Date__c;
                            unemployedEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            unemployedEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(unemployedEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Family Carer') {
                            AfterUKEmployerWrapper familyCarerEmployedWrapper = new AfterUKEmployerWrapper();
                            familyCarerEmployedWrapper.startDate                = employer.Start_Date__c;
                            familyCarerEmployedWrapper.endDate                  = employer.End_Date__c;
                            familyCarerEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            familyCarerEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(familyCarerEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Homemaker') {
                            AfterUKEmployerWrapper homemakerEmployedWrapper = new AfterUKEmployerWrapper();
                            homemakerEmployedWrapper.startDate                = employer.Start_Date__c;
                            homemakerEmployedWrapper.endDate                  = employer.End_Date__c;
                            homemakerEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            homemakerEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(homemakerEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Disabled') {
                            AfterUKEmployerWrapper disabledEmployedWrapper = new AfterUKEmployerWrapper();
                            disabledEmployedWrapper.startDate                = employer.Start_Date__c;
                            disabledEmployedWrapper.endDate                  = employer.End_Date__c;
                            disabledEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            disabledEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(disabledEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Retired') {
                            AfterUKEmployerWrapper retiredEmployedWrapper = new AfterUKEmployerWrapper();
                            retiredEmployedWrapper.startDate                = employer.Start_Date__c;
                            retiredEmployedWrapper.endDate                  = employer.End_Date__c;
                            retiredEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            retiredEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(retiredEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Education') {
                            AfterUKEmployerWrapper educationEmployedWrapper = new AfterUKEmployerWrapper();
                            educationEmployedWrapper.startDate                = employer.Start_Date__c;
                            educationEmployedWrapper.endDate                  = employer.End_Date__c;
                            educationEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            educationEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(educationEmployedWrapper);
                        } else if (employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Illness') {
                            AfterUKEmployerWrapper illnessEmployedWrapper = new AfterUKEmployerWrapper();
                            illnessEmployedWrapper.startDate                = employer.Start_Date__c;
                            illnessEmployedWrapper.endDate                  = employer.End_Date__c;
                            illnessEmployedWrapper.afterLeftTheUK           = employer.Type_Of_After_UK_Employment__c;
                            illnessEmployedWrapper.isCurrently              = employer.Current_Work__c == 'Yes' ? true : false;
                            workAfterUKData.add(illnessEmployedWrapper);
                        }
                    }

                    formData.workAfterUK = workAfterUKData;

                    DocumentsStepWrapper documentsData = new DocumentsStepWrapper();
                    documentsData.applicationId = app.Id;
                    documentsData.applicationName = app.Name;
                    documentsData.notes = app.Full_Form_Notes__c;
                    formData.documents = documentsData;

                    MissingInfoWrapper missingData = new MissingInfoWrapper();
                    missingData.lastUKEmpl = app.Is_Contains_Last_UK_Emploers__c;
                    missingData.nino = app.Is_Contains_NINO__c;
                    missingData.prsi = app.Is_Contains_PRSI__c;
                    missingData.relationship = app.Is_Contains_Relationship_Details__c;
                    missingData.workAfterUK = app.Is_Contains_Work_After_UK_Details__c;
                    missingData.c3AppealLetter = app.Is_Contains_C3_Appeal_Letter__c;
                    missingData.appealApplication = app.Appeal_Application__c;
                    formData.missingInfo = missingData;

                    result.put('formData', formData);
                }
            } else {
                result.put('error', 'Id Not Found');
            }
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } else if (reqURI == '/api/v1/mobile-form/get-app') {
            String stripeId = RestContext.request.params.get('id');
            Map<String, Object> result = new Map<String, Object>();
            if (String.isNotBlank(stripeId)) {
                result = ApplicationManagerHandler.getMobileData(stripeId, result);
                Application__c app = (Application__c) result.get('formData');
                if (app != null) {
                    MobileDataWrapper wrapper = new MobileDataWrapper();
                    wrapper.yourName = app.Your_Name__c;
                    wrapper.yourDateOfBirth = String.valueOf(app.Date_Of_Birth__c);
                    wrapper.yourMaritalStatus = app.Marital_status__c;
                    wrapper.nameAndAddressOfLastUKEmployed = app.Name_And_Address_Of_Last_UK_Employed__c;
                    wrapper.approxDateLeaveUK = String.valueOf(app.Date_Of_Leaving_Last_UK__c);
                    wrapper.youWorkingImmediatelyBeforeLeavingUK = app.You_Worked_Immediately_Before_Leaving_UK__c;
                    wrapper.nameAndAddressOfFirstWorkAfterUK = app.Name_And_Address_Of_First_Work_After_UK__c;
                    wrapper.approxDateStopFirstWorking = String.valueOf(app.Approx_Date_Stop_First_Working__c);
                    wrapper.youDone = app.You_Have_Done_Where_2006_NOW__c;
                    wrapper.nationalInsuranceNumber = app.National_Insurance_Number__c;
                    wrapper.requestPRSIorSocialInsStatement = app.Request_PRSI_or_Social_Ins_Statement__c;
                    wrapper.yearsInTheUK = Integer.valueOf(app.Years_Of_Work_In_The_UK__c);
                    result.put('formData', wrapper);
                } else {
                    result.put('error', 'Id Not Found');
                }
            }
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        }
    }

        //     public String yourName;
        // public String yourDateOfBirth;
        // public String yourMaritalStatus;
        // public String approxDateLeaveUK;
        // public Boolean youWorkingImmediatelyBeforeLeavingUK;
        // public String nameAndAddressOfFirstWorkAfterUK;
        // public String approxDateStopFirstWorking;
        // public String youDone;
        // public String nationalInsuranceNumber;
        // public String requestPRSIorSocialInsStatement;
        // public AddressDataWrapper address;
        // public Decimal yearsInTheUK;

    public class FormDataWrapper {
        public ApplicationPersonalStepWrapper personal;
        public RelationshipStepWrapper relationship;
        public UkWorkStepWrapper ukwork;
        public List<AfterUKEmployerWrapper> workAfterUK;
        public DocumentsStepWrapper documents;
        public MissingInfoWrapper missingInfo;
        public Boolean isAutoUpdate;
    }

    public class MissingInfoWrapper {
        public Boolean lastUKEmpl;
        public Boolean nino;
        public Boolean prsi;
        public Boolean relationship;
        public Boolean workAfterUK;
        public Boolean c3AppealLetter;
        public Boolean appealApplication;
    }

    public class RequestDataWrapper {
        public String id;
        public Decimal amount;
        public String email;
        public String phone;
        public String name;
        public AddressDataWrapper address;
        public String firstName;
        public String lastName;
        public String packageName;
        public String paymentMethod;
        public String customer;
        public Boolean tax;
        public String latest_charge;
        public String howDidYouHearAboutUs;
        public String agent;
        public String isEuropeanCountry;
        public String currencyCode;
    }

    public class AddressDataWrapper {
        //line1 == street
        //line2 - optional
        public String line1;
        public String line2;
        public String postal_code;
        public String state;
        public String city;
        public String country;
    }

    public class ApplicationPersonalStepWrapper {
        public String salutation;
        public String firstName;
        public String secondName;
        public String dateOfBirth;
        public String insuranceNumber;
        public Boolean workOrPayUKNationalInsurance;
        public Boolean privateUKPension;
        public Decimal approxValue;
        public String currentOccupation;
        public currentAddressAbroad currentAddressAbroad;
        public lastUKHomeAddress lastUKHomeAddress;
        public lastUKHomeAddress lastUKHomeAddress2;
        public lastUKHomeAddress lastUKHomeAddress3;
        public List<previousUKAddress> previousUKAddress;
        public String stepName;
        public Boolean isKnowNationalInsuranceNumber;
        public Boolean appealApplication;
        public Boolean currentlyGettingUKPension;
    }

    public class currentAddressAbroad {
        public String country;
        public String street;
        public String city;
        public String state;
        public String postcode;
    }

    public class lastUKHomeAddress {
        public String country;
        public String street;
        public String city;
        public String state;
        public String postcode;
        public Date fromDate;
        public Date toDate;
    }

    public class previousUKAddress {
        public String country;
        public String street;
        public String city;
        public String state;
        public String postcode;
    }

    public class RelationshipStepWrapper {
        public Boolean changeYouName;
        public Date dateOfMarriedOrPartnership;
        public Boolean divorcedOrwidowed;
        public String fullMaindenOrPreviousName;
        public Boolean single;
        public Date exactDate;
        public String stepName;
    }

    public class UkWorkStepWrapper {
        public Date dateOfLeavingLastUKEmployment;
        public Date endDateOfLastUKEmployer;
        public String nameOfLastUKEmployer;
        public Date startDateOfLastUKEmployer;
        public String workInUKBeforeLeaving;
        public Decimal yearsWorkInUK;
        public LastUKEmployerAddress lastUKEmployerAddress;
        public String stepName;
    }

    public class LastUKEmployerAddress {
        public String country;
        public String street;
        public String city;
        public String state;
        public String postcode;
    }

    public class WorkAfterUKStepWrapper {
        public List<AfterUKEmployerWrapper> workAfterUK;
        public String stepName;
    }

    public class AfterUKEmployerWrapper implements Comparable {
        public String nameOfYourEmployerAbroad;
        public String afterLeftTheUK;
        public String country;
        public String street;
        public String city;
        public String state;
        public String postcode;
        public Date startDate;
        public Date endDate;
        public Boolean isCurrently;

        public Integer compareTo(Object compareTo) {
            AfterUKEmployerWrapper employerWrapper = (AfterUKEmployerWrapper)compareTo;
            if (startDate == employerWrapper.startDate) return 0;
            else if (startDate > employerWrapper.startDate) return 1;
            else return -1;
        }
    }

    public class DocumentsStepWrapper {
        public String applicationId;
        public String applicationName;
        public String statements;
        public String youCV;
        public String notes;
    }

    public class PaymentDataWrapper {
        public String id;
        public String paymentId;
        public String paymentMethod;
        public String customer;
        public Decimal amount;
        public String email;
        public String name;
        public String firstName;
        public String lastName;
        public String phone;
        public AddressDataWrapper address;
        public String currencyCode;
    }

    public class MobileDataWrapper {
        public String yourName;
        public String yourDateOfBirth;
        public String yourMaritalStatus;
        public String approxDateLeaveUK;
        public String nameAndAddressOfLastUKEmployed;
        public Boolean youWorkingImmediatelyBeforeLeavingUK;
        public String nameAndAddressOfFirstWorkAfterUK;
        public String approxDateStopFirstWorking;
        public String youDone;
        public String nationalInsuranceNumber;
        public Boolean requestPRSIorSocialInsStatement;
        public Integer yearsInTheUK;
    }
}