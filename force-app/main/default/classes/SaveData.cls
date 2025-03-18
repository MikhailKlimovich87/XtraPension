public class SaveData {
    public static Map<String, Object> setApplicationDocumentsDetails(ApplicationManager.DocumentsStepWrapper requestData, String stripeId, Boolean isFromAgentForm) {
        Map<String, Object> result = new Map<String, Object>();
        Application__c app = [
            SELECT
                Id,
                Status__c,
                First_Name__c,
                Second_Name__c,
                Name,
                Is_Generate_Client_Summary_PDF__c,
                Form_Complete_Date__c,
                Form_Was_Copmleted_By__c,
                Contact__c
            FROM Application__c
            WHERE Stripe_Transaction_Id__c = :stripeId
                AND Expiry_Date__c > :Datetime.now()
            LIMIT 1
        ];
        if (isFromAgentForm == true) {
            app.Form_Was_Copmleted_By__c = 'Agent';
        } else app.Form_Was_Copmleted_By__c = 'Client';
        if (requestData?.statements == null && isFromAgentForm == false) {
            result.put('status', 'Success');
            result.put('isComplete', 'true');
            if (app.Is_Generate_Client_Summary_PDF__c == false) {
                System.enqueueJob(new GeneratePDFCallout(app.Id));
                CustomSummerPdf.generateClientSummary(app.Id);
                if (isFromAgentForm == false) {
                    app.Status__c = 'Form Completed';
                }
                update app;
            }
        } else if(isFromAgentForm == true) {
            result.put('status', 'Success');
            result.put('isComplete', 'true');
            System.enqueueJob(new GeneratePDFCallout(app.Id));
            if (app.Is_Generate_Client_Summary_PDF__c == false) {
                CustomSummerPdf.generateClientSummary(app.Id);
            }
            app.Is_Generate_Client_Summary_PDF__c = true;
            update app;
        }
        String idCurrentContentVersion = requestData?.statements;
        List<ContentDocumentLink> oldDocuments = [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersionId,
                LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocument.Title LIKE '%UPLOAD%' AND
                  LinkedEntityId = :app.Id
        ];
        if (!oldDocuments.isEmpty() && !String.isBlank(idCurrentContentVersion)) {
            ContentDocumentLink lastVersionOfUploadDocument;
            for (ContentDocumentLink link : oldDocuments) {
                if (link.ContentDocument.LatestPublishedVersionId != idCurrentContentVersion &&
                    link.ContentDocument.Title.contains('ForSignature') &&
                    !link.ContentDocument.Title.contains('completed') &&
                    link.ContentDocument.Title.contains('UPLOAD')) {
                    lastVersionOfUploadDocument = link;
                    break;
                }
            }
            if (lastVersionOfUploadDocument != null) {
                ContentDocument updateDocument = new ContentDocument();
                updateDocument.Id = lastVersionOfUploadDocument.ContentDocumentId;
                updateDocument.Title = lastVersionOfUploadDocument.ContentDocument.Title.replace('ForSignature', 'v' + (oldDocuments.size() - 1) + '.0');
                update updateDocument;

                List<ContentVersion> contentVersions = [
                    SELECT
                        Id,
                        Title,
                        FileType,
                        ContentSize,
                        ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :idCurrentContentVersion
                    LIMIT 1
                ];
                if (contentVersions.isEmpty()) {
                    sendErrorMessage(app, idCurrentContentVersion);
                    result.put('status', 'Success');
                    result.put('isComplete', 'true');
                    return result;
                }
                ContentVersion currentContentVersion = contentVersions[0];

                List<Application_Document__c> relatedApplicationDocuments = [
                    SELECT
                        File_Name__c
                    FROM Application_Document__c
                    WHERE Application__c = :app.Id AND
                          File_Name__c LIKE '%UPLOAD%'
                    LIMIT 1
                ];
                if (!relatedApplicationDocuments.isEmpty()) {
                    ContentDocumentLink conDocLinkUploadDoc = new ContentDocumentLink();
                    conDocLinkUploadDoc.LinkedEntityId = relatedApplicationDocuments[0].Id;
                    conDocLinkUploadDoc.ContentDocumentId = currentContentVersion.ContentDocumentId;
                    conDocLinkUploadDoc.shareType = 'V';
                    conDocLinkUploadDoc.Visibility = 'AllUsers';
                    Database.insert(conDocLinkUploadDoc, false);
                    if (isFromAgentForm == false) {
                        app.Status__c = 'Form Completed';
                    }
                    app.Form_Complete_Date__c = Date.today();
                    update app;
                    result.put('status', 'Success');
                    result.put('isComplete', 'true');
                    return result;
                }
            } else {
                List<ContentVersion> contentVersions = [
                    SELECT
                        Id,
                        Title,
                        FileType,
                        ContentSize,
                        ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :idCurrentContentVersion
                    LIMIT 1
                ];
                if (contentVersions.isEmpty()) {
                    sendErrorMessage(app, idCurrentContentVersion);
                    result.put('status', 'Success');
                    result.put('isComplete', 'true');
                    return result;
                }
                ContentVersion currentContentVersion = contentVersions[0];
                try {
                    List<Application_Document__c> relatedApplicationDocuments = [
                        SELECT
                            File_Name__c
                        FROM Application_Document__c
                        WHERE Application__c = :app.Id AND
                              File_Name__c LIKE '%UPLOAD%'
                        LIMIT 1
                    ];
                    List<SObject> newContentDocumentLinkAndApplication = new List<SObject>();
                    if (relatedApplicationDocuments.isEmpty()) {
                        List<Application_Document__c> newApplicationDocuments = new List<Application_Document__c>();
                        newApplicationDocuments.add(new Application_Document__c(
                            Application__c = requestData?.applicationId,
                            File_Name__c   = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_UPLOAD_ForSignature',
                            File_Size__c   = currentContentVersion.ContentSize,
                            Large_File__c  = Integer.valueOf(currentContentVersion.ContentSize) > 6000000 ? true : false,
                            Status__c      = 'New',
                            Type__c        = 'CV'
                        ));
                        insert newApplicationDocuments;

                        newContentDocumentLinkAndApplication.add(new ContentDocumentLink(
                            ContentDocumentId = currentContentVersion.ContentDocumentId,
                            LinkedEntityId    = newApplicationDocuments[0].Id,
                            ShareType         = 'V',
                            Visibility        = 'AllUsers'
                        ));
                    }
                    if (isFromAgentForm == false) {
                        app.Status__c = 'Form Completed';
                    }
                    app.Form_Complete_Date__c = Date.today();
                    newContentDocumentLinkAndApplication.add(app);
                    upsert newContentDocumentLinkAndApplication;
                    result.put('status', 'Success');
                    result.put('isComplete', 'true');
                } catch (Exception ex) {
                    result.put('status', 'Error');
                    result.put('message', ex.getLineNumber() + '-' + ex.getMessage());
                }
            }
        }
        return result;
    }

        private static void sendErrorMessage(Application__c app, String idCurrentContentVersion) {
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTargetObjectId(app.Contact__c);
        message.setSenderDisplayName('XtraPension');
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setHtmlBody('<div>Contnt version is empty  for the app: ' + app.Name + '</div>'+
                            '<div>Content version Id is: ' + idCurrentContentVersion + '</div>');
        message.setWhatId(app.Id);
        message.setSubject('XtraPension error!!!');
        message.toAddresses = new String[] {'mihail.klimovich@outlook.com'};
        message.setTreatTargetObjectAsRecipient(false);
        Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
    }
}