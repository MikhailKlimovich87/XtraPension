public class SFTPAppealReplyUploaderBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private static final Integer MAX_FILE_SIZE = 8400000;
    private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP = Printing_House_SFTP__c.getInstance();
    private static final String SFTP_CONNECTION_ENDPOINT = XtraPension_Data__c.getInstance().SFTP_Upload_File_Link__c;

    public class SFTPWrapper {
        public String key;
        public String sftpHost;
        public String sftpPort;
        public String sftpUserName;
        public String sftpPassword;
        public String folderName;
        public List<SFTPFile> files;
    }

    public class SFTPFile {
        public String fileName;
        public String body;
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT
                Name,
                (
                    SELECT
                        ContentDocument.LatestPublishedVersion.VersionData,
                        ContentDocument.LatestPublishedVersion.Title,
                        ContentDocument.LatestPublishedVersion.FileExtension,
                        ContentDocument.LatestPublishedVersion.ContentSize
                    FROM ContentDocumentLinks
                    WHERE ContentDocument.LatestPublishedVersion.Title LIKE '%REPLY%'
                    LIMIT 1
                )
            FROM HMRC_Appeal_Reply__c
            WHERE Status__c = 'New' AND
                  Sent_To_HMRC_Date__c = NULL AND
                  Application__r.Status__c = 'HMRC Appeal'
        ]);
    }

    public void execute(Database.BatchableContext BC, List<HMRC_Appeal_Reply__c> replies) {
        if (replies.size() == 0) {
            return;
        }
        HMRC_Appeal_Reply__c currReply = replies[0];
        if (currReply.ContentDocumentLinks.size() == 0) {
            return;
        }
        ContentVersion cv = currReply.ContentDocumentLinks[0].ContentDocument.LatestPublishedVersion;

        SFTPFile sftpFile = new SFTPFile();
        sftpFile.fileName = cv.Title + '.' + cv.FileExtension;
        sftpFile.body     = EncodingUtil.base64Encode(cv.VersionData);

        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.HMRC_Appeal_Reply_Folder__c;
        sftpWrapper.files        = new List<SFTPFile>{sftpFile};

        HttpResponse response = uploadFileToSFTP(sftpWrapper);
        System.debug('response ===== ' + response);

        if (response.getStatusCode() == 200) {
            currReply.Sent_To_HMRC_Date__c = Date.today();
            currReply.Status__c = 'Sent to HMRC';
        } else {
            currReply.Error_Message__c = response.getBody();
            currReply.Status__c = 'Failed';
        }
        update currReply;
    }

    public void finish(Database.BatchableContext BC) {
    }

    private static HttpResponse uploadFileToSFTP(SFTPWrapper sftpWrapper) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(SFTP_CONNECTION_ENDPOINT);
        request.setHeader('Content-Type', 'application/json');
        request.setMethod('POST');
        request.setTimeout(110000);
        request.setBody(JSON.serialize(sftpWrapper));
        Http http = new Http();

        return http.send(request);
    }
}