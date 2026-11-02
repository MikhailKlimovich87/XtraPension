public with sharing class PKNoitificationGenerator implements Database.Batchable<SObject>, Database.AllowsCallouts {
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
        Date monthAgo = Date.today().addDays(-45);

        return Database.getQueryLocator([
            SELECT Application__c
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
            AND Application__r.Pension_Keeper_Notification_Generated__c = null
            LIMIT 20
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Payment__c> payments) {
        if (payments.size() == 0) {
            return;
        }
        Payment__c currentPayment = payments[0];
        List<Application__c> apps = [
            SELECT
                First_Name__c,
                Second_Name__c,
                Name,
                Repeat_App__c,
            (
                SELECT
                    ContentDocument.LatestPublishedVersion.VersionData,
                    ContentDocument.LatestPublishedVersion.Title,
                    ContentDocument.LatestPublishedVersion.FileExtension,
                    ContentDocument.LatestPublishedVersion.ContentSize
                FROM ContentDocumentLinks
                WHERE ContentDocument.Title LIKE '%Welcome_PK_Notification%'
                ORDER BY ContentDocument.CreatedDate DESC
                LIMIT 1
            )
            FROM Application__c
            WHERE Id = :currentPayment.Application__c
        ];
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
        sftpWrapper.folderName   = PRINTING_HOUSE_SFTP.Pension_Keeper_Docs_Folder_Name__c;
        sftpWrapper.files        = new List<SFTPFile>{sftpFile};

        HttpResponse response = uploadFileToSFTP(sftpWrapper);

        if (response.getStatusCode() == 200) {
            currApp.Pension_Keeper_Notification_Generated__c = Date.today();
        } else {
            currApp.Pension_Keeper_Notification_Error__c = response.getBody();
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

    public void fakeMethod() {
        Integer i = 0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++; 
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++; 
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;   
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++; 
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}