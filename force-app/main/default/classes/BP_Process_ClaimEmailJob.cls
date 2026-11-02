public with sharing class BP_Process_ClaimEmailJob implements Queueable, Database.AllowsCallouts {

    // Org-wide email address
    private static final String ORG_WIDE_EMAIL = 'clients@xtrapension.com';

    private String contactId;
    private String email;
    private String templateId;
    private String recordId;
    private static OrgWideEmailAddress orgWideEmailAddress;

    public BP_Process_ClaimEmailJob(String contactId, String email, String templateId, String recordId) {
        this.contactId = contactId;
        this.email = email;
        this.templateId = templateId;
        this.recordId = recordId;
    }

    // The e-mail carries the wet-signature PDFs that were actually printed and posted
    // (the stored IPCBR1 / IPC1394 wet-signature files), not freshly generated copies.
    public void execute(QueueableContext context) {
        Blob blob1394;
        Blob blobBR1;
        String fileNameIPC;
        String fileBR;
        for (ContentDocumentLink link : [
            SELECT
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
              AND (ContentDocument.Title LIKE '%IPC1394_Wet_Signature%' OR ContentDocument.Title LIKE '%IPCBR1_Wet_Signature%')
            ORDER BY ContentDocument.CreatedDate DESC
        ]) {
            String title = link.ContentDocument.Title;
            Blob body = link.ContentDocument.LatestPublishedVersion.VersionData;
            if (title.endsWith('IPC1394_Wet_Signature') && blob1394 == null) {
                blob1394 = body;
                fileNameIPC = title;
            } else if (title.endsWith('IPCBR1_Wet_Signature') && blobBR1 == null) {
                blobBR1 = body;
                fileBR = title;
            }
        }

        if (blob1394 == null || blobBR1 == null) {
            insert new Application_Form_Error__c(
                Error_Body__c = 'Posted-claim e-mail not sent for claim ' + recordId
                    + ': the wet-signature IPCBR1 / IPC1394 PDFs that were posted were not found on the claim.',
                Error_Date__c = Date.today()
            );
            return;
        }

        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        // Claims created outside application/create have no Contact: resolve one (or log and stop)
        Id targetContactId = String.isNotBlank(contactId)
            ? (Id) contactId
            : BP_PortalUtils.resolveEmailContactId(recordId, 'Posted-claim');
        if (targetContactId == null) {
            return;
        }

        Messaging.EmailFileAttachment attachmentIPC1391 = new Messaging.EmailFileAttachment();
        attachmentIPC1391.setFileName(
            fileNameIPC + '.pdf'
        );
        attachmentIPC1391.setBody(blob1394);

        attachments.add(attachmentIPC1391);

        Messaging.EmailFileAttachment attachmentBR1 = new Messaging.EmailFileAttachment();
        attachmentBR1.setFileName(
            fileBR + '.pdf'
        );
        attachmentBR1.setBody(blobBR1);

        attachments.add(attachmentBR1);
        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();

        OrgWideEmailAddress orgWide = getOrgWideEmailAddress();

        message.setTargetObjectId(targetContactId);
        message.setUseSignature(true);
        message.setBccSender(false);
        message.setSaveAsActivity(true);
        message.setTreatTargetObjectAsRecipient(false);
        message.setTemplateId(templateId);
        message.setToAddresses(new String[] { email });

        message.setWhatId(recordId);

        message.setOrgWideEmailAddressId(orgWide.Id);

        message.setFileAttachments(attachments);

        if (!Test.isRunningTest()) {

            Messaging.SendEmailResult[] results =
                Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ message }
                );

            if (results[0].isSuccess()) {

                update new Basic__c (Id = recordId, Process_Claim_Email_Date__c = Date.today());

                /*
                 * Give Salesforce a moment to create the EmailMessage
                 * activity before trying to link Files to it.
                 */
                EmailMessage emailMessage = findEmailMessage(
                    recordId,
                    email
                );

                if (emailMessage != null) {

                    createFileAndLinkToEmail(
                        emailMessage.Id,
                        fileNameIPC,
                        blob1394
                    );

                    createFileAndLinkToEmail(
                        emailMessage.Id,
                        fileBR,
                        blobBR1
                    );
                }
            }
        }
    }
    @TestVisible
    private static void createFileAndLinkToEmail(
        Id emailMessageId,
        String fileName,
        Blob fileBody
    ) {

        ContentVersion version = new ContentVersion(
            Title = fileName.substringBeforeLast('.'),
            PathOnClient = fileName,
            VersionData = fileBody
        );

        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            ContentDocumentId = version.ContentDocumentId,
            LinkedEntityId = emailMessageId,
            ShareType = 'V'
        );
    }
    @TestVisible
    private static EmailMessage findEmailMessage(
        Id reapplyId,
        String emailAddress
    ) {
        List<EmailMessage> emails = [
            SELECT
                Id,
                Subject,
                ToAddress,
                RelatedToId,
                CreatedDate
            FROM EmailMessage
            WHERE RelatedToId = :reapplyId
            AND ToAddress = :emailAddress
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return emails.isEmpty() ? null : emails[0];
    }

    private OrgWideEmailAddress getOrgWideEmailAddress() {
        if (orgWideEmailAddress == null) {
            List<OrgWideEmailAddress> addresses = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address = :ORG_WIDE_EMAIL
                WITH USER_MODE
                LIMIT 1
            ];
            if (!addresses.isEmpty()) {
                orgWideEmailAddress = addresses[0];
            }
        }
        return orgWideEmailAddress;
    }
    
}