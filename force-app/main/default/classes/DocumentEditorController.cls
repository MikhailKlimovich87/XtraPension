public class DocumentEditorController {
    public class EditModalWrapper {
        @AuraEnabled
        public List<EmployerData> abroadEmployers {get; set;}
        @AuraEnabled
        public EmployerData lastUkEmployer{get; set;}
        @AuraEnabled
        public List<HTMLData> htmlInfo{get; set;}
    }
    public class HTMLData {
        @AuraEnabled
        public String templateName{get; set;}
        @AuraEnabled
        public String htmlValue{get; set;}
    }

    public class MessageData {
        @AuraEnabled
        public String applicationId{get; set;}
        @AuraEnabled
        public String fieldValue{get; set;}
        @AuraEnabled
        public String typeOfTemplate{get; set;}
        @AuraEnabled
        public Date dateOfReply{get; set;}
    }

    public class EmployerData {
        @AuraEnabled
        public String startDate{get; set;}
        @AuraEnabled
        public String endDate{get; set;}
        @AuraEnabled
        public String employerName{get; set;}
        @AuraEnabled
        public String addressData {get; set;}
        @AuraEnabled
        public Integer numberOfEmployer {get; set;}
        @AuraEnabled
        public Boolean includeEmployer {get; set;}
        @AuraEnabled
        public String checkboxFieldName{get; set;}
        @AuraEnabled
        public String employerId{get; set;}
        @AuraEnabled
        public Boolean isEmployedType{get; set;}
        @AuraEnabled
        public Boolean currentWork {get; set;}
        @AuraEnabled
        public String employerType{get; set;}
    }

    public static Application__c currentApp;
    public static final Map<String, String> TEMPLATE_NAME_TO_APPLICATION_FIELD = new Map<String, String> {
        'NINO'                                             => 'NINO_Template__c',
        'CUSTOM'                                           => 'Custom_Reply_Template__c',
        'APPEAL'                                           => 'Appeal_Template__c',
        'CURRENT JOB'                                      => 'Current_Job_Reply_Template__c',
        'DWP STATUS CHECK'                                 => 'DWP_Status_Check_Template__c',
        'CERTIFIED DOC'                                    => 'Certified_Doc_Template__c',
        'EU RESIDENCY APPEAL'                              => 'EU_Residency_Appeal_Template__c',
        'MAIDEN NAME'                                      => 'Maiden_Name_Template__c',
        'DWP C2 REQUEST'                                   => 'DWP_C2_Request_Template__c',
        'BOUNCE LETTER'                                    => 'Bounce_Letter_Template__c',
        '64-8 UPDATE LETTER'                               => 'Update_Letter_Template__c',
        'EU RESIDENCY LETTER'                              => 'EU_Residency_Letter_Template__c',
        'REPLY TO \'EU C2 & C3 REJECTION\''                => 'Reply_to_EU_C2_C3_Rejection_Template__c',
        'CLASS3 APPEAL DESPITE 3+ YEARS'                   => 'Class_3_Appeal_Despite_3_Years_Template__c',
        'BAD / ERROR IN C2 DECISION'                       => 'Bad_Error_In_C2_Decision_Template__c',
        'NO SHORTFALL TABLE PROVIDED'                      => 'No_Shortfall_Table_Provided_Template__c',
        'CUSTOM CARNAGE (EG STEWART-LORD!)'                => 'Custom_Carnage_Template__c',
        'MISSING CORRESPONDENCE'                           => 'Missing_Correspondence_Template__c',
        'CF83 NOT RECEIVED LETTER AGAIN TO HMRC'           => 'CF83_NOT_Received_letter_again_Template__c',
        'LATE PAYMENT APPEAL'                              => 'Late_Payment_Appeal_Template__c',
        'HIGHER LEVEL / STAGE 2 APPEAL > STATUTORY REVIEW' => 'Higher_Level_Appeal_Template__c'

    };
    public static final Map<String, String> TEMPLATE_NAME_TO_BODY_DATA = new Map<String, String> {
        'NINO'                                             => XtraPensionConstants.NINO_TEMPLATE,
        'CUSTOM'                                           => XtraPensionConstants.CUSTOM_TEMPLATE,
        'APPEAL'                                           => XtraPensionConstants.APPEAL_TEMPLATE,
        'CURRENT JOB'                                      => XtraPensionConstants.CURRENT_JOB_TEMPLATE,
        'DWP STATUS CHECK'                                 => XtraPensionConstants.DWP_STATUS_CHECK_TEMPLATE,
        'CERTIFIED DOC'                                    => XtraPensionConstants.CERTIFIED_DOC_TEMPLATE,
        'EU RESIDENCY APPEAL'                              => XtraPensionConstants.EU_RESIDENCY_APPEAL_TEMPLATE,
        'MAIDEN NAME'                                      => XtraPensionConstants.MAIDEN_NAME,
        'BOUNCE LETTER'                                    => XtraPensionConstants.BOUNCE_LETTER,
        '64-8 UPDATE LETTER'                               => XtraPensionConstants.UPDATE_LETTER,
        'EU RESIDENCY LETTER'                              => XtraPensionConstants.EU_RESIDENCY_LETTER_TEMPLATE,
        'REPLY TO \'EU C2 & C3 REJECTION\''                => XtraPensionConstants.REPLY_TO_EU_C2_C3_REJECTION_TEMPLATE,
        'CLASS3 APPEAL DESPITE 3+ YEARS'                   => XtraPensionConstants.CLASS_3_APPEAL_DESPITE_3_PLUS_YEARS_TEMPLATE,
        'BAD / ERROR IN C2 DECISION'                       => XtraPensionConstants.BAD_ERROR_IN_C2_DECISION_TEMPLATE,
        'NO SHORTFALL TABLE PROVIDED'                      => XtraPensionConstants.NO_SHORTFALL_TABLE_PROVIDED_TEMPLATE,
        'CUSTOM CARNAGE (EG STEWART-LORD!)'                => XtraPensionConstants.CUSTOM_CARNAGE_EG_STEWART_LORD_TEMPLATE,
        'MISSING CORRESPONDENCE'                           => XtraPensionConstants.MISSING_CORRESPONDENCE_TEMPLATE,
        'CF83 NOT RECEIVED LETTER AGAIN TO HMRC'           => XtraPensionConstants.CF83_NOT_Received_Letter_Again_To_HMRC_TEMPLATE,
        'LATE PAYMENT APPEAL'                              => XtraPensionConstants.LATE_PAYMENT_APPEAL_TEMPLATE,
        'HIGHER LEVEL / STAGE 2 APPEAL > STATUTORY REVIEW' => XtraPensionConstants.HIGHER_LEVEL_STAGE2_APPEAL_STATUTORY_REVIEW_TEMPLATE
    };

    @AuraEnabled(cacheable='true')
    public static EditModalWrapper getEmailTemplateData(String applicationId) {
        EditModalWrapper resultWrapper = new EditModalWrapper();
        resultWrapper.abroadEmployers = new List<EmployerData>();
        resultWrapper.htmlInfo = new List<HTMLData>();
        List<HTMLData> templates = new List<HTMLData>();
        List<Application__c> applications = [
            SELECT
                Name,
                NINO_Template__c,
                HMRC_Ref__c,
                National_Insurance_Number__c,
                Custom_Reply_Template__c,
                Appeal_Template__c,
                Full_Maiden_Previous_Name__c,
                Current_Job_Reply_Template__c,
                DWP_Status_Check_Template__c,
                Bounce_Letter_Template__c,
                Certified_Doc_Template__c,
                EU_Residency_Appeal_Template__c,
                Maiden_Name_Template__c,
                DWP_C2_Request_Template__c,
                Update_Letter_Template__c,
                EU_Residency_Letter_Template__c,
                Class_3_Appeal_Despite_3_Years_Template__c,
                Bad_Error_In_C2_Decision_Template__c,
                No_Shortfall_Table_Provided_Template__c,
                Custom_Carnage_Template__c,
                Missing_Correspondence_Template__c,
                CF83_NOT_Received_letter_again_Template__c,
                Late_Payment_Appeal_Template__c,
                Higher_Level_Appeal_Template__c,
                Date_Of_Marriage_Or_Civil_Partnership__c,
                Date_Of_Leaving_Last_UK__c,
                CurrencyIsoCode,
                First_Name__c,
                Second_Name__c,
                Reply_to_EU_C2_C3_Rejection_Template__c,
                Email__c,
                DWP_Callback_Request__c,
                Tracking_Number_Received_Date__c,
                Letter_Date__c,
                    (SELECT
                        Employer_Name__c,
                        Start_Date__c,
                        End_Date__c,
                        Employers_Address__Street__s,
                        Employers_Address__City__s,
                        toLabel(Employers_Address__CountryCode__s),
                        toLabel(Employers_Address__StateCode__s),
                        Employers_Address__PostalCode__s,
                        Employers_Address_Country__c,
                        Type_Of_UK_Employment__c,
                        Type_Of_After_UK_Employment__c,
                        Type__c,
                        Current_Work__c,
                        Add_to_custom_letter__c
                    FROM Employers__r
                    ORDER BY Start_Date__c)
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        if (applications.isEmpty()) {
            return null;
        }
        if (applications.size() == 0) {
            return null;
        }
        Application__c currentApplication = applications[0];
        for (String name : TEMPLATE_NAME_TO_APPLICATION_FIELD.keySet()) {
            HTMLData bodyData = new HTMLData();
            String fieldValue = (String)currentApplication.get(TEMPLATE_NAME_TO_APPLICATION_FIELD.get(name));
            if (fieldValue == null) {
                String templateBody = name != 'DWP C2 REQUEST' ?
                                        TEMPLATE_NAME_TO_BODY_DATA.get(name) :
                                        name == 'DWP C2 REQUEST' && currentApplication.CurrencyIsoCode == 'EUR' ?
                                            XtraPensionConstants.DWP_C2_REQUEST_EUROPE :
                                            name == 'DWP C2 REQUEST' && currentApplication.CurrencyIsoCode != 'EUR' ?
                                                XtraPensionConstants.DWP_C2_REQUEST_OUTSIDE_EUROPE :
                                                null;
                bodyData.htmlValue = replaceKeyWords(templateBody, currentApplication);
            } else {
                bodyData.htmlValue = replaceKeyWords(fieldValue, currentApplication);
            }
            bodyData.templateName = name;
            templates.add(bodyData);
        }
        resultWrapper.htmlInfo.addAll(templates);
        if (currentApplication.Employers__r.size() != 0) {
            for (Employer__c empl : currentApplication.Employers__r) {
                if (empl.Type__c == 'UK Work' && empl.Type__c != 'Not employed') {
                    EmployerData lastUKEmployer = new EmployerData();
                    lastUKEmployer.employerName = empl.Type_Of_UK_Employment__c == 'Employed' ?
                        empl.Employer_Name__c :
                        '';
                    lastUKEmployer.startDate = empl.Start_Date__c != null ?
                        ((Datetime)empl.Start_Date__c).format('EEE dd MMM yyyy') :
                        null;
                    lastUKEmployer.endDate   = empl.End_Date__c != null ?
                        ((Datetime)empl.End_Date__c).format('EEE dd MMM yyyy') :
                        null;
                    lastUKEmployer.addressData = empl.Type_Of_UK_Employment__c == 'Employed' ?
                        empl.Employers_Address__Street__s + ', ' +
                        empl.Employers_Address__City__s + ', ' +
                        empl.Employers_Address__PostalCode__s + ', ' +
                        empl.Employers_Address__CountryCode__s :
                        '';
                    lastUKEmployer.employerType = empl.Type_Of_UK_Employment__c;
                    resultWrapper.lastUkEmployer = lastUKEmployer;
                } else if (empl.Type__c == 'Work After UK') {
                    EmployerData abroadEmplolyer = new EmployerData();
                    abroadEmplolyer.employerName = empl.Employer_Name__c;
                    abroadEmplolyer.startDate = empl?.Start_Date__c != null ? ((Datetime)empl?.Start_Date__c).format('EEE dd MMM yyyy') : '';
                    abroadEmplolyer.endDate =  empl?.End_Date__c == null ? '' : ((Datetime)empl?.End_Date__c).format('EEE dd MMM yyyy');
                    if (empl.Type_Of_After_UK_Employment__c == 'Employed') {
                        abroadEmplolyer.isEmployedType = true;
                        abroadEmplolyer.employerType = 'Employed';
                        abroadEmplolyer.addressData = (String) empl.Employers_Address__Street__s  + ', ' +
                                                      ((String) empl.Employers_Address__City__s == null ? '' : (String) empl.Employers_Address__City__s + ', ' ) +
                                                      ((String) empl.Employers_Address__PostalCode__s == null ? '' : (String) empl.Employers_Address__PostalCode__s + ', ' ) +
                                                     (String) empl.Employers_Address__CountryCode__s;
                        abroadEmplolyer.currentWork = empl.Current_Work__c == 'Yes' ? true : false;
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Career Break') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Career Break';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Self-Employed';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Unemployed') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Unemployed';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Family Carer') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Family Carer';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Homemaker') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Homemaker';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Disabled') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Disabled';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Retired') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Retired';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Education') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Education';
                    } else if (empl.Type_Of_After_UK_Employment__c == 'Illness') {
                        abroadEmplolyer.isEmployedType = false;
                        abroadEmplolyer.employerType = 'Illness';
                    }
                    abroadEmplolyer.employerId = empl.Id;
                    abroadEmplolyer.includeEmployer = empl.Add_to_custom_letter__c;
                    resultWrapper.abroadEmployers.add(abroadEmplolyer);
                }
            }
        }
        return resultWrapper;
    }

    @AuraEnabled
    public static Id generateHMRCReplyFile(MessageData messageData) {
        if (messageData == null) {
            return 'Didn\'t get data';
        }
        List<Application__c> applicaitons = [
            SELECT
                NINO_Template__c,
                Custom_Reply_Template__c,
                Appeal_Template__c,
                Current_Job_Reply_Template__c,
                DWP_Status_Check_Template__c,
                Certified_Doc_Template__c,
                EU_Residency_Appeal_Template__c,
                Maiden_Name_Template__c,
                DWP_C2_Request_Template__c,
                HMRC_Reply_Doc_Generate_Date__c,
                Bounce_Letter_Template__c,
                Update_Letter_Template__c,
                EU_Residency_Letter_Template__c,
                Class_3_Appeal_Despite_3_Years_Template__c,
                Bad_Error_In_C2_Decision_Template__c,
                No_Shortfall_Table_Provided_Template__c,
                Custom_Carnage_Template__c,
                Missing_Correspondence_Template__c,
                CF83_NOT_Received_letter_again_Template__c,
                Late_Payment_Appeal_Template__c,
                Reply_to_EU_C2_C3_Rejection_Template__c,
                Higher_Level_Appeal_Template__c
            FROM Application__c
            WHERE Id = :messageData.applicationId
        ];
        if (messageData == null) {
            return 'Didn\'t find any applications';
        }
        Application__c currentApp = applicaitons[0];
        String fieldName = TEMPLATE_NAME_TO_APPLICATION_FIELD.get(messageData.typeOfTemplate.toUpperCase('en'));
        System.debug(fieldName);
        System.debug(messageData.fieldValue);
        currentApp.put(fieldName, messageData.fieldValue);
        currentApp.put('HMRC_Reply_Doc_Generate_Date__c', messageData.dateOfReply);
        Database.update(currentApp);

        Id jobID = System.enqueueJob(new HMRCRepliesDocsGenerator(currentApp.Id, fieldName));
        return jobID;
    }

    private static String replaceKeyWords(String bodyData, Application__c currentApplication) {
        String resultData = bodyData.replace('{TodayDate}', String.valueOf(Date.today().format()));
        if(currentApplication.HMRC_Ref__c != null) resultData = resultData.replace('{Customer Email}', currentApplication?.Email__c);
        if(currentApplication.HMRC_Ref__c != null) resultData = resultData.replace('{HMRC Ref}', currentApplication?.HMRC_Ref__c);
        if(currentApplication.Name != null) resultData = resultData.replace('{AppName}', currentApplication?.Name);
        if(currentApplication.National_Insurance_Number__c != null) resultData = resultData.replace('{NINO}', currentApplication?.National_Insurance_Number__c);
        if(currentApplication.Second_Name__c != null) resultData = resultData.replace('{Married_Name}', currentApplication?.Second_Name__c);
        if(currentApplication.Full_Maiden_Previous_Name__c != null) resultData = resultData.replace('{Maiden_Name}', currentApplication?.Full_Maiden_Previous_Name__c);
        if(currentApplication.Date_Of_Marriage_Or_Civil_Partnership__c != null) resultData = resultData.replace('{Date_of_Marriage}', String.valueOf(currentApplication?.Date_Of_Marriage_Or_Civil_Partnership__c.format()));
        if(currentApplication.Date_Of_Leaving_Last_UK__c != null) resultData = resultData.replace('{DateOfLeavingUK}', String.valueOf(currentApplication?.Date_Of_Leaving_Last_UK__c.format()));
        if(currentApplication.DWP_Callback_Request__c != null) resultData = resultData.replace('[DWP Callback Request]', currentApplication?.DWP_Callback_Request__c);
        if(currentApplication.Tracking_Number_Received_Date__c != null) resultData = resultData.replace('[PH1 Reply Date]', String.valueOf(currentApplication?.Tracking_Number_Received_Date__c.format()));
        if(currentApplication.Letter_Date__c != null) resultData = resultData.replace('[Letter Date]', String.valueOf(currentApplication?.Letter_Date__c.format()));

        Employer__c lastUKEmployer;
        Employer__c firstAfterUKEmployer;
        for(Employer__c empl : currentApplication.Employers__r) {
            if (firstAfterUKEmployer == null && empl.Type__c == 'Work After UK') {
                firstAfterUKEmployer = empl;
            }
            if (lastUKEmployer == null && empl.Type__c == 'UK Work') {
                lastUKEmployer = empl;
            }
            if(lastUKEmployer != null && firstAfterUKEmployer != null) break;
        }
        if(lastUKEmployer != null) {
            resultData = resultData.replace('[UK Work Employer Name]',
                                             lastUKEmployer.Employer_Name__c != null ? lastUKEmployer.Employer_Name__c : lastUKEmployer.Type_Of_UK_Employment__c
                                            );
            resultData = resultData.replace('[Left UK]', String.valueOf(lastUKEmployer?.End_Date__c.format()));
        } else {
            resultData = resultData.replace('[UK Work Employer Name]', '');
            resultData = resultData.replace('[Left UK]', '');
        }
        if(firstAfterUKEmployer != null) {
            resultData = resultData.replace('[Abroad Start Date]', String.valueOf(firstAfterUKEmployer?.Start_Date__c.format()));
            resultData = resultData.replace('[First Work After UK Employer Name]',
                                             firstAfterUKEmployer?.Employer_Name__c != null ? firstAfterUKEmployer?.Employer_Name__c : firstAfterUKEmployer?.Type_Of_After_UK_Employment__c
                                            );
        } else {
            resultData = resultData.replace('[Abroad Start Date]', '');
            resultData = resultData.replace('[First Work After UK Employer Name]', '');
        }
        return resultData.replace('{FullName}', currentApplication?.First_Name__c + ' ' + currentApplication?.Second_Name__c)
                         .replace('{First Name}', currentApplication?.First_Name__c);
    }
}