public without sharing class ClearingHouseController {
    private final static String NO_NINO_STYLE = 'background:red';
    private final static String ALL_DATA_STYLE = 'background:green';
    private final static String PARTIAL_DATA_STYLE = 'background:yellow';
    private final static String NINO_STYLE = 'background:none';

    @AuraEnabled(cacheable='true')
    public static CleaningHouseTableWrapper getApplications() {
        CleaningHouseTableWrapper resultData = new CleaningHouseTableWrapper();
        resultData.tableUp = new List<CleaningHouseWrapper>();
        resultData.tableDown = new List<CleaningHouseWrapper>();
        List<Application__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name,
                Status__c,
                National_Insurance_Number__c,
                Full_Maiden_Previous_Name__c,
                Marital_status__c,
                Age__c,
                Years_Of_Work_In_The_UK__c,
                Agent_Making_Sale__c,
                Purchased__c,
                Date_Of_Leaving_Last_UK__c,
                (SELECT
                    Type__c,
                    Type_Of_UK_Employment__c,
                    Type_Of_After_UK_Employment__c,
                    Employers_Address__City__s,
                    Employers_Address__PostalCode__s,
                    Employers_Address__Street__s,
                    toLabel(Employers_Address__CountryCode__s),
                    Start_Date__c,
                    End_Date__c,
                    Current_Work__c
                FROM Employers__r
                ORDER BY Start_Date__c),
                (SELECT Id
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%UPLOAD%')
            FROM Application__c
            WHERE Status__c = 'Form In Progress' OR
                  Status__c = 'Form Completed' OR
                  Status__c = 'NINO/Doc Needed' OR
                  Status__c = 'Pending Client' OR
                  Status__c = 'Fix'
            ORDER BY CreatedDate DESC
        ];
        if (apps.isEmpty()) {
            return null;
        }
        List<CleaningHouseWrapper> dataUp = new List<CleaningHouseWrapper>();
        List<CleaningHouseWrapper> dataDown = new List<CleaningHouseWrapper>();
        Integer counter = 0;
        Integer counterNINO_PRSI = 0;
        Integer counterNINO_NoPRSI = 0;
        Integer counterNoNINO_PRSI = 0;
        Integer counterNoNINO_NoPRSI = 0;
        for(Application__c app : apps) {
            CleaningHouseWrapper currApp = new CleaningHouseWrapper();
            currApp.app = app;
            if (app.National_Insurance_Number__c != null &&
                app.ContentDocumentLinks.size() != 0) {
                currApp.rowStyle = ALL_DATA_STYLE;
            } else if (app.National_Insurance_Number__c != null &&
                       app.ContentDocumentLinks.size() == 0) {
                currApp.rowStyle = PARTIAL_DATA_STYLE;
            } else {
                currApp.rowStyle = NINO_STYLE;
            }
            currApp.noNINO_Style = app.National_Insurance_Number__c == null ?
                                    NO_NINO_STYLE :
                                    NINO_STYLE;
            currApp.doc = app.ContentDocumentLinks.size() == 0 ?
                            'Missing':
                            'Yes';
            currApp.docStyle = app.ContentDocumentLinks.size() == 0 ?
                                  NO_NINO_STYLE :
                                  null;
            if (String.isBlank(app.Full_Maiden_Previous_Name__c) && (app.Marital_status__c == 'Married' || app.Marital_status__c == 'Divorced' || app.Marital_status__c == 'Bereaved')) {
                currApp.fullMaidenNameStyle = NO_NINO_STYLE;
            }
            List<Employer__c> currAfterUKEmpls = new List<Employer__c>();
            Integer startGapYear;
            Integer yearOfLeavingUK = Date.valueOf(app.Date_Of_Leaving_Last_UK__c)?.year();
            if (yearOfLeavingUK != null && yearOfLeavingUK <= 2006) {
                startGapYear = 2006;
            } else if (yearOfLeavingUK != null && yearOfLeavingUK > 2006) {
                startGapYear = yearOfLeavingUK;
            } else startGapYear = 2006;
            Set<String> employersCountryName = new Set<String>();
            for (Employer__c empl : app.Employers__r) {

                if (empl.Type__c == 'UK Work' && currApp.lastUKEmplType == null) {
                    currApp.lastUKEmplType = empl.Type_Of_UK_Employment__c;
                    currApp.lastUKEmplAddress = empl.Employers_Address__Street__s != null ?
                                                    empl.Employers_Address__Street__s :
                                                    '';
                    currApp.lastUKEmplAddress += empl.Employers_Address__City__s != null ?
                                                    '\n ' + empl.Employers_Address__City__s :
                                                    '';
                    currApp.lastUKEmplAddress += empl.Employers_Address__PostalCode__s != null ?
                                                    '\n ' + empl.Employers_Address__PostalCode__s :
                                                    '';
                }
                if (empl.Type__c == 'Work After UK' &&
                    (Date.valueOf(empl?.Start_Date__c)?.year() >= startGapYear ||
                    Date.valueOf(empl?.Start_Date__c)?.year() <= startGapYear && Date.valueOf(empl?.End_Date__c)?.year() >= startGapYear) &&
                    currApp.workAfter2006 == null) {
                    currApp.workAfter2006 = empl.Type_Of_After_UK_Employment__c;
                }
                if (empl.Type__c == 'Work After UK' && (Date.valueOf(empl?.Start_Date__c)?.year() >= startGapYear || Date.valueOf(empl?.End_Date__c)?.year() >= startGapYear)) {
                    currAfterUKEmpls.add(empl);
                    if (empl.Employers_Address__CountryCode__s != null) {
                        employersCountryName.add(empl.Employers_Address__CountryCode__s);
                    }
                }
            }
            if (!employersCountryName.isEmpty()) {
                List<String> currEmplCountries = new List<String>(employersCountryName);
                for (Integer i = 0; i < currEmplCountries.size(); i++) {
                    if (i == 0) {
                        currApp.abroadEmplCountries = currEmplCountries.get(i);
                    } else {
                        currApp.abroadEmplCountries += '\n' + currEmplCountries.get(i);
                    }
                }
            }
            if (currApp.workAfter2006 == null) {
                currApp.workAfter2006Style = NO_NINO_STYLE;
            }

            Integer gap;
            if (!currAfterUKEmpls.isEmpty()) {
                gap = 0;
                for (Integer i = 0; i < currAfterUKEmpls.size(); i++) {
                    if (currAfterUKEmpls[i]?.Start_Date__c == null ||
                        currAfterUKEmpls[i]?.End_Date__c == null) continue;
                    if(currAfterUKEmpls.size() == 1) {
                        Integer startYear = Date.valueOf(currAfterUKEmpls[i]?.Start_Date__c)?.year();
                        Integer endYear = Date.valueOf(currAfterUKEmpls[i]?.End_Date__c)?.year();
                        if (startYear >= startGapYear) {
                            gap = startYear - startGapYear;
                        }
                        if (currAfterUKEmpls[i].Current_Work__c == 'No' && endYear >= 2006) {
                            gap += (Date.today().year() - endYear);
                        } else if (currAfterUKEmpls[i].Current_Work__c == 'No' && endYear < 2006) {
                            gap += (Date.today().year() - 2006);
                        }
                        break;
                    }
                    if(currAfterUKEmpls.size() > 1 && i == 0) {
                        Integer startYear = Date.valueOf(currAfterUKEmpls[i]?.Start_Date__c)?.year();
                        if (startYear > startGapYear) gap = startYear - startGapYear - 1;
                        continue;
                    }
                    if (currAfterUKEmpls[i - 1]?.End_Date__c == null) continue;
                    if (currAfterUKEmpls.size() > 1 && i > 0 && i != currAfterUKEmpls.size() - 1) {
                        Integer difference = Date.valueOf(currAfterUKEmpls[i]?.Start_Date__c)?.year() - Date.valueOf(currAfterUKEmpls[i-1]?.End_Date__c)?.year() - 1;
                        if (difference >= 1) {
                            gap += difference;
                        }
                        continue;
                    }
                    if (currAfterUKEmpls.size() > 1 && i == currAfterUKEmpls.size() - 1 && currAfterUKEmpls[i].Current_Work__c == 'No') {
                        Integer differenceNow = Date.today().year() - Date.valueOf(currAfterUKEmpls[i]?.End_Date__c)?.year();
                        if (differenceNow >= 1) {
                            gap += differenceNow;
                        }
                    }
                }
            } else gap = 18;
            currApp.gapYrsAfter2006 = gap;
            if (gap > 0) {
                currApp.gapStyle = NO_NINO_STYLE;
            }
            if (currApp.lastUKEmplType == 'Employed' && String.isBlank(currApp.lastUKEmplAddress)) {
                currApp.lastUKEmplAddressStyle = NO_NINO_STYLE;
            }
            if (counter < 5) dataUp.add(currApp);
            else dataDown.add(currApp);

            if (app.National_Insurance_Number__c != null && app.ContentDocumentLinks.size() != 0) {
                counterNINO_PRSI++;
            } else if (app.National_Insurance_Number__c != null && app.ContentDocumentLinks.size() == 0) {
                counterNINO_NoPRSI++;
            } else if (app.National_Insurance_Number__c == null && app.ContentDocumentLinks.size() != 0) {
                counterNoNINO_PRSI++;
            } else if (app.National_Insurance_Number__c == null && app.ContentDocumentLinks.size() == 0) {
                counterNoNINO_NoPRSI++;
            }
            counter++;
        }
        CleaningHouseTotalResultWrapper totalResultWrapper = new CleaningHouseTotalResultWrapper();
        totalResultWrapper.amountNINO_PRSI = counterNINO_PRSI;
        totalResultWrapper.amountNINO_NoPRSI = counterNINO_NoPRSI;
        totalResultWrapper.amountNoNINO_PRSI = counterNoNINO_PRSI;
        totalResultWrapper.amountNoNINO_NoPRSI = counterNoNINO_NoPRSI;
        totalResultWrapper.total = apps.isEmpty() ? 0 : apps.size();
        resultData.totalResult = totalResultWrapper;
        if(!dataUp.isEmpty()) {
            resultData.tableUp.addAll(dataUp);
        }
        if(!dataDown.isEmpty()) {
            resultData.tableDown.addAll(dataDown);
        }
        return resultData;
    }

    public class CleaningHouseTableWrapper {
        @AuraEnabled
        public List<CleaningHouseWrapper> tableUp{get; set;}
        @AuraEnabled
        public List<CleaningHouseWrapper> tableDown{get; set;}
        @AuraEnabled
        public CleaningHouseTotalResultWrapper totalResult {get; set;}
    }

    public class CleaningHouseWrapper {
        @AuraEnabled
        public Application__c app{get; set;}
        @AuraEnabled
        public String noNINO_Style{get; set;}
        @AuraEnabled
        public String fullMaidenNameStyle{get; set;}
        @AuraEnabled
        public String doc{get; set;}
        @AuraEnabled
        public String docStyle{get; set;}
        @AuraEnabled
        public String lastUKEmplType{get; set;}
        @AuraEnabled
        public String lastUKEmplAddress{get; set;}
        @AuraEnabled
        public String lastUKEmplAddressStyle{get; set;}
        @AuraEnabled
        public String workAfter2006{get; set;}
        @AuraEnabled
        public String workAfter2006Style{get; set;}
        @AuraEnabled
        public Integer gapYrsAfter2006{get; set;}
        @AuraEnabled
        public String gapStyle{get; set;}
        @AuraEnabled
        public String rowStyle {get; set;}
        @AuraEnabled
        public String  abroadEmplCountries{get; set;}
    }

    public class CleaningHouseTotalResultWrapper {
        @AuraEnabled
        public Integer total {get; set;}
        @AuraEnabled
        public Integer  amountNINO_PRSI{get; set;}
        @AuraEnabled
        public Integer amountNINO_NoPRSI {get; set;}
        @AuraEnabled
        public Integer amountNoNINO_PRSI {get; set;}
        @AuraEnabled
        public Integer amountNoNINO_NoPRSI {get; set;}
    }
}