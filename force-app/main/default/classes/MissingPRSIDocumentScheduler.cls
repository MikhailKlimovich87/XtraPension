public class MissingPRSIDocumentScheduler implements Schedulable{
    public void execute(SchedulableContext SC) {
        List<Application__c> updatedApps = new List<Application__c>();
        for (Application__c app : [ SELECT
                                        Contain_Docs__c,
                                        Type_Of_Employment__c,
                                        Last_UK_Emp_Addr__c,
                                        Last_UK_Employer_Address__City__s,
                                        Last_UK_Employer_Address__PostalCode__s,
                                        Last_UK_Employer_Address__Street__s,
                                   		Last_UK_Employer_Start_Date__c,
                                        Last_UK_Employer_End_Date__c,
                                        Last_UK_Employer_Name__c,
                                        Date_Of_Leaving_Last_UK__c,
                                        Work_after_UK__c,
                                        Gap_Yrs_After_2006__c,
                                        Abroad_Employers_Countries__c,
                                        (SELECT Id
                                        FROM ContentDocumentLinks
                                        WHERE ContentDocument.Title LIKE '%UPLOAD%'),
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
                                            Employer_Name__c,
                                            Current_Work__c
                                        FROM Employers__r
                                        ORDER BY Start_Date__c)
                                    FROM Application__c
                                    WHERE Status__c = 'Form In Progress' OR
                                          Status__c = 'Form Completed' OR
                                          Status__c = 'NINO/Doc Needed' OR
                                          Status__c = 'Pending Client' OR
                                          Status__c = 'Fix'
                                    ORDER BY CreatedDate DESC]) {
            if (app.ContentDocumentLinks.size() > 0 && app.Contain_Docs__c == false) {
                app.Contain_Docs__c = true;
            }
            if (!app.Employers__r.isEmpty()) {
                Integer yearOfLeavingUK = Date.valueOf(app.Date_Of_Leaving_Last_UK__c)?.year();
                Integer startGapYear;
                if (yearOfLeavingUK != null && yearOfLeavingUK <= 2006) {
                    startGapYear = 2006;
                } else if (yearOfLeavingUK != null && yearOfLeavingUK > 2006) {
                    startGapYear = yearOfLeavingUK;
                } else startGapYear = 2006;
                List<Employer__c> currAfterUKEmpls = new List<Employer__c>();
                String workAfter2006;
                Set<String> employersCountryName = new Set<String>();
                for (Employer__c empl : app.Employers__r) {
                    if (empl.Type__c == 'UK Work') {
                        app.Type_Of_Employment__c = empl.Type_Of_UK_Employment__c;
                        app.Last_UK_Emp_Addr__c = empl.Employers_Address__Street__s != null ?
                                                        empl.Employers_Address__Street__s :
                                                        '';
                        app.Last_UK_Emp_Addr__c += empl.Employers_Address__City__s != null ?
                                                        '\n ' + empl.Employers_Address__City__s :
                                                        '';
                        app.Last_UK_Emp_Addr__c += empl.Employers_Address__PostalCode__s != null ?
                                                        '\n ' + empl.Employers_Address__PostalCode__s :
                                                        '';
                        app.Last_UK_Employer_Address__Street__s = empl.Employers_Address__Street__s != null ?
                                                                    empl.Employers_Address__Street__s :
                                                                    '';
                        app.Last_UK_Employer_Address__City__s = empl.Employers_Address__City__s != null ?
                                                                    empl.Employers_Address__City__s :
                                                                    '';
                        app.Last_UK_Employer_Address__PostalCode__s = empl.Employers_Address__PostalCode__s != null ?
                                                                          empl.Employers_Address__PostalCode__s :
                                                                          '';
                        app.Last_UK_Employer_Start_Date__c = Date.valueOf(empl.Start_Date__c);
                        app.Last_UK_Employer_End_Date__c = Date.valueOf(empl.End_Date__c);
                        app.Last_UK_Employer_Name__c = empl.Employer_Name__c != null ?
                                                                    empl.Employer_Name__c :
                                                                    '';
                    }
                    if (empl.Type__c == 'Work After UK' &&
                            (Date.valueOf(empl?.Start_Date__c)?.year() >= startGapYear ||
                             (Date.valueOf(empl?.Start_Date__c)?.year() <= startGapYear && Date.valueOf(empl?.End_Date__c)?.year() >= startGapYear)) &&
                             workAfter2006 == null) {
                        workAfter2006 = empl.Type_Of_After_UK_Employment__c;
                    }
                    if (empl.Type__c == 'Work After UK' &&
                       (Date.valueOf(empl?.Start_Date__c)?.year() >= startGapYear || Date.valueOf(empl?.End_Date__c)?.year() >= startGapYear)) {
                        currAfterUKEmpls.add(empl);
                        if (empl.Employers_Address__CountryCode__s != null) {
                            employersCountryName.add(empl.Employers_Address__CountryCode__s);
                        }
                    }
                }
                if (workAfter2006 != null) {
                    app.Work_after_UK__c = workAfter2006;
                }
                if (!employersCountryName.isEmpty()) {
                    List<String> currEmplCountries = new List<String>(employersCountryName);
                    for (Integer i = 0; i < currEmplCountries.size(); i++) {
                        if (i == 0) {
                            app.Abroad_Employers_Countries__c = currEmplCountries.get(i);
                        } else {
                            app.Abroad_Employers_Countries__c += '\n' + currEmplCountries.get(i);
                        }
                    }
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
                            if (currAfterUKEmpls[i].Current_Work__c == 'No') {
                                gap += (Date.today().year() - endYear);
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
                app.Gap_Yrs_After_2006__c = gap;
            }
            updatedApps.add(app);
        }
        if (!updatedApps.isEmpty()) {
            update updatedApps;
        }
    }
}