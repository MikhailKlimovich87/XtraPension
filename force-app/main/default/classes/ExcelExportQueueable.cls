public class ExcelExportQueueable implements Queueable, Database.AllowsCallouts {
    private Id exportRequestId;
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

    public ExcelExportQueueable(Id exportRequestId) {
        this.exportRequestId = exportRequestId;
    }

    public void execute(QueueableContext context) {

        PageReference excelPage = Page.ExcelExportPage;

        excelPage.getParameters().put(
            'requestId',
            exportRequestId
        );

        Blob excelBlob;

        if (Test.isRunningTest()) {
            excelBlob =
                Blob.valueOf('Test Excel Content');
        } else {
            excelBlob = excelPage.getContent();
        }
        String fileNameData =
            'Week - ' +
            DateTime.newInstance(Date.today().addDays(-7), Time.newInstance(0, 0, 0, 0)).format('dd-MM-yyyy') +
            ' to ' +
            DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0)).format('dd-MM-yyyy') +
            ' - Addresses.xls';
        ContentVersion newFile =
            new ContentVersion();

        newFile.Title = fileNameData;

        newFile.PathOnClient =
            'WelcomeEmailReport.xls';
        newFile.VersionData = excelBlob;
        newFile.IsMajorVersion = true;

        SFTPFile sftpFile = new SFTPFile();
        sftpFile.fileName = fileNameData;
        sftpFile.body     = EncodingUtil.base64Encode(excelBlob);

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
            insert newFile;
            System.debug('File uploaded successfully to SFTP.');
        } else {
            System.debug('Failed to upload file to SFTP.');
            System.debug('Response Status: ' + response.getStatus());}
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