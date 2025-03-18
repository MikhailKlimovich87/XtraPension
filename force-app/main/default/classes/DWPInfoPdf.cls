public class DWPInfoPdf {
    ApexPages.StandardController stdController = null;
    public String baseURL{get;set;}
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public Employer__c empUKObj{get;set;}

    public DWPInfoPdf(ApexPages.StandardController Controller) {
        baseURL = URL.getOrgDomainUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Email__c,
                Related_Contact_Phone__c,
                National_Insurance_Number__c,
                First_Name__c,
                Second_Name__c,
                Full_Maiden_Previous_Name__c,
                Date_Of_Birth__c,
                Date_Of_Marriage_Or_Civil_Partnership__c,
                Date_Of_Leaving_Last_UK__c,
                Full_Current_Address_Abroad__c,
                Are_You_Single__c,
                Are_You_Divorced__c,
                Divorce_Date__c,
                Last_UK_Home_Address__City__s,
                Last_UK_Home_Address__PostalCode__s,
                Last_UK_Home_Address__Street__s
            FROM Application__c
			WHERE Id =: MstrId
		];
        List<Employer__c> employers = [
            SELECT
                Employers_Address__Street__s,
				Employers_Address__City__s,
				Employers_Address__CountryCode__s,
				Employers_Address__StateCode__s,
				Employers_Address__PostalCode__s,
				Start_Date__c,
				End_Date__c,
				Employer_Name__c,
				Employers_Address_Country__c,
                Type__c,
				Type_Of_UK_Employment__c,
                Type_Of_After_UK_Employment__c
            FROM Employer__c
            WHERE Application__c =: MstrId
        ];
        for (Employer__c employer : employers) {
            if (employer.Type__c == 'UK Work' && empUKObj == null) {
                empUKObj = employer;
            }
        }
        System.debug(empUKObj);
    }
}