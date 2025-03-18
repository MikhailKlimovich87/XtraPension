public with sharing class GetNINOPdf {
    public String MstrId{get;set;}
    public String baseURL{get;set;}
    public Application__c appObj{get;set;}
    public List<Employer__c> employers{get;set;}

    public GetNINOPdf(ApexPages.StandardController controller) {
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        List<Application__c> apps = [
            SELECT
                Name,
                National_Insurance_Number__c,
                First_Name__c,
                Second_Name__c,
                Date_Of_Birth__c,
                Salutation__c,
                Current_Address_Abroad__City__s,
                Current_Address_Abroad__PostalCode__s,
                Current_Address_Abroad__Street__s,
                Current_Address_Abroad_Country__c,
                Current_Address_Abroad_State__c,
                Previous_UK_Address_1__Street__s,
                Previous_UK_Address_1_Country__c,
                Previous_UK_Address_1__PostalCode__s,
                Previous_UK_Address_1__City__s,
                Previous_UK_Address1_State__c,
                Previous_UK_Address_Start_Date_1__c,
                Previous_UK_Address_End_Date_1__c,
                Previous_UK_Address_2__Street__s,
                Previous_UK_Address_2_Country__c,
                Previous_UK_Address_2__PostalCode__s,
                Previous_UK_Address_2__City__s,
                Previous_UK_Address2_State__c,
                Previous_UK_Address_Start_Date_2__c,
                Previous_UK_Address_End_Date_2__c,
                Previous_UK_Address_3__Street__s,
                Previous_UK_Address_3_Country__c,
                Previous_UK_Address_3__PostalCode__s,
                Previous_UK_Address_3__City__s,
                Previous_UK_Address3_State__c,
                Previous_UK_Address_Start_Date_3__c,
                Previous_UK_Address_End_Date_3__c,
                Related_Contact_Phone__c,
                Are_You_Single__c,
                Date_Of_Marriage_Or_Civil_Partnership__c,
                Divorce_Date__c,
                Full_Maiden_Previous_Name__c,
                    (SELECT
                        Start_Date__c,
                        End_Date__c,
                        Employer_Name__c,
                        Employers_Address__City__s,
                        Employers_Address_State__c,
                        Employers_Address_Country__c,
                        Employers_Address__Street__s,
                        Employers_Address__PostalCode__s,
                        Type_Of_UK_Employment__c
                    FROM Employers__r
                    WHERE Type__c = 'UK Work')
            FROM Application__c
            WHERE Id = :MstrId
        ];
        if (!apps.isEmpty()) {
            appObj = apps[0];
            if (!appObj.Employers__r.isEmpty()) {
                employers =  appObj.Employers__r;
            }
        }
    }
}