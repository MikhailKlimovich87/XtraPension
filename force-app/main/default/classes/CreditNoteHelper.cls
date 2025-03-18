public class CreditNoteHelper {
    public static void generateCreditNotePdf(Id paymentId) {
        List<Payment__c> payments = [
            SELECT
                Application__r.First_Name__c,
                Application__r.Second_Name__c ,
                Application__r.Name,
                Application__r.OwnerId
            FROM Payment__c
            WHERE Id = :paymentId
        ];
        if (payments.isEmpty()) {
            return;
        }
        Payment__c paymentObj = payments[0];
        PageReference savepage;
        savepage = Page.CreditNote;
        savepage.getParameters().put('id',paymentId);
        Blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }

		String fileTitle = paymentObj.Application__r.First_Name__c + '_' + paymentObj.Application__r.Second_Name__c + '_' + paymentObj.Application__r.Name +'_CreditNote';

		ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = fileTitle+'.pdf';
		conVer.Title = fileTitle;
		conVer.VersionData = pdfBlob;
		insert conVer;

		ContentVersion conDoc = [
            SELECT
                ContentDocumentId,
                ContentSize
            FROM ContentVersion
            WHERE Id =:conVer.Id][0];


		ContentDocumentLink conDocLink = New ContentDocumentLink();
		conDocLink.LinkedEntityId = paymentId;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
		conDocLink.Visibility = 'AllUsers';
		insert conDocLink;
    }
}