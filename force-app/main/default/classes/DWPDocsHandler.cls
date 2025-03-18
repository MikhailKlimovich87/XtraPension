public class DWPDocsHandler {
    private static final List<String> DWP_FILE_NAMES = new List<String> {
        'DWP 2 - Summary',
        'DWP 3 - Work History'
    };

    public static List<Id> generateDocs(Application__c currentApplication) {
        List<Id> docIds = new List<Id>();
        PageReference summarypage;
        summarypage = Page.DWPInfo;
        summarypage.getParameters().put('id', currentApplication.Id);
        blob summaryPdfBlob;
        if (!Test.isRunningTest()) {
            summaryPdfBlob = summarypage.getContent();
        } else {
            summaryPdfBlob = Blob.valueOf('Test');
        }
        Id summaryId = saveDocument(DWP_FILE_NAMES[0], summaryPdfBlob, currentApplication);
        docIds.add(summaryId);
        PageReference workhistorypage;
        workhistorypage = Page.DWPWorkHistory;
        workhistorypage.getParameters().put('id', currentApplication.Id);
        blob workHistoryPdfBlob;
        if (!Test.isRunningTest()) {
            workHistoryPdfBlob = workhistorypage.getContent();
        } else {
            workHistoryPdfBlob = Blob.valueOf('Test');
        }
        Id workHistoryId = saveDocument(DWP_FILE_NAMES[1], workHistoryPdfBlob, currentApplication);
        docIds.add(workHistoryId);
        return docIds;
    }

    private static Id saveDocument(String docName, Blob contentData, Application__c currentApplication) {
        List<ContentDocumentLink> currentDocs = Database.query (
            'SELECT ' +
                'ContentDocumentId, ' +
                'ContentDocument.Title, ' +
                'ContentDocument.LatestPublishedVersionId, ' +
                'LinkedEntityId ' +
            'FROM ContentDocumentLink ' +
            'WHERE ContentDocument.Title LIKE \'%' + docName +'%\' AND ' +
                   'LinkedEntityId = \'' + currentApplication.Id + '\''
        );
        String title = docName + ' - ' + currentApplication.Name + '_' + currentApplication.First_Name__c + '_' + currentApplication.Second_Name__c;
        ContentVersion conVer = new ContentVersion();
        // if (currentDocs.isEmpty()) {
            conVer.ContentLocation = 'S';
            conVer.PathOnClient = title + '.pdf';
            conVer.Title = title;
            conVer.VersionData = contentData;
            insert conVer;

            ContentVersion conDoc = [SELECT ContentDocumentId, ContentSize FROM ContentVersion WHERE Id =:conVer.Id][0];

            ContentDocumentLink conDocLink = new ContentDocumentLink();
            conDocLink.LinkedEntityId = currentApplication.Id;
            conDocLink.ContentDocumentId = conDoc.ContentDocumentId;
            conDocLink.shareType = 'V';
            conDocLink.Visibility = 'AllUsers';
            insert conDocLink;
        // } else {
        //     conVer.ContentDocumentId = currentDocs[0].ContentDocumentId;
        //     conVer.VersionData = contentData;
        //     conVer.PathOnClient = title + '.pdf';
        //     insert conVer;
        // }
        return conVer.Id;
    }
}