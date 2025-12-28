public class HRMCReplyPdf {
    public Application__c appObj{get;set;}
    public String baseURL{get;set;}
    public String MstrId{get;set;}
    public String fieldName{get;set;}
    public String bodyData{get;set;}

    public HRMCReplyPdf(ApexPages.StandardController Controller) {
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        fieldName = ApexPages.currentPage().getParameters().get('template');
        appObj = [
			SELECT
                Name,
                NINO_Template__c,
                Custom_Reply_Template__c,
                Appeal_Template__c,
                Current_Job_Reply_Template__c,
                EU_Residency_Appeal_Template__c,
                Maiden_Name_Template__c,
                EU_Residency_Letter_Template__c,
                Class_3_Appeal_Despite_3_Years_Template__c,
                Bad_Error_In_C2_Decision_Template__c,
                No_Shortfall_Table_Provided_Template__c,
                Custom_Carnage_Template__c,
                Missing_Correspondence_Template__c,
                CF83_NOT_Received_letter_again_Template__c,
                Late_Payment_Appeal_Template__c,
                Reply_to_EU_C2_C3_Rejection_Template__c,
                HMRC_Ref__c,
                National_Insurance_Number__c,
                Second_Name__c,
                First_Name__c,
                HMRC_Reply_Doc_Generate_Date__c
            FROM Application__c
			WHERE Id =: MstrId
		];
        bodyData = (String)appObj.get(fieldName);
    }
}