public class UpdateLetterPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}

    public UpdateLetterPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
      		SELECT
        		First_Name__c,
        		Second_Name__c,
                Full_Maiden_Previous_Name__c,
                National_Insurance_Number__c,
                Related_Contact_Phone__c,
                Email__c,
                Date_Of_Birth__c,
                Full_Current_Address_Abroad__c,
                Full_UK_Home_Address__c
            FROM Application__c
            WHERE Id = :MstrId
        ];
    }
}