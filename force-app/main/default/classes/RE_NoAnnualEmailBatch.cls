public with sharing class RE_NoAnnualEmailBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
    public String extraCondition;

    public RE_NoAnnualEmailBatch(String extraCond) {
        this.extraCondition = extraCond;
    }

    public RE_NoAnnualEmailBatch() {
        this.extraCondition = '';
    }

    public final Map<String, String> CURRENCY_TO_TEMPLATE = new Map<String, String>{
        'CAD' => 'Reapply_Can',
        'USD' => 'Reapply_ROW',
        'EUR' => 'Reapply_IrlEU',
        'NZD' => 'Reapply_NZ',
        'ZAR' => 'Reapply_SA',
        'AUD' => 'Reapply_Aus'
    };

    public final Map<String, String> VALID_FILE_NAME = new Map<String, String>{
        'Reapply_Can' => 'Reapply-Can',
        'Reapply_ROW' => 'Reapply-ROW',
        'Reapply_IrlEU' => 'Reapply-IrlEU',
        'Reapply_NZ' => 'Reapply-NZ',
        'Reapply_SA' => 'Reapply-SA',
        'Reapply_Aus' => 'Reapply-Aus'
    };

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            'SELECT ' +
                'Id,' +
                'Pension_Keeper_Email_Send_Date__c, ' +
                'Status__c, ' +
                'Email__c, ' +
                'CurrencyIsoCode, ' +
                'Application__r.Contact__c ' +
            'FROM Reapply__c ' +
            'WHERE No_Annual_Email_Send_Date__c = null ' +
            'AND Pension_Keeper_Email_Send_Date__c = null ' +
            'AND (Application__r.Status__c = \'No Annual\' OR Application__r.Status__c = \'Annual Service\') ' +
            extraCondition
        );
    }

    public void execute(Database.BatchableContext context, List<Reapply__c> scope) {
        String orgWideEmailAddress = 'clients@xtrapension.com';
        String currStr = 'Reapply_ROW';

        if (String.isNotBlank(CURRENCY_TO_TEMPLATE.get(scope[0].CurrencyIsoCode))) {
            currStr = CURRENCY_TO_TEMPLATE.get(scope[0].CurrencyIsoCode);
        }

        StaticResource pdfStatic = [
            SELECT Body, Name
            FROM StaticResource
            WHERE Name = :currStr
            LIMIT 1
        ];

        StaticResource pdfKeeperStatic = [
            SELECT Body, Name
            FROM StaticResource
            WHERE Name = 'Pension_Keeper'
            LIMIT 1
        ];

        Blob pdfBody = pdfStatic.Body;
        Blob pensionKeeperBody = pdfKeeperStatic.Body;

        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :orgWideEmailAddress
            LIMIT 1
        ];

        List<EmailTemplate> welcomeEmailTemplate = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = 'REAPPLY_No_Annual_Service_Clients'
            LIMIT 1
        ];

        for (Reapply__c app : scope) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();

            message.setTargetObjectId(app.Application__r.Contact__c);
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);

            if (!welcomeEmailTemplate.isEmpty()) {
                message.setTemplateId(welcomeEmailTemplate[0].Id);
            }

            message.setToAddresses(new String[] { app.Email__c });
            message.setWhatId(app.Id);

            if (!owea.isEmpty()) {
                message.setOrgWideEmailAddressId(owea[0].Id);
            }

            /*
             * Attachments that the recipient receives
             */
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();

            String pdfFileName = VALID_FILE_NAME.get(pdfStatic.Name) + '.pdf';

            attachment.setFileName(pdfFileName);
            attachment.setContentType('application/pdf');
            attachment.setBody(pdfBody);

            Messaging.EmailFileAttachment attachmentKeeper = new Messaging.EmailFileAttachment();

            attachmentKeeper.setFileName('Pension_Keeper.pdf');
            attachmentKeeper.setContentType('application/pdf');
            attachmentKeeper.setBody(pensionKeeperBody);

            message.setFileAttachments(
                new Messaging.EmailFileAttachment[] {
                    attachment,
                    attachmentKeeper
                }
            );

            if (!Test.isRunningTest()) {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ message }
                );

                if (results[0].isSuccess()) {
                    /*
                     * Give Salesforce a moment to create the EmailMessage
                     * activity before trying to link Files to it.
                     */
                    EmailMessage emailMessage = findEmailMessage(app.Id, app.Email__c);

                    if (emailMessage != null) {
                        createFileAndLinkToEmail(emailMessage.Id, pdfFileName, pdfBody);
                        createFileAndLinkToEmail(emailMessage.Id, 'Pension_Keeper.pdf', pensionKeeperBody);
                    }
                }
            }

            /*
             * Mark THIS Reapply record as processed.
             */
            app.No_Annual_Email_Send_Date__c = Date.today();
        }

        update scope;
    }

    public void finish(Database.BatchableContext context) {
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
}