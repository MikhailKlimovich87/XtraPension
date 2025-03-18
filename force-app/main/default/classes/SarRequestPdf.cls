public class SarRequestPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}

    public SarRequestPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Name,
                Full_Current_Address_Abroad__c,
                Salutation__c,
                First_Name__c,
                Second_Name__c,
                Date_Of_Birth__c,
                National_Insurance_Number__c,
                Last_UK_Home_Address__Street__s,
                Last_UK_Home_Address_Country__c,
                Last_UK_Home_Address__PostalCode__s,
                Last_UK_Home_Address__City__s
            FROM Application__c
			WHERE Id =: MstrId
		];
    }
}