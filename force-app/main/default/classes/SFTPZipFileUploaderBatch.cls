public class SFTPZipFileUploaderBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {
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
                First_Name__c,
                Second_Name__c,
                Name,
            (
                SELECT
                    ContentDocument.LatestPublishedVersion.VersionData,
                    ContentDocument.LatestPublishedVersion.Title,
                    ContentDocument.LatestPublishedVersion.FileExtension,
                    ContentDocument.LatestPublishedVersion.ContentSize
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%ZIP%'
                LIMIT 1
            )
            FROM Application__c
            WHERE (Status__c = 'Printing House' OR 
                   Status__c = 'REPEAT(NO edits)') AND
                   FTP_Send_Date__c = NULL
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Application__c> apps) {
        if (apps.size() == 0) {
            return;
        }
        Application__c currApp = apps[0];
        if (currApp.ContentDocumentLinks.size() == 0) {
            return;
        }
        ContentVersion cv = currApp.ContentDocumentLinks[0].ContentDocument.LatestPublishedVersion;

        SFTPFile sftpFile = new SFTPFile();
        sftpFile.fileName = cv.Title + '.' + cv.FileExtension;
        sftpFile.body     = EncodingUtil.base64Encode(cv.VersionData);

        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.FolderName__c;
        sftpWrapper.files        = new List<SFTPFile>{sftpFile};

        HttpResponse response = uploadFileToSFTP(sftpWrapper);

        if (response.getStatusCode() == 200) {
            currApp.FTP_Send_Date__c = Date.today();
        } else {
            currApp.FTP_Uploading_Error__c = response.getBody();
        }
        update currApp;
    }

    public void finish(Database.BatchableContext BC) {
        //notification with errors
        //notification With success
    }


    public static HttpResponse uploadFileToSFTP(SFTPWrapper sftpWrapper) {

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