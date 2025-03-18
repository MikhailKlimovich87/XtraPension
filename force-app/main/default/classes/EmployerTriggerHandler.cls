public class EmployerTriggerHandler {
    public Map<Id, Employer__c> oldEmployers;
    public Map<Id, Employer__c> newEmployers;
    public List<Employer__c> beforeInsertEmployers;
    public Map<String, String> abroadEmployerFieldNameByApllicationField;
    public Map<String, String> lastUKEmployerFieldNameByApllicationField;

    public EmployerTriggerHandler (Map<Id, Employer__c> oldAfterEmployers, Map<Id, Employer__c> newAfterEmployers, List<Employer__c> beforeInsertEmployers) {
        this.oldEmployers = oldAfterEmployers;
        this.newEmployers = newAfterEmployers;
        this.beforeInsertEmployers = beforeInsertEmployers;
        this.abroadEmployerFieldNameByApllicationField = new Map<String, String> {
            'Employer_Name__c'                  => 'Abroad_Employer_Name1__c',
            'Employers_Address__City__s'        => 'Abroad_Employer_Address1__City__s',
            'Employers_Address__CountryCode__s' => 'Abroad_Employer_Address1__CountryCode__s',
            'Employers_Address__PostalCode__s'  => 'Abroad_Employer_Address1__PostalCode__s',
            'Employers_Address__StateCode__s'   => 'Abroad_Employer_Address1__StateCode__s',
            'Employers_Address__Street__s'      => 'Abroad_Employer_Address1__Street__s',
            'Employers_Address_Country__c'      => 'Abroad_Employer_Address1_Country__c',
            'Employers_Address_State__c'        => 'Abroad_Employer_Address1_State__c'
        };
        this.lastUKEmployerFieldNameByApllicationField = new Map<String, String> {
            'Employer_Name__c'                  => 'Last_UK_Employer_Name__c',
            'Employers_Address__City__s'        => 'Last_UK_Employer_Address__City__s',
            'Employers_Address__CountryCode__s' => 'Last_UK_Employer_Address__CountryCode__s',
            'Employers_Address__PostalCode__s'  => 'Last_UK_Employer_Address__PostalCode__s',
            'Employers_Address__StateCode__s'   => 'Last_UK_Employer_Address__StateCode__s',
            'Employers_Address__Street__s'      => 'Last_UK_Employer_Address__Street__s',
            'Employers_Address_Country__c'      => 'Last_UK_Employer_Address_Country__c',
            'Employers_Address_State__c'        => 'Last_UK_Employer_Address_State__c',
            'End_Date__c'                       => 'Date_Of_Leaving_Last_UK__c',
            'Type_Of_UK_Employment__c'          => 'Type_Of_Employment__c'
        };
    }

    public void regenerateEmployerContryNameOrState() {
        if (oldEmployers == null || newEmployers == null) {
            return;
        }
        for (Employer__c employer : newEmployers.values()) {
            if ((employer.Employers_Address__CountryCode__s != oldEmployers.get(employer.Id).Employers_Address__CountryCode__s ||
                employer.Employers_Address__StateCode__s != oldEmployers.get(employer.Id).Employers_Address__StateCode__s) &&
                employer.Is_First_Employer__c &&
                employer.Type__c == 'Work After UK') {
                employer.Employers_Address_Country__c = CountryCodeHelper.getCountryNameByIsoCode(employer.Employers_Address__CountryCode__s);
                employer.Employers_Address_State__c = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                        employer.Employers_Address__CountryCode__s,
                                                        employer.Employers_Address__StateCode__s);
            }
            if ((employer.Employers_Address__CountryCode__s != oldEmployers.get(employer.Id).Employers_Address__CountryCode__s ||
                employer.Employers_Address__StateCode__s != oldEmployers.get(employer.Id).Employers_Address__StateCode__s) &&
                employer.Type__c == 'UK Work') {
                employer.Employers_Address_Country__c = CountryCodeHelper.getCountryNameByIsoCode(employer.Employers_Address__CountryCode__s);
                employer.Employers_Address_State__c = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                    employer.Employers_Address__CountryCode__s,
                                                    employer.Employers_Address__StateCode__s);
        }
        }
    }

    public void updateApplicationAfterUKEmployerStartDate() {
        Map<Id, Employer__c> updateEmployers = new Map<Id, Employer__c>();
        Set<Id> applicationIds = new Set<Id>();
        if (oldEmployers == null || newEmployers == null) {
            return;
        }
        List<ChangedFieldsWrapper> changedData = new List<ChangedFieldsWrapper>();
        for (Employer__c employer : newEmployers.values()) {
            if (employer.Start_Date__c != oldEmployers.get(employer.Id).Start_Date__c && employer.Is_First_Employer__c && employer.Type__c == 'Work After UK') {
                updateEmployers.put(employer.Id, employer);
                applicationIds.add(employer.Application__c);
            }
            if (employer.Is_First_Employer__c && employer.Type__c == 'Work After UK' && employer.Type_Of_After_UK_Employment__c == 'Employed') {
                if (employer.Employers_Address__City__s != oldEmployers.get(employer.Id).Employers_Address__City__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address__City__s'),
                            employer.Employers_Address__City__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__CountryCode__s != oldEmployers.get(employer.Id).Employers_Address__CountryCode__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address__CountryCode__s'),
                            employer.Employers_Address__CountryCode__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__PostalCode__s != oldEmployers.get(employer.Id).Employers_Address__PostalCode__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address__PostalCode__s'),
                            employer.Employers_Address__PostalCode__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__StateCode__s != oldEmployers.get(employer.Id).Employers_Address__StateCode__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address__StateCode__s'),
                            employer.Employers_Address__StateCode__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__Street__s != oldEmployers.get(employer.Id).Employers_Address__Street__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address__Street__s'),
                            employer.Employers_Address__Street__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employer_Name__c != oldEmployers.get(employer.Id).Employer_Name__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employer_Name__c'),
                            employer.Employer_Name__c,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address_Country__c != oldEmployers.get(employer.Id).Employers_Address_Country__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address_Country__c'),
                            employer.Employers_Address_Country__c,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address_State__c != oldEmployers.get(employer.Id).Employers_Address_State__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            abroadEmployerFieldNameByApllicationField.get('Employers_Address_State__c'),
                            employer.Employers_Address_State__c,
                            employer.Application__c
                        )
                    );
                }
            }
            if (employer.Type__c == 'UK Work') {
                if (employer.Employers_Address__City__s != oldEmployers.get(employer.Id).Employers_Address__City__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address__City__s'),
                            employer.Employers_Address__City__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__CountryCode__s != oldEmployers.get(employer.Id).Employers_Address__CountryCode__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address__CountryCode__s'),
                            employer.Employers_Address__CountryCode__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__PostalCode__s != oldEmployers.get(employer.Id).Employers_Address__PostalCode__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address__PostalCode__s'),
                            employer.Employers_Address__PostalCode__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__StateCode__s != oldEmployers.get(employer.Id).Employers_Address__StateCode__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address__StateCode__s'),
                            employer.Employers_Address__StateCode__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address__Street__s != oldEmployers.get(employer.Id).Employers_Address__Street__s) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address__Street__s'),
                            employer.Employers_Address__Street__s,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employer_Name__c != oldEmployers.get(employer.Id).Employer_Name__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employer_Name__c'),
                            employer.Employer_Name__c,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address_Country__c != oldEmployers.get(employer.Id).Employers_Address_Country__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address_Country__c'),
                            employer.Employers_Address_Country__c,
                            employer.Application__c
                        )
                    );
                }
                if (employer.Employers_Address_State__c != oldEmployers.get(employer.Id).Employers_Address_State__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Employers_Address_State__c'),
                            employer.Employers_Address_State__c,
                            employer.Application__c
                        )
                    );
                }
                if (employer.End_Date__c != oldEmployers.get(employer.Id).End_Date__c) {
                    Application__c updateApplication = new Application__c();
                    updateApplication.Id = employer.Application__c;
                    updateApplication.Date_Of_Leaving_Last_UK__c = employer.End_Date__c;
                    if (updateApplication.Id != null) {
                        update updateApplication;
                    }
                }
                if (employer.Type_Of_UK_Employment__c != oldEmployers.get(employer.Id).Type_Of_UK_Employment__c) {
                    changedData.add(
                        new ChangedFieldsWrapper(
                            lastUKEmployerFieldNameByApllicationField.get('Type_Of_UK_Employment__c'),
                            employer.Type_Of_UK_Employment__c,
                            employer.Application__c
                        )
                    );
                }
            }
        }
        if (!changedData.isEmpty()) {
            updateAddressesFields(changedData);
        }
        if (updateEmployers.isEmpty()) {
            return;
        }
        Map<Id, Application__c> currentApplications = new Map<Id, Application__c>([
            SELECT
                Abroad_Start_Date__c
            FROM Application__c
            WHERE Id IN :applicationIds
        ]);
        if (currentApplications.isEmpty()) {
            return;
        }
        List<Application__c> updateApps = new List<Application__c>();
        for (Employer__c employer : updateEmployers.values()) {
            Application__c app = currentApplications.get(employer.Application__c);
            app.Abroad_Start_Date__c = employer.Start_Date__c;
            if (employer.Type_Of_After_UK_Employment__c == 'Employed') {
                app.Abroad_Employer_Start_Date1__c = employer.Start_Date__c;
            } else if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed') {
                app.Self_Employed_Start_Date1__c = employer.Start_Date__c;
            }
            updateApps.add(app);
        }
        if (!updateApps.isEmpty()) {
            update updateApps;
        }
    }

    private void updateAddressesFields(List<ChangedFieldsWrapper> updatedEmployers) {
        Map<Id, List<ChangedFieldsWrapper>> appIdByUpdatesDataList = new Map<Id, List<ChangedFieldsWrapper>>();
        for (ChangedFieldsWrapper wrapper : updatedEmployers) {
            List<ChangedFieldsWrapper> currentWrappers = appIdByUpdatesDataList.get(wrapper.applicationId);
            if (currentWrappers == null) {
                currentWrappers = new List<ChangedFieldsWrapper>();
                currentWrappers.add(wrapper);
                appIdByUpdatesDataList.put(wrapper.applicationId,currentWrappers);
            } else {
                currentWrappers.add(wrapper);
                appIdByUpdatesDataList.put(wrapper.applicationId, currentWrappers);
            }
        }
        List<Application__c> updateApps = new List<Application__c>();
        for (Id appId : appIdByUpdatesDataList.keySet()) {
            List<ChangedFieldsWrapper> currentWrappers = appIdByUpdatesDataList.get(appId);
            if (!currentWrappers.isEmpty()) {
                Application__c changeApp = new Application__c();
                changeApp.Id = appId;
                for (ChangedFieldsWrapper wrapper : currentWrappers) {
                    changeApp.put(wrapper.fieldName, wrapper.newValue);
                }
                updateApps.add(changeApp);
            }
        }
        if (!updateApps.isEmpty()) {
            update updateApps;
        }
    }

    public void addCountryAndStateData() {
        // List<Employer__c> newEmployersWith = new List<Employer__c>();
        for (Employer__c employer : beforeInsertEmployers) {
            if (String.isNotBlank(employer.Employers_Address__CountryCode__s)) {
                employer.Employers_Address_Country__c = CountryCodeHelper.getCountryNameByIsoCode(employer.Employers_Address__CountryCode__s);
            }
            if (String.isNotBlank(employer.Employers_Address__StateCode__s)) {
                employer.Employers_Address_State__c = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                        employer.Employers_Address__CountryCode__s,
                                                        employer.Employers_Address__StateCode__s);
            }
        }
    }

    public void checkEmployersAfterCreate() {
        List<Employer__c> currentEmployers = [
            SELECT
                Id,
                Application__r.Status__c,
                Type__c,
                Application__c,
                Type_Of_After_UK_Employment__c,
                Type_Of_UK_Employment__c,
                Employers_Address__City__s,
                Employers_Address__CountryCode__s,
                Employers_Address__StateCode__s,
                Employers_Address__Street__s,
                Employers_Address__PostalCode__s,
                Employers_Address_Country__c,
                Employers_Address_State__c,
                Employer_Name__c,
                Start_Date__c,
                End_Date__c
            FROM Employer__c
            WHERE Id IN :newEmployers.keySet()
                AND Application__r.Status__c != 'Form In Progress'
        ];
        if(!currentEmployers.isEmpty() && currentEmployers.size() == 1) {
            Employer__c newEmployer = currentEmployers[0];
            switch on newEmployer.Type__c  {
                when 'UK Work' {
                    Application__c updateApplication = new Application__c();
                    if (newEmployer.Type_Of_UK_Employment__c == 'Employed') {
                        updateApplication.Id                                       = newEmployer.Application__c;
                        updateApplication.Date_Of_Leaving_Last_UK__c               = newEmployer.End_Date__c;
                        updateApplication.Type_Of_Employment__c                    = newEmployer.Type_Of_UK_Employment__c;
                        updateApplication.Last_UK_Employer_Name__c                 = newEmployer.Employer_Name__c;
                        updateApplication.Last_UK_Employer_Start_Date__c           = newEmployer.Start_Date__c;
                        updateApplication.Last_UK_Employer_End_Date__c             = newEmployer.End_Date__c;
                        updateApplication.Last_UK_Employer_Address__City__s        = newEmployer.Employers_Address__City__s;
                        updateApplication.Last_UK_Employer_Address__CountryCode__s = newEmployer.Employers_Address__CountryCode__s;
                        updateApplication.Last_UK_Employer_Address__StateCode__s   = newEmployer.Employers_Address__StateCode__s;
                        updateApplication.Last_UK_Employer_Address__Street__s      = newEmployer.Employers_Address__Street__s;
                        updateApplication.Last_UK_Employer_Address__PostalCode__s  = newEmployer.Employers_Address__PostalCode__s;
                        updateApplication.Last_UK_Employer_Address_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(newEmployer.Employers_Address__CountryCode__s);
                        updateApplication.Last_UK_Employer_Address_State__c        = CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                                        newEmployer.Employers_Address__CountryCode__s,
                                                                                        newEmployer.Employers_Address__StateCode__s);
                    } else if (newEmployer.Type_Of_UK_Employment__c == 'Self-Employed' || newEmployer.Type_Of_UK_Employment__c == 'Unemployed') {
                        updateApplication.Id                                       = newEmployer.Application__c;
                        updateApplication.Type_Of_Employment__c                    = newEmployer.Type_Of_UK_Employment__c;
                        updateApplication.Date_Of_Leaving_Last_UK__c               = newEmployer.End_Date__c;
                        updateApplication.Last_UK_Employer_Name__c                 = null;
                        updateApplication.Last_UK_Employer_Start_Date__c           = null;
                        updateApplication.Last_UK_Employer_End_Date__c             = null;
                        updateApplication.Last_UK_Employer_Address__City__s        = null;
                        updateApplication.Last_UK_Employer_Address__CountryCode__s = null;
                        updateApplication.Last_UK_Employer_Address__StateCode__s   = null;
                        updateApplication.Last_UK_Employer_Address__Street__s      = null;
                        updateApplication.Last_UK_Employer_Address__PostalCode__s  = null;
                        updateApplication.Last_UK_Employer_Address_Country__c      = null;
                        updateApplication.Last_UK_Employer_Address_State__c        = null;
                    }
                    if (updateApplication.Id  != null) {
                        update updateApplication;
                    }
                }
                when 'Work After UK' {
                    if (newEmployer.Type_Of_After_UK_Employment__c == 'Career Break' ||
                        newEmployer.Type_Of_After_UK_Employment__c == 'Unemployed'   ||
                        newEmployer.Type_Of_After_UK_Employment__c == 'Family Carer' ||
                        newEmployer.Type_Of_After_UK_Employment__c == 'Homemaker'    ||
                        newEmployer.Type_Of_After_UK_Employment__c == 'Disabled'     ||
                        newEmployer.Type_Of_After_UK_Employment__c == 'Retired') {
                        return;
                    }
                    Map<Id, Employer__c> afterUKEmployers = new Map<Id, Employer__c>([
                        SELECT
                            Type__c,
                            Start_Date__c,
                            End_Date__c,
                            Type_Of_After_UK_Employment__c,
                            Employer_Name__c,
                            Application__c,
                            Employers_Address__City__s,
                            Employers_Address__CountryCode__s,
                            Employers_Address__StateCode__s,
                            Employers_Address__Street__s,
                            Employers_Address__PostalCode__s,
                            Employers_Address_Country__c,
                            Employers_Address_State__c,
                            Is_First_Employer__c
                        FROM Employer__c
                        WHERE Application__c = :newEmployer.Application__c AND
                              Type__c = 'Work After UK'
                        ORDER BY Start_Date__c ASC
                    ]);
                    if (!afterUKEmployers.isEmpty() && afterUKEmployers.size() > 1) {
                        findTheFirstAfterUKEmployer(afterUKEmployers.values());
                    }
                }
            }
        } else return;
    }

    private void findTheFirstAfterUKEmployer(List<Employer__c> employers) {
        Boolean isExistFirstEmployer = false;
        Application__c updateApplication = new Application__c();
        List<Sobject> updateData = new List<Sobject>();
        for (Employer__c employer : employers) {
            if (employer.Type_Of_After_UK_Employment__c == 'Self-Employed' && isExistFirstEmployer == false) {
                updateApplication.Id                                       = employer.Application__c;
                updateApplication.Self_Employed_Start_Date1__c             = employer.Start_Date__c;
                updateApplication.Self_Employed_End_Date1__c               = employer.End_Date__c;
                updateApplication.SelfEmployment_Employment_Abroad__c      = 'Self-employed';
                updateApplication.Abroad_Start_Date__c                     = null;
                updateApplication.Abroad_Employer_Name1__c                 = null;
                updateApplication.Abroad_Employer_Start_Date1__c           = null;
                updateApplication.Abroad_Employer_End_Date1__c             = null;
                updateApplication.Abroad_Employer_Address1__City__s        = null;
                updateApplication.Abroad_Employer_Address1__CountryCode__s = null;
                updateApplication.Abroad_Employer_Address1__StateCode__s   = null;
                updateApplication.Abroad_Employer_Address1__Street__s      = null;
                updateApplication.Abroad_Employer_Address1__PostalCode__s  = null;
                updateApplication.Abroad_Employer_Address1_Country__c      = null;
                updateApplication.Abroad_Employer_Address1_State__c        = null;
                isExistFirstEmployer = true;
                employer.Is_First_Employer__c = true;
                updateData.add(employer);
                updateData.add(updateApplication);
                continue;
            }
            if (employer.Type_Of_After_UK_Employment__c == 'Employed' && isExistFirstEmployer == false) {
                updateApplication.Abroad_Start_Date__c                     = employer.Start_Date__c;
                updateApplication.Abroad_Employer_Name1__c                 = employer.Employer_Name__c;
                updateApplication.Abroad_Employer_Start_Date1__c           = employer.Start_Date__c;
                updateApplication.Abroad_Employer_End_Date1__c             = employer.End_Date__c;
                updateApplication.Abroad_Employer_Address1__City__s        = employer.Employers_Address__City__s;
                updateApplication.Abroad_Employer_Address1__CountryCode__s = employer.Employers_Address__CountryCode__s;
                updateApplication.Abroad_Employer_Address1__StateCode__s   = employer.Employers_Address__StateCode__s;
                updateApplication.Abroad_Employer_Address1__Street__s      = employer.Employers_Address__Street__s;
                updateApplication.Abroad_Employer_Address1__PostalCode__s  = employer.Employers_Address__PostalCode__s;
                updateApplication.Abroad_Employer_Address1_Country__c      = employer.Employers_Address_Country__c;
                updateApplication.Abroad_Employer_Address1_State__c        = employer.Employers_Address_State__c;
                updateApplication.Id                                       = employer.Application__c;
                updateApplication.Self_Employed_Start_Date1__c             = null;
                updateApplication.Self_Employed_End_Date1__c               = null;
                updateApplication.SelfEmployment_Employment_Abroad__c      = 'Employed';
                isExistFirstEmployer = true;
                employer.Is_First_Employer__c = true;
                updateData.add(employer);
                updateData.add(updateApplication);
                continue;
            }
            if (employer.Is_First_Employer__c  == true && isExistFirstEmployer == true) {
                employer.Is_First_Employer__c = false;
                updateData.add(employer);
            }

        }
        if (!updateData.isEmpty()) {
            update updateData;
        }
    }

    private class ChangedFieldsWrapper {
        private String fieldName{get; set;}
        private String newValue{get; set;}
        private Id applicationId{get; set;}

        private ChangedFieldsWrapper(String fieldName, String newValue, Id appId) {
            this.fieldName     = fieldName;
            this.newValue      = newValue;
            this.applicationId = appId;
        }
    }
}