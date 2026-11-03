public class RE_DataHelper {
    private final static String REAPPLY_PRODUCT = 'Reapply';
    // private final static List<String> AGENT_RECEPIENTS = new List<String> {
    //     'mihail.klimovich@outlook.com',
    //     'mishaklimovich87@gmail.com'
    // };
    private final static String PK_REGISTRATION_TEMPLATE_NAME = 'Pension Keeper Registration Data Information';
    private final static String PK_REGISTRATION_ORG_WIDE = 'keeper@xtrapension.com';
    public final static Map<String, String> CURRENCY_TO_TEMPLATE = new Map<String, String>{
        'CAD' => 'PK_Reapply_Can',
        'USD' => 'PK_Reapply_ROW',
        'EUR' => 'PK_Reapply_IrlEU',
        'NZD' => 'PK_Reapply_NZ',
        'ZAR' => 'PK_Reapply_SA',
        'AUD' => 'PK_Reapply_Aus'
    };

    public final static Map<String, String> VALID_FILE_NAME = new Map<String, String>{
        'PK_Reapply_Can' => 'Reapply-Can',
        'PK_Reapply_ROW' => 'Reapply-ROW',
        'PK_Reapply_IrlEU' => 'Reapply-IrlEU',
        'PK_Reapply_NZ' => 'Reapply-NZ',
        'PK_Reapply_SA' => 'Reapply-SA',
        'PK_Reapply_Aus' => 'Reapply-Aus'
    };

    private final static List<String> AGENT_RECEPIENTS = new List<String> {
        'fernando@xtrapension.com',
        'jr@xtrapension.com'
    };
    private static final Map<String, String> STATE_CODES {
        get {
            if (STATE_CODES == null) {
                STATE_CODES = new Map<String, String>();
                List<Schema.PicklistEntry> values = Reapply__c.Address_abroad__StateCode__s
                    .getDescribe()
                    .getPickListValues();
                for (Schema.PicklistEntry v : values) {
                    STATE_CODES.put(v.getValue(), v.getLabel());
                }
            }
            return STATE_CODES;
        }
        private set;
    }
    
    private static final OrgWideEmailAddress DEFAULT_ORG_WIDE_EMAIL_ADDRESS {
        get {
            if (DEFAULT_ORG_WIDE_EMAIL_ADDRESS == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    DEFAULT_ORG_WIDE_EMAIL_ADDRESS = orgWideEmailAddresses[0];
                }
            }
            return DEFAULT_ORG_WIDE_EMAIL_ADDRESS;
        }
        private set;
    }

    public static Map<String, Object> findReapply(RE_RequestWrapper.ReapplyDataWrapper reapplyData) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (reapplyData.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            Reapply__c reapply = RE_PortalUtils.getFindReapplyData(reapplyData.recordId);
            if (reapply == null) {
                result.put('status', 'error');
                result.put('message', 'Reapply record not found');
                return result;
            }
            
            RE_ResponseWrapper.ApplicationDataWrapper appDataWrapper = new RE_ResponseWrapper.ApplicationDataWrapper(reapply);
            
            if (reapply.Application__c != null) {
                List<Application__History> appHistories = RE_PortalUtils.getApplicationHistory(reapply.Application__c);
                // if (appHistories.size() > 0 && reapply.Submit_Form__c == false) {
                //     Application__History firstHistory = appHistories[0];
                //     Application__History lastHistory = appHistories[appHistories.size() - 1];
                //     appDataWrapper.ukYears = String.valueOf(firstHistory.NewValue);
                //     appDataWrapper.payNationalInsuranceYears = String.valueOf(lastHistory.NewValue);
                // }
                List<Employer__c> employers = [
                    SELECT Type_Of_UK_Employment__c, Application__r.Salutation__c
                    FROM Employer__c
                    WHERE Application__c = :reapply.Application__c
                    AND Type__c = 'UK Work' 
                    LIMIT 1
                ];
                if (employers.size() > 0 ) {
                    Employer__c employer = employers[0];
                    if (employer.Type_Of_UK_Employment__c == 'Unemployed' ||
                    employer.Type_Of_UK_Employment__c == 'Not employed') {
                        appDataWrapper.isShowJSA = true;
                    }
                    if ((employer.Application__r.Salutation__c == 'Mrs' ||
                        employer.Application__r.Salutation__c == 'Ms' ||
                        employer.Application__r.Salutation__c == 'Miss' ||
                        employer.Application__r.Salutation__c == 'Sr') &&
                        (employer.Type_Of_UK_Employment__c == 'Unemployed' ||
                    employer.Type_Of_UK_Employment__c == 'Not employed')) {
                        appDataWrapper.isShowChildBenefit = true;
                    }
                }
            }
            if (reapply.Reapply_Payments__r.size() > 0) {
                appDataWrapper.isPaymentSubmit = true;
            }
            
            result.put('status', 'success');
            result.put('reapply', appDataWrapper);
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + ' - ' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getReapplyQuestion(RE_RequestWrapper.ReapplyDataWrapper reapplyData) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (reapplyData.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            Reapply__c reapply = RE_PortalUtils.getFindReapplyData(reapplyData.recordId);
            if (reapply == null) {
                result.put('status', 'error');
                result.put('message', 'Reapply record not found');
                return result;
            }
            
            RE_ResponseWrapper.ApplicationDataWrapper appDataWrapper = new RE_ResponseWrapper.ApplicationDataWrapper(reapply);
            
            if (reapply.Application__c != null) {
                List<Application__History> appHistories = RE_PortalUtils.getApplicationHistory(reapply.Application__c);
                    appDataWrapper.isShowJSA = true;
                    appDataWrapper.isShowChildBenefit = true;
            }
            result.put('status', 'success');
            result.put('reapply', appDataWrapper);
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + ' - ' + e.getMessage());
        }
        return result;
    }

    
    public static Map<String, Object> updateReapply(RE_RequestWrapper.UpdateReapplyDataWrapper reapplyData) {
        System.debug('reapplyData: ' + JSON.serialize(reapplyData));
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (reapplyData.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            List<Reapply__c> reapplies = [
                SELECT Id
                FROM Reapply__c
                WHERE Id = :reapplyData.recordId
                LIMIT 1
            ];
            if (reapplies.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Reapply record not found');
                return result;
            }
            Reapply__c updatedReapply = new Reapply__c(
                Id = reapplyData.recordId,
                //First_Name__c = reapplyData.firstName,
                //Second_Name__c = reapplyData.secondName,
                // Live_in_UK__c = reapplyData.ukYears != null ? Decimal.valueOf(reapplyData.ukYears) : null,
                // NINO_contribution_pay__c = reapplyData.payNationalInsuranceYears != null ?
                //                                 Decimal.valueOf(reapplyData.payNationalInsuranceYears) :
                //                                 null,
                Where_you_receiving_JSA_before_left_UK__c = reapplyData.receivedJobSeekersAllowance != null ? 
                                                                Boolean.valueOf(reapplyData.receivedJobSeekersAllowance) :
                                                                false,
                Last_received_JSA_date__c = reapplyData.receiveJSALastDate != null ?
                                                Date.valueOf(reapplyData.receiveJSALastDate) :
                                                null,
                Where_you_receiving_Child_Benefit__c = reapplyData.receivedChildBenefit != null ?
                                                            Boolean.valueOf(reapplyData.receivedChildBenefit) :
                                                            false,
                Last_received_Child_Benefit_date__c = reapplyData.receiveChildBenefitLastDate != null ?
                                                        Date.valueOf(reapplyData.receiveChildBenefitLastDate) :
                                                        null,
                Submit_Form__c = true
            );
            
            List<String> selectedYears = new List<String>();
            if (reapplyData.isApr2024 == true) {
                selectedYears.add('2024 to 2025');
            }
            if (reapplyData.isApr2025 == true) {
                selectedYears.add('2025 to 2026');
            }
            if (!selectedYears.isEmpty()) {
                updatedReapply.NINO_contributions_in_tax_years__c = String.join(selectedYears, ';');
            } else {
                updatedReapply.NINO_contributions_in_tax_years__c = null;
            }
            
            update updatedReapply;
            result.put('status', 'success');
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> submitReapplyQuestions(RE_RequestWrapper.UpdateReapplyDataWrapper reapplyData) {
        System.debug('reapplyData: ' + JSON.serialize(reapplyData));
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (reapplyData.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            List<Reapply__c> reapplies = [
                SELECT Id
                FROM Reapply__c
                WHERE Id = :reapplyData.recordId
                LIMIT 1
            ];
            if (reapplies.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Reapply record not found');
                return result;
            }
            Reapply__c updatedReapply = new Reapply__c(
                Id = reapplyData.recordId,
                //First_Name__c = reapplyData.firstName,
                //Second_Name__c = reapplyData.secondName,
                Live_in_UK__c = reapplyData.ukYears != null ? Decimal.valueOf(reapplyData.ukYears) : null,
                NINO_contribution_pay__c = reapplyData.payNationalInsuranceYears != null ?
                                                Decimal.valueOf(reapplyData.payNationalInsuranceYears) :
                                                null,
                Where_you_receiving_JSA_before_left_UK__c = reapplyData.receivedJobSeekersAllowance != null ? 
                                                                Boolean.valueOf(reapplyData.receivedJobSeekersAllowance) :
                                                                false,
                Last_received_JSA_date__c = reapplyData.receiveJSALastDate != null ?
                                                Date.valueOf(reapplyData.receiveJSALastDate) :
                                                null,
                Where_you_receiving_Child_Benefit__c = reapplyData.receivedChildBenefit != null ?
                                                            Boolean.valueOf(reapplyData.receivedChildBenefit) :
                                                            false,
                Last_received_Child_Benefit_date__c = reapplyData.receiveChildBenefitLastDate != null ?
                                                        Date.valueOf(reapplyData.receiveChildBenefitLastDate) :
                                                        null,
                Submit_Form__c = true,
                Status__c = 'Form Completed'
            );
            
            List<String> selectedYears = new List<String>();
            if (reapplyData.isApr2024 == true) {
                selectedYears.add('2024 to 2025');
            }
            if (reapplyData.isApr2025 == true) {
                selectedYears.add('2025 to 2026');
            }
            if (!selectedYears.isEmpty()) {
                updatedReapply.NINO_contributions_in_tax_years__c = String.join(selectedYears, ';');
            } else {
                updatedReapply.NINO_contributions_in_tax_years__c = null;
            }
            
            update updatedReapply;
            result.put('status', 'success');
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getMessage());
        }
        return result;
    }

    
    public static Map<String, Object> getPaymentData(RE_RequestWrapper.ReapplyDataWrapper repplyWrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (repplyWrapper.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            List<Reapply__c> reapplies = [
                SELECT
                    Application__c,
                    Name,
                    First_Name__c,
                    Second_Name__c,
                    Email__c,
                    Former_Name__c, 
                    Date_of_birth__c,
                    NINO__c, 
                    Address_abroad__City__s, 
                    Address_abroad__CountryCode__s,
                    toLabel(Address_abroad__CountryCode__s) CountryCode, 
                    Address_abroad__PostalCode__s, 
                    Address_abroad__StateCode__s, 
                    Address_abroad__Street__s, 
                    Phone__c, 
                    Application__r.PK_Portal_User_Active__c,
                    Stripe_Customer_Id__c, 
                    Payment_Method_Id__c, 
                    CurrencyIsoCode, 
                    Application__r.Status__c
                FROM Reapply__c
                WHERE Id = :repplyWrapper.recordId
                LIMIT 1
            ];
            if (reapplies.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Reapply record not found');
                return result;
            }
            Reapply__c reapply = reapplies[0];
            RE_ResponseWrapper.CurrentApplicationDataWrapper appDataWrapper = new RE_ResponseWrapper.CurrentApplicationDataWrapper(reapply);
            result.put('paymentData', appDataWrapper);
            result.put('status', 'success');
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() +' - ' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> openEditPage(RE_RequestWrapper.MakeChangeDataWrapper repplyWrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (repplyWrapper.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            update new Reapply__c (
                Id = repplyWrapper.recordId,
                Submit_Form__c = false
            );
            result.put('status', 'success');
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() +' - ' + e.getMessage());
        }
        return result;
    }
    
    public static Map<String, Object> savePaymentData(RE_RequestWrapper.PaymentDataWrapper repplyWrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (repplyWrapper.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Record ID is null');
                return result;
            }
            System.debug('repplyWrapper ===== ' + repplyWrapper);
            List<Sobject> reapplyData = new List<Sobject>();
            reapplyData.add(
                new Reapply__c(
                    Id = repplyWrapper?.recordId,
                    //Email__c = repplyWrapper?.email,
                    //First_Name__c = repplyWrapper?.firstName,
                    //Second_Name__c = repplyWrapper?.lastName,
                    //Phone__c = repplyWrapper?.phone,
                    // Address_abroad__City__s = repplyWrapper?.address?.city,
                    // Address_abroad__CountryCode__s = repplyWrapper?.address?.country,
                    // Address_abroad__PostalCode__s = repplyWrapper?.address?.postalCode,
                    // Address_abroad__StateCode__s = STATE_CODES.containsKey(repplyWrapper?.address?.state) ?
                    //                                 repplyWrapper?.address?.state :
                    //                                 repplyWrapper?.foundApplication?.currentAddress?.state,
                    // Address_abroad__Street__s = repplyWrapper?.address?.street,
                    Status__c = 'Form Completed',
                    CurrencyIsoCode = repplyWrapper?.currencyCode,
                    Payment_Method_Id__c = repplyWrapper?.paymentMethod,
                    Stripe_Customer_Id__c = repplyWrapper?.customer,
                    Form_Complete_Date__c = Date.today(),
                    Agent__c = repplyWrapper?.agent
                )
            );
            List<Product2> products = [SELECT Id FROM Product2 WHERE Name = 'Reapply' LIMIT 1];
            String cardInfo = getCardData(repplyWrapper.paymentMethod);
            reapplyData.add(
                new Reapply_Payment__c(
                    Source__c = repplyWrapper.latest_charge,
                    Amount__c = repplyWrapper.amount != null ? repplyWrapper.amount / 100 : 0,
                    Payment_Method_Id__c = repplyWrapper.paymentMethod,
                    Customer_Id__c = repplyWrapper.customer,
                    CurrencyIsoCode = repplyWrapper.currencyCode,
                    Product__c = products.size() > 0 ? products[0].Id : null,
                    Status__c = 'Paid',
                    Reapply__c = repplyWrapper.recordId,
                    Payment_Date__c = Date.today(),
                    Card_Data__c = cardInfo
                )
            );
            if(repplyWrapper.stageOption == 'Bundle' &&
               repplyWrapper.foundApplication.applicationId != null && 
               repplyWrapper.foundApplication.isPensionKeeperCustomer == false) {
                Date pensionAge = repplyWrapper.foundApplication.dob != null ? 
                                    PK_PortalUtils.calculatePensionDate(Date.valueOf(repplyWrapper.foundApplication.dob)) :
                                    null;
                String pensionAgeGap = repplyWrapper.foundApplication.dob != null && pensionAge != null ? 
                                            PK_PortalUtils.getYearsMonthsDaysBetween(Date.valueOf(repplyWrapper.foundApplication.dob), pensionAge) :
                                            null;
                List<Application__c> apps = [
                    SELECT
                        National_Insurance_Number__c,
                        Second_Name__c
                    FROM Application__c
                    WHERE Id = :repplyWrapper.foundApplication.applicationId
                ];
                String pkPassword = apps.size() > 0 ? PK_PortalAuthHelper.generatePassword(apps[0]) : null;
                reapplyData.add(
                    new Application__c(
                        Id = repplyWrapper.foundApplication.applicationId,
                        Status__c = 'Pension Keeper',
                        PK_Portal_User_Active__c = true,
                        PK_Portal_User_PW__c = pkPassword,
                        PK_Registration_Date__c = Date.today(),
                        PK_Date_Pension_Age_Reached__c = pensionAge,
                        Pension_Age__c = pensionAgeGap,
                        PK_Auto_Renewal__c = false
                    )
                );
                ApplicationTriggerHandler.sendPKRegistrationEmail(repplyWrapper.foundApplication.applicationId);
            }

            if (reapplyData.size() > 0) {
                upsert reapplyData;
            }
            RE_GenerateReapplyForm.getReapplyForm(repplyWrapper.recordId);
            RE_GenerateRVNForm.getRVNForm(repplyWrapper.recordId);
            sendAgentNotification(repplyWrapper);
            result.put('status', 'success');
            result.put('cardData', cardInfo);
            result.put('paymentMethod', repplyWrapper.paymentMethod);
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() +' - ' + e.getMessage());
        }
        return result;
    }

    private static String getCardData(String paymentMethod) {
        if (paymentMethod == null) {
            return null;
        }
        String cardInfo;
        StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
            'payment_methods/' + paymentMethod,
            'GET',
            null
        );
        if (requestPaymentMethodResult.isError != true) {
            Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
            RE_ResponseWrapper.CardDataWrapper cardData = new RE_ResponseWrapper.CardDataWrapper((Map<String,Object>) methodData.get('card'));
            cardInfo = cardData.cardBrand + ' - ' + cardData.last4Digits;
        }
        return cardInfo;
    }

    private static void sendAgentNotification(RE_RequestWrapper.PaymentDataWrapper repplyWrapper) {
        String htmlBody =
            '<div>Client email address ' + repplyWrapper?.email + '</div>' +
            '<div>Tel  ' + repplyWrapper?.phone +'</div>';
        String currencyData = repplyWrapper?.currencyCode == 'EUR' ?
                                '€ ' : repplyWrapper?.currencyCode == 'ZAR' ?
                                    repplyWrapper?.currencyCode + ' ' :
                                    repplyWrapper?.currencyCode + '$ ';    
        String subject =  'Reapply - ' +
                          repplyWrapper?.foundApplication?.currentAddress?.country + 
                          ' - ' + repplyWrapper?.foundApplication?.applicationNumber +
                          ' - ' + repplyWrapper?.firstName + ' ' + repplyWrapper?.lastName +
                          ' - ' + currencyData + repplyWrapper?.amount/100 + ' sale';
        
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(repplyWrapper?.recordId);
        message.setSubject(subject);
        message.setHtmlBody(htmlBody);
        message.setOrgWideEmailAddressId(DEFAULT_ORG_WIDE_EMAIL_ADDRESS != null ? DEFAULT_ORG_WIDE_EMAIL_ADDRESS.Id : null);
        message.setToAddresses(AGENT_RECEPIENTS);
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }


    public static Map<String, Object> createReapplyApplicationRecords(RE_RequestWrapper.NewReapplyDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            String cardInfo = getCardData(wrapper.paymentMethod);
            Account account = new Account();
            String phoneDuplicateFinder = '%' + wrapper.phone.substring(1, wrapper.phone.length() - 4) + '%';
            String personContactId = '';
            account = new Account(
                LastName                = wrapper?.name,
                PersonEmail             = wrapper?.email,
                PersonMobilePhone       = wrapper?.phone,
                PersonMailingCity       = wrapper.address?.city,
                PersonMailingCountry    = wrapper.address?.country,
                PersonMailingState      = wrapper.address?.state,
                PersonMailingPostalCode = wrapper.address?.postalCode,
                PersonMailingStreet     = wrapper.address?.street,
                Mailing_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.address?.country),
                Mailing_State__c        = wrapper?.address?.country == 'IE' ?
                                                wrapper?.address?.state :
                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                    wrapper?.address?.country,
                                                    wrapper?.address?.state)
            );
            insert account;

            List<Contact> currentContact = [
                SELECT
                    Id,
                    AccountId
                FROM Contact
                WHERE AccountId = :account.Id
                LIMIT 1
            ];
            if (!currentContact.isEmpty()) {
                personContactId = currentContact[0].Id;
            }
            Application__c application = new Application__c(
                First_Name__c                         = wrapper?.firstName,
                Second_Name__c                        = wrapper?.lastName,
                Expiry_Date__c                        = Datetime.now().addYears(1),
                Payment_Method__c                     = wrapper?.paymentMethod,
                Stripe_Customer_Id__c                 = wrapper?.customer,
                Status__c                             = 'Pension Keeper',
                Last_Payment_Date__c                  = Date.today(),
                Stripe_Transaction_Id__c              = wrapper?.id,
                Contact__c                            = personContactId,
                Amount__c                             = wrapper?.amount != null ?  wrapper?.amount / 100 : 0,
                Related_Contact_Phone__c              = account.PersonMobilePhone,
                Email__c                              = account.PersonEmail,
                Current_Address_Abroad__City__s       = wrapper?.address?.city,
                Current_Address_Abroad__Street__s     = wrapper?.address?.street,
                Current_Address_Abroad__StateCode__s  = PK_PortalUtils.getContryStateName( wrapper?.address?.country,  wrapper?.address?.state),
                CurrencyIsoCode                       = wrapper?.currencyCode,
                Current_Address_Abroad__CountryCode__s= wrapper?.address?.country,
                Current_Address_Abroad__PostalCode__s = wrapper?.address?.postalCode,
                Current_Address_Abroad_Country__c     = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.address?.country),
                Live_In_The_EU__c                     = wrapper?.currencyCode == 'EUR' ? true : false,
                Pension_Keeper_Changed_Date__c        = Date.today(),
                How_Did_You_Hear_About_Us__c          = wrapper?.howDidYouHearAboutUs,
                PK_Sale_Agent__c                      = wrapper?.agent,
                Package_Name__c                       = 'Standard',
                Current_Address_Abroad_State__c       = wrapper?.address?.country == 'IE' ?
                                                                wrapper.address?.state :
                                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                    wrapper?.address?.country,
                                                                    wrapper.address?.state
                                                                ),
                PK_Auto_Renewal__c                    = true,
                PK_Registration_Date__c               = Date.today()
            );
            insert application;
            SuccessDocsController.generateDocs(application.Id);
            //result.putAll(PK_PortalApplicationHelper.createPayment(application.Id, wrapper?.latest_charge, account.Id, wrapper?.id));
            Id reapplyId = RE_ApplicationDataAction.createRelatedReapply(application.Id, false);
            List<Product2> products = [SELECT Id FROM Product2 WHERE Name = 'Reapply' LIMIT 1];
            
            insert new Reapply_Payment__c(
                    Source__c = wrapper.latest_charge,
                    Amount__c = wrapper.amount != null ? wrapper.amount / 100 : 0,
                    Payment_Method_Id__c = wrapper.paymentMethod,
                    Customer_Id__c = wrapper.customer,
                    CurrencyIsoCode = wrapper.currencyCode,
                    Product__c = products.size() > 0 ? products[0].Id : null,
                    Status__c = 'Paid',
                    Reapply__c = reapplyId,
                    Payment_Date__c = Date.today(),
                    Card_Data__c = cardInfo
                );
            sendReapplyRegistrationDataMessage(reapplyId);
            if (result.get('status') != 'error') {
                result.put('status', 'success');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getMessage());
        }
        return result;
    }

    @future
    private static void sendReapplyRegistrationDataMessage(Id reappId) {
        if (reappId == null) {
            return;
        }
        List<Reapply__c> scope = [
            SELECT 
                Id,
                Pension_Keeper_Email_Send_Date__c,
                Status__c,
                Email__c,
                CurrencyIsoCode,
                Application__r.Contact__c
            FROM Reapply__c
            WHERE Id = :reappId
        ];
        String orgWideEmailAddress = 'clients@xtrapension.com';
        String currStr = 'USD';

        if (String.isNotBlank(CURRENCY_TO_TEMPLATE.get(scope[0].CurrencyIsoCode))) {
            currStr = CURRENCY_TO_TEMPLATE.get(scope[0].CurrencyIsoCode);
        }

        Blob pdfBody;
        List<StaticResource> pdfStatics = [
            SELECT Body, Name
            FROM StaticResource
            WHERE Name = :currStr
            LIMIT 1
        ];

        if (pdfStatics.isEmpty()) {
            return;
        }

        pdfBody = pdfStatics[0].Body;

        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :orgWideEmailAddress
        ];

        List<EmailTemplate> welcomeEmailTemplate = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :'REAPPLY_Pension_Keeper_PK_Reapply_Clients'
        ];

        for (Reapply__c app : scope) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(app.Application__r.Contact__c);
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);

            if (welcomeEmailTemplate.size() > 0) {
                message.setTemplateId(welcomeEmailTemplate[0].Id);
            }

            message.setToAddresses(new String[] { app.Email__c });
            message.setWhatId(app.Id);

            if (owea.size() > 0) {
                message.setOrgWideEmailAddressId(owea.get(0).Id);
            }

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(VALID_FILE_NAME.get(pdfStatics[0].Name) + '.pdf');
            attachment.setContentType('application/pdf');
            attachment.setBody(pdfBody);

            message.setFileAttachments(
                new Messaging.EmailFileAttachment[] {
                    attachment
                }
            );

            if (!Test.isRunningTest()) {
                Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>{ message };
                Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);

                if (results[0].isSuccess()) {
                    EmailMessage emailMessage = findEmailMessage(
                        app.Id,
                        app.Email__c
                    );

                    if (emailMessage != null) {
                        createFileAndLinkToEmail(
                            emailMessage.Id,
                            VALID_FILE_NAME.get(pdfStatics[0].Name) + '.pdf',
                            pdfBody
                        );
                    }
                }
            }
            app.Pension_Keeper_Email_Send_Date__c = Date.today();
        }
        update scope;
    }

    @TestVisible
    private static EmailMessage findEmailMessage(
        Id reapplyId,
        String emailAddress
    ) {
        List<EmailMessage> emails = [
            SELECT
                Id,
                Subject,
                ToAddress,
                RelatedToId,
                CreatedDate
            FROM EmailMessage
            WHERE RelatedToId = :reapplyId
            AND ToAddress = :emailAddress
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return emails.isEmpty() ? null : emails[0];
    }

    @TestVisible
    private static void createFileAndLinkToEmail(
        Id emailMessageId,
        String fileName,
        Blob fileBody
    ) {
        ContentVersion version = new ContentVersion(
            Title = fileName.substringBeforeLast('.'),
            PathOnClient = fileName,
            VersionData = fileBody
        );

        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = version.ContentDocumentId,
            LinkedEntityId = emailMessageId,
            ShareType = 'V'
        );
    }
}