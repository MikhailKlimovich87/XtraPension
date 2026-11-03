public class PK_WelcomeEmailReminderBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private final String MESSAGE_BODY = 'Hi! See UK State Pension email sent now re annual Pension Keeper service. Stay updated & protect the entitlement you\'ve bought! Thanks. XtraPension';

    public class GeneratedFileResult {
        public Blob pdfBlob;
        public Id contentDocumentId;
    }

    private OrgWideEmailAddress orgWideEmail {
        get {
            if (orgWideEmail == null) {
                orgWideEmail = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = 'clients@xtrapension.com'
                    LIMIT 1
                ];
            }
            return orgWideEmail;
        }
        private set;
    }

    private EmailTemplate emailTemplate {
        get {
            if (emailTemplate == null) {
                emailTemplate = [
                    SELECT Id
                    FROM EmailTemplate
                    WHERE Name = 'Join PK Notification'
                    LIMIT 1
                ];
            }
            return emailTemplate;
        }
        private set;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {

        Date monthAgo = Date.today().addDays(-45);

        return Database.getQueryLocator([
            SELECT
                Id,
                Application__c,
                Application__r.Contact__c,
                Application__r.Email__c,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Application__r.Name,
                Application__r.Related_Contact_Phone__c,
                Application__r.Current_Address_Abroad__CountryCode__s
            FROM Payment__c
            WHERE Status__c = 'Paid'
            AND Payment_Date__c = :monthAgo
            AND (
                Product_Name__c = 'Success'
                OR Product_Name__c = 'Appeal Success'
            )
            AND (
                Application__r.Status__c = 'No Annual'
                OR Application__r.Status__c = 'Annual Service'
            )
            AND Application__r.Sent_Mass_Email_Message__c = false
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Payment__c> payments) {

        if (payments.isEmpty()) {
            return;
        }

        Payment__c currPayment = payments[0];

        List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();

        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();

        message.setTargetObjectId(currPayment.Application__r.Contact__c);
        message.setUseSignature(false);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setWhatId(currPayment.Application__c);
        message.setOrgWideEmailAddressId(orgWideEmail.Id);
        message.setTemplateId(emailTemplate.Id);

        message.toAddresses = new String[] {
            currPayment.Application__r.Email__c
        };

        GeneratedFileResult fileResult = generateWelcomePKPage(
            currPayment.Application__r
        );

        Blob pdfBody = fileResult.pdfBlob;

        if (pdfBody != null) {

            List<Messaging.EmailFileAttachment> attachments =
                new List<Messaging.EmailFileAttachment>();

            Messaging.EmailFileAttachment efa =
                new Messaging.EmailFileAttachment();

            efa.setFileName(
                currPayment.Application__r.First_Name__c + '_' +
                currPayment.Application__r.Second_Name__c + '_' +
                currPayment.Application__r.Name +
                '_Welcome_PK_Notification.pdf'
            );

            efa.setBody(pdfBody);

            attachments.add(efa);

            message.setFileAttachments(attachments);
        }

        emailMessages.add(message);

        Messaging.SendEmailResult[] results =
            Messaging.sendEmail(emailMessages);

        if (results[0].isSuccess()) {

            EmailMessage em = [
                SELECT Id
                FROM EmailMessage
                WHERE RelatedToId = :currPayment.Application__c
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (
                em != null &&
                fileResult != null &&
                fileResult.contentDocumentId != null
            ) {

                ContentDocumentLink emailLink =
                    new ContentDocumentLink();

                emailLink.LinkedEntityId = em.Id;
                emailLink.ContentDocumentId =
                    fileResult.contentDocumentId;
                emailLink.ShareType = 'V';
                emailLink.Visibility = 'AllUsers';

                insert emailLink;
            }

            Application__c updatedApp = new Application__c(
                Id = currPayment.Application__c,
                Sent_Mass_Email_Message__c = true,
                Mass_Sms_Message_Send_Date__c = Date.today()
            );

            System.enqueueJob(
                new MassSendSmsQueueable(
                    MESSAGE_BODY,
                    currPayment.Application__r.Related_Contact_Phone__c,
                    currPayment.Application__r.Current_Address_Abroad__CountryCode__s
                )
            );

            update updatedApp;
        }
    }

    public void finish(Database.BatchableContext BC) {
    }

    private GeneratedFileResult generateWelcomePKPage(
        Application__c appObj
    ) {

        PageReference savepage = Page.PensionKeeperLetter;

        savepage.getParameters().put('id', appObj.Id);

        Blob pdfBlob;

        if (!Test.isRunningTest()) {
            pdfBlob = savepage.getContent();
        } else {
            pdfBlob = Blob.valueOf('Test');
        }

        String finalTitle =
            appObj.First_Name__c + '_' +
            appObj.Second_Name__c + '_' +
            appObj.Name +
            '_Welcome_PK_Notification';

        List<ContentDocumentLink> existingLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :appObj.Id
            AND ContentDocument.Title LIKE '%Welcome_PK_Notification%'
            LIMIT 1
        ];

        ContentVersion conVer = new ContentVersion();

        conVer.ContentLocation = 'S';
        conVer.PathOnClient = finalTitle + '.pdf';
        conVer.Title = finalTitle;
        conVer.VersionData = pdfBlob;

        if (!existingLinks.isEmpty()) {
            conVer.ContentDocumentId =
                existingLinks[0].ContentDocumentId;
        }

        insert conVer;

        Id contentDocumentId;

        if (existingLinks.isEmpty()) {

            ContentVersion conDoc = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :conVer.Id
                LIMIT 1
            ];

            contentDocumentId = conDoc.ContentDocumentId;

            ContentDocumentLink conDocLink =
                new ContentDocumentLink();

            conDocLink.LinkedEntityId = appObj.Id;
            conDocLink.ContentDocumentId = contentDocumentId;
            conDocLink.ShareType = 'V';
            conDocLink.Visibility = 'AllUsers';

            insert conDocLink;

        } else {

            contentDocumentId =
                existingLinks[0].ContentDocumentId;
        }

        GeneratedFileResult result =
            new GeneratedFileResult();

        result.pdfBlob = pdfBlob;
        result.contentDocumentId = contentDocumentId;

        return result;
    }
}