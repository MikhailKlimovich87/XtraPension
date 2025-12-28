public class PrintingHouseReplyModalController {

    @AuraEnabled
    public static void sendEmail(String toAddress, String subject, String body, List<Id> contentDocumentIds) {
        if (String.isBlank(toAddress)) {
            throw new AuraHandledException('Recipient email is required.');
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { toAddress });
        email.setSubject(subject);
        email.setHtmlBody(body);

        List<Messaging.EmailFileAttachment> fileAttachments = new List<Messaging.EmailFileAttachment>();

        if (!contentDocumentIds.isEmpty()) {
            List<ContentVersion> versions = [
                SELECT Id, Title, FileType, VersionData
                FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocumentIds
                AND IsLatest = true
            ];

            for (ContentVersion v : versions) {
                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                efa.setFileName(v.Title + '.' + v.FileType);
                efa.setBody(v.VersionData);
                fileAttachments.add(efa);
            }
            email.setFileAttachments(fileAttachments);
        }

        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });

        if (!results[0].isSuccess()) {
            throw new AuraHandledException('Email failed: ' + results[0].getErrors()[0].getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static InitialFilesWrapper getAvailableDocuments(Id appId) {
        InitialFilesWrapper wrapper = new InitialFilesWrapper();
        for(ContentDocumentLink link : [
            SELECT
                ContentDocumentId,
                ContentDocument.Title
            FROM ContentDocumentLink
            WHERE
                LinkedEntityId = :appId AND
                ContentDocument.FileType != 'SNOTE'
        ]) {
            wrapper.allAvailableFiles.add(link);
            if(link.ContentDocument.Title.contains('REPLY')) wrapper.replyFiles.add(link);
        }
        return wrapper;
    }

    @AuraEnabled(cacheable=false)
    public static ResultWrapper sendDocs(Id appId, List<Id> attachFiles, Id fileIdToHMRC) {
        ResultWrapper wrapper = new ResultWrapper();
        List<SObject> appealDate = new List<SObject>();
        appealDate.add(
            new Application__c(
                Id = appId,
                Status__c = 'HMRC Appeal'
            )
        );
        HMRC_Appeal_Reply__c reply = new HMRC_Appeal_Reply__c(
            Application__c = appId,
            Client_Attach_File_Ids__c = JSON.serializePretty(attachFiles)
        );
        appealDate.add(reply);
        try {
            upsert appealDate;
            insert new ContentDocumentLink(
                LinkedEntityId = reply.Id,
                ContentDocumentId = fileIdToHMRC,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            wrapper.isSent = true;
        } catch (Exception ex) {
            wrapper.errorMessage = ex.getMessage();
        }
        return wrapper;
    }

    public class ResultWrapper {
        @AuraEnabled
        public Boolean isSent = false;
        @AuraEnabled
        public String errorMessage;
    }

    public class InitialFilesWrapper {
        @AuraEnabled
        public List<ContentDocumentLink> allAvailableFiles;
        @AuraEnabled
        public List<ContentDocumentLink> replyFiles;

        public InitialFilesWrapper () {
            allAvailableFiles = new List<ContentDocumentLink>();
            replyFiles = new List<ContentDocumentLink>();
        }
    }

}