public class DWPWorkHistoryPdf {
    public String MstrId{get;set;}
    public Employer__c empUKObj{get;set;}
    public List<Employer__c> empAfterUKObjList{get;set;}
    public Application__c appObj{get;set;}

    public DWPWorkHistoryPdf(ApexPages.StandardController Controller){
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Type_Of_Employment__c
            FROM Application__c
			WHERE Id =: MstrId
		];
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
		if (appObj.Type_Of_Employment__c == 'Not employed') {
			empAfterUKObjList = null;
			empUKObj = null;
		}
    }
}