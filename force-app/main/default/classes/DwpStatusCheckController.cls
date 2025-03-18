public class DwpStatusCheckController {

    @AuraEnabled
    public static string genetateDWPDoc(String recordId) {
        if (recordId == null) throw new DWPException('Application Id is null');
		List<Application__c> apps = [
			SELECT
				First_Name__c,
				Second_Name__c,
				Name
			FROM Application__c
			WHERE Id = :recordId
		];
		if(apps.isEmpty()) throw new DWPException('Couldn\'t find app with this record Id');
		Application__c currentApplication = apps[0];
		PageReference savepage;
        savepage = Page.statusCheck;
        savepage.getParameters().put('id', recordId);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
           	pdfBlob = savepage.getContent();
        } else {
           	pdfBlob = Blob.valueOf('Test');
        }
        String finalTitle = currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c + '_' +
                            currentApplication.Name + '_DWPStatusCheck';

        ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = finalTitle+'.pdf';
		conVer.Title = finalTitle;
		conVer.VersionData = pdfBlob;
		insert conVer;

		ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		ContentDocumentLink conDocLink = new ContentDocumentLink();
		conDocLink.LinkedEntityId = currentApplication.Id;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
		conDocLink.Visibility = 'AllUsers';
		insert conDocLink;
        return conDocLink.Id;
    }

    public class DWPException extends Exception {}
}