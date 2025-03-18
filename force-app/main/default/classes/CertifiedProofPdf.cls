public class CertifiedProofPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}
    public String docBody{get;set;}

    public CertifiedProofPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Id,
                Full_Current_Address_Abroad__c,
                HMRC_Ref__c,
                Certified_Doc_Template__c
            FROM Application__c
			WHERE Id =: MstrId
            LIMIT 1
		];
        if (appObj.Certified_Doc_Template__c != null) {
            docBody = appObj.Certified_Doc_Template__c;
        }
    }
}