public with sharing class RE_PensionKeeperEmailBatch implements Database.Batchable<SObject> {
    public String extrCondition;

    public RE_PensionKeeperEmailBatch(String cond) {
        this.extrCondition = cond;
    }

    public RE_PensionKeeperEmailBatch() {
        this.extrCondition = '';
    }

    public final Map<String, String> CURRENCY_TO_TEMPLATE = new Map<String, String>{
        'CAD' => 'PK_Reapply_Can',
        'USD' => 'PK_Reapply_ROW',
        'EUR' => 'PK_Reapply_IrlEU',
        'NZD' => 'PK_Reapply_NZ',
        'ZAR' => 'PK_Reapply_SA',
        'AUD' => 'PK_Reapply_Aus'
    };

    public final Map<String, String> VALID_FILE_NAME = new Map<String, String>{
        'PK_Reapply_Can' => 'Reapply-Can',
        'PK_Reapply_ROW' => 'Reapply-ROW',
        'PK_Reapply_IrlEU' => 'Reapply-IrlEU',
        'PK_Reapply_NZ' => 'Reapply-NZ',
        'PK_Reapply_SA' => 'Reapply-SA',
        'PK_Reapply_Aus' => 'Reapply-Aus'
    };

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator(
            'SELECT ' +
                'Id,' +
                'Pension_Keeper_Email_Send_Date__c,' +
                'Status__c,' +
                'Email__c,' +
                'CurrencyIsoCode,' +
                'Application__r.Contact__c  ' +
            'FROM Reapply__c ' +
            'WHERE Pension_Keeper_Email_Send_Date__c = null ' +
            'AND No_Annual_Email_Send_Date__c = null ' +
            'AND Application__r.Status__c = \'Pension Keeper\' ' +
            extrCondition
        );
    }

    public void execute(Database.BatchableContext context, List<Reapply__c> scope) {
        String orgWideEmailAddress = 'clients@xtrapension.com';
        String currStr = 'USD';

        if (String.isNotBlank(CURRENCY_TO_TEMPLATE.get(scope[0].CurrencyIsoCode))) {
            currStr = CURRENCY_TO_TEMPLATE.get(scope[0].CurrencyIsoCode);
        }

        Blob pdfBody;
        List<StaticResource> pdfStatics = [
            SELECT Body, Name
            FROM StaticResource
            WHERE Name = :currStr
            LIMIT 1
        ];

        if (pdfStatics.isEmpty()) {
            System.debug('Static Resource not found for template: ' + currStr);
            return;
        }

        pdfBody = pdfStatics[0].Body;

        OrgWideEmailAddress[] owea = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :orgWideEmailAddress
        ];

        List<EmailTemplate> welcomeEmailTemplate = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName = :'REAPPLY_Pension_Keeper_PK_Clients'
        ];

        for (Reapply__c app : scope) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setTargetObjectId(app.Application__r.Contact__c);
            message.setUseSignature(false);
            message.setBccSender(false);
            message.setSaveAsActivity(true);
            message.setTreatTargetObjectAsRecipient(false);

            if (welcomeEmailTemplate.size() > 0) {
                message.setTemplateId(welcomeEmailTemplate[0].Id);
            }

            message.setToAddresses(new String[] { app.Email__c });
            message.setWhatId(app.Id);

            if (owea.size() > 0) {
                message.setOrgWideEmailAddressId(owea.get(0).Id);
            }

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(VALID_FILE_NAME.get(pdfStatics[0].Name) + '.pdf');
            attachment.setContentType('application/pdf');
            attachment.setBody(pdfBody);

            message.setFileAttachments(
                new Messaging.EmailFileAttachment[] {
                    attachment
                }
            );

            if (!Test.isRunningTest()) {
                Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage>{ message };
                Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);

                if (results[0].isSuccess()) {
                    EmailMessage emailMessage = findEmailMessage(
                        app.Id,
                        app.Email__c
                    );

                    if (emailMessage != null) {
                        createFileAndLinkToEmail(
                            emailMessage.Id,
                            VALID_FILE_NAME.get(pdfStatics[0].Name) + '.pdf',
                            pdfBody
                        );
                    }
                }
            }
            app.Pension_Keeper_Email_Send_Date__c = Date.today();
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
}