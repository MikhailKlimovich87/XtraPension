public class ReSubLetterPdf {
    public String MstrId{get;set;}
    public Application__c appObj{get;set;}

    public ReSubLetterPdf(ApexPages.StandardController Controller) {
        MstrId = ApexPages.currentPage().getParameters().get('id');
        appObj = [
      		SELECT
        		First_Name__c,
        		Second_Name__c,
                Tracking_No_Rx_d_by_XP__c,
                Tracking_Number__c,
                Full_Maiden_Previous_Name__c,
                National_Insurance_Number__c,
                Related_Contact_Phone__c,
                Email__c,
                Date_Of_Birth__c,
                DWP_Callback_Request__c,
                DHL_Repeat__c
            FROM Application__c
            WHERE Id = :MstrId
        ];

    }
}