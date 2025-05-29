public class DWP_C2RequestPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public String topDocBody{get;set;}
	public String bottomDocBody{get;set;}
    public Employer__c empUKObj{get;set;}
    public List<Employer__c> empAfterUKObjList{get;set;}

    public DWP_C2RequestPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Id,
                First_Name__c,
                Second_Name__c,
                National_Insurance_Number__c,
                DWP_C2_Request_Template__c,
                Full_Current_Address_Abroad__c,
				HMRC_Reply_Doc_Generate_Date__c,
                Tel__c,
				Email__c
            FROM Application__c
			WHERE Id =: MstrId
            LIMIT 1
		];
        if (appObj.DWP_C2_Request_Template__c != null) {
			String[] textAreaData = appObj.DWP_C2_Request_Template__c.split('SPLIT=============');
			if (textAreaData.size() == 2) {
				topDocBody = textAreaData[0];
 				bottomDocBody = textAreaData[1];
			}
        }
        List<Employer__c> lastUkEmployer= [
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
				Type_Of_UK_Employment__c
			FROM Employer__c
			WHERE Application__c =: MstrId
				AND Type__c = 'UK Work'
			ORDER BY Start_Date__c DESC];
		empUKObj = lastUkEmployer.size() != 0 ? lastUkEmployer[0] : null;
		List<Employer__c> afterUKEmployers = [
			SELECT
				Employer_Name__c,
				Start_Date__c,
				End_Date__c,
				Employers_Address__Street__s,
				Employers_Address__City__s,
				toLabel(Employers_Address__CountryCode__s),
				toLabel(Employers_Address__StateCode__s),
				Employers_Address__PostalCode__s,
				Add_to_custom_letter__c,
				Employers_Address_Country__c,
				Type_Of_After_UK_Employment__c,
				Current_Work__c
			FROM Employer__c
			WHERE Application__c =: MstrId
				AND Type__c = 'Work After UK'
				AND Add_to_custom_letter__c = true
			ORDER BY Start_Date__c ASC
		];
		empAfterUKObjList = afterUKEmployers.size() == 0 ? null : afterUKEmployers;
    }
}