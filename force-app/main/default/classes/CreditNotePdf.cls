public class CreditNotePdf {
    public String baseURL{get;set;}
    public String MstrId{get;set;}
    public Payment__c paymentObj{get;set;}
    public Credit_Note__c creditNoteObj{get;set;}

    public CreditNotePdf(ApexPages.StandardController Controller) {
        baseURL = URL.getSalesforceBaseUrl().toExternalForm();
        MstrId = ApexPages.currentPage().getParameters().get('id');
        List<Payment__c> payments = [
            SELECT
                Application__r.First_Name__c,
                Application__r.Second_Name__c ,
                Application__r.Contact__r.Account.PersonContact.MailingStreet,
                Application__r.Contact__r.Account.PersonContact.MailingCity,
                Application__r.Contact__r.Account.PersonContact.MailingState,
                Application__r.Contact__r.Account.Mailing_State__c,
                Application__r.Contact__r.Account.PersonMailingState,
                Application__r.Contact__r.Account.PersonContact.MailingPostalCode,
                Application__r.Contact__r.Account.Mailing_Country__c,
                Application__r.Name,
                (SELECT
                    Name,
                    Refund_Date__c,
                    Refund_Method__c,
                    Amount__c,
                    Product_Name__c,
                    Total__c,
                    Tax_EU__c,
                    Client_Info__c
                FROM Credit_Notes__r)
            FROM Payment__c
            WHERE Id = :MstrId
        ];
        if (!payments.isEmpty()) {
            paymentObj = payments[0];
            if (!paymentObj.Credit_Notes__r.isEmpty()) {
                creditNoteObj = paymentObj.Credit_Notes__r[0];
            }
        }
    }
}