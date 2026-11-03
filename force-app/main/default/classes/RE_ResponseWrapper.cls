public class RE_ResponseWrapper {
    
    public class ApplicationDataWrapper {
        public String firstName;
        public String secondName;
        public String formerName;
        public String email;
        public String phone;
        public AddressDataWrapper currentAddress;
        public Boolean isApr2024 = false;
        public Boolean isApr2025 = false;
        public String ukYears;
        public String payNationalInsuranceYears;
        public Boolean receivedJobSeekersAllowance = true;
        public String receiveJSALastDate;
        public Boolean receivedChildBenefit = false;
        public String receiveChildBenefitLastDate;
        public Boolean isShowJSA = false;
        public Boolean isShowChildBenefit = false;
        public Boolean isSubmit = false;
        public Boolean isPaymentSubmit = false;
        public Boolean isAnnualOrNotAnnualApp = false;
        public Boolean isShowUKYears = false;
        
        public ApplicationDataWrapper(Reapply__c currReapp) {
            if(currReapp != null) {
                this.firstName = currReapp.First_Name__c;
                this.secondName = currReapp.Second_Name__c;
                this.formerName = currReapp.Former_Name__c;
                this.email = currReapp.Email__c;
                this.phone = currReapp.Phone__c;
                this.currentAddress = new AddressDataWrapper(currReapp);
                this.isShowUKYears = currReapp.Live_in_UK__c == null || currReapp.NINO_contribution_pay__c == null ? true : false;
                this.ukYears = currReapp.Live_in_UK__c!= null ? String.valueOf(currReapp.Live_in_UK__c) : String.valueOf(currReapp.Application__r.Years_Of_Work_In_The_UK__c);
                this.payNationalInsuranceYears = currReapp.NINO_contribution_pay__c != null ? String.valueOf(currReapp.NINO_contribution_pay__c) : String.valueOf(currReapp.Application__r.Years_Of_Work_In_The_UK__c);
                this.receivedJobSeekersAllowance = currReapp.Where_you_receiving_JSA_before_left_UK__c;
                this.receiveJSALastDate = currReapp.Last_received_JSA_date__c != null ? String.valueOf(currReapp.Last_received_JSA_date__c) : null;
                this.receivedChildBenefit = currReapp.Where_you_receiving_Child_Benefit__c;
                this.receiveChildBenefitLastDate = currReapp.Last_received_Child_Benefit_date__c != null ? String.valueOf(currReapp.Last_received_Child_Benefit_date__c) : null;
                this.isApr2024 = currReapp.NINO_contributions_in_tax_years__c != null &&
                    currReapp.NINO_contributions_in_tax_years__c.contains('2024 to 2025') ?
                    true :
                    false;
                this.isApr2025 = currReapp.NINO_contributions_in_tax_years__c != null &&
                    currReapp.NINO_contributions_in_tax_years__c.contains('2025 to 2026') ?
                    true :
                    false;
                this.isSubmit = currReapp.Submit_Form__c;
                this.isAnnualOrNotAnnualApp = currReapp.Application__r.Status__c == 'Annual Service' || currReapp.Application__r.Status__c == 'No Annual' ? true : false;
            }
        }
    }
    
    public class CurrentApplicationDataWrapper {
        public String applicationId;
        public String applicationNumber;
        public String firstName;
        public String lastName;
        public String email;
        public Date dob;
        public String nationalInsuranceNumber;
        public AddressDataWrapper currentAddress;
        public String paymentMethod;
        public String customerId;
        public String phone;
        public String currencyCode;
        public CardDataWrapper cardData;
        public Boolean isShowApplicationDetails;
        public Boolean isPensionKeeperCustomer;
        public Boolean isAnnualOrNotAnnualApp = false;
        
        
        public CurrentApplicationDataWrapper(Reapply__c reapply) {
            this.applicationId = reapply.Application__c;
            this.applicationNumber = reapply.Name;
            this.firstName = reapply.First_Name__c;
            this.lastName = reapply.Second_Name__c;
            this.email = reapply.Email__c;
            this.dob = reapply.Date_of_birth__c;
            this.nationalInsuranceNumber = reapply.NINO__c;
            this.currentAddress = new AddressDataWrapper(reapply);
            this.customerId = reapply.Stripe_Customer_Id__c;
            this.phone = reapply.Phone__c;
            this.currencyCode = reapply.CurrencyIsoCode;
            this.isPensionKeeperCustomer = reapply.Application__r.PK_Portal_User_Active__c && reapply.Application__r.Status__c == 'Pension Keeper' ? true : false;
            this.paymentMethod = reapply.Payment_Method_Id__c;
            this.isAnnualOrNotAnnualApp = reapply.Application__r.Status__c == 'Annual Service' || reapply.Application__r.Status__c == 'No Annual' ? true : false;
            //if(reapply.Application__r.Payment_Method__c != null && reapply.Application__r.Payment_Method__c.contains(';')) {
                //List<String> paymentMethods = reapply.Application__r.Payment_Method__c.split(';');
                //this.paymentMethod = paymentMethods[paymentMethods.size() - 1].trim();
            //} else if(reapply.Application__r.Payment_Method__c != null && !reapply.Application__r.Payment_Method__c.contains(';')) this.paymentMethod = reapply.Application__r.Payment_Method__c;
            if (this.paymentMethod != null) {
                StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
                    'payment_methods/' + this.paymentMethod,
                'GET',
                null
                    );
                if (requestPaymentMethodResult.isError != true) {
                    Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
                    cardData = new CardDataWrapper((Map<String,Object>) methodData.get('card'));
                    
                }
            }
        }
    }
    
    public class AddressDataWrapper {
        public String street;
        public String postalCode;
        public String state;
        public String city;
        public String country;
        public String countryCode;
        
        public AddressDataWrapper(Reapply__c reapply) {
            this.street = reapply.Address_abroad__Street__s;
            this.postalCode = reapply.Address_abroad__PostalCode__s;
            this.state = reapply.Address_abroad__StateCode__s;
            this.city = reapply.Address_abroad__City__s;
            this.countryCode =  reapply.Address_abroad__CountryCode__s;
            System.debug(reapply.Address_abroad__CountryCode__s);
            this.country = reapply.Address_abroad__CountryCode__s != null ? (String)reapply.get('CountryCode') : null;
        }
    }
    
    public class CardDataWrapper {
        public String last4Digits;
        public String cardBrand;
        public Integer expireYear;
        public Integer expireMonth;
        
        public CardDataWrapper(Map<String,Object> inputData) {
            this.last4Digits = (String)inputData.get('last4');
            this.cardBrand = (String)inputData.get('brand');
            this.expireYear = (Integer)inputData.get('exp_year');
            this.expireMonth = (Integer)inputData.get('exp_month');
        }
    }
    
    public class FullReapplyDataWrapper {
        public String fullName1;
        public String fullName2;
        public String yourUKAddressLine1;
        public String yourUKAddressLine2;
        public String yourUKAddressLine3;
        public String yourUKAddressLine4;
        public Double liveUKYears;
        public Double payNIContributionsYears;
        public String nino12;
        public String nino34;
        public String nino56;
        public String nino67;
        public String nino8;
        public String dayOfBirth;
        public String monthOfBirth;
        public String yearOfBirth;
        public String leaveUKDay;
        public String leaveUKMonth;
        public String leaveUKYear;
        public String abroadCountries;
        public Boolean chLiveOutsideUK;
        public Boolean unchLiveOutside;
        public String yourAbroadAddressLine1;
        public String yourAbroadAddressLine2;
        public String yourAbroadAddressLine3;
        public String yourAbroadAddressLine4;
        public Boolean preferUseUKAddress;
        public Boolean preferUseAbroadAddress;
        public Boolean workingAbrdFullCurrTawYear;
        public Boolean notWorkingAbrdFullCurrTawYear;
        public Boolean ordinalyResidentUK;
        public Boolean notOrdinalyResidentUK;
        public Boolean payVolContOngoingPeriod;
        public Boolean gapInNI;
        public Boolean bothOngoingPeriodAndGaps;
        public Boolean x24To25Years;
        public Boolean x25To26TaxYears;
        public Boolean employedEmplStatus;
        public Boolean selfEmploedEmplStatus;
        public Boolean neitherEmplStatus;
        public String lastEmployerName;
        public String lastEmployerAddressLine1;
        public String lastEmployerAddressLine2;
        public String lastEmployerAddressLine3;
        public String lastEmployerAddressLine4;
        public Boolean stopWorkLastUKEmpl;
        public Boolean notStopWorkLastUKEmployer;
        public String endLastEmplDay;
        public String endLastEmplMonth;
        public String endLastEmplYear;
        public Boolean workedAsEmployee;
        public Boolean notWorkedAsEmployee;
        public String abrdEmployerName;
        public String abrdEmplAddressLine1;
        public String abrdEmplAddressLine2;
        public String abrdEmplAddressLine3;
        public String abrdEmplAddressLine4;
        public Boolean endedSelfEmployment;
        public Boolean notEndedSelfEmployment;
        public String selfEmplEndDay;
        public String selfEmplEndMonth;
        public String selfEmplEndYear;
        public Boolean receiveJSA;
        public Boolean notReceiveJSA;
        public String receiveJSALastDay;
        public String receiveJSALastMonth;
        public String receiveJSALastYear;
        public Boolean receiveChildBenefit;
        public Boolean notReceiveChildBenefit;
        public String receiveChildBenefitLastDay;
        public String receiveChildBenefitLastMonth;
        public String receiveChildBenefitLastYear;
        public String startEmplDay;
        public String startEmplMonth;
        public String startEmplYear;
        public String ceasedEmplEndDay;
        public String ceasedEmplEndMonth;
        public String ceasedEmplEndYear;
        public Boolean overseasGovernmentEmpl;
        public Boolean notOverseasGovernmentEmpl;
        public String emplUKAddressLine3;
        public String emplUKAddressLine4;
        public String emplUKAddressLine2;
        public String emplUKAddressLine1;
        public Boolean workForEmplBeforeLeftUK;
        public Boolean notWorkForEmplBeforeLeftUK;
        public Boolean emplHoldContract;
        public Boolean emplNotHoldContract;
        public String yourSalary1234;
        public String yourSalary56;
        public Boolean payByDirectDebit;
        public Boolean payByAnnualPayment;
        public Boolean payByAgent;
        public Boolean haveOtherEmplAbroad;
        public Boolean notHaveOtherEmplAbroad;
        public Boolean selfEmplAbroad;
        public Boolean notSelfEmplAbroad;
        public String selfEmplAbroadStartDay;
        public String selfEmplAbroadStartMonth;
        public String selfEmplAbroadStartYear;
        public String selfEmplAbrdEndDay;
        public String selfEmplAbroadEndMonth;
        public String selfEmplAbroadEndYear;
        public Boolean paidWeekly;
        public Boolean paidMonthly;
        public String agentName;
        public String agentAddressLine1;
        public String agentAddressLine2;
        public String agentAddressLine3;
        public String agentAddressLine4;
        public Boolean payGapsUseDirectDebit;
        public Boolean payGapsUseSterlingCheque;
        public String fullNameSign1;
        public String fullNameSign2;
        public String phoneNumber;
        public String signDay;
        public String signMonth;
        public String signYear;
        public String reappNameTop;
        public String reappNameBottom;
        
        public FullReapplyDataWrapper(Reapply__c currReapply, Boolean isDocusign) {
            List<String> customerNames = RE_AddressWrapperUtil.buildWrappedName(
                new List<String>{
                    currReapply.Salutation__c,
                    currReapply.First_Name__c,
                    currReapply.Second_Name__c
                },
                30
            );
            this.fullName1 = customerNames.size() > 0 ? customerNames[0] : '';
            this.fullName2 = customerNames.size() > 1 ? customerNames[1] : '';
            this.reappNameTop = currReapply.Name;
            this.reappNameBottom = currReapply.Name;

            List<String> ukAddr = RE_AddressWrapperUtil.buildWrappedAddress(
                new List<String>{
                    currReapply.UK_Address__Street__s,
                    currReapply.UK_Address__City__s
                },
                35,
                false
            );
            this.yourUKAddressLine1 = ukAddr.size() > 0 ? ukAddr[0] : '';
            this.yourUKAddressLine2 = ukAddr.size() > 1 ? ukAddr[1] : '';
            this.yourUKAddressLine3 = ukAddr.size() > 2 ? ukAddr[2] : '';
            this.yourUKAddressLine4 = currReapply.UK_Address__PostalCode__s;
            String nino = currReapply.NINO__c;
            if (nino != null && nino.length() >= 9) {
                this.nino12 = nino.substring(0, 2);
                this.nino34 = nino.substring(2, 4);
                this.nino56 = nino.substring(4, 6);
                this.nino67 = nino.substring(6, 8);
                this.nino8  = nino.substring(8, 9);
            }
            Date dob = currReapply.Date_of_birth__c;
            if (dob != null) {
                this.dayOfBirth = String.valueOf(dob.day()).leftPad(2, '0');
                this.monthOfBirth = String.valueOf(dob.month()).leftPad(2, '0');
                this.yearOfBirth = String.valueOf(dob.year());
            }
            this.liveUKYears = currReapply.Live_in_UK__c;
            List<String> abroadAddr = RE_AddressWrapperUtil.buildWrappedAddress(
                new List<String>{
                    currReapply.Address_abroad__Street__s,
                    currReapply.Address_abroad__City__s,
                    currReapply.Address_abroad__StateCode__s,
                    currReapply.Address_abroad__PostalCode__s
                },
                35,
                false
            );
            this.yourAbroadAddressLine1 = abroadAddr.size() > 0 ? abroadAddr[0] : '';
            this.yourAbroadAddressLine2 = abroadAddr.size() > 1 ? abroadAddr[1] : '';
            this.yourAbroadAddressLine3 = abroadAddr.size() > 2 ? abroadAddr[2] : '';            
            this.yourAbroadAddressLine4 = currReapply.Address_abroad__CountryCode__s;
            
            this.payNIContributionsYears = currReapply.NINO_contribution_pay__c;
            Date leaveUKDate = currReapply.What_date_did_or_will_you_leave_the_UK__c;
            if (leaveUKDate != null) {
                this.leaveUKDay = String.valueOf(leaveUKDate.day()).leftPad(2, '0');
                this.leaveUKMonth = String.valueOf(leaveUKDate.month()).leftPad(2, '0');
                this.leaveUKYear = String.valueOf(leaveUKDate.year());
            }
            this.abroadCountries = currReapply.Countries_names_with_dates__c;
            this.chLiveOutsideUK = currReapply.Are_you_currently_living_outside_the_UK__c == true ? true : false;
            this.unchLiveOutside = currReapply.Are_you_currently_living_outside_the_UK__c == false ? true : false;
            this.preferUseUKAddress = currReapply.Prefer_contact_address__c == 'UK' ? true : false;
            this.preferUseAbroadAddress = currReapply.Prefer_contact_address__c == 'Abroad' ? true : false;
            this.workingAbrdFullCurrTawYear = currReapply.living_working_abroad_current_tax_year__c == true ? true : false;
            this.notWorkingAbrdFullCurrTawYear = currReapply.living_working_abroad_current_tax_year__c == false ? true : false;
            this.ordinalyResidentUK = currReapply.Resident_in_rhe_UK_before_left__c == true ? true : false;
            this.notOrdinalyResidentUK = currReapply.Resident_in_rhe_UK_before_left__c == false ? true : false;
            this.payVolContOngoingPeriod = currReapply.Pay_voluntary_contributions__c == 'ongoing periods (for future years)' ? true : false;
            this.gapInNI = currReapply.Pay_voluntary_contributions__c == 'gaps in your National Insurance record, for example shortfalls for previous years' ? true : false;
            this.bothOngoingPeriodAndGaps = currReapply.Pay_voluntary_contributions__c == 'both ongoing periods and gaps for previous years' ? true : false;
            this.x24To25Years = currReapply.NINO_contributions_in_tax_years__c != null && currReapply.NINO_contributions_in_tax_years__c.contains('2024 to 2025') ? true : false;
            this.x25To26TaxYears = currReapply.NINO_contributions_in_tax_years__c != null && currReapply.NINO_contributions_in_tax_years__c.contains('2025 to 2026') ? true : false;
            if (currReapply.employment_status_before_left_UK__c == 'employed') {
                this.employedEmplStatus = true;
                this.lastEmployerName = currReapply.Last_employer_Name__c;
                this.stopWorkLastUKEmpl = currReapply.Stopped_working_for_last_UK_employer__c == true ? true : false;
                this.notStopWorkLastUKEmployer = currReapply.Stopped_working_for_last_UK_employer__c == false ? true : false;
                Date lastEmplEndDate = currReapply.Last_employment_ended_date__c;
                if (lastEmplEndDate != null) {
                    this.endLastEmplDay = String.valueOf(lastEmplEndDate.day()).leftPad(2, '0');
                    this.endLastEmplMonth = String.valueOf(lastEmplEndDate.month()).leftPad(2, '0');
                    this.endLastEmplYear = String.valueOf(lastEmplEndDate.year());
                }
                List<String> lastEmpAddr = RE_AddressWrapperUtil.buildWrappedAddress(
                    new List<String>{
                        currReapply.Last_employer_Address__Street__s,
                        currReapply.Last_employer_Address__City__s
                    },
                    30,
                    false
                );
                this.lastEmployerAddressLine1 = lastEmpAddr.size() > 0 ? lastEmpAddr[0] : '';
                this.lastEmployerAddressLine2 = lastEmpAddr.size() > 1 ? lastEmpAddr[1] : '';
                this.lastEmployerAddressLine3 = lastEmpAddr.size() > 2 ? lastEmpAddr[2] : '';
                this.lastEmployerAddressLine4 = currReapply.Last_employer_Address__PostalCode__s;
                
            }
            if (currReapply.employment_status_before_left_UK__c == 'self_employed') {
                this.selfEmploedEmplStatus = true;
                this.endedSelfEmployment = currReapply.Has_your_UK_self_employment_ended__c == true ? true : false;
                this.notEndedSelfEmployment = currReapply.Has_your_UK_self_employment_ended__c == false ? true : false;
                Date selfEmplEndDate = currReapply.Uk_self_employment_ended_date__c;
                if(selfEmplEndDate != null) {
                    this.selfEmplEndDay = String.valueOf(selfEmplEndDate.day()).leftPad(2, '0');
                    this.selfEmplEndMonth = String.valueOf(selfEmplEndDate.month()).leftPad(2, '0');
                    this.selfEmplEndYear = String.valueOf(selfEmplEndDate.year());
                }
            }
            if (currReapply.employment_status_before_left_UK__c == 'neither_employed_nor_self_employed') {
                this.neitherEmplStatus = true;
            }
                this.receiveJSA = currReapply.Where_you_receiving_JSA_before_left_UK__c == true ? true : false;
                System.debug('currReapply.Where_you_receiving_JSA_before_left_UK__c ===== ' + currReapply.Where_you_receiving_JSA_before_left_UK__c);
                System.debug('this.receiveJSA === ' + this.receiveJSA);
                this.notReceiveJSA = currReapply.Where_you_receiving_JSA_before_left_UK__c == false ? true : false;
                Date receiveJSADate = currReapply.Last_received_JSA_date__c;
                if(receiveJSADate != null) {
                    this.receiveJSALastDay = String.valueOf(receiveJSADate.day()).leftPad(2, '0');
                    this.receiveJSALastMonth = String.valueOf(receiveJSADate.month()).leftPad(2, '0');
                    this.receiveJSALastYear = String.valueOf(receiveJSADate.year());
                }
                this.receiveChildBenefit = currReapply.Where_you_receiving_Child_Benefit__c == true ? true : false;
                this.notReceiveChildBenefit = currReapply.Where_you_receiving_Child_Benefit__c == false ? true : false;
                Date receivedChildBenefitDate = currReapply.Last_received_Child_Benefit_date__c;
                if(receivedChildBenefitDate != null) {
                    this.receiveChildBenefitLastDay = String.valueOf(receivedChildBenefitDate.day()).leftPad(2, '0');
                    this.receiveChildBenefitLastMonth = String.valueOf(receivedChildBenefitDate.month()).leftPad(2, '0');
                    this.receiveChildBenefitLastYear = String.valueOf(receivedChildBenefitDate.year());
                }
            //}
            this.workedAsEmployee = currReapply.Is_previously_worked_abroad_as_an_emp__c == true ? true : false;
            this.notWorkedAsEmployee = currReapply.Is_previously_worked_abroad_as_an_emp__c == false ? true : false;
            if (this.workedAsEmployee == true) {
                this.abrdEmployerName = currReapply.Employer_abroad_Name__c;
                List<String> abrdEmpAddr = RE_AddressWrapperUtil.buildWrappedAddress(
                    new List<String>{
                        currReapply.Employer_abroad_Address__Street__s,
                        currReapply.Employer_abroad_Address__City__s,
                        currReapply.Employer_abroad_Address__StateCode__s,
                        currReapply.Employer_abroad_Address__PostalCode__s
                    },
                    29,
                    false
                );
                this.abrdEmplAddressLine1 = abrdEmpAddr.size() > 0 ? abrdEmpAddr[0] : '';
                this.abrdEmplAddressLine2 = abrdEmpAddr.size() > 1 ? abrdEmpAddr[1] : '';
                this.abrdEmplAddressLine3 = abrdEmpAddr.size() > 2 ? abrdEmpAddr[2] : '';
                this.abrdEmplAddressLine4 = currReapply.Employer_abroad_Address__CountryCode__s;
                Date startEmplDate = currReapply.Start_employment_date__c;
                if(startEmplDate != null) {
                    this.startEmplDay = String.valueOf(startEmplDate.day()).leftPad(2, '0');
                    this.startEmplMonth = String.valueOf(startEmplDate.month()).leftPad(2, '0');
                    this.startEmplYear =  String.valueOf(startEmplDate.year());
                }
                Date emplCeasedEndDate = currReapply.Employment_ceased_end_date__c;
                if(emplCeasedEndDate != null) {
                    this.ceasedEmplEndDay = String.valueOf(emplCeasedEndDate.day()).leftPad(2, '0');
                    this.ceasedEmplEndMonth = String.valueOf(emplCeasedEndDate.month()).leftPad(2, '0');
                    this.ceasedEmplEndYear =  String.valueOf(emplCeasedEndDate.year());
                }
                this.overseasGovernmentEmpl = currReapply.Employer_an_overseas_gov_international__c == true ? true : false;
                this.notOverseasGovernmentEmpl = currReapply.Employer_an_overseas_gov_international__c == false ? true : false;
                this.workForEmplBeforeLeftUK = currReapply.Self_employer_work_before_left_UK__c == true ? true : false;
                this.notWorkForEmplBeforeLeftUK = currReapply.Self_employer_work_before_left_UK__c == false ? true : false;
                if (this.workForEmplBeforeLeftUK == true) {
                    this.emplUKAddressLine1 = currReapply.Employer_s_UK_address__Street__s;
                    this.emplUKAddressLine2 = currReapply.Employer_s_UK_address__City__s;
                    this.emplUKAddressLine4 = currReapply.Employer_s_UK_address__PostalCode__s;
                }
            }
            this.emplHoldContract = currReapply.Employer_hold_your_contract_of_service__c == true ? true : false;
            this.emplNotHoldContract = currReapply.Employer_hold_your_contract_of_service__c == false ? true : false;
            this.haveOtherEmplAbroad = currReapply.Any_other_employments_abroad__c == true ? true : false;
            this.notHaveOtherEmplAbroad = currReapply.Any_other_employments_abroad__c == false ? true : false;
            this.selfEmplAbroad = currReapply.Self_employed_abroad__c == true ? true : false;
            this.notSelfEmplAbroad = currReapply.Self_employed_abroad__c == false ? true : false;
            Date startSelfEmploymentAbroadDate = currReapply.Start_self_employment_abroad_date__c;
            if(startSelfEmploymentAbroadDate != null) {
                this.selfEmplAbroadStartDay = String.valueOf(startSelfEmploymentAbroadDate.day()).leftPad(2, '0');
                this.selfEmplAbroadStartMonth = String.valueOf(startSelfEmploymentAbroadDate.month()).leftPad(2, '0');
                this.selfEmplAbroadStartYear =  String.valueOf(startSelfEmploymentAbroadDate.year());
            }
            Date endSelfEmploymentAbroadDate = currReapply.End_self_employment_abroad_date__c;
            if(endSelfEmploymentAbroadDate != null) {
                this.selfEmplAbrdEndDay = String.valueOf(endSelfEmploymentAbroadDate.day()).leftPad(2, '0');
                this.selfEmplAbroadEndMonth = String.valueOf(endSelfEmploymentAbroadDate.month()).leftPad(2, '0');
                this.selfEmplAbroadEndYear =  String.valueOf(endSelfEmploymentAbroadDate.year());
            }
            this.fullNameSign1 = currReapply.First_Name__c + ' ' + currReapply.Second_Name__c;
            this.phoneNumber = currReapply.Phone__c;
            this.payByDirectDebit = currReapply.Wish_to_pay_by__c == 'Direct Debit' ? true : false ;
            this.payByAnnualPayment = currReapply.Wish_to_pay_by__c == 'Annual payment' ? true : false ;
            this.payByAgent = currReapply.Wish_to_pay_by__c == 'Agent' ? true : false ;
            this.payGapsUseDirectDebit = currReapply.Direct_debit_chosen__c == 'Direct Debit' ? true : false;
            this.payGapsUseSterlingCheque = currReapply.Direct_debit_chosen__c == 'Sterling cheque' ? true : false;
            if (isDocusign == true) {
                Date todayDate = Date.today();
                this.signDay = String.valueOf(todayDate.day()).leftPad(2, '0');
                this.signMonth = String.valueOf(todayDate.month()).leftPad(2, '0');
                this.signYear = String.valueOf(todayDate.year());
            }
        }
    }
    
    public class RVN_FormWrapper {
        public String paid2025To2026TaxYears;
        public String nino;
        public String fullName;
        public String dob;
        public String phoneNumber;
        public String currAddress;
        public String declarationFullName;
        public String bestTimeToCall;
        public String isThisAddressWhereWeCanSendYou;
        public String willYouBeLiving2026To2027Year;
        public String willYourEmplBePayingNI;
        public String payYourVoluntaryClass3Contributions;
        public String annualPaymentDetailsSentToSomeoneElse;
        public String reappNameTop;
        public String reappNameBottom;
        
        public RVN_FormWrapper(Reapply__c currReapply) {
            this.paid2025To2026TaxYears = currReapply.NINO_contributions_in_tax_years__c != null ? 'Yes' : 'No';
            this.reappNameTop = currReapply.Name;
            this.reappNameBottom = currReapply.Name;
            this.nino = currReapply.NINO__c;
            this.fullName = currReapply.Salutation__c + ' ' + currReapply.First_Name__c + ' ' + currReapply.Second_Name__c;
            if (currReapply.Date_of_birth__c != null) {
                Datetime dt = Datetime.newInstance(currReapply.Date_of_birth__c.year(), currReapply.Date_of_birth__c.month(), currReapply.Date_of_birth__c.day());
                this.dob = dt.format('dd/MM/yyyy');
            }
            this.phoneNumber = currReapply.Phone__c;
            String addressAbroad = currReapply.Address_abroad__Street__s;
            if (currReapply.Address_abroad__City__s != null) addressAbroad += ', ' + currReapply.Address_abroad__City__s;
            if (currReapply.Address_abroad__StateCode__s != null) addressAbroad += ', ' + currReapply.Address_abroad__StateCode__s;
            if (currReapply.Address_abroad__PostalCode__s != null) addressAbroad += ', ' + currReapply.Address_abroad__PostalCode__s;
            if (currReapply.Address_abroad__CountryCode__s != null) addressAbroad += ', ' + currReapply.Address_abroad__CountryCode__s;
            this.currAddress = addressAbroad;
            this.declarationFullName = currReapply.Salutation__c + ' ' + currReapply.First_Name__c + ' ' + currReapply.Second_Name__c;
            this.bestTimeToCall = currReapply.Best_time_to_call__c;
            this.isThisAddressWhereWeCanSendYou = currReapply.Is_this_the_address_where_we_can_send_yo__c == true ? 'Yes' : 'No';
            this.willYouBeLiving2026To2027Year = currReapply.Abroad_for_the_full_2026_2027_taxYear__c == true ? 'Yes' : 'No';
            this.willYourEmplBePayingNI = currReapply.employer_be_paying_your_NI_contr_abroad__c == true ? 'Yes' : 'No';
            this.payYourVoluntaryClass3Contributions = currReapply.Wish_to_pay_by__c;
            this.annualPaymentDetailsSentToSomeoneElse = currReapply.annual_payment_details_sent_to_someone_e__c == true ? 'Yes' : 'No';
        }
    }
}