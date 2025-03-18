public class ContentVersionTriggerHandler {
    public static List<String> typesOfDocument = new List<String>{'UPLOAD', 'CF083', '64-8', 'CustomLetter'};
    public static void linkFileToApplicationDocument(List<ContentVersion> currentContentVersions) {
        if (currentContentVersions.isEmpty()) {
            return;
        }
        ContentVersion actualContVers = currentContentVersions[0];
        String currentType = '';
        for (String type : typesOfDocument) {
            if (actualContVers.Title.contains(type)) {
                currentType = type;
                break;
            }
        }
        if (String.isBlank(currentType)) {
            return;
        }
        List<ContentDocumentLink> relatedContentDocLinks= [
            SELECT
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :actualContVers.ContentDocumentId
        ];
        Schema.DescribeSObjectResult r = Application_Document__c.sObjectType.getDescribe();
        String keyPrefix = r.getKeyPrefix();
        for (ContentDocumentLink link : relatedContentDocLinks) {
            String objectPrefix = String.valueOf(link.LinkedEntityId).substring(0, 3);
            if (objectPrefix == keyPrefix) {
                return;
            }
        }
        Schema.DescribeSObjectResult resultApplication = Application__c.sObjectType.getDescribe();
        String keyApplicationPrefix = resultApplication.getKeyPrefix();
        String applicationId = '';
        for (ContentDocumentLink link : relatedContentDocLinks) {
            String objectPrefix = String.valueOf(link.LinkedEntityId).substring(0, 3);
            if (objectPrefix == keyApplicationPrefix) {
                applicationId = link.LinkedEntityId;
            }
        }
        if (String.isBlank(applicationId)) return;
        List<Application_Document__c> nessesaryApplDocument = Database.query(
            'SELECT File_Name__c ' +
            'FROM Application_Document__c ' +
            'WHERE File_Name__c LIKE \'%' + currentType + '%\' AND ' +
                   'Application__c = \'' + applicationId + '\' ' +
            'LIMIT 1'
        );
        if (nessesaryApplDocument.isEmpty() && currentType == 'UPLOAD') {
            List<Application__c> apps = [
                SELECT
                    Name,
                    First_Name__c,
                    Second_Name__c,
                    Form_Complete_Date__c
                FROM Application__c
                WHERE Id = :applicationId
            ];
            if (apps.isEmpty()) return;
            Application__c actualApp = apps[0];
            List<SObject> upsertData = new List<SObject>();
            actualApp.Form_Complete_Date__c = Date.today();
            upsertData.add(actualApp);
            Application_Document__c newApplicationDocument = new Application_Document__c(
                Application__c = applicationId,
                File_Name__c   = actualApp.First_Name__c + '_' + actualApp.Second_Name__c + '_' + actualApp.Name + '_UPLOAD_ForSignature',
                File_Size__c   = actualContVers.ContentSize,
                Large_File__c  = Integer.valueOf(actualContVers.ContentSize) > 6000000 ? true : false,
                Status__c      = 'New',
                Type__c        = 'CV'
            );
            upsertData.add(newApplicationDocument);
            if (!upsertData.isEmpty()) {
                upsert upsertData;
            } else return;
            ContentDocumentLink conDocLinkUploadDoc = new ContentDocumentLink();
            conDocLinkUploadDoc.LinkedEntityId = newApplicationDocument.Id;
            conDocLinkUploadDoc.ContentDocumentId = actualContVers.ContentDocumentId;
            conDocLinkUploadDoc.shareType = 'V';
            conDocLinkUploadDoc.Visibility = 'AllUsers';
            insert conDocLinkUploadDoc;
            return;
        } else if (nessesaryApplDocument.isEmpty()) return;
        ContentDocumentLink newLink = new ContentDocumentLink(
            LinkedEntityId = nessesaryApplDocument[0].Id,
            ContentDocumentId = actualContVers.ContentDocumentId,
            shareType = 'V',
            Visibility = 'AllUsers'
        );
        insert newLink;
    }
}