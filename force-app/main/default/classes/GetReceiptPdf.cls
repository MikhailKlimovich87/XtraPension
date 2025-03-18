public class GetReceiptPdf {
    public String baseURL{get;set;}
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}

    public GetReceiptPdf(ApexPages.StandardController Controller) {
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
			SELECT
                Current_Address_Abroad__City__s,
                Current_Address_Abroad_Country__c,
                Current_Address_Abroad__Street__s,
                Current_Address_Abroad__PostalCode__s,
                Current_Address_Abroad_State__c,
                HMRC_Ref__c,
                National_Insurance_Number__c,
                Second_Name__c,
                First_Name__c,
                Salutation__c,
                Contact__r.MailingStreet,
                Contact__r.Account.Mailing_Line_2__c,
                Contact__r.MailingCity,
                Contact__r.Account.Mailing_State__c,
                Contact__r.MailingPostalCode,
                Full_Current_Address_Abroad__c,
                Contact__r.Account.Mailing_Country__c
            FROM Application__c
			WHERE Id =: MstrId
		];
    }
}