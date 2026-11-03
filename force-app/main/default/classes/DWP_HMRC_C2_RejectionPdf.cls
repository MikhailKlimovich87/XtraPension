public class DWP_HMRC_C2_RejectionPdf {
    public Application__c appObj{get;set;}
    public String MstrId{get;set;}
    public String fieldName{get;set;}
    public String bodyData{get;set;}

    public DWP_HMRC_C2_RejectionPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Name,
                C2_Client_Rejection_Template__c,
                HMRC_Ref__c,
                National_Insurance_Number__c,
                Second_Name__c,
                First_Name__c,
                Full_Current_Address_Abroad__c,
                HMRC_Reply_Doc_Generate_Date__c
            FROM Application__c
			WHERE Id =: MstrId
		];
        bodyData = (String)appObj.get('C2_Client_Rejection_Template__c');
    }

}