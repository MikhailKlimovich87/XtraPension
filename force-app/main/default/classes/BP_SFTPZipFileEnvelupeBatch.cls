public class BP_SFTPZipFileEnvelupeBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    private static final Integer MAX_FILE_SIZE = 8400000;
    private static final Printing_House_SFTP__c PRINTING_HOUSE_SFTP = Printing_House_SFTP__c.getInstance();
    private static final XtraPension_Data__c SFTP_CONNECTION_DATA = XtraPension_Data__c.getInstance();
    private BP_SftpBatchAlert alert = new BP_SftpBatchAlert('Created-claim SFTP upload (Stage 1)');

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
                Last_Name__c,
                Name,
                Claim_Created_ZIP_for_UPLOAD__c,
            (
                SELECT
                    ContentDocument.LatestPublishedVersion.VersionData,
                    ContentDocument.LatestPublishedVersion.Title,
                    ContentDocument.LatestPublishedVersion.FileExtension,
                    ContentDocument.LatestPublishedVersion.ContentSize
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%Stage 1%'
                LIMIT 1
            )
            FROM Basic__c
            WHERE FTP_Claim_Created_Send_Date__c = NULL 
            AND Claim_Created_ZIP_for_UPLOAD__c = true
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Basic__c> apps) {
        if (apps.size() == 0) {
            return;
        }
        Basic__c currApp = apps[0];
        if (currApp.ContentDocumentLinks.size() == 0) {
            return;
        }
        ContentVersion cv = currApp.ContentDocumentLinks[0].ContentDocument.LatestPublishedVersion;

        // Enforce MAX_FILE_SIZE.
        if (cv.ContentSize > MAX_FILE_SIZE) {
            currApp.FTP_Claim_Created_Error__c = 'File size exceeds the maximum allowed size of ' + MAX_FILE_SIZE + ' bytes.';
            currApp.Claim_Created_ZIP_for_UPLOAD__c = false;
            update currApp;
            alert.addFailure(currApp, currApp.FTP_Claim_Created_Error__c);
            return;
        }
    
        SFTPFile sftpFile = new SFTPFile();
        sftpFile.fileName = cv.Title + '.' + cv.FileExtension;
        sftpFile.body     = EncodingUtil.base64Encode(cv.VersionData);

        SFTPWrapper sftpWrapper  = new SFTPWrapper();
        sftpWrapper.key          = PRINTING_HOUSE_SFTP.Key__c;
        sftpWrapper.sftpHost     = PRINTING_HOUSE_SFTP.Host__c;
        sftpWrapper.sftpPort     = PRINTING_HOUSE_SFTP.Port__c;
        sftpWrapper.sftpUserName = PRINTING_HOUSE_SFTP.UserName__c;
        sftpWrapper.sftpPassword = PRINTING_HOUSE_SFTP.Password__c;
        sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.Claim_Stage_1_Folder__c;
        sftpWrapper.files        = new List<SFTPFile>{sftpFile};

        String errorBody;
        try {
            HttpResponse response = uploadFileToSFTP(sftpWrapper);
            Integer statusCode = response.getStatusCode();
            if (statusCode >= 200 && statusCode < 300) {
                currApp.FTP_Claim_Created_Send_Date__c = Date.today();
            } else {
                errorBody = response.getBody();
            }
        } catch (Exception ex) {
            errorBody = 'SFTP callout failed: ' + ex.getMessage();
        }

        if (errorBody != null) {
            if (errorBody.length() > 255) {
                errorBody = errorBody.substring(0, 255);
            }
            currApp.FTP_Claim_Created_Error__c = errorBody;

            currApp.Claim_Created_ZIP_for_UPLOAD__c = false;
            alert.addFailure(currApp, errorBody);
        }
        update currApp;
    }

    public void finish(Database.BatchableContext BC) {
        alert.send();
        // Stage 2 only picks claims the printer's "BIG ENVELOPE" e-mail has flagged
        // (Claim_Full_Form_ZIP_for_UPLOAD__c = true), so chaining it hourly does not change when it is sent.
        if(!Test.isRunningTest()) {
            //Id batchJobId = Database.executeBatch(new BP_SFTPZipFileFullFormBatch(), 1);
        }
    }


    public static HttpResponse uploadFileToSFTP(SFTPWrapper sftpWrapper) {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(SFTP_CONNECTION_DATA.BP_SFTP_Upload_File_Link__c);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('X-API-KEY', SFTP_CONNECTION_DATA.BR_X_Api_Key__c);
        request.setMethod('POST');
        request.setTimeout(110000);
        request.setBody(JSON.serialize(sftpWrapper));
        Http http = new Http();

        return http.send(request);
    }
}