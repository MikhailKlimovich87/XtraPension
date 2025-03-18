public class DocumentEditorController {
    public class EditModalWrapper {
        @AuraEnabled
        public List<Employer__c> abroadEmployers {get; set;}
        @AuraEnabled
        public Employer__c lastUkEmployer{get; set;}
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
    }
    public static Application__c currentApp;
    public static final Map<String, String> TEMPLATE_NAME_TO_APPLICATION_FIELD = new Map<String, String> {
        'NINO'                => 'NINO_Template__c',
        'CUSTOM'              => 'Custom_Reply_Template__c',
        'APPEAL'              => 'Appeal_Template__c',
        'CURRENT JOB'         => 'Current_Job_Reply_Template__c',
        'DWP STATUS CHECK'    => 'DWP_Status_Check_Template__c',
        'CERTIFIED DOC'       => 'Certified_Doc_Template__c',
        'EU RESIDENCY APPEAL' => 'EU_Residency_Appeal_Template__c',
        'MAIDEN NAME'         => 'Maiden_Name_Template__c',
        'DWP C2 REQUEST'      => 'DWP_C2_Request_Template__c'
    };
    public static final Map<String, String> TEMPLATE_NAME_TO_BODY_DATA = new Map<String, String> {
        'NINO'                => XtraPensionConstants.NINO_TEMPLATE,
        'CUSTOM'              => XtraPensionConstants.CUSTOM_TEMPLATE,
        'APPEAL'              => XtraPensionConstants.APPEAL_TEMPLATE,
        'CURRENT JOB'         => XtraPensionConstants.CURRENT_JOB_TEMPLATE,
        'DWP STATUS CHECK'    => XtraPensionConstants.DWP_STATUS_CHECK_TEMPLATE,
        'CERTIFIED DOC'       => XtraPensionConstants.CERTIFIED_DOC_TEMPLATE,
        'EU RESIDENCY APPEAL' => XtraPensionConstants.EU_RESIDENCY_APPEAL_TEMPLATE,
        'MAIDEN NAME'         => XtraPensionConstants.MAIDEN_NAME,
        'DWP C2 REQUEST'      => XtraPensionConstants.DWP_C2_REQUEST
    };

    @AuraEnabled(cacheable='true')
    public static EditModalWrapper getEmailTemplateData(String applicationId) {
        EditModalWrapper resultWrapper = new EditModalWrapper();
        resultWrapper.abroadEmployers = new List<Employer__c>();
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
                Certified_Doc_Template__c,
                EU_Residency_Appeal_Template__c,
                Maiden_Name_Template__c,
                DWP_C2_Request_Template__c,
                Date_Of_Marriage_Or_Civil_Partnership__c,
                Date_Of_Leaving_Last_UK__c,
                First_Name__c,
                Second_Name__c,
                Email__c,
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
                        Type__c
                    FROM Employers__r)
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
                bodyData.htmlValue = replaceKeyWords(TEMPLATE_NAME_TO_BODY_DATA.get(name), currentApplication);
            } else {
                bodyData.htmlValue = replaceKeyWords(fieldValue, currentApplication);
            }
            bodyData.templateName = name;
            templates.add(bodyData);
        }
        resultWrapper.htmlInfo.addAll(templates);
        if (currentApplication.Employers__r.size() != 0) {
            for (Employer__c empl : currentApplication.Employers__r) {
                if (empl.Type__c == 'UK Work') {
                    resultWrapper.lastUkEmployer = empl;
                } else if (empl.Type__c == 'Work After UK') {
                    resultWrapper.abroadEmployers.add(empl);
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
                DWP_C2_Request_Template__c
            FROM Application__c
            WHERE Id = :messageData.applicationId
        ];
        if (messageData == null) {
            return 'Didn\'t find any applications';
        }
        Application__c currentApp = applicaitons[0];
        String fieldName = TEMPLATE_NAME_TO_APPLICATION_FIELD.get(messageData.typeOfTemplate.toUpperCase('en'));
        currentApp.put(fieldName, messageData.fieldValue);
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

        return resultData.replace('{FullName}', currentApplication?.First_Name__c + ' ' + currentApplication?.Second_Name__c)
                         .replace('{First Name}', currentApplication?.First_Name__c);
    }
}