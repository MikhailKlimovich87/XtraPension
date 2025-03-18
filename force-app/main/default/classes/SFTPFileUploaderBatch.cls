public with sharing class SFTPFileUploaderBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    //max uploading file size 8mb (8400000 bytes) with JSON.serialize()
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
                Status__c,
                Application__c,
                Application__r.First_Name__c,
                Application__r.Second_Name__c,
                Application__r.Name,
                File_Name__c,
            (
                SELECT
                    ContentDocument.LatestPublishedVersion.VersionData,
                    ContentDocument.LatestPublishedVersion.Title,
                    ContentDocument.LatestPublishedVersion.FileExtension,
                    ContentDocument.LatestPublishedVersion.ContentSize
                FROM ContentDocumentLinks
                ORDER BY ContentDocument.LatestPublishedVersion.CreatedDate DESC

                LIMIT 1
            )
            FROM Application_Document__c
            WHERE Status__c = 'Ready For PH'
            AND Large_File__c = FALSE
            LIMIT 80
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Application_Document__c> ADs) {

        if (ADs.size() > 0) {
            Map<Id, List<Application_Document__c>> appIdByListAppDocs = new Map<Id, List<Application_Document__c>>();
            for (Application_Document__c doc : ADs) {
                if (appIdByListAppDocs.get(doc.Application__c) == null) {
                    List<Application_Document__c> appDocs = new List<Application_Document__c>();
                    appDocs.add(doc);
                    appIdByListAppDocs.put(doc.Application__c, appDocs);
                } else {
                    List<Application_Document__c> appDocs = appIdByListAppDocs.get(doc.Application__c);
                    appDocs.add(doc);
                    appIdByListAppDocs.put(doc.Application__c, appDocs);
                }
            }
            List<Application_Document__c> updatedADs = new List<Application_Document__c>();
            for (Id docId : appIdByListAppDocs.keySet()) {
                List<Application_Document__c> currentDocs = appIdByListAppDocs.get(docId);
                Application_Document__c agentAD        = new Application_Document__c();
                Application_Document__c cf083AD        = new Application_Document__c();
                Application_Document__c customLetterAD = new Application_Document__c();
                Application_Document__c uploadAD       = new Application_Document__c();

                for (Application_Document__c ad : currentDocs) {
                    if (ad.File_Name__c.contains('CF083')) {
                        cf083AD = ad;
                    } else if (ad.File_Name__c.contains('64-8')) {
                        agentAD = ad;
                    } else if (ad.File_Name__c.contains('CustomLetter')) {
                        customLetterAD = ad;
                    } else if (ad.File_Name__c.contains('UPLOAD')) {
                        uploadAD = ad;
                    }
                }
                List<Application_Document__c> changeDocsOrderList = new List<Application_Document__c>();
                changeDocsOrderList.add(agentAD);
                changeDocsOrderList.add(cf083AD);
                changeDocsOrderList.add(customLetterAD);
                changeDocsOrderList.add(uploadAD);
                changeDocsOrderList.add(agentAD);

                for (Integer i = 0; i < changeDocsOrderList.size(); i++) {
                    if (changeDocsOrderList[i].ContentDocumentLinks.size() > 0) {

                        ContentVersion cv = changeDocsOrderList[i].ContentDocumentLinks[0].ContentDocument.LatestPublishedVersion;

                        if (cv.ContentSize <= MAX_FILE_SIZE) {
                            String fileNameData = changeDocsOrderList[i].Application__r.Name.contains('A0') ?
                                changeDocsOrderList[i].Application__r.Name.replace('A0', 'A-00') + '_D' + (i + 1) :
                                changeDocsOrderList[i].Application__r.Name + '_D' + (i + 1);
                            if (changeDocsOrderList[i].File_Name__c.contains('64-8')) {
                                fileNameData += '_64-8_ForSignature_completed' + '.' + cv.FileExtension;
                            } else if(changeDocsOrderList[i].File_Name__c.contains('CF083')) {
                                fileNameData += '_CF083_ForSignature_completed' + '.' + cv.FileExtension;
                            } else if(changeDocsOrderList[i].File_Name__c.contains('CustomLetter')) {
                                fileNameData += '_CustomLetter_ForSignature_completed' + '.' + cv.FileExtension;
                            } else if(changeDocsOrderList[i].File_Name__c.contains('UPLOAD')) {
                                fileNameData += '_Upload_ForSignature_completed' + '.' + cv.FileExtension;
                            }
                            SFTPFile sftpFile = new SFTPFile();
                            sftpFile.fileName = fileNameData;
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
                                changeDocsOrderList[i].Status__c = 'Sent To PH';
                            } else {
                                changeDocsOrderList[i].Uploading_Error__c = response.getBody();
                            }
                            if (!fileNameData.contains('D5')) {
                                updatedADs.add(changeDocsOrderList[i]);
                            }
                        } else {
                            changeDocsOrderList[i].Large_File__c = true;
                            updatedADs.add(changeDocsOrderList[i]);
                        }
                    }
                }
            }
            if (updatedADs.size() > 0) {
                Database.update(updatedADs, false);
            }
        }
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