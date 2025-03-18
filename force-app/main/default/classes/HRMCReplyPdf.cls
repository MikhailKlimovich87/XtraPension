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
                HMRC_Ref__c,
                National_Insurance_Number__c,
                Second_Name__c,
                First_Name__c
            FROM Application__c
			WHERE Id =: MstrId
		];
        bodyData = (String)appObj.get(fieldName);
    }
}