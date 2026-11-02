public class PrintingHouseReplyModalController {

    @AuraEnabled(cacheable=false)
    public static InitialFilesWrapper getAvailableDocuments(Id appId) {
        InitialFilesWrapper wrapper = new InitialFilesWrapper();
        for(ContentDocumentLink link : [
            SELECT
                ContentDocumentId,
                ContentDocument.Title,
                ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE
                LinkedEntityId = :appId AND
                ContentDocument.FileType != 'SNOTE'
        ]) {
            wrapper.allAvailableFiles.add(link);
            if(link.ContentDocument.Title.contains('REPLY') || link.ContentDocument.Title.contains('UPLOAD')) wrapper.replyFiles.add(link);
        }
        return wrapper;
    }

    @AuraEnabled(cacheable=false)
    public static ResultWrapper sendDocs(Id appId, List<Id> attachFiles, List<Id> filesIdToHMRC) {
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
            List<ContentDocumentLink> replyLinks = new List<ContentDocumentLink>();
            for (Id replyId : filesIdToHMRC) {
                replyLinks.add(
                    new ContentDocumentLink(
                        LinkedEntityId = reply.Id,
                        ContentDocumentId = replyId,
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    )
                );
            }
            if (replyLinks.size() > 0) {
                insert replyLinks;
            }
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