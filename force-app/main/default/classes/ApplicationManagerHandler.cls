public with sharing class ApplicationManagerHandler {
	private static final Map<String, String> STATE_CODES {
        get {
            if (STATE_CODES == null) {
				STATE_CODES = new Map<String, String>();
				List<Schema.PicklistEntry> values = Application__c.Current_Address_Abroad__StateCode__s
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

    private static final String XTRAPENSION_LINK = XtraPension_Data__c.getInstance().Form_Link__c;
    private static final String XTRAPENSION_PRODUCT_NAME = 'XtraPension Application';
    private static final List<String> ORDER_OF_PRODUCT_NAME = new List<String> {
        'Deposit', 'Application', 'Success'
    };
    private static final Map<String, String> COUNTRY_CODE_BY_NAME = CountryCodeHelper.getCountryCodeByCountryName();
    private static final String MISSING_INFO_TEMPLATE_NAME = 'Missing Info';
    private static final String MISSING_INFO_OWD_NAME = 'clients@xtrapension.com';

    public static Map<String, Object> createApplication(ApplicationManager.RequestDataWrapper applicationData) {
        if (applicationData != null) {
            Map<String, Object> result = new Map<String, Object>();
            try {
                Account account = new Account();
                String phoneDuplicateFinder = '%' + applicationData.phone.substring(1, applicationData.phone.length() - 4) + '%';
                String personContactId = '';
                account = new Account(
                    //add logic check if only 1 word
                    //add line 2 from form
                    LastName                = applicationData?.name,
                    PersonEmail             = applicationData?.email,
                    PersonMobilePhone       = applicationData?.phone,
                    PersonMailingCity       = applicationData.address?.city,
                    PersonMailingCountry    = applicationData.address?.country,
                    PersonMailingState      = applicationData.address?.state,
                    PersonMailingPostalCode = applicationData.address?.postal_code,
                    PersonMailingStreet     = applicationData.address?.line1,
                    Mailing_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.address?.country),
                    Mailing_State__c        = applicationData?.address?.country == 'IE' ?
                                                applicationData?.address?.state :
                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                    applicationData?.address?.country,
                                                    applicationData?.address?.state),
                    Mailing_Line_2__c       = applicationData.address?.line2
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
                List<Agent__c> mainAgent = [
                    SELECT
                        Id,
                        Name
                    FROM Agent__c
                ];
                Id agentId = mainAgent.size() == 0 ? null : mainAgent[0].Id;
                String stateName = '';
                if (applicationData?.address?.country == 'IE' &&
                    applicationData.address?.state.contains('County')) {
                    stateName = CountryCodeHelper.getStateCodeByStateName(
                        applicationData?.address?.country,
                        applicationData.address?.state.remove('County').trim());
                } else if(applicationData?.address?.country == 'AE' ||
                          applicationData?.address?.country == 'MY' ||
                          applicationData?.address?.country == 'ID') {
                    stateName = CountryCodeHelper.getStateCodeByStateName(
                        applicationData?.address?.country,
                        applicationData.address?.state);
                } else stateName = applicationData.address?.state;
                String currentStateValue = STATE_CODES.get(stateName);
				if (String.isBlank(currentStateValue) && String.isNotBlank(stateName)) {
					stateName = '';
                    Application_Form_Error__c errorData = new Application_Form_Error__c();
                    errorData.Error_Body__c = applicationData?.name + ' - ' + applicationData?.email + '\n' + 'State Code doesn\'t exist on the org. Please check it and add';
                    errorData.Error_Date__c = Date.today();
                    insert errorData;
				}
                String streetData = applicationData?.address?.line1;
                if (String.isNotBlank(applicationData?.address?.line2)) {
                    streetData += ', ' + applicationData?.address?.line2;
                }
                Application__c application = new Application__c(
                    First_Name__c                         = applicationData?.firstName,
                    Second_Name__c                        = applicationData?.lastName,
                    Expiry_Date__c                        = Datetime.now().addYears(1),
                    Package_Name__c                       = applicationData?.packageName,
                    Payment_Method__c                     = applicationData?.paymentMethod,
                    Stripe_Customer_Id__c                 = applicationData?.customer,
                    Status__c                             = 'Form In Progress',
                    Is_Payment_Completed__c               = true,
                    Last_Payment_Date__c                  = Date.today(),
                    Step__c                               = 'Personal Details',
                    Stripe_Transaction_Id__c              = applicationData?.id,
                    Contact__c                            = personContactId,
                    Personal_Details_Form_Link__c         = XTRAPENSION_LINK + applicationData?.id,
                    Amount__c                             = applicationData?.amount != null ?  applicationData?.amount / 100 : 0,
                    Last_UK_Home_Address__CountryCode__s  = 'GB',
                    Related_Contact_Phone__c              = account.PersonMobilePhone,
                    Email__c                              = account.PersonEmail,
                    Live_In_The_EU__c                     = applicationData?.currencyCode == 'EUR' ? true : false,
                    Agent__c                              = mainAgent.size() == 0 ? null : mainAgent[0].Id,
                    Pay_Voluntary_Contribution_At__c      = 'Class 2',
                    How_Did_You_Hear_About_Us__c          = applicationData?.howDidYouHearAboutUs,
                    Freeform_RichText_Line1__c            = XtraPensionConstants.FREEFORM_CLASS2_FIELD_DEFAULT_VALUE,
                    Freeform_RichText_Line5__c            = XtraPensionConstants.FREEFORM_FIELD_DEFAULT_VALUE,
                    Agent_Making_Sale__c                  = applicationData?.agent == null ? 'None' : applicationData?.agent,
                    Current_Address_Abroad__City__s       = applicationData?.address?.city,
                    Current_Address_Abroad__Street__s     = streetData,
                    Current_Address_Abroad__StateCode__s  = stateName,
                    Current_Address_Abroad__CountryCode__s= applicationData?.address?.country,
                    Current_Address_Abroad__PostalCode__s = applicationData?.address?.postal_code,
                    CurrencyIsoCode                       = applicationData?.currencyCode,
                    Current_Address_Abroad_Country__c     = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.address?.country),
                    Current_Address_Abroad_State__c       = applicationData?.address?.country == 'IE' ?
                                                                applicationData.address?.state :
                                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                    applicationData?.address?.country,
                                                                    applicationData.address?.state
                                                                )
                );
                insert application;
                List<PriceBookEntry> priceBookEntries = new List<PriceBookEntry>();
                if (!Test.isRunningTest()) {
                    priceBookEntries = [
                        SELECT
                            Id,
                            Product2Id,
                            Product2.Name,
                            Pricebook2Id,
                            CurrencyIsoCode,
                            Pricebook2.IsStandard,
                            UnitPrice
                        FROM PriceBookEntry
                        WHERE Pricebook2.IsStandard = true AND
                              CurrencyIsoCode = :application?.CurrencyIsoCode
                    ];
                } else {
                    priceBookEntries = [
                        SELECT
                            Id,
                            Product2Id,
                            Product2.Name,
                            Pricebook2Id,
                            Pricebook2.IsStandard,
                            UnitPrice
                        FROM PriceBookEntry
                    ];
                }
                if (priceBookEntries.isEmpty()) {
                    result.put('status', 'Error');
                    result.put('message', 'PriceBookEntries are empty');
                    return result;
                }
                Map<String, PriceBookEntry> productNameByPricebookEntry = new Map<String, PriceBookEntry>();
                for (PriceBookEntry price : priceBookEntries) {
                    productNameByPricebookEntry.put(price.Product2.Name, price);
                }
                Order newOrder = new Order(
                    Status          = 'Draft',
                    EffectiveDate   = Date.today(),
                    Pricebook2Id    = priceBookEntries[0].Pricebook2Id,
                    AccountId       = account.Id,
                    Application__c  = application.Id,
                    CurrencyIsoCode = applicationData?.currencyCode
                );
                insert newOrder;
                List<Sobject> newSobjects = new List<Sobject>();
                for (String productName : ORDER_OF_PRODUCT_NAME) {
                    PriceBookEntry entry = productNameByPricebookEntry.get(productName);
                    newSobjects.add(
                        new OrderItem(
		                    Product2Id       = entry.Product2Id,
		                    OrderId          = newOrder.Id,
		                    PricebookEntryId = entry.Id,
		                    Quantity         = 1,
                            UnitPrice        = entry.UnitPrice
		                )
                    );
                    newSobjects.add(
                        new Payment__c (
                            Amount__c         = entry.UnitPrice,
                            Product__c        = entry.Product2Id,
                            Status__c         = entry.Product2.Name != 'Deposit' ? 'Draft' : 'Paid',
                            CurrencyIsoCode   = applicationData?.currencyCode,
                            Payment_Method__c = application.Payment_Method__c,
                            Customer_Id__c    = application.Stripe_Customer_Id__c,
                            Order__c          = newOrder.Id,
                            Application__c    = application.Id,
                            Payment_Date__c   = entry.Product2.Name == 'Deposit' ? Date.today() : null,
                            Payment_Intent__c = entry.Product2.Name == 'Deposit' ? applicationData?.id : null,
                            Source__c         = applicationData?.latest_charge
                        )
                    );
                    }
                    if (newSobjects != null) {
                        insert newSobjects;
                    }
                Map<String, Id> productNameById = new Map<String, Id>();
                result.put('status', 'Success');
            } catch (Exception e) {
                Application_Form_Error__c errorData = new Application_Form_Error__c();
                errorData.Error_Body__c = applicationData?.name + ' - ' + applicationData?.email + '\n' + e.getLineNumber() + '-' + e.getMessage();
                errorData.Error_Date__c = Date.today();
                insert errorData;
                result.put('status', 'Error');
                result.put('message', e.getLineNumber() + '-' + e.getMessage());
            }
            return result;
        }
        return new Map<String, Object>();
    }

    public static Map<String, Object> setApplicationPersonalDetails(ApplicationManager.ApplicationPersonalStepWrapper applicationData, String stripeId, Boolean isFullForm) {
        Map<String, Object> result = new Map<String, Object>();
        Datetime todayDateTime = Datetime.now();
        String queryLine = 'SELECT ' +
                                'Id, ' +
                                'Salutation__c, ' +
                                'First_Name__c, ' +
                                'Second_Name__c, ' +
                                'Date_Of_Birth__c, ' +
                                'National_Insurance_Number__c, ' +
                                'Work_Or_Pay_UK_National_Insurance__c, ' +
                                'Private_UK_Pension__c, ' +
                                'Approx_Value_Of_UK_Pension__c, ' +
                                'Previous_UK_Address_1__City__s, ' +
                                'Previous_UK_Address_1__CountryCode__s, ' +
                                'Previous_UK_Address_1__PostalCode__s, ' +
                                'Previous_UK_Address_1__StateCode__s, ' +
                                'Previous_UK_Address_1__Street__s, ' +
                                'Previous_UK_Address_Start_Date_1__c, ' +
                                'Previous_UK_Address_End_Date_1__c, ' +
                                'Previous_UK_Address_2__City__s, ' +
                                'Previous_UK_Address_2__CountryCode__s, ' +
                                'Previous_UK_Address_2__PostalCode__s, ' +
                                'Previous_UK_Address_2__StateCode__s, ' +
                                'Previous_UK_Address_2__Street__s, ' +
                                'Previous_UK_Address_Start_Date_2__c, ' +
                                'Previous_UK_Address_End_Date_2__c, ' +
                                'Previous_UK_Address_3__City__s, ' +
                                'Previous_UK_Address_3__CountryCode__s, ' +
                                'Previous_UK_Address_3__PostalCode__s, ' +
                                'Previous_UK_Address_3__StateCode__s, ' +
                                'Previous_UK_Address_3__Street__s, ' +
                                'Previous_UK_Address_Start_Date_3__c, ' +
                                'Previous_UK_Address_End_Date_3__c, ' +
                                'Current_Occupation__c, ' +
                                'Current_Address_Abroad__City__s, ' +
                                'Current_Address_Abroad__Street__s, ' +
                                'Current_Address_Abroad__StateCode__s, ' +
                                'Current_Address_Abroad__CountryCode__s, ' +
                                'Current_Address_Abroad__PostalCode__s, ' +
                                'Last_UK_Home_Address__City__s, ' +
                                'Last_UK_Home_Address__CountryCode__s, ' +
                                'Last_UK_Home_Address__Street__s, ' +
                                'Last_UK_Home_Address__StateCode__s, ' +
                                'Last_UK_Home_Address__PostalCode__s, ' +
                                'Step__c, ' +
                                'Is_Know_National_Insurance_Number__c, ' +
                                'Getting_UK_Pension_Now__c ' +
                            'FROM Application__c ' +
                            'WHERE Stripe_Transaction_Id__c = :stripeId' +
                                ' AND Expiry_Date__c > :todayDateTime' +
                            ' LIMIT 1 ';
        Application__c app = Database.query(queryLine);
        if (app == null) {
            result.put('status', 'Error');
            result.put('message',  'Don\'t found application');
        }
        try {
            app.Salutation__c                          = applicationData?.salutation;
            app.First_Name__c                          = applicationData?.firstName;
            app.Second_Name__c                         = applicationData?.secondName;
            app.Date_Of_Birth__c                       = applicationData?.dateOfBirth != null ? Date.valueOf(applicationData?.dateOfBirth) : null;
            app.National_Insurance_Number__c           = applicationData?.insuranceNumber?.replaceAll('(\\s+)', '');
            app.Work_Or_Pay_UK_National_Insurance__c   = applicationData?.workOrPayUKNationalInsurance;
            app.Private_UK_Pension__c                  = applicationData?.privateUKPension;
            app.Approx_Value_Of_UK_Pension__c          = applicationData?.approxValue;
            app.Current_Occupation__c                  = applicationData?.currentOccupation;
            app.Current_Address_Abroad__City__s        = applicationData?.currentAddressAbroad?.city;
            app.Current_Address_Abroad__Street__s      = applicationData?.currentAddressAbroad?.street;
            app.Current_Address_Abroad__StateCode__s   = applicationData?.currentAddressAbroad?.state;
            app.Current_Address_Abroad__CountryCode__s = applicationData?.currentAddressAbroad?.country;
            app.Current_Address_Abroad__PostalCode__s  = applicationData?.currentAddressAbroad?.postcode;
            app.Current_Address_Abroad_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.currentAddressAbroad?.country);
            app.Current_Address_Abroad_State__c        = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                            applicationData?.currentAddressAbroad?.country,
                                                            applicationData?.currentAddressAbroad?.state);
            app.Last_UK_Home_Address__City__s          = applicationData?.lastUKHomeAddress?.city;
            app.Last_UK_Home_Address__Street__s        = applicationData?.lastUKHomeAddress?.street;
            app.Last_UK_Home_Address__StateCode__s     = applicationData?.lastUKHomeAddress?.state;
            app.Last_UK_Home_Address__PostalCode__s    = applicationData?.lastUKHomeAddress?.postcode;
            app.Last_UK_Home_Address_Country__c        = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.lastUKHomeAddress?.country);
            app.Last_UK_Home_Address_State__c          = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                            applicationData?.lastUKHomeAddress?.country,
                                                            applicationData?.lastUKHomeAddress?.state);
            if (isFullForm == false) {
                app.Step__c                                = 'Relationship';
            }
            app.Getting_UK_Pension_Now__c              = applicationData?.currentlyGettingUKPension; 
            app.Is_Know_National_Insurance_Number__c   = applicationData?.insuranceNumber == null ? false : true;
            app.Previous_UK_Address_1__City__s         = applicationData?.lastUKHomeAddress?.city;
            app.Previous_UK_Address_1__CountryCode__s  = applicationData?.lastUKHomeAddress?.country;
            app.Previous_UK_Address_1__PostalCode__s   = applicationData?.lastUKHomeAddress?.postcode;
            app.Previous_UK_Address_1__StateCode__s    = applicationData?.lastUKHomeAddress?.state;
            app.Previous_UK_Address_1__Street__s       = applicationData?.lastUKHomeAddress?.street;
            app.Previous_UK_Address_Start_Date_1__c    = Date.valueOf(applicationData?.lastUKHomeAddress?.fromDate);
            app.Previous_UK_Address_End_Date_1__c      = Date.valueOf(applicationData?.lastUKHomeAddress?.toDate);
            app.Previous_UK_Address_2__City__s         = applicationData?.lastUKHomeAddress2?.city != null ? applicationData?.lastUKHomeAddress2?.city : null;
            app.Previous_UK_Address_2__CountryCode__s  = applicationData?.lastUKHomeAddress2?.country != null ? applicationData?.lastUKHomeAddress2?.country : null;
            app.Previous_UK_Address_2__PostalCode__s   = applicationData?.lastUKHomeAddress2?.postcode != null ? applicationData?.lastUKHomeAddress2?.postcode : null;
            app.Previous_UK_Address_2__StateCode__s    = applicationData?.lastUKHomeAddress2?.state != null ? applicationData?.lastUKHomeAddress2?.state : null;
            app.Previous_UK_Address_2__Street__s       = applicationData?.lastUKHomeAddress2?.street != null ? applicationData?.lastUKHomeAddress2?.street : null;
            app.Previous_UK_Address_Start_Date_2__c    = Date.valueOf(applicationData?.lastUKHomeAddress2?.fromDate);
            app.Previous_UK_Address_End_Date_2__c      = Date.valueOf(applicationData?.lastUKHomeAddress2?.toDate);
            app.Previous_UK_Address_3__City__s         = applicationData?.lastUKHomeAddress3?.city != null ? applicationData?.lastUKHomeAddress3?.city : null;
            app.Previous_UK_Address_3__CountryCode__s  = applicationData?.lastUKHomeAddress3?.country  != null ? applicationData?.lastUKHomeAddress3?.country : null;
            app.Previous_UK_Address_3__PostalCode__s   = applicationData?.lastUKHomeAddress3?.postcode  != null ? applicationData?.lastUKHomeAddress3?.postcode : null;
            app.Previous_UK_Address_3__StateCode__s    = applicationData?.lastUKHomeAddress3?.state != null ? applicationData?.lastUKHomeAddress3?.state : null;
            app.Previous_UK_Address_3__Street__s       = applicationData?.lastUKHomeAddress3?.street != null ? applicationData?.lastUKHomeAddress3?.street : null;
            app.Previous_UK_Address_Start_Date_3__c    = Date.valueOf(applicationData?.lastUKHomeAddress3?.fromDate);
            app.Previous_UK_Address_End_Date_3__c      = Date.valueOf(applicationData?.lastUKHomeAddress3?.toDate);
            app.Previous_UK_Address_1_Country__c       = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.lastUKHomeAddress?.country);
            app.Previous_UK_Address_2_Country__c       = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.lastUKHomeAddress2?.country);
            app.Previous_UK_Address_3_Country__c       = CountryCodeHelper.getCountryNameByIsoCode(applicationData?.lastUKHomeAddress3?.country);
            app.Previous_UK_Address1_State__c          = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                            applicationData?.lastUKHomeAddress?.country,
                                                            applicationData?.lastUKHomeAddress?.state);
            app.Previous_UK_Address2_State__c          = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                            applicationData?.lastUKHomeAddress2?.country,
                                                            applicationData?.lastUKHomeAddress2?.state);
            app.Previous_UK_Address3_State__c          = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                            applicationData?.lastUKHomeAddress3?.country,
                                                            applicationData?.lastUKHomeAddress3?.state);
            update app;
            result.put('status', 'Success');
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> setApplicationRelationshipDetails(ApplicationManager.RelationshipStepWrapper requestData, String stripeId, Boolean isFullForm) {
        Map<String, Object> result = new Map<String, Object>();
        Application__c app = [
            SELECT
                Did_You_Change_Name__c,
                Did_Client_Change_Name__c,
                Date_Of_Marriage_Or_Civil_Partnership__c,
                Are_You_Divorced__c,
                Full_Maiden_Previous_Name__c,
                Are_You_Single__c,
                Divorce_Date__c,
                Step__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        if (app == null) {
            result.put('error', 'Don\'t found application');
        }
        try {
            app.Are_You_Single__c   = requestData?.single;
            if (isFullForm == false) {
                app.Step__c             = 'UK Work';
            }
            if (requestData?.single == true && requestData?.divorcedOrwidowed) {
                app.Did_You_Change_Name__c                   = false;
                app.Did_Client_Change_Name__c                = 'No';
                app.Date_Of_Marriage_Or_Civil_Partnership__c = null;
                app.Full_Maiden_Previous_Name__c             = '';
                app.Are_You_Divorced__c                      = requestData?.divorcedOrwidowed;
                app.Divorce_Date__c                          = Date.valueOf(requestData?.exactDate);
            } else if (requestData?.single == true && !requestData?.divorcedOrwidowed) {
                app.Did_You_Change_Name__c                   = false;
                app.Did_Client_Change_Name__c                = 'No';
                app.Date_Of_Marriage_Or_Civil_Partnership__c = null;
                app.Full_Maiden_Previous_Name__c             = '';
                app.Are_You_Divorced__c                      = requestData?.divorcedOrwidowed;
                app.Divorce_Date__c                          = null;
            } else {
                app.Are_You_Divorced__c                      = false;
                app.Divorce_Date__c                          = null;
                app.Did_You_Change_Name__c                   = requestData?.changeYouName;
                app.Did_Client_Change_Name__c                = requestData?.changeYouName == true ? 'Yes' : 'No';
                app.Date_Of_Marriage_Or_Civil_Partnership__c = Date.valueOf(requestData?.dateOfMarriedOrPartnership);
                app.Full_Maiden_Previous_Name__c             = requestData?.fullMaindenOrPreviousName;
            }
            update app;
            result.put('status', 'Success');
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> setApplicationUkWorkDetails(ApplicationManager.UkWorkStepWrapper requestData, String stripeId, Boolean isFullForm) {
        Map<String, Object> result = new Map<String, Object>();
        Application__c app = [
            SELECT
                Id,
                Type_Of_Employment__c,
                Date_Of_Leaving_Last_UK__c,
                Years_Of_Work_In_The_UK__c,
                Is_Know_National_Insurance_Number__c,
                Step__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        List<Employer__c> relatedEmployers = [
            SELECT
                Application__r.Id,
                Type__c
            FROM Employer__c
            WHERE Application__r.Id = :app.Id
                AND Type__c = 'UK Work'
        ];
        try {
            delete relatedEmployers;
            List<SObject> currentSobjects = new List<SObject>();
            app.Date_Of_Leaving_Last_UK__c               = Date.valueOf(requestData?.endDateOfLastUKEmployer);
            app.Years_Of_Work_In_The_UK__c               = requestData?.yearsWorkInUK;
            if (isFullForm == false) {
                app.Step__c                                  = 'Work After UK';
            }
            app.Type_Of_Employment__c                    = requestData?.workInUKBeforeLeaving;
            app.Last_UK_Employer_Name__c                 = requestData?.nameOfLastUKEmployer;
            app.Last_UK_Employer_Start_Date__c           = Date.valueOf(requestData?.startDateOfLastUKEmployer);
            app.Last_UK_Employer_End_Date__c             = Date.valueOf(requestData?.endDateOfLastUKEmployer);
            app.Last_UK_Employer_Address__City__s        = requestData?.workInUKBeforeLeaving == 'Employed' ? requestData?.lastUKEmployerAddress?.city : null;
            app.Last_UK_Employer_Address__CountryCode__s = requestData?.workInUKBeforeLeaving == 'Employed' ? requestData?.lastUKEmployerAddress?.country : null;
            app.Last_UK_Employer_Address__StateCode__s   = requestData?.workInUKBeforeLeaving == 'Employed' ? requestData?.lastUKEmployerAddress?.state : null;
            app.Last_UK_Employer_Address__Street__s      = requestData?.workInUKBeforeLeaving == 'Employed' ? requestData?.lastUKEmployerAddress?.street : null;
            app.Last_UK_Employer_Address__PostalCode__s  = requestData?.workInUKBeforeLeaving == 'Employed' ? requestData?.lastUKEmployerAddress?.postcode : null;
            app.Last_UK_Employer_Address_Country__c      = requestData?.workInUKBeforeLeaving == 'Employed' ?
                                                                CountryCodeHelper.getCountryNameByIsoCode(requestData?.lastUKEmployerAddress?.country):
                                                                null;
            app.Last_UK_Employer_Address_State__c        = requestData?.workInUKBeforeLeaving == 'Employed' ?
                                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                    requestData?.lastUKEmployerAddress?.country,
                                                                    requestData?.lastUKEmployerAddress?.state)
                                                                : null;
            app.Date_of_Last_Pay_Contributions__c        = Date.valueOf(requestData?.endDateOfLastUKEmployer);
            if (app.Is_Know_National_Insurance_Number__c == true && requestData?.workInUKBeforeLeaving == 'Self-Employed') {
                app.Is_Self_Assessment__c        = true;
                app.Is_Individual_Pay_Section__c = true;
            }
            if ((app.Is_Know_National_Insurance_Number__c == false && requestData?.workInUKBeforeLeaving == 'Self-Employed') ||
                 requestData?.workInUKBeforeLeaving == 'Employed' ||
                 requestData?.workInUKBeforeLeaving == 'Unemployed') {
                app.Is_Self_Assessment__c        = false;
                app.Is_Individual_Pay_Section__c = true;
            }
            currentSobjects.add(app);
            if(requestData?.workInUKBeforeLeaving == 'Employed') {
                Employer__c newEmployer = new Employer__c(
                    Employer_Name__c                  = requestData?.nameOfLastUKEmployer,
                    Start_Date__c                     = Date.valueOf(requestData?.startDateOfLastUKEmployer),
                    End_Date__c                       = Date.valueOf(requestData?.endDateOfLastUKEmployer),
                    Employers_Address__City__s        = requestData?.lastUKEmployerAddress?.city,
                    Employers_Address__CountryCode__s = requestData?.lastUKEmployerAddress?.country,
                    Employers_Address__StateCode__s   = requestData?.lastUKEmployerAddress?.state,
                    Employers_Address__Street__s      = requestData?.lastUKEmployerAddress?.street,
                    Employers_Address__PostalCode__s  = requestData?.lastUKEmployerAddress?.postcode,
                    Application__c                    = app.Id,
                    Type__c                           = 'UK Work',
                    Type_Of_UK_Employment__c          = 'Employed',
                    Employers_Address_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(requestData?.lastUKEmployerAddress?.country),
                    Employers_Address_State__c        = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                            requestData?.lastUKEmployerAddress?.country,
                                                            requestData?.lastUKEmployerAddress?.state)
                );
                currentSobjects.add(newEmployer);
            } else if(requestData?.workInUKBeforeLeaving == 'Self-Employed') {
                Employer__c newEmployer = new Employer__c(
                    Employer_Name__c                  = requestData?.nameOfLastUKEmployer,
                    Start_Date__c                     = Date.valueOf(requestData?.startDateOfLastUKEmployer),
                    End_Date__c                       = Date.valueOf(requestData?.endDateOfLastUKEmployer),
                    Application__c                    = app.Id,
                    Type__c                           = 'UK Work',
                    Type_Of_UK_Employment__c          = 'Self-Employed'
                );
                currentSobjects.add(newEmployer);
            } else if(requestData?.workInUKBeforeLeaving == 'Unemployed') {
                Employer__c newEmployer = new Employer__c(
                    Employer_Name__c                  = requestData?.nameOfLastUKEmployer,
                    Start_Date__c                     = Date.valueOf(requestData?.startDateOfLastUKEmployer),
                    End_Date__c                       = Date.valueOf(requestData?.endDateOfLastUKEmployer),
                    Application__c                    = app.Id,
                    Type__c                           = 'UK Work',
                    Type_Of_UK_Employment__c          = 'Unemployed'
                );
                currentSobjects.add(newEmployer);
            } else if(requestData?.workInUKBeforeLeaving == 'Not employed') {
                Employer__c newEmployer = new Employer__c(
                    Employer_Name__c                  = requestData?.nameOfLastUKEmployer,
                    Start_Date__c                     = Date.valueOf(requestData?.startDateOfLastUKEmployer),
                    End_Date__c                       = Date.valueOf(requestData?.endDateOfLastUKEmployer),
                    Application__c                    = app.Id,
                    Type__c                           = 'UK Work',
                    Type_Of_UK_Employment__c          = 'Not employed'
                );
                currentSobjects.add(newEmployer);
            }
            upsert currentSobjects;
            result.put('status', 'Success');
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> setApplicationWorkAfterUKDetails(ApplicationManager.WorkAfterUKStepWrapper requestData, String stripeId, Boolean isFullForm) {
        Map<String, Object> result = new Map<String, Object>();
        Application__c app = [
            SELECT
                Id,
                Step__c,
                Abroad_Employer_Name1__c,
                Abroad_Employer_Start_Date1__c,
                Abroad_Employer_End_Date1__c,
                Abroad_Employer_Address1__City__s,
                Abroad_Employer_Address1__CountryCode__s,
                Abroad_Employer_Address1__StateCode__s,
                Abroad_Employer_Address1__Street__s,
                Abroad_Employer_Address1__PostalCode__s,
                Abroad_Employer_Address1_Country__c,
                Abroad_Employer_Address1_State__c,
                Career_Break_Employer_Start_Date1__c,
                Career_Break_Employer_End_Date1__c,
                Self_Employed_Start_Date1__c,
                Self_Employed_End_Date1__c,
                SelfEmployment_Employment_Abroad__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        List<Employer__c> relatedEmployers = [
            SELECT
                Application__r.Id,
                Type__c
            FROM Employer__c
            WHERE Application__r.Id = :app.Id
                AND Type__c = 'Work After UK'
        ];
        try {
            if (!relatedEmployers.isEmpty()) {
                delete relatedEmployers;
            }
            app.put('Abroad_Employer_Name1__c', null);
            app.put('Abroad_Employer_Start_Date1__c', null);
            app.put('Abroad_Employer_End_Date1__c', null);
            app.put('Abroad_Employer_Address1__City__s', null);
            app.put('Abroad_Employer_Address1__CountryCode__s', null);
            app.put('Abroad_Employer_Address1__StateCode__s', null);
            app.put('Abroad_Employer_Address1__Street__s', null);
            app.put('Abroad_Employer_Address1__PostalCode__s', null);
            app.put('Abroad_Employer_Address1_Country__c', null);
            app.put('Abroad_Employer_Address1_State__c', null);
            app.put('Career_Break_Employer_Start_Date1__c', null);
            app.put('Career_Break_Employer_End_Date1__c', null);
            app.put('Self_Employed_Start_Date1__c', null);
            app.put('Self_Employed_End_Date1__c', null);
            app.put('Self_Employed_End_Date1__c', null);
            app.put('SelfEmployment_Employment_Abroad__c', null);
            update app;
            List<SObject> newEmployers = new List<SObject>();
            Employer__c firstEmployer;
            if (requestData?.workAfterUK != null) {
                requestData.workAfterUK.sort();
                for (ApplicationManager.AfterUKEmployerWrapper employer : requestData.workAfterUK) {
                    String countryName = CountryCodeHelper.getCountryNameByIsoCode(employer?.country);
                    String stateName   = CountryCodeHelper.getCountryStateNameByIsoCode(employer?.country, employer?.state);
                    if (employer?.afterLeftTheUK == 'Employed') {
                        Employer__c newEmployer = new Employer__c(
                            Employer_Name__c                  = employer?.nameOfYourEmployerAbroad,
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Employers_Address__City__s        = employer?.city,
                            Employers_Address__CountryCode__s = employer?.country,
                            Employers_Address__StateCode__s   = employer?.state,
                            Employers_Address__Street__s      = employer?.street,
                            Employers_Address__PostalCode__s  = employer?.postcode,
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Employers_Address_Country__c      = countryName,
                            Employers_Address_State__c        = stateName,
                            Type_Of_After_UK_Employment__c    = 'Employed',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No',
                            Is_First_Employer__c              = firstEmployer == null ? true : false
                        );
                        if (app.Abroad_Employer_Name1__c == null && firstEmployer == null) {
                            app.put('Abroad_Start_Date__c', Date.valueOf(employer?.startDate));
                            app.put('Abroad_Employer_Name1__c', employer?.nameOfYourEmployerAbroad);
                            app.put('Abroad_Employer_Start_Date1__c', Date.valueOf(employer?.startDate));
                            app.put('Abroad_Employer_End_Date1__c', Date.valueOf(employer?.endDate));
                            app.put('Abroad_Employer_Address1__City__s', employer?.city);
                            app.put('Abroad_Employer_Address1__CountryCode__s', employer?.country);
                            app.put('Abroad_Employer_Address1__StateCode__s', employer?.state);
                            app.put('Abroad_Employer_Address1__Street__s', employer?.street);
                            app.put('Abroad_Employer_Address1__PostalCode__s',  employer?.postcode);
                            app.put('Abroad_Employer_Address1_Country__c', countryName);
                            app.put('Abroad_Employer_Address1_State__c', stateName);
                            app.put('SelfEmployment_Employment_Abroad__c', 'Employed');
                            firstEmployer = newEmployer;
                        }
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Career Break') {
                        Employer__c newEmployer = new Employer__c(
                            Employer_Name__c                  = employer?.nameOfYourEmployerAbroad,
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Employers_Address__City__s        = employer?.city,
                            Employers_Address__CountryCode__s = employer?.country,
                            Employers_Address__StateCode__s   = employer?.state,
                            Employers_Address__Street__s      = employer?.street,
                            Employers_Address__PostalCode__s  = employer?.postcode,
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Employers_Address_Country__c      = countryName,
                            Employers_Address_State__c        = stateName,
                            Type_Of_After_UK_Employment__c    = 'Career Break',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        if (app.Career_Break_Employer_Start_Date1__c == null) {
                            app.put('Career_Break_Employer_Start_Date1__c', Date.valueOf(employer?.startDate));
                            app.put('Career_Break_Employer_End_Date1__c', Date.valueOf(employer?.endDate));
                        }
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Self-Employed') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Self-Employed',
                            Is_First_Employer__c              = firstEmployer == null ? true : false,
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        if (app.Self_Employed_Start_Date1__c == null && firstEmployer == null) {
                            app.put('Self_Employed_Start_Date1__c', Date.valueOf(employer?.startDate));
                            app.put('Self_Employed_End_Date1__c', Date.valueOf(employer?.endDate));
                            app.put('Abroad_Start_Date__c', Date.valueOf(employer?.startDate));
                            app.put('SelfEmployment_Employment_Abroad__c', 'Self-employed');
                            firstEmployer = newEmployer;
                        }
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Unemployed') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Unemployed',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Family Carer') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Family Carer',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Homemaker') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Homemaker',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Disabled') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Disabled',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Retired') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Retired',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Education') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Education',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    } else if (employer?.afterLeftTheUK == 'Illness') {
                        Employer__c newEmployer = new Employer__c(
                            Start_Date__c                     = Date.valueOf(employer?.startDate),
                            End_Date__c                       = Date.valueOf(employer?.endDate),
                            Application__c                    = app.Id,
                            Type__c                           = 'Work After UK',
                            Type_Of_After_UK_Employment__c    = 'Illness',
                            Current_Work__c                   = employer?.isCurrently == true ? 'Yes' : 'No'
                        );
                        newEmployers.add(newEmployer);
                    }
                }
            }
            if (isFullForm == false) {
                app.Step__c = 'Documents';
            }
            newEmployers.add(app);
            upsert newEmployers;
            result.put('status', 'Success');
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> setNotesInfo(ApplicationManager.DocumentsStepWrapper requestData, String stripeId) {
        Map<String, Object> result = new Map<String, Object>();

        List<Application__c> apps = [
            SELECT Id
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];

        if(apps.size() == 0) {
            result.put('status', 'Error');
            result.put('message', 'Didn\'t find any application');
        } else if( requestData?.notes != null){
            try {
                ContentNote cnt = new ContentNote();
                cnt.Content = Blob.valueof(requestData?.notes);
                cnt.Title = 'Notes from Full Form';
                insert cnt;

                ContentDocumentLink clnk = new ContentDocumentLink();
                clnk.LinkedEntityId = apps[0].Id;
                clnk.ContentDocumentId = cnt.Id;
                clnk.ShareType = 'V';
                insert clnk;

                result.put('status', 'Success');
            } catch (Exception ex) {
                result.put('status', 'Error');
                result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
            }
        } else {
            result.put('status', 'Success');
        }
        return result;
    }

    public static Map<String, Object> setMissingInfo(ApplicationManager.MissingInfoWrapper requestData, String stripeId) {
        Map<String, Object> result = new Map<String, Object>();
        Application__c app = [
            SELECT
                Contact__c,
                Email__c,
                Missing_Template_Data__c,
                Is_Contains_Last_UK_Emploers__c,
                Is_Contains_NINO__c,
                Is_Contains_PRSI__c,
                Is_Contains_Relationship_Details__c,
                Is_Contains_Work_After_UK_Details__c,
                Is_Generate_Client_Summary_PDF__c,
                Is_Contains_C3_Appeal_Letter__c,
                Missing_Info_Send_Date__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        if (app == null) {
            result.put('status', 'Error');
            result.put('message', 'Didn\'t find nessasary application');
            return result;
        }
        if (app.Missing_Info_Send_Date__c != null) {
            result.put('status', 'Error');
            result.put('message', 'Missing Info email has been already sent earlier');
            return result;
        }
        try {
            app.put('Is_Contains_Last_UK_Emploers__c', requestData?.lastUKEmpl);
            app.put('Is_Contains_NINO__c', requestData?.nino);
            app.put('Is_Contains_PRSI__c', requestData?.prsi);
            app.put('Is_Contains_Relationship_Details__c', requestData?.relationship);
            app.put('Is_Contains_Work_After_UK_Details__c', requestData?.workAfterUK);
            app.put('Is_Contains_C3_Appeal_Letter__c', requestData?.c3AppealLetter);
            String extraData = '';
            if (requestData?.lastUKEmpl == true) {
                extraData += XtraPensionConstants.LAST_UK_EMPLOYERS_INFO;
            }
            if (requestData?.nino == true) {
                extraData += XtraPensionConstants.NINO_INFO;
            }
            if (requestData?.prsi == true) {
                extraData += XtraPensionConstants.PRSI_INFO;
            }
            if (requestData?.relationship == true) {
                extraData += XtraPensionConstants.RELATIONSHIP_INFO;
            }
            if (requestData?.workAfterUK == true) {
                extraData += XtraPensionConstants.WORK_AFTER_UK_INFO;
            }
            if (requestData?.c3AppealLetter == true) {
                extraData += XtraPensionConstants.C3_APPEAL_LETTER_INFO;
            }
            if (!String.isBlank(extraData)) {
                app.Missing_Template_Data__c = extraData;
                update app;
            }
            if (app.Is_Contains_Last_UK_Emploers__c == true ||
                app.Is_Contains_NINO__c == true ||
                app.Is_Contains_PRSI__c == true ||
                app.Is_Contains_Relationship_Details__c == true ||
                app.Is_Contains_Work_After_UK_Details__c == true ||
                app.Is_Contains_C3_Appeal_Letter__c == true ) {
                sendEmailWithEmptyData(app);
            }
            result.put('status', 'Success');
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
        }
        return result;
    }


    public static Map<String, Object> setApplicationDocumentsDetails(ApplicationManager.DocumentsStepWrapper requestData, String stripeId) {
        Map<String, Object> result = new Map<String, Object>();
        Application__c app = [
            SELECT
                Id,
                Status__c,
                First_Name__c,
                Second_Name__c,
                Name,
                Is_Generate_Client_Summary_PDF__c,
                Form_Complete_Date__c,
                Form_Was_Copmleted_By__c,
                Contact__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        if (requestData?.statements == null) {
            result.put('status', 'Success');
            result.put('isComplete', 'true');
            app.Status__c = 'Form Completed';
            update app;
        } else {
            String idCurrentContentVersion = requestData?.statements;
            List<ContentDocumentLink> oldDocuments = [
                SELECT
                    ContentDocumentId,
                    ContentDocument.Title,
                    ContentDocument.LatestPublishedVersionId,
                    LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocument.Title LIKE '%UPLOAD%' AND
                    LinkedEntityId = :app.Id
            ];
            if (!oldDocuments.isEmpty()) {
                ContentDocumentLink lastVersionOfUploadDocument;
                for (ContentDocumentLink link : oldDocuments) {
                    if (link.ContentDocument.LatestPublishedVersionId != idCurrentContentVersion &&
                        link.ContentDocument.Title.contains('ForSignature') &&
                        !link.ContentDocument.Title.contains('completed') &&
                        link.ContentDocument.Title.contains('UPLOAD')) {
                        lastVersionOfUploadDocument = link;
                        break;
                    }
                }
                if (lastVersionOfUploadDocument != null) {
                    ContentDocument updateDocument = new ContentDocument();
                    updateDocument.Id = lastVersionOfUploadDocument.ContentDocumentId;
                    updateDocument.Title = lastVersionOfUploadDocument.ContentDocument.Title.replace('ForSignature', 'v' + (oldDocuments.size() - 1) + '.0');
                    update updateDocument;

                    List<ContentVersion> contentVersions = [
                        SELECT
                            Id,
                            Title,
                            FileType,
                            ContentSize,
                            ContentDocumentId
                        FROM ContentVersion
                        WHERE Id = :idCurrentContentVersion
                        LIMIT 1
                    ];
                    if (contentVersions.isEmpty()) {
                        sendErrorMessage(app, idCurrentContentVersion);
                        result.put('status', 'Success');
                        result.put('isComplete', 'true');
                        return result;
                    } else {
                        ContentVersion currentContentVersion = contentVersions[0];

                        List<Application_Document__c> relatedApplicationDocuments = [
                            SELECT
                                File_Name__c
                            FROM Application_Document__c
                            WHERE Application__c = :app.Id AND
                            File_Name__c LIKE '%UPLOAD%'
                            LIMIT 1
                        ];
                        if (!relatedApplicationDocuments.isEmpty()) {
                            ContentDocumentLink conDocLinkUploadDoc = new ContentDocumentLink();
                            conDocLinkUploadDoc.LinkedEntityId = relatedApplicationDocuments[0].Id;
                            conDocLinkUploadDoc.ContentDocumentId = currentContentVersion.ContentDocumentId;
                            conDocLinkUploadDoc.shareType = 'V';
                            conDocLinkUploadDoc.Visibility = 'AllUsers';
                            Database.insert(conDocLinkUploadDoc, false);
                            app.Status__c = 'Form Completed';
                            app.Form_Complete_Date__c = Date.today();
                            update app;
                            result.put('status', 'Success');
                            result.put('isComplete', 'true');
                            return result;
                        }
                    }
                } else {
                    List<ContentVersion> contentVersions = [
                        SELECT
                            Id,
                            Title,
                            FileType,
                            ContentSize,
                            ContentDocumentId
                        FROM ContentVersion
                        WHERE Id = :idCurrentContentVersion
                        LIMIT 1
                    ];
                    if (contentVersions.isEmpty()) {
                        sendErrorMessage(app, idCurrentContentVersion);
                        result.put('status', 'Success');
                        result.put('isComplete', 'true');
                        return result;
                    }
                    ContentVersion currentContentVersion = contentVersions[0];
                    try {
                        List<Application_Document__c> relatedApplicationDocuments = [
                            SELECT
                                File_Name__c
                            FROM Application_Document__c
                            WHERE Application__c = :app.Id AND
                                File_Name__c LIKE '%UPLOAD%'
                            LIMIT 1
                        ];
                        List<SObject> newContentDocumentLinkAndApplication = new List<SObject>();
                        if (relatedApplicationDocuments.isEmpty()) {
                            List<Application_Document__c> newApplicationDocuments = new List<Application_Document__c>();
                            newApplicationDocuments.add(
                                new Application_Document__c(
                                    Application__c = requestData?.applicationId,
                                    File_Name__c   = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_UPLOAD_ForSignature',
                                    File_Size__c   = currentContentVersion.ContentSize,
                                    Large_File__c  = Integer.valueOf(currentContentVersion.ContentSize) > 6000000 ? true : false,
                                    Status__c      = 'New',
                                    Type__c        = 'CV'
                                )
                            );
                            insert newApplicationDocuments;

                            newContentDocumentLinkAndApplication.add(
                                new ContentDocumentLink(
                                    ContentDocumentId = currentContentVersion.ContentDocumentId,
                                    LinkedEntityId    = newApplicationDocuments[0].Id,
                                    ShareType         = 'V',
                                    Visibility        = 'AllUsers'
                                )
                            );
                        }
                        app.Status__c = 'Form Completed';
                        app.Form_Complete_Date__c = Date.today();
                        newContentDocumentLinkAndApplication.add(app);
                        upsert newContentDocumentLinkAndApplication;
                        result.put('status', 'Success');
                        result.put('isComplete', 'true');
                    } catch (Exception ex) {
                        result.put('status', 'Error');
                        result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
                    }
                }
            }
        }
        return result;
    }

    public static Map<String, Object> getApplication(String stripeId, Map<String, Object> result, Boolean isFullForm) {
        Datetime todayDateTime = Datetime.now();
        String fullFormQueryStatuses = isFullForm == true ?
            '(Status__c = \'Form In Progress\' ' +
            'OR Status__c = \'Form Completed\' ' +
            'OR Status__c = \'NINO/Doc Needed\' OR Status__c = \'NO NINO\') ' :
            '(Status__c = \'Form In Progress\' OR Status__c = \'NO NINO\') ';
        String queryLine1 =
            'SELECT ' +
                'Id ' +
              'FROM Application__c ' +
            'WHERE Stripe_Transaction_Id__c =: stripeId ' +
            'LIMIT 1';
        String queryLine2 =
            'SELECT ' +
                'Id, ' +
                'Name, ' +
                'Salutation__c, ' +
                'First_Name__c, ' +
                'Second_Name__c, ' +
                'Date_Of_Birth__c, ' +
                'National_Insurance_Number__c, ' +
                'Work_Or_Pay_UK_National_Insurance__c, ' +
                'Private_UK_Pension__c, ' +
                'Approx_Value_Of_UK_Pension__c, ' +
                'Current_Occupation__c, ' +
                'Current_Address_Abroad__City__s, ' +
                'Current_Address_Abroad__Street__s, ' +
                'Current_Address_Abroad__StateCode__s, ' +
                'Current_Address_Abroad__CountryCode__s, ' +
                'Current_Address_Abroad__PostalCode__s, ' +
                'Last_UK_Home_Address__City__s, ' +
                'Last_UK_Home_Address__CountryCode__s, ' +
                'Last_UK_Home_Address__Street__s, ' +
                'Last_UK_Home_Address__StateCode__s, ' +
                'Last_UK_Home_Address__PostalCode__s, ' +
                'Previous_UK_Address_1__City__s, ' +
                'Previous_UK_Address_1__CountryCode__s, ' +
                'Previous_UK_Address_1__PostalCode__s, ' +
                'Previous_UK_Address_1__StateCode__s, ' +
                'Previous_UK_Address_1__Street__s, ' +
                'Previous_UK_Address_Start_Date_1__c, ' +
                'Previous_UK_Address_End_Date_1__c, ' +
                'Previous_UK_Address_2__City__s, ' +
                'Previous_UK_Address_2__CountryCode__s, ' +
                'Previous_UK_Address_2__PostalCode__s, ' +
                'Previous_UK_Address_2__StateCode__s, ' +
                'Previous_UK_Address_2__Street__s, ' +
                'Previous_UK_Address_Start_Date_2__c, ' +
                'Previous_UK_Address_End_Date_2__c, ' +
                'Previous_UK_Address_3__City__s, ' +
                'Previous_UK_Address_3__CountryCode__s, ' +
                'Previous_UK_Address_3__PostalCode__s, ' +
                'Previous_UK_Address_3__StateCode__s, ' +
                'Previous_UK_Address_3__Street__s, ' +
                'Previous_UK_Address_Start_Date_3__c, ' +
                'Previous_UK_Address_End_Date_3__c, ' +
                'Abroad_Employer_Name1__c, ' +
                'Abroad_Employer_Start_Date1__c, ' +
                'Abroad_Employer_End_Date1__c, ' +
                'Abroad_Employer_Address1__City__s, ' +
                'Abroad_Employer_Address1__CountryCode__s, ' +
                'Abroad_Employer_Address1__StateCode__s, ' +
                'Abroad_Employer_Address1__Street__s, ' +
                'Abroad_Employer_Address1__PostalCode__s, ' +
                'Career_Break_Employer_Name1__c, ' +
                'Career_Break_Employer_Start_Date1__c, ' +
                'Career_Break_Employer_End_Date1__c, ' +
                'Career_Break_Employer_Address1__City__s, ' +
                'Career_Break_Employer_Address1__CountryCode__s, ' +
                'Career_Break_Employer_Address1__StateCode__s, ' +
                'Career_Break_Employer_Address1__Street__s, ' +
                'Career_Break_Employer_Address1__PostalCode__s, ' +
                'Self_Employed_Start_Date1__c, ' +
                'Self_Employed_End_Date1__c, ' +
                'Did_You_Change_Name__c, ' +
                'Date_Of_Marriage_Or_Civil_Partnership__c, ' +
                'Are_You_Divorced__c, ' +
                'Full_Maiden_Previous_Name__c, ' +
                'Are_You_Single__c, ' +
                'Type_Of_Employment__c, ' +
                'Date_Of_Leaving_Last_UK__c, ' +
                'Divorce_Date__c, ' +
                'Years_Of_Work_In_The_UK__c, ' +
                'Last_UK_Employer_Name__c, ' +
                'Last_UK_Employer_Start_Date__c, ' +
                'Last_UK_Employer_End_Date__c, ' +
                'Last_UK_Employer_Address__City__s, ' +
                'Last_UK_Employer_Address__CountryCode__s, ' +
                'Last_UK_Employer_Address__StateCode__s, ' +
                'Last_UK_Employer_Address__Street__s, ' +
                'Last_UK_Employer_Address__PostalCode__s, ' +
                    '(SELECT ' +
                        'Employer_Name__c, ' +
                        'Start_Date__c, ' +
                        'End_Date__c, ' +
                        'Employers_Address__City__s, ' +
                        'Employers_Address__CountryCode__s, ' +
                        'Employers_Address__StateCode__s, ' +
                        'Employers_Address__Street__s, ' +
                        'Employers_Address__PostalCode__s, ' +
                        'Current_Work__c, ' +
                        'Type__c, ' +
                        'Type_Of_After_UK_Employment__c ' +
                    'FROM Employers__r), ' +
                'Step__c, ' +
                'Is_Know_National_Insurance_Number__c, ' +
                'Is_Contains_Last_UK_Emploers__c, ' +
                'Is_Contains_NINO__c, ' +
                'Is_Contains_PRSI__c, ' +
                'Is_Contains_Relationship_Details__c, ' +
                'Is_Contains_Work_After_UK_Details__c, ' +
                'Is_Contains_C3_Appeal_Letter__c, ' +
                'Full_Form_Notes__c, ' +
                'Appeal_Application__c, ' +
                'Getting_UK_Pension_Now__c ' +
            'FROM Application__c ' +
            'WHERE Stripe_Transaction_Id__c =: stripeId ' +
                'AND Expiry_Date__c >: todayDateTime ' +
                'AND '+ fullFormQueryStatuses +
            'LIMIT 1';

        try {
            List<Application__c> apps = Database.query(queryLine1);
            if (apps.isEmpty()) {
                result.put('status', 'Error');
                result.put('message', 'Application not found');
            } else {
                List<Application__c> appAfterFirstQuery = Database.query(queryLine2);
                if (!appAfterFirstQuery.isEmpty()) {
                    result.put('status', 'Success');
                    result.put('currentStep', appAfterFirstQuery[0].Step__c);
                    result.put('formData', appAfterFirstQuery[0]);
                } else {
                    result.put('status', 'Error');
                    result.put('message', 'Application completed');
                }
            }
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getMobileData(String stripeId, Map<String, Object> result) {
        Datetime todayDateTime = Datetime.now();
        String queryLine =
            'SELECT ' +
                'Your_Name__c, ' +
                'Date_Of_Birth__c, ' +
                'Marital_status__c, ' +
                'Name_And_Address_Of_Last_UK_Employed__c, ' +
                'Date_Of_Leaving_Last_UK__c, ' +
                'You_Worked_Immediately_Before_Leaving_UK__c, ' +
                'Name_And_Address_Of_First_Work_After_UK__c, ' +
                'Approx_Date_Stop_First_Working__c, ' +
                'You_Have_Done_Where_2006_NOW__c, ' +
                'National_Insurance_Number__c, ' +
                'Request_PRSI_or_Social_Ins_Statement__c, ' +
                'Years_Of_Work_In_The_UK__c ' +
            'FROM Application__c ' +
            'WHERE Stripe_Transaction_Id__c =: stripeId ' +
                'AND Expiry_Date__c >: todayDateTime ' +
                'AND Status__c = \'Form In Progress\' ' +
            'LIMIT 1';
        try {
            Application__c app = Database.query(queryLine);
            if (app != null) {
                result.put('status', 'Success');
                result.put('formData', app);
            } else {
                result.put('status', 'Error');
                result.put('message','Not found');
            }
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message',ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getPaymentData(String paymentId) {
        Map<String, Object> result = new Map<String, Object>();
        List<Payment__c> payments = [
            SELECT
                Name,
                Application__r.Email__c,
                Amount__c,
                Product__r.Name,
                Customer_Id__c,
                CurrencyIsoCode,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Application__r.Current_Address_Abroad__PostalCode__s,
                Application__r.Current_Address_Abroad__StateCode__s,
                Application__r.Current_Address_Abroad__Street__s,
                Application__r.Current_Address_Abroad__CountryCode__s,
                Application__r.Current_Address_Abroad__City__s,
                Application__r.Related_Contact_Phone__c,
                Payment_Method__c
            FROM Payment__c
            WHERE Id = :paymentId /*AND Status__c != 'Paid'*/
            LIMIT 1
        ];

        if (!payments.isEmpty()) {
            Payment__c currentPayment = payments[0];
            ApplicationManager.AddressDataWrapper addressData = new ApplicationManager.AddressDataWrapper();
            addressData.line1 = currentPayment.Application__r.Current_Address_Abroad__Street__s;
            addressData.postal_code = currentPayment.Application__r.Current_Address_Abroad__PostalCode__s;
            addressData.state = currentPayment.Application__r.Current_Address_Abroad__StateCode__s;
            addressData.city = currentPayment.Application__r.Current_Address_Abroad__City__s;
            addressData.country = currentPayment.Application__r.Current_Address_Abroad__CountryCode__s;
            result.put('status', 'Success');
            result.put('email', currentPayment.Application__r.Email__c);
            result.put('amount', currentPayment.Amount__c * 100);
            result.put('productName', currentPayment.Product__r.Name);
            result.put('customerId', currentPayment.Customer_Id__c);
            result.put('currencyCode', currentPayment.CurrencyIsoCode);
            result.put('address', addressData);
            result.put('firstName', currentPayment.Application__r.First_Name__c);
            result.put('lastName', currentPayment.Application__r.Second_Name__c);
            result.put('phone', currentPayment.Application__r.Related_Contact_Phone__c);
            result.put('paymentMethod', currentPayment.Payment_Method__c);
        } else {
            result.put('status', 'Error');
            result.put('message', 'Not found');
        }
        return result;
    }

    public static Map<String, Object> changeStatusFailedPayment(ApplicationManager.PaymentDataWrapper requestData) {
        Map<String, Object> result = new Map<String, Object>();
        String paymentId     = requestData?.paymentId;
        String paymentMethod = requestData?.paymentMethod;
        List<Payment__c> payments = [
            SELECT
                Status__c,
                Payment_Method__c,
                Application__c,
                Application__r.Payment_Method__c,
                Payment_Date__c,
                Error_Message__c
            FROM Payment__c
            WHERE Id = :paymentId
            LIMIT 1
        ];
        if (!payments.isEmpty()) {
            List<SObject> updateRecords = new List<SObject>();
            Payment__c currentPayment = payments[0];
            StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
				'payment_methods/' + paymentMethod,
				'GET',
				null
			);
			Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
			Map<String,Object> cardData = (Map<String,Object>)methodData.get('card');
			currentPayment.Card_Data__c = cardData.get('brand') + ' - ' + cardData.get('last4');
            currentPayment.Status__c = 'Paid';
            currentPayment.Payment_Date__c = Date.today();
            currentPayment.Payment_Method__c = paymentMethod;
            currentPayment.Error_Message__c = '';
            updateRecords.add(currentPayment);
            Application__c relatedApplication = new Application__c();
            relatedApplication.Id = currentPayment.Application__c;
            relatedApplication.Payment_Method__c = paymentMethod;
            updateRecords.add(relatedApplication);

            List<Payment__c> relatedPayments = [
                SELECT
                    Payment_Method__c,
                    Application__c
                FROM Payment__c
                WHERE Application__c = :relatedApplication.Id AND
                      Id != :currentPayment.Id
            ];
            if (!relatedPayments.isEmpty()) {
                for (Payment__c pay : relatedPayments) {
                    pay.Payment_Method__c = paymentMethod;
                    updateRecords.add(pay);
                }
            }
            update updateRecords;
            result.put('status', 'Success');
        }
        return result;
    }

    public static Map<String, Object> setFirstStatusApp(String stripeId) {
        Map<String, Object> result = new Map<String, Object>();
        Datetime todayDateTime = Datetime.now();
        String firstQueryLine =
            'SELECT Id ' +
            'FROM Application__c ' +
            'WHERE Stripe_Transaction_Id__c =: stripeId ' +
            'LIMIT 1';
        String secondQueryLine =
            'SELECT ' +
                'Status__c, ' +
                'Step__c ' +
            'FROM Application__c ' +
            'WHERE Stripe_Transaction_Id__c =: stripeId ' +
                'AND Expiry_Date__c >: todayDateTime ' +
                'AND (Status__c = \'Form In Progress\' OR ' +
                     'Status__c = \'Form Completed\' OR ' +
                     'Status__c = \'NINO/Doc Needed\' OR ' +
                     'Status__c = \'Pending Client\' OR ' +
                     'Status__c = \'Fix\')' +
            'LIMIT 1';
        try {
            List<Application__c> apps = Database.query(firstQueryLine);
            if (apps.isEmpty()) {
                result.put('status', 'Error');
                result.put('message', 'Application not found');
            } else {
                List<Application__c> appAfterFirstQuery = Database.query(secondQueryLine);
                if (!appAfterFirstQuery.isEmpty()) {
                    Application__c currApp = appAfterFirstQuery[0];
                    update new Application__c(
                        Id = currApp.Id,
                        Step__c = 'Personal Details',
                        Status__c = 'Form In Progress'
                    );
                    result.put('status', 'Success');
                } else {
                    result.put('status', 'Error');
                    result.put('message', 'Application completed');
                }
            }
        } catch (Exception ex) {
            result.put('status', 'Error');
            result.put('message', ex.getMessage());
        }
        return result;
    }

    public static Map<String, Object> setFullFormData(ApplicationManager.FormDataWrapper applicationData, String stripeId) {
        Map<String, Object> result = new Map<String, Object>();
        Map<String, Object> personalDetailResult = setApplicationPersonalDetails(applicationData.personal, stripeId, true);
        Map<String, Object> relationshipDetailResult = setApplicationRelationshipDetails(applicationData.relationship, stripeId, true);
        Map<String, Object> ukWorkDetailResult = setApplicationUkWorkDetails(applicationData.ukwork, stripeId, true);
        ApplicationManager.WorkAfterUKStepWrapper afterUKWrapper = new ApplicationManager.WorkAfterUKStepWrapper();
        afterUKWrapper.workAfterUK = applicationData.workAfterUK;
        Map<String, Object> workAfterUKDetailResult = setApplicationWorkAfterUKDetails(afterUKWrapper, stripeId, true);
        Map<String, Object> notesResult = setNotesInfo(applicationData.documents, stripeId);

        if (applicationData.isAutoUpdate == false) {
            Map<String, Object> missingInfoResult = setMissingInfo(applicationData.missingInfo, stripeId);
            if (missingInfoResult.get('status') == null || missingInfoResult.get('status') != 'Success') {
                if (result.get('message') == null) {
                    result.put('status', 'Error');
                    result.put('message', 'Error in the Missing Info checkboxes');
                }
                result = missingInfoResult;
                return result;
            }
        }
        if (personalDetailResult.get('status') == null || personalDetailResult.get('status') != 'Success') {
            result = personalDetailResult;
            if (result.get('message') == null) {
                result.put('status', 'Error');
                result.put('message', 'Error in the `Personal Details` Step');
            }
            return result;
        }
        if (relationshipDetailResult.get('status') == null || relationshipDetailResult.get('status') != 'Success') {
            result = relationshipDetailResult;
            if (result.get('message') == null) {
                result.put('status', 'Error');
                result.put('message', 'Error in the `Relationship Details` Step');
            }
            return result;
        }
        if (ukWorkDetailResult.get('status') == null || ukWorkDetailResult.get('status') != 'Success') {
            result = ukWorkDetailResult;
            if (result.get('message') == null) {
                result.put('status', 'Error');
                result.put('message', 'Error in the `UK Work` Step');
            }
            return result;
        }
        if (workAfterUKDetailResult.get('status') == null || workAfterUKDetailResult.get('status') != 'Success') {
            result = workAfterUKDetailResult;
            if (result.get('message') == null) {
                result.put('status', 'Error');
                result.put('message', 'Error in the `Work After UK` Step');
            }
            return result;
        }
        if (notesResult.get('status') == null || notesResult.get('status') != 'Success') {
            result = notesResult;
            if (result.get('message') == null) {
                result.put('status', 'Error');
                result.put('message', 'Error in the Notes saving');
            }
            return result;
        }
        if (result.get('status') == null) {
            result.put('isComplete', 'true');
            result.put('status', 'Success');
        }
        return result;
    }

    public static Map<String, Object> setMobileFormData(ApplicationManager.MobileDataWrapper mobileData, String stripeId) {
        Map<String, Object> result = new Map<String, Object>();
        if (mobileData == null || String.isBlank(stripeId)) {
            result.put('status', 'Error');
            result.put('message', 'Inbound data is Empty');
            return result;
        }
        List<Application__c> apps = [
            SELECT
                Id,
                Your_Name__c,
                Date_Of_Birth__c,
                Marital_status__c,
                Name_And_Address_Of_Last_UK_Employed__c,
                Date_Of_Leaving_Last_UK__c,
                You_Worked_Immediately_Before_Leaving_UK__c,
                Name_And_Address_Of_First_Work_After_UK__c,
                Approx_Date_Stop_First_Working__c,
                You_Have_Done_Where_2006_NOW__c,
                National_Insurance_Number__c,
                Request_PRSI_or_Social_Ins_Statement__c,
                Years_Of_Work_In_The_UK__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            result.put('status', 'Error');
            result.put('message', 'PriceBookEntries are empty');
            return result;
        }
        Application__c currApp = apps[0];
        currApp.Your_Name__c = mobileData?.yourName;
        currApp.Date_Of_Birth__c = mobileData?.yourDateOfBirth != null ? Date.valueOf(mobileData?.yourDateOfBirth) : null;
        currApp.Marital_status__c = mobileData?.yourMaritalStatus;
        currApp.Name_And_Address_Of_Last_UK_Employed__c = mobileData?.nameAndAddressOfLastUKEmployed;
        currApp.Date_Of_Leaving_Last_UK__c = mobileData?.approxDateLeaveUK != null ? Date.valueOf(mobileData?.approxDateLeaveUK) : null;
        currApp.You_Worked_Immediately_Before_Leaving_UK__c = mobileData?.youWorkingImmediatelyBeforeLeavingUK;
        currApp.Name_And_Address_Of_First_Work_After_UK__c = mobileData?.nameAndAddressOfFirstWorkAfterUK;
        currApp.Approx_Date_Stop_First_Working__c = mobileData?.approxDateStopFirstWorking != null ? Date.valueOf(mobileData?.approxDateStopFirstWorking) : null;
        currApp.You_Have_Done_Where_2006_NOW__c = mobileData?.youDone;
        currApp.National_Insurance_Number__c = mobileData?.nationalInsuranceNumber;
        currApp.Request_PRSI_or_Social_Ins_Statement__c = mobileData?.requestPRSIorSocialInsStatement;
        currApp.Years_Of_Work_In_The_UK__c = mobileData?.yearsInTheUK;

        update currApp;

        result.put('isComplete', 'true');
        result.put('status', 'Success');

        return result;
    }

    private static Messaging.SendEmailResult[] sendEmailWithEmptyData(Application__c app) {
        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :MISSING_INFO_OWD_NAME
        ];
        List<EmailTemplate> receiptEmailTemplate = [
            SELECT
                Id
            FROM EmailTemplate
            WHERE Name = :MISSING_INFO_TEMPLATE_NAME
        ];
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        if (!receiptEmailTemplate.isEmpty()) {
            message.setTemplateID(receiptEmailTemplate[0].Id);
        }
        message.setWhatId(app.Id);
        if ( owea.size() > 0 ) {
            message.setOrgWideEmailAddressId(owea.get(0).Id);
        }
        message.toAddresses = new String[] { app.Email__c };
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
        app.Missing_Info_Send_Date__c = Date.today();
        update app;
        return results;
    }

    private static void sendErrorMessage(Application__c app, String idCurrentContentVersion) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setSenderDisplayName('XtraPension');
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setHtmlBody('<div>Contnt version is empty  for the app: ' + app.Name + '</div>'+
                            '<div>Content version Id is: ' + idCurrentContentVersion + '</div>');
        message.setWhatId(app.Id);
        message.setSubject('XtraPension error!!!');
        message.toAddresses = new String[] {'mihail.klimovich@outlook.com'};
        message.setTreatTargetObjectAsRecipient(false);
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }
}