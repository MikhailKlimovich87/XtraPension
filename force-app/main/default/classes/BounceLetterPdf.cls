public class BounceLetterPdf {
    public Application__c appObj{get;set;}
    public String MstrId{get;set;}

    public BounceLetterPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                First_Name__c,
                HMRC_Reply_Doc_Generate_Date__c,
                Bounce_Letter_Template__c
            FROM Application__c
			WHERE Id =: MstrId
		];
    }
}