public class PK_HowToBuyMoreYearsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private static final EmailTemplate NOTIFICATION_EMAIL_TEMPLATE {
        get {
            if (NOTIFICATION_EMAIL_TEMPLATE == null) {
                List<EmailTemplate> emailTemplates = [
                    SELECT Id, HtmlValue
                    FROM EmailTemplate
                    WHERE Name = 'PK - How to Buy More Years Template'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!emailTemplates.isEmpty()) {
                    NOTIFICATION_EMAIL_TEMPLATE = emailTemplates[0];
                }
            }
        return NOTIFICATION_EMAIL_TEMPLATE;
    }
        private set;
    }

    private static final OrgWideEmailAddress OWD {
        get {
            if (OWD == null) {
                List<OrgWideEmailAddress> orgWideEmailAddresses = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'keeper@xtrapension.com'
                    WITH USER_MODE
                    LIMIT 1
                ];
                if (!orgWideEmailAddresses.isEmpty()) {
                    OWD = orgWideEmailAddresses[0];
                }
            }
            return OWD;
        }
        private set;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date weekAgo = Date.today().addDays(-7);
        return Database.getQueryLocator([
            SELECT
                Id,
                Name,
                Email__c,
                First_Name__c,
                Second_Name__c,
                Contact__c
            FROM Application__c
            WHERE Status__c = 'Pension Keeper'
            AND PK_Portal_User_Active__c = true 
            AND PK_Registration_Date__c = :weekAgo
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Application__c> apps) {
        if (apps.size() == 0) {
            return;
        }
        Set<Id> appIds = new Set<Id>();

        for (Application__c app : apps) {
            appIds.add(app.Id);
        }

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
        sendNotificationEmail(appIds);
    }

    private void sendNotificationEmail(Set<Id> appIds) {

        Map<Id, List<Id>> filesByApplication = new Map<Id, List<Id>>();
        List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();

        for (Application__c currApp : [
            SELECT
                Id,
                Name,
                Email__c,
                First_Name__c,
                Second_Name__c,
                Contact__c,
                (
                    SELECT
                        ContentDocumentId,
                        ContentDocument.Title,
                        ContentDocument.LatestPublishedVersionId,
                        ContentDocument.LatestPublishedVersion.VersionData,
                        ContentDocument.LatestPublishedVersion.FileExtension
                    FROM ContentDocumentLinks
                    WHERE
                        ContentDocument.Title LIKE '%Next Step 2 - Get Receipt%'
                )
            FROM Application__c
            WHERE Id IN :appIds
        ]) {

            Messaging.SingleEmailMessage message =
                new Messaging.SingleEmailMessage();

            message.setTargetObjectId(currApp.Contact__c);
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);
            message.setTemplateId(NOTIFICATION_EMAIL_TEMPLATE.Id);
            message.setWhatId(currApp.Id);
            message.setOrgWideEmailAddressId(OWD.Id);
            message.setToAddresses(new String[] { currApp.Email__c });

            List<Messaging.EmailFileAttachment> attachments =
                new List<Messaging.EmailFileAttachment>();

            List<Id> documentIds = new List<Id>();

            for (ContentDocumentLink cdl : currApp.ContentDocumentLinks) {

                Messaging.EmailFileAttachment efa =
                    new Messaging.EmailFileAttachment();

                efa.setFileName(
                    cdl.ContentDocument.Title +
                    '.' +
                    cdl.ContentDocument.LatestPublishedVersion.FileExtension
                );

                efa.setBody(
                    cdl.ContentDocument.LatestPublishedVersion.VersionData
                );

                attachments.add(efa);
                documentIds.add(cdl.ContentDocumentId);
            }

            if (!attachments.isEmpty()) {
                message.setFileAttachments(attachments);
            }

            filesByApplication.put(currApp.Id, documentIds);
            emailMessages.add(message);
        }

        Messaging.sendEmail(emailMessages);

        // Get EmailMessages
        List<EmailMessage> emailMsgs = [
            SELECT Id, RelatedToId, CreatedDate
            FROM EmailMessage
            WHERE RelatedToId IN :appIds
            ORDER BY CreatedDate DESC
        ];

        // Keep only the newest EmailMessage per Application
        Map<Id, EmailMessage> latestEmailByApp = new Map<Id, EmailMessage>();

        for (EmailMessage em : emailMsgs) {
            if (!latestEmailByApp.containsKey(em.RelatedToId)) {
                latestEmailByApp.put(em.RelatedToId, em);
            }
        }

        Set<Id> emailIds = new Set<Id>();

        for (EmailMessage em : latestEmailByApp.values()) {
            emailIds.add(em.Id);
    }

    // Existing document links
    Set<String> existingKeys = new Set<String>();

    if (!emailIds.isEmpty()) {

        for (ContentDocumentLink cdl : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :emailIds
        ]) {
            existingKeys.add(
                cdl.LinkedEntityId + '-' + cdl.ContentDocumentId
            );
        }
    }

    List<ContentDocumentLink> emailLinks =
        new List<ContentDocumentLink>();

    for (Id appId : latestEmailByApp.keySet()) {

        EmailMessage em = latestEmailByApp.get(appId);

        if (!filesByApplication.containsKey(appId)) {
            continue;
        }

        for (Id docId : filesByApplication.get(appId)) {

            String key = em.Id + '-' + docId;

            if (!existingKeys.contains(key)) {

                emailLinks.add(
                    new ContentDocumentLink(
                        LinkedEntityId = em.Id,
                        ContentDocumentId = docId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    )
                );

                existingKeys.add(key);
            }
        }
    }

    if (!emailLinks.isEmpty()) {
        insert emailLinks;
    }
}
    public void finish(Database.BatchableContext bc) {
        System.debug(
            'NextSteps2FileGeneratorBatch completed'
        );
    }
}