public class RE_ApplicationDataAction {
    private static final String EMPLOYMENT_TYPE_EMPLOYED = 'Employed';
    private static final String EMPLOYMENT_TYPE_SELF_EMPLOYED = 'Self-Employed';
    private static final String EMPLOYMENT_TYPE_NOT_EMPLOYED = 'Not employed';
    private static final String EMPLOYMENT_TYPE_UNEMPLOYED = 'Unemployed';
    private static final String EMPLOYMENT_TYPE_UK_WORK = 'UK Work';
    private static final String EMPLOYMENT_TYPE_WORK_AFTER_UK = 'Work After UK';
    private static final String CURRENT_WORK_YES = 'Yes';
    private static final String EMPLOYED_DIRECTLY_YES = 'Yes';
    private static final String EMPLOYMENT_STATUS_MAP_EMPLOYED = 'employed';
    private static final String EMPLOYMENT_STATUS_MAP_SELF_EMPLOYED = 'self_employed';
    private static final String EMPLOYMENT_STATUS_MAP_NEITHER = 'neither_employed_nor_self_employed';
    private static Map<String, String> countryCodeToLabel;

    static {
        countryCodeToLabel = new Map<String, String>();
        Schema.DescribeFieldResult fieldDescribe = Schema.sObjectType.Employer__c.fields.Employers_Address__CountryCode__s;
        
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            countryCodeToLabel.put(entry.getValue(), entry.getLabel());
        }
    }
    
    @AuraEnabled
    public static String createRelatedReapply(Id appId, Boolean isCreateFromBatch) {
        try {
            validateApplicationId(appId);
            
            Savepoint sp = Database.setSavepoint();
            try {
                ApplicationDataWrapper data = gatherApplicationData(appId);
                validateNoExistingReapply(appId);
                
                Reapply__c reapply = buildReapplyRecord(data);
                if (isCreateFromBatch) {
                    reapply.CreatedFromReapplyCreatorBatch__c = true;
                }
                
                // Validate the record before insert
                validateReapplyRecord(reapply);
                
                insert reapply;
                
                // Return the new record ID so LWC can navigate to it
                return reapply.Id;
                
            } catch (Exception e) {
                Database.rollback(sp);
                // Log the full error
                System.debug('=== INNER ERROR ===');
                System.debug('Error: ' + e.getMessage());
                System.debug('Stack: ' + e.getStackTraceString());
                
                // Re-throw with specific error message
                throw new ReapplyException('Error creating Reapply: ' + e.getMessage());
            }
            
        } catch (Exception e) {
            // Log the full error
            System.debug('=== OUTER ERROR ===');
            System.debug('Error Type: ' + e.getTypeName());
            System.debug('Error Message: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            
            if (e instanceof ReapplyException) {
                throw e;
            }
            
            // Otherwise, wrap it with a meaningful message
            throw new ReapplyException('Error: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id getReapplyRecordId(Id appId) {
        if (appId == null) return null;
    
        List<Reapply__c> existingReapplies = [
            SELECT Id
            FROM Reapply__c
            WHERE Application__c = :appId
            LIMIT 1
        ];
    
        return existingReapplies.isEmpty() ? null : existingReapplies[0].Id;
    }
    
    @AuraEnabled
    public static Boolean hasExistingReapply(Id appId) {
        if (appId == null) return false;
    
        List<Reapply__c> existingReapplies = [
            SELECT Id
            FROM Reapply__c
            WHERE Application__c = :appId
            LIMIT 1
        ];
    
        return !existingReapplies.isEmpty();
    }
    
    private static void validateReapplyRecord(Reapply__c reapply) {
        // Check for null required fields
        if (reapply.Application__c == null) {
            throw new ReapplyException('Application reference is required');
        }
        
        if (String.isBlank(reapply.Name)) {
            throw new ReapplyException('Reapply Name is required');
        }
        
        // Add more validations as needed
    }
        
    private static void validateApplicationId(Id appId) {
        if (appId == null) {
            throw new ReapplyException('Application Id is required');
        }
    }
    
    private static void validateNoExistingReapply(Id appId) {
        List<Reapply__c> existingReapplies = [
            SELECT Id
            FROM Reapply__c
            WHERE Application__c = :appId
            LIMIT 1
        ];
        if (!existingReapplies.isEmpty()) {
            throw new ReapplyException('A Reapply record already exists for this Application');
        }
    }
    
    private static ApplicationDataWrapper gatherApplicationData(Id appId) {
        List<Application__c> applications = RE_PortalUtils.getApplicationData(appId);
        if (applications.isEmpty()) {
            throw new ReapplyException('Application not found');
        }
        
        Application__c application = applications[0];
        List<Application__History> appHistories = RE_PortalUtils.getApplicationHistory(appId);
        
        ApplicationDataWrapper wrapper = new ApplicationDataWrapper();
        wrapper.application = application;
        wrapper.appHistories = appHistories;
        wrapper.beforeLeftUK_Employer = findEmployerByType(application.Employers__r, EMPLOYMENT_TYPE_UK_WORK);
        wrapper.afterLeftUK_Employers = findEmployersByType(application.Employers__r, EMPLOYMENT_TYPE_WORK_AFTER_UK);
        
        return wrapper;
    }
    
    private static Employer__c findEmployerByType(List<Employer__c> employers, String type) {
        if (employers == null) return null;
        for (Employer__c employer : employers) {
            if (type.equals(employer.Type__c)) {
                return employer;
            }
        }
        return null;
    }
    
    private static List<Employer__c> findEmployersByType(List<Employer__c> employers, String type) {
        List<Employer__c> result = new List<Employer__c>();
        if (employers == null) return result;
        
        for (Employer__c employer : employers) {
            if (type.equals(employer.Type__c)) {
                result.add(employer);
            }
        }
        return result;
    }
    
    private static Reapply__c buildReapplyRecord(ApplicationDataWrapper data) {
        Application__c app = data.application;
        
        Reapply__c reapply = new Reapply__c();
        
        // Basic information
        reapply.Application__c = app.Id;
        reapply.Name = 'R' + app.Name.substring(1);
        reapply.First_Name__c = app.First_Name__c;
        reapply.Second_Name__c = app.Second_Name__c;
        reapply.Email__c = app.Email__c;
        reapply.Phone__c = app.Related_Contact_Phone__c;
        reapply.Salutation__c = app.Salutation__c;
        
        // Personal details
        reapply.NINO__c = app.National_Insurance_Number__c?.replace(' ', '');
        reapply.Date_of_birth__c = app.Date_Of_Birth__c;
        
        // Address mapping
        mapAddressFields(reapply, app);

        // Payment information
        reapply.Payment_Method_Id__c = extractPaymentMethodId(app.Payment_Method__c);
        reapply.Stripe_Customer_Id__c = getStripeCustomerId(app);
        
        //Abroad countries mapping
        mapAbroadCountries(reapply, data.afterLeftUK_Employers, data.application);

        // History data mapping
        mapHistoryData(reapply, data.appHistories);
        
        // Date and location information
        reapply.What_date_did_or_will_you_leave_the_UK__c = app.Date_Of_Leaving_Last_UK__c;
        mapAbroadAddress(reapply, app);
        
        // Employment mapping
        mapEmploymentData(reapply, data);
        
        return reapply;
    }
    
    private static void mapAddressFields(Reapply__c reapply, Application__c app) {
        reapply.UK_Address__City__s = app.Last_UK_Home_Address__City__s;
        reapply.UK_Address__Street__s = app.Last_UK_Home_Address__Street__s;
        reapply.UK_Address__PostalCode__s = app.Last_UK_Home_Address__PostalCode__s;
    }

    private static void mapAbroadAddress(Reapply__c reapply, Application__c app) {
        reapply.Address_abroad__Street__s = app.Current_Address_Abroad__Street__s;
        reapply.Address_abroad__City__s = app.Current_Address_Abroad__City__s;
        reapply.Address_abroad__PostalCode__s = app.Current_Address_Abroad__PostalCode__s;
        reapply.Address_abroad__StateCode__s = app.Current_Address_Abroad__StateCode__s;
        reapply.Address_abroad__CountryCode__s = app.Current_Address_Abroad__CountryCode__s;
        reapply.Address_abroad_Country__c = app.Current_Address_Abroad__CountryCode__s != null ?
                                                CountryCodeHelper.getCountryNameByIsoCode(app.Current_Address_Abroad__CountryCode__s) : null;
        reapply.Address_abroad_State__c = app.Current_Address_Abroad__CountryCode__s != null &&
                                          app.Current_Address_Abroad__StateCode__s != null ?
                                              CountryCodeHelper.getCountryStateNameByIsoCode(
                                                app.Current_Address_Abroad__CountryCode__s,
                                                app.Current_Address_Abroad__StateCode__s) : null;
    }
    
    private static String extractPaymentMethodId(String paymentMethod) {
        if (String.isBlank(paymentMethod)) return '';
        
        if (paymentMethod.contains(';')) {
            List<String> paymentMethods = paymentMethod.split(';');
            return paymentMethods[paymentMethods.size() - 1].trim();
        }
        
        return paymentMethod;
    }
    
    private static String getStripeCustomerId(Application__c app) {
        return String.isNotBlank(app.Current_Customer_Id__c) 
            ? app.Current_Customer_Id__c 
            : app.Stripe_Customer_Id__c;
    }
    
    private static void mapHistoryData(Reapply__c reapply, List<Application__History> histories) {
        if (histories == null || histories.isEmpty()) return;
    
        try {
            Application__History firstHistory = histories[0];
            Application__History lastHistory = histories[histories.size() - 1];
        
            if (firstHistory.NewValue != null) {
                String stringValue = (String) String.valueOf(firstHistory.NewValue);
                if (String.isNotBlank(stringValue) && stringValue.isNumeric()) {
                    reapply.Live_in_UK__c = Decimal.valueOf(stringValue);
                }
            }
    
            if (lastHistory.NewValue != null) {
                String stringValue = (String) String.valueOf(lastHistory.NewValue);
                if (String.isNotBlank(stringValue) && stringValue.isNumeric()) {
                    reapply.NINO_contribution_pay__c = Decimal.valueOf(stringValue);
                }
            }
        } catch (Exception e) {
            System.debug('Error mapping history data: ' + e.getMessage());
        }
    }

    private static void mapAbroadCountries(Reapply__c reapply, List<Employer__c> afterLeftUKEmployers, Application__c app) {
        if (afterLeftUKEmployers == null || afterLeftUKEmployers.isEmpty()) {
            return;
        }
    
        // Group employers by country
        Map<String, List<Employer__c>> countryEmployersMap = new Map<String, List<Employer__c>>();
    
        for (Employer__c employer : afterLeftUKEmployers) {
            String countryCode = employer.Employers_Address__CountryCode__s;
        
            // If employer country code is empty, use application's current address country code
            if (String.isBlank(countryCode)) {
                countryCode = app.Current_Address_Abroad__CountryCode__s;
            }
        
            if (String.isNotBlank(countryCode)) {
                if (!countryEmployersMap.containsKey(countryCode)) {
                    countryEmployersMap.put(countryCode, new List<Employer__c>());
                }
                countryEmployersMap.get(countryCode).add(employer);
            }
        }
    
    
        // Build the formatted string for each country
        List<String> countryDateStrings = new List<String>();
    
        for (String countryCode : countryEmployersMap.keySet()) {
            List<Employer__c> employersInCountry = countryEmployersMap.get(countryCode);
        
            // Find the earliest start date and latest end date for this country
            Date earliestStart = null;
            Date latestEnd = null;
            Boolean hasCurrentWork = false;
        
            for (Employer__c employer : employersInCountry) {
                // Track start date
                if (employer.Start_Date__c != null) {
                    if (earliestStart == null || employer.Start_Date__c < earliestStart) {
                        earliestStart = employer.Start_Date__c;
                    }
                }
            
                // Track end date and current work status
                if (CURRENT_WORK_YES.equals(employer.Current_Work__c)) {
                    hasCurrentWork = true;
                } else if (employer.End_Date__c != null) {
                    if (latestEnd == null || employer.End_Date__c > latestEnd) {
                        latestEnd = employer.End_Date__c;
                    }
                }
            }
        
            // Format the date range for this country
            String countryLabel = getCountryLabel(countryCode);
            if (String.isBlank(countryLabel)) {
                countryLabel = countryCode; // Fallback to code if label not found
            }
        
            String startDateStr = earliestStart != null ? formatDate(earliestStart) : '';
            String endDateStr = hasCurrentWork ? 'current' : 
                           (latestEnd != null ? formatDate(latestEnd) : '');
        
            // Format: "Country: start_date - end_date"
            String countryDateString = countryLabel + ': ' + startDateStr + ' - ' + endDateStr;
            countryDateStrings.add(countryDateString);
        }
    
        // Join all country strings with semicolon
        reapply.Countries_names_with_dates__c = String.join(countryDateStrings, '; ');
    }

    private static String formatDate(Date dt) {
        if (dt == null) return '';
        // Format as dd/MM/yyyy
        Integer day = dt.day();
        Integer month = dt.month();
        Integer year = dt.year();
        return String.valueOf(day).leftPad(2, '0') + '/' + 
                String.valueOf(month).leftPad(2, '0') + '/' + 
                String.valueOf(year);
    }
    
    private static void mapEmploymentData(Reapply__c reapply, ApplicationDataWrapper data) {
        mapBeforeLeftUKEmployment(reapply, data.beforeLeftUK_Employer);
        mapAfterLeftUKEmployment(reapply, data.afterLeftUK_Employers, data.application);
    }
    
    private static void mapBeforeLeftUKEmployment(Reapply__c reapply, Employer__c employer) {
        if (employer == null) return;
        
        String employmentType = employer.Type_Of_UK_Employment__c;
        System.debug('mapEmploymentStatus: ' + mapEmploymentStatus(employmentType));
        reapply.employment_status_before_left_UK__c = mapEmploymentStatus(employmentType);
        
        if (EMPLOYMENT_TYPE_EMPLOYED.equals(employmentType)) {
            mapEmployedBeforeLeftUK(reapply, employer);
        } else if (EMPLOYMENT_TYPE_SELF_EMPLOYED.equals(employmentType)) {
            mapSelfEmployedBeforeLeftUK(reapply, employer);
        }
    }
    
    private static String mapEmploymentStatus(String employmentType) {
        if (EMPLOYMENT_TYPE_EMPLOYED.equals(employmentType)) {
            return EMPLOYMENT_STATUS_MAP_EMPLOYED;
        } else if (EMPLOYMENT_TYPE_SELF_EMPLOYED.equals(employmentType)) {
            return EMPLOYMENT_STATUS_MAP_SELF_EMPLOYED;
        } else if (EMPLOYMENT_TYPE_NOT_EMPLOYED.equals(employmentType) || EMPLOYMENT_TYPE_UNEMPLOYED.equals(employmentType)) {
            return EMPLOYMENT_STATUS_MAP_NEITHER;
        }
        return null;
    }
    
    private static void mapEmployedBeforeLeftUK(Reapply__c reapply, Employer__c employer) {
        reapply.Last_employer_Name__c = employer.Employer_Name__c;
        reapply.Last_employer_Address__PostalCode__s = employer.Employers_Address__PostalCode__s;
        reapply.Last_employer_Address__City__s = employer.Employers_Address__City__s;
        reapply.Last_employer_Address__Street__s = employer.Employers_Address__Street__s;
        reapply.Last_employment_ended_date__c = employer.End_Date__c;
    }
    
    private static void mapSelfEmployedBeforeLeftUK(Reapply__c reapply, Employer__c employer) {
        reapply.Has_your_UK_self_employment_ended__c = true;
        reapply.Uk_self_employment_ended_date__c = employer.End_Date__c;
    }
    
    private static void mapAfterLeftUKEmployment(Reapply__c reapply, List<Employer__c> afterLeftUKEmployers, Application__c app) {
        if (afterLeftUKEmployers.isEmpty()) return;
        
        List<Employer__c> emplEmployers = findEmployedEmployerAfterUK(afterLeftUKEmployers);
        if (emplEmployers.size() > 0) {
            mapEmployedAfterLeftUK(reapply, emplEmployers[0], app);
        } 
        if (emplEmployers.size() > 1) {
            reapply.Is_previously_worked_abroad_as_an_emp__c = true;
        }
        
        mapSelfEmployedAfterLeftUK(reapply, afterLeftUKEmployers);
        
        // Check for multiple employments
        //List<Employer__c> allEmployedEmployers = getEmployersByType(afterLeftUKEmployers, EMPLOYMENT_TYPE_EMPLOYED);
        if (afterLeftUKEmployers.size() > 1) {
            reapply.Any_other_employments_abroad__c = true;
        }
    }
    
    private static List<Employer__c> findEmployedEmployerAfterUK(List<Employer__c> employers) {
        List<Employer__c> employedEmployers = new List<Employer__c>();
         for (Employer__c empl : employers) {
            if (EMPLOYMENT_TYPE_EMPLOYED.equals(empl.Type_Of_After_UK_Employment__c)) {
                employedEmployers.add(empl);
            }
        }
        return employedEmployers;
    }
    
    private static void mapEmployedAfterLeftUK(Reapply__c reapply, Employer__c employer, Application__c app) {
        reapply.Is_previously_worked_abroad_as_an_emp__c = true;
        reapply.Employer_abroad_Name__c = employer.Employer_Name__c;
        reapply.Employer_abroad_Address__Street__s = employer.Employers_Address__Street__s;
        reapply.Employer_abroad_Address__City__s = employer.Employers_Address__City__s;
        reapply.Employer_abroad_Address__StateCode__s = employer.Employers_Address__StateCode__s;
        reapply.Employer_abroad_Address__PostalCode__s = employer.Employers_Address__PostalCode__s;
        reapply.Employer_abroad_Address__CountryCode__s = employer.Employers_Address__CountryCode__s;
        
        if (employer.End_Date__c != null && !CURRENT_WORK_YES.equals(employer.Current_Work__c)) {
            reapply.Employment_ceased_end_date__c = employer.End_Date__c;
        }

        if (employer.Start_Date__c != null) {
            reapply.Start_employment_date__c = employer.Start_Date__c;
        }       
        
        if (EMPLOYED_DIRECTLY_YES.equals(app.Employed_Direcly__c)) {
            reapply.Employer_an_overseas_gov_international__c = true;
        }
    }
    
    private static void mapSelfEmployedAfterLeftUK(Reapply__c reapply, List<Employer__c> afterLeftUKEmployers) {
        for (Employer__c empl : afterLeftUKEmployers) {
            if (EMPLOYMENT_TYPE_SELF_EMPLOYED.equals(empl.Type_Of_After_UK_Employment__c)) {
                reapply.Self_employed_abroad__c = true;
                reapply.Start_self_employment_abroad_date__c = empl.Start_Date__c;
                reapply.End_self_employment_abroad_date__c = !CURRENT_WORK_YES.equals(empl.Current_Work__c) ? empl.End_Date__c : null;
                break;
            }
        }
    }
    
    private static List<Employer__c> getEmployersByType(List<Employer__c> employers, String type) {
        List<Employer__c> result = new List<Employer__c>();
        for (Employer__c empl : employers) {
            if (type.equals(empl.Type_Of_After_UK_Employment__c)) {
                result.add(empl);
            }
        }
        return result;
    }

    private static String getCountryLabel(String countryCode) {
        if (String.isBlank(countryCode)) {
            return null;
        }
        return countryCodeToLabel.get(countryCode);
    }
    
    // Wrapper class for data aggregation
    private class ApplicationDataWrapper {
        public Application__c application;
        public List<Application__History> appHistories;
        public Employer__c beforeLeftUK_Employer;
        public List<Employer__c> afterLeftUK_Employers;
    }

    public class ReapplyException extends Exception {
    }
}