public class NextSteps2FileGeneratorBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    public NextSteps2FileGeneratorBatch() {}

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name
            FROM Application__c
            WHERE Status__c = 'Pension Keeper'
            AND PK_Portal_User_Active__c = true
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Application__c> apps) {

        Set<Id> appIds = new Set<Id>();

        for (Application__c app : apps) {
            appIds.add(app.Id);
        }

        // Existing file titles + ContentDocumentIds by Application
        Map<Id, Map<String, Id>> existingFilesByApp =
            new Map<Id, Map<String, Id>>();

        List<ContentDocumentLink> existingLinks = [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :appIds
        ];

        Set<Id> docIds = new Set<Id>();

        for (ContentDocumentLink cdl : existingLinks) {
            docIds.add(cdl.ContentDocumentId);
        }

        Map<Id, String> titleByDocId = new Map<Id, String>();

        if (!docIds.isEmpty()) {

            for (ContentVersion cv : [
                SELECT ContentDocumentId, Title
                FROM ContentVersion
                WHERE ContentDocumentId IN :docIds
                AND IsLatest = true
            ]) {
                titleByDocId.put(cv.ContentDocumentId, cv.Title);
            }

            for (ContentDocumentLink cdl : existingLinks) {

                String title = titleByDocId.get(cdl.ContentDocumentId);

                if (title == null) {
                    continue;
                }

                if (!existingFilesByApp.containsKey(cdl.LinkedEntityId)) {
                    existingFilesByApp.put(
                        cdl.LinkedEntityId,
                        new Map<String, Id>()
                    );
                }

                existingFilesByApp
                    .get(cdl.LinkedEntityId)
                    .put(title, cdl.ContentDocumentId);
            }
        }

        List<ContentVersion> versionsToInsert =
            new List<ContentVersion>();

        for (Application__c app : apps) {

            try {

                String title =
                    app.Name + ' - Next Step 2 - Get Receipt';

                PageReference pdfPage = Page.GetReceipt;
                pdfPage.getParameters().put('id', app.Id);

                Blob pdfBlob;

                if (Test.isRunningTest()) {
                    pdfBlob = Blob.valueOf('Test PDF Content');
                } else {
                    pdfBlob = pdfPage.getContentAsPDF();
                }

                ContentVersion cv = new ContentVersion();

                cv.Title = title;
                cv.PathOnClient = title + '.pdf';
                cv.VersionData = pdfBlob;
                cv.IsMajorVersion = true;

                // If file already exists, create NEW VERSION
                if (
                    existingFilesByApp.containsKey(app.Id) &&
                    existingFilesByApp.get(app.Id).containsKey(title)
                ) {
                    cv.ContentDocumentId =
                        existingFilesByApp
                            .get(app.Id)
                            .get(title);
                }

                versionsToInsert.add(cv);

            } catch (Exception ex) {

                System.debug(
                    'Error generating file for App ' +
                    app.Id +
                    ': ' +
                    ex.getMessage()
                );
            }
        }

        if (!versionsToInsert.isEmpty()) {

            insert versionsToInsert;

            // Create links ONLY for brand new files
            List<ContentDocumentLink> linksToInsert =
                new List<ContentDocumentLink>();

            for (ContentVersion cv : [
                SELECT Id, Title, ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :versionsToInsert
            ]) {

                for (Application__c app : apps) {

                    String expectedTitle =
                        app.Name + ' - Next Step 2 - Get Receipt';

                    if (cv.Title != expectedTitle) {
                        continue;
                    }

                    Boolean alreadyExists =
                        existingFilesByApp.containsKey(app.Id) &&
                        existingFilesByApp
                            .get(app.Id)
                            .containsKey(expectedTitle);

                    // Only create link for NEW documents
                    if (!alreadyExists) {

                        ContentDocumentLink cdl =
                            new ContentDocumentLink();

                        cdl.LinkedEntityId = app.Id;
                        cdl.ContentDocumentId = cv.ContentDocumentId;
                        cdl.ShareType = 'V';
                        cdl.Visibility = 'AllUsers';

                        linksToInsert.add(cdl);
                    }
                }
            }

            if (!linksToInsert.isEmpty()) {
                insert linksToInsert;
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(
            'NextSteps2FileGeneratorBatch completed'
        );
    }
}