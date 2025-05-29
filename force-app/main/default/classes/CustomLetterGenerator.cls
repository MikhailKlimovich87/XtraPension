public class CustomLetterGenerator {

    @future(callout=true)
    public static void generateCustomLetter(Id appId) {
        List<Application__c> apps = [
            SELECT
    	        Id,
    	        Name,
    	        First_Name__c,
    	        Second_Name__c,
                DWP_Callback_Request__c,
                Contains_new_version_of_Custom_Letter__c
            FROM Application__c
            WHERE Id = :appId
            LIMIT 1
        ];
        if(apps.size() == 0) return;
        Application__c app = apps[0];
   	    PageReference savepage ;
        savepage = Page.CustomLetter;
        savepage.getParameters().put('id', app.Id);
        blob pdfBlob;
        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }

		List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocument.Title,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%CustomLetter%' AND
                  LinkedEntityId = :app.Id
        ];
        String forSignatureContDocument;
        for (ContentDocumentLink link : oldDocuments) {
            if (link.ContentDocument.Title.contains('ForSignature')) {
                forSignatureContDocument = link.ContentDocumentId;
                break;
            }
        }
        if (forSignatureContDocument != null) {
            List<ContentDocument> contentDocument = [
                SELECT Title
                FROM ContentDocument
                WHERE Id = :forSignatureContDocument
            ];
            if (!contentDocument.isEmpty()) {
                contentDocument[0].Title = contentDocument[0].Title.replace('ForSignature', 'v' + oldDocuments.size() + '.0');
                update contentDocument;
            }
        }

        String FinalTitle = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name +'_CustomLetter_ForSignature';

		ContentVersion conVer = new ContentVersion();
		conVer.ContentLocation = 'S';
		conVer.PathOnClient = FinalTitle+'.pdf';
		conVer.Title = FinalTitle;
		conVer.VersionData = pdfBlob;
		system.debug('conVer@@ ' + conVer);
		insert conVer;

		ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

		ContentDocumentLink conDocLink = New ContentDocumentLink();
		conDocLink.LinkedEntityId = app.Id;
		conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
		conDocLink.shareType = 'V';
        conDocLink.Visibility = 'AllUsers';
		insert conDocLink;
    
    	update new Application__c(Id = app.Id, Contains_new_version_of_Custom_Letter__c = true);
    }
}