public with sharing class DocumentEditorControllerHelper {
    public static String replaceKeyWords(String bodyData, Application__c currentApplication, List<Employer__c> employers) {
        String resultData = bodyData.replace('{TodayDate}', String.valueOf(Date.today().format()));
        Boolean hasOnlyEmployedSelEmployedEmployers = false;
        for(Employer__c empl : employers) {
            if (empl.Type__c != 'Work After UK') continue;
            if (empl.Type_Of_After_UK_Employment__c == 'Employed' || empl.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                continue;
            } else {
                hasOnlyEmployedSelEmployedEmployers = true;
                break;
            }
        }
        
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
        for(Employer__c empl : employers) {
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
        if (hasOnlyEmployedSelEmployedEmployers == true
        && resultData.contains('{Began_Overseas_Employment}')) {
                                    resultData = resultData.replace('{Began_Overseas_Employment}', '');
                                } else if(hasOnlyEmployedSelEmployedEmployers == false
                                && resultData.contains('{Began_Overseas_Employment}')) {
                                                            resultData = resultData.replace(
                                                                '{Began_Overseas_Employment}',
                                                            '<li>Began overseas employment on <b>[Abroad Start Date]</b> with <b>[First Work After UK Employer Name].</b></li>'
                                                                );
                                                        }
                                                        return resultData.replace('{FullName}', currentApplication?.First_Name__c + ' ' + currentApplication?.Second_Name__c)
                                                            .replace('{First Name}', currentApplication?.First_Name__c);
                                                    }
                                                    
                                                }