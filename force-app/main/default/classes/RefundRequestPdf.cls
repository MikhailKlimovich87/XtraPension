public class RefundRequestPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}

    public RefundRequestPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Id,
                National_Insurance_Number__c,
                First_Name__c,
                Second_Name__c,
                Name,
                Full_Current_Address_Abroad__c,
                Related_Contact_Phone__c
            FROM Application__c
			WHERE Id =: MstrId
            LIMIT 1
		];
    }
}