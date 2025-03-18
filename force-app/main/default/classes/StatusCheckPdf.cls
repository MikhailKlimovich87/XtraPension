public class StatusCheckPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public String docBody{get;set;}

    public StatusCheckPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Id,
                Salutation__c,
                First_Name__c,
                Second_Name__c,
                Full_Current_Address_Abroad__c,
                Date_Of_Birth__c,
                National_Insurance_Number__c,
                DWP_Status_Check_Template__c,
                HMRC_Ref__c,
                Email__c
            FROM Application__c
			WHERE Id =: MstrId
            LIMIT 1
		];
        if (appObj.DWP_Status_Check_Template__c != null) {
            docBody = appObj.DWP_Status_Check_Template__c;
        }
    }
}